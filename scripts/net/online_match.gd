## One online pairing over a Transport: the handshake, the lobby where both
## players pick characters (the host also picks the court), the rollback
## match itself, and rematches. Poll it once per game tick.
##
## The host plays on the left, the guest on the right.
## Lobby packets start with byte 1, then var_to_bytes of a Dictionary.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const RollbackSession := preload("res://scripts/net/rollback_session.gd")

enum State { CONNECTING, LOBBY, PLAYING, ENDED, FAILED }

## Bump when the wire format or the rules change incompatibly.
const PROTOCOL := 3  # 3: analog movement angle in the input
const PKT_LOBBY := 1
const RESEND_TICKS := 20
const TIMEOUT_TICKS := 600

var transport
var balance: Dictionary
var is_host := false
var state: int = State.CONNECTING
var failure := ""
## They left after the result was settled (from the results screen).
var opponent_left := false
var local_name := "PLAYER"
var remote_name := ""
var local_pick := 0
var local_locked := false
var remote_pick := -1
var remote_locked := false
var court := 0
var input_delay := 2
var sim: MatchSim
var session: RollbackSession
## Which side this machine plays.
var local_side := 0
var mixtape_match_id := ""

var _build := 0
var _ticks := 0
var _quiet := 0
var _start_sent := false
var _started := false


func _init(net_transport, rules: Dictionary, hosting: bool, player_name: String) -> void:
	transport = net_transport
	balance = rules
	is_host = hosting
	local_side = 0 if hosting else 1
	local_name = player_name
	_build = build_hash()


## Both players must run the same rules, or the sims would drift apart.
static func build_hash() -> int:
	return (str(PROTOCOL) + FileAccess.get_file_as_string("res://data/balance.json")).hash()


## Call every tick. While playing, returns the sim events of the new frame.
func poll(local_input: Dictionary) -> Array[Dictionary]:
	_ticks += 1
	_quiet += 1
	for data in transport.receive():
		_quiet = 0
		if data.size() > 0 and data[0] == PKT_LOBBY:
			_on_message(bytes_to_var(data.slice(1)))
		elif session != null:
			session.handle_packet(data)
	if state == State.FAILED or state == State.ENDED:
		return []
	if transport.failure != "":
		_fail(transport.failure)
		return []
	if _quiet > TIMEOUT_TICKS and (transport.has_peer() or state != State.CONNECTING):
		_fail("NO RESPONSE FROM HOST" if state == State.CONNECTING else "CONNECTION LOST")
		return []
	match state:
		State.CONNECTING:
			if not is_host and _ticks % RESEND_TICKS == 1:
				_send({"t": "hello", "proto": PROTOCOL, "build": _build, "name": local_name})
		State.LOBBY:
			if _ticks % RESEND_TICKS == 1:
				_send_pick()
				if is_host and _start_sent:
					_send_start()
		State.PLAYING:
			if session != null:
				if not session.connected():
					_fail("OPPONENT DISCONNECTED")
					return []
				return session.tick(local_input)
	return []


# --- Lobby actions (called by the menus) ------------------------------------

func set_pick(character: int, locked: bool) -> void:
	local_pick = character
	local_locked = locked
	_send_pick()


func set_court(index: int) -> void:
	court = index
	_send_pick()


func can_start() -> bool:
	return is_host and state == State.LOBBY and local_locked and remote_locked


## Host only: start the match with both picks and the chosen court.
func start() -> void:
	if not can_start():
		return
	_start_sent = true
	mixtape_match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_send_start()


func request_rematch() -> void:
	_send({"t": "rematch"})
	_back_to_lobby()


func leave() -> void:
	_send({"t": "bye"})
	state = State.ENDED
	transport.close()


## True once the match is over and no late input can change the result.
func match_settled() -> bool:
	return session != null and session.confirmed_phase() == MatchSim.Phase.MATCH_OVER


# --- Messages ---------------------------------------------------------------

func _on_message(msg) -> void:
	if not msg is Dictionary or not msg.has("t"):
		return
	match msg.t:
		"hello":
			if not is_host:
				return
			if int(msg.get("proto", 0)) != PROTOCOL or int(msg.get("build", 0)) != _build:
				_send({"t": "reject", "reason": "DIFFERENT GAME VERSION"})
				return
			remote_name = str(msg.get("name", "PLAYER")).left(16)
			_send({"t": "welcome", "proto": PROTOCOL, "build": _build, "name": local_name})
			if state == State.CONNECTING:
				state = State.LOBBY
				_send_pick()
		"welcome":
			if is_host or state != State.CONNECTING:
				return
			if int(msg.get("build", 0)) != _build:
				_fail("DIFFERENT GAME VERSION")
				return
			remote_name = str(msg.get("name", "PLAYER")).left(16)
			state = State.LOBBY
			_send_pick()
		"reject":
			_fail(str(msg.get("reason", "REJECTED")))
		"pick":
			remote_pick = clampi(int(msg.get("character", 0)), 0, balance.characters.size() - 1)
			remote_locked = bool(msg.get("locked", false))
			if not is_host:
				court = clampi(int(msg.get("court", 0)), 0, balance.courts.size() - 1)
		"start":
			if not is_host and state == State.LOBBY:
				mixtape_match_id = str(msg.get("mixtape", ""))
				court = clampi(int(msg.get("court", 0)), 0, balance.courts.size() - 1)
				input_delay = clampi(int(msg.get("delay", 2)), 0, 8)
				_begin(int(msg.p1), int(msg.p2))
			if not is_host:
				_send({"t": "started"})
		"started":
			if is_host and state == State.LOBBY and _start_sent:
				_begin(local_pick, remote_pick)
		"rematch":
			if state == State.PLAYING or state == State.LOBBY:
				_back_to_lobby()
		"bye":
			if match_settled():
				# They left from the results screen: the result stands.
				opponent_left = true
				state = State.ENDED
			else:
				_fail("OPPONENT LEFT")


func _send_pick() -> void:
	_send({"t": "pick", "character": local_pick, "locked": local_locked, "court": court})


func _send_start() -> void:
	_send({"t": "start", "court": court, "p1": local_pick, "p2": remote_pick, "delay": input_delay, "mixtape": mixtape_match_id})


func _begin(p1: int, p2: int) -> void:
	sim = MatchSim.new(balance, balance.characters[p1], balance.characters[p2], court)
	session = RollbackSession.new(sim, transport, local_side, input_delay)
	state = State.PLAYING


func _back_to_lobby() -> void:
	state = State.LOBBY
	session = null
	sim = null
	local_locked = false
	remote_locked = false
	_start_sent = false


func _send(msg: Dictionary) -> void:
	var data := PackedByteArray([PKT_LOBBY])
	data.append_array(var_to_bytes(msg))
	transport.send(data)


func _fail(reason: String) -> void:
	failure = reason
	state = State.FAILED
	transport.close()
