## Rollback netcode for one online match (GGPO-style).
##
## Each tick the local input is scheduled a few frames ahead (input delay)
## and sent, together with recent unacknowledged inputs, so a lost packet is
## covered by the next one. The sim runs ahead using a prediction of the
## remote player's input (their last known one). When their real input for
## an earlier frame arrives and differs, the sim is rewound to the state
## saved before that frame and re-simulated to the present.
##
## Peers also compare checksums of confirmed frames to catch desyncs, and
## a peer that is running ahead of the other waits a frame now and then so
## neither has to roll back too far.
##
## Packets (first byte): 5 = inputs, 6 = checksum. The lobby uses others.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const InputCodec := preload("res://scripts/net/input_codec.gd")

const PKT_INPUT := 5
const PKT_CHECKSUM := 6
## How far the sim may run past the last confirmed remote input.
const MAX_PREDICTION := 8
## Inputs resent in every packet, at most.
const MAX_RESEND := 32
const CHECKSUM_INTERVAL := 60
## No packet for this long (ticks) means the peer is gone.
const TIMEOUT_TICKS := 300

var sim: MatchSim
var transport
var local_side := 0
var input_delay := 2

## The next frame to simulate.
var frame := 0
var local_inputs := {}       # frame -> encoded input
var remote_inputs := {}      # frame -> encoded input, confirmed
var used_remote := {}        # frame -> encoded input the sim used
var states := {}             # frame -> sim state before that frame
var last_local_frame := -1   # highest frame with a local input
var last_remote_frame := -1  # highest frame with every remote input up to it
var remote_ack := -1         # highest local input the peer has confirmed
var remote_frame := 0        # peer's frame when it last sent
var remote_advantage := 0
var _rollback_from := -1
var _sent_checksums := {}
var _local_checksums := {}
var _remote_checksums := {}
var _quiet_ticks := 0
var _sync_cooldown := 0

var desynced := false
var desync_frame := -1
var stats := {"rollbacks": 0, "max_depth": 0, "resimulated": 0, "stalls": 0}


func _init(match_sim: MatchSim, net_transport, side: int, delay := 2) -> void:
	sim = match_sim
	transport = net_transport
	local_side = side
	input_delay = delay
	# The first frames have no local input yet: they are idle on both ends.
	for f in input_delay:
		local_inputs[f] = InputCodec.IDLE
	last_local_frame = input_delay - 1


func connected() -> bool:
	return _quiet_ticks < TIMEOUT_TICKS


## Advances the match by at most one frame. Returns the sim events of the
## newly simulated frame (events from re-simulated frames already played).
func tick(local_input: Dictionary) -> Array[Dictionary]:
	_quiet_ticks += 1
	_sync_cooldown = maxi(0, _sync_cooldown - 1)
	var can_advance := frame - last_remote_frame <= MAX_PREDICTION and not _should_wait()
	if can_advance:
		last_local_frame = frame + input_delay
		local_inputs[last_local_frame] = InputCodec.encode(local_input)
	else:
		stats.stalls += 1
	_send_inputs()
	_rollback()
	var events: Array[Dictionary] = []
	if can_advance:
		events = _simulate(frame, true)
		frame += 1
	_checksums()
	_forget_old()
	return events


func handle_packet(data: PackedByteArray) -> void:
	if data.is_empty():
		return
	_quiet_ticks = 0
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	var kind := buf.get_u8()
	if kind == PKT_INPUT:
		remote_frame = maxi(remote_frame, buf.get_32())
		remote_advantage = buf.get_8()
		remote_ack = maxi(remote_ack, buf.get_32())
		var start := buf.get_32()
		var count := buf.get_u8()
		for i in count:
			_on_remote_input(start + i, buf.get_u16())
	elif kind == PKT_CHECKSUM:
		var f := buf.get_32()
		_remote_checksums[f] = buf.get_64()
		_compare_checksum(f)


# --- Inputs ----------------------------------------------------------------

func _on_remote_input(f: int, v: int) -> void:
	if remote_inputs.has(f):
		return
	remote_inputs[f] = v
	while remote_inputs.has(last_remote_frame + 1):
		last_remote_frame += 1
	# Already simulated with a different guess: rewind from there.
	if f < frame and used_remote.get(f, -1) != v:
		_rollback_from = f if _rollback_from < 0 else mini(_rollback_from, f)


func _send_inputs() -> void:
	var start := maxi(remote_ack + 1, last_local_frame - MAX_RESEND + 1)
	start = maxi(start, 0)
	var count := last_local_frame - start + 1
	var buf := StreamPeerBuffer.new()
	buf.put_u8(PKT_INPUT)
	buf.put_32(frame)
	buf.put_8(clampi(_local_advantage(), -127, 127))
	buf.put_32(last_remote_frame)
	buf.put_32(start)
	buf.put_u8(maxi(count, 0))
	for f in range(start, start + maxi(count, 0)):
		buf.put_u16(local_inputs.get(f, InputCodec.IDLE))
	transport.send(buf.data_array)


## The remote input to use for frame f: real if we have it, otherwise the
## last real one (players usually keep doing what they were doing).
func _remote_for(f: int) -> int:
	if remote_inputs.has(f):
		return remote_inputs[f]
	var last := mini(last_remote_frame, f - 1)
	return remote_inputs.get(last, InputCodec.IDLE) if last >= 0 else InputCodec.IDLE


func _simulate(f: int, fresh: bool) -> Array[Dictionary]:
	states[f] = sim.save_state()
	var remote := _remote_for(f)
	used_remote[f] = remote
	var mine := InputCodec.decode(local_inputs.get(f, InputCodec.IDLE))
	var theirs := InputCodec.decode(remote)
	sim.step([mine, theirs] if local_side == 0 else [theirs, mine])
	if fresh:
		return sim.events.duplicate()
	return []


func _rollback() -> void:
	if _rollback_from < 0:
		return
	var from := _rollback_from
	_rollback_from = -1
	if not states.has(from):
		return
	var depth := frame - from
	stats.rollbacks += 1
	stats.max_depth = maxi(stats.max_depth, depth)
	stats.resimulated += depth
	sim.load_state(states[from])
	for f in range(from, frame):
		_simulate(f, false)


# --- Keeping both peers in step ---------------------------------------------

## How many frames we are ahead of where the peer is now (positive = ahead).
func _local_advantage() -> int:
	return frame - remote_frame


## Wait a frame when we are clearly further ahead of the peer than they are
## of us, so the faster machine doesn't force constant deep rollbacks.
func _should_wait() -> bool:
	if _sync_cooldown > 0 or frame < 30:
		return false
	var gap := (_local_advantage() - remote_advantage) / 2
	if gap >= 2:
		_sync_cooldown = 10
		return true
	return false


# --- Desync detection --------------------------------------------------------

func _checksums() -> void:
	# A frame is final once every input before it is confirmed on both ends.
	var final_frame := mini(last_remote_frame + 1, frame - 1)
	var f := (final_frame / CHECKSUM_INTERVAL) * CHECKSUM_INTERVAL
	if f <= 0 or _sent_checksums.has(f) or not states.has(f):
		return
	_sent_checksums[f] = true
	var sum: int = var_to_str(states[f]).hash()
	_local_checksums[f] = sum
	var buf := StreamPeerBuffer.new()
	buf.put_u8(PKT_CHECKSUM)
	buf.put_32(f)
	buf.put_64(sum)
	transport.send(buf.data_array)
	_compare_checksum(f)


func _compare_checksum(f: int) -> void:
	if _local_checksums.has(f) and _remote_checksums.has(f) \
			and _local_checksums[f] != _remote_checksums[f] and not desynced:
		desynced = true
		desync_frame = f
		push_warning("Online desync detected at frame %d" % f)


func _forget_old() -> void:
	var keep_from := mini(last_remote_frame, remote_ack) - MAX_PREDICTION - 2
	if keep_from <= 0 or frame % 60 != 0:
		return
	for table in [states, used_remote, local_inputs, remote_inputs]:
		for f in table.keys():
			if f < keep_from:
				table.erase(f)
