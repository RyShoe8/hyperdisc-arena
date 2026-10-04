## Pure match rules for HyperDisc Arena. No nodes, no rendering, no wall-clock
## time: everything advances one fixed tick per step() call, driven only by
## the inputs passed in. Keeping it that way is what lets rollback netcode
## re-simulate matches later.
##
## Coordinates: x runs from the left back wall (0) to the right back wall
## (court.width); y runs from the top wall (0) to the bottom wall
## (court.height). Speeds are pixels per tick.
##
## An input is a Dictionary {"x": -1|0|1, "y": -1|0|1, "a": bool, "b": bool}
## where x/y are absolute screen directions and a/b are "pressed this tick".
extends RefCounted

enum Phase { SERVE, PLAY, POINT_PAUSE, SET_PAUSE, MATCH_OVER }
enum Disc { HELD, FLYING, LOB }

const LEFT := 0
const RIGHT := 1


class PlayerState:
	var side: int
	var character: Dictionary
	var pos := Vector2.ZERO
	var holding := false
	var hold_ticks := 0
	var serving := false
	var dash_ticks := 0
	var dash_dir := Vector2.ZERO
	var recovery_ticks := 0
	var knock_vel := 0.0
	var knock_ticks := 0
	## Recent stick directions as Vector2i(numpad code, tick), oldest first.
	var history: Array[Vector2i] = []


class DiscState:
	var state: int = Disc.HELD
	var owner := LEFT
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var curve := 0.0
	var z := 0.0
	var thrower := -1
	var speed := 0.0
	var power := 1.0
	var supersonic := false
	var rally := 0
	var lob_from := Vector2.ZERO
	var lob_to := Vector2.ZERO
	var lob_tick := 0


var cfg: Dictionary
var tick := 0
var phase: int = Phase.SERVE
var phase_ticks := 0
var scores: Array[int] = [0, 0]
var sets_won: Array[int] = [0, 0]
var set_number := 1
var sudden_death := false
var set_ticks_left := 0
var winner := -1
var server := LEFT
var players: Array[PlayerState] = []
var disc := DiscState.new()
## Things that happened during the last step(), for the view and audio.
var events: Array[Dictionary] = []


func _init(balance: Dictionary, left_character: Dictionary, right_character: Dictionary) -> void:
	cfg = balance
	for side in [LEFT, RIGHT]:
		var p := PlayerState.new()
		p.side = side
		p.character = left_character if side == LEFT else right_character
		players.append(p)
	set_ticks_left = _set_length_ticks()
	_start_serve(LEFT)


# --- Public helpers --------------------------------------------------------

static func forward(side: int) -> int:
	return 1 if side == LEFT else -1


func court_width() -> float:
	return float(cfg.court.width)


func court_height() -> float:
	return float(cfg.court.height)


func net_x() -> float:
	return float(cfg.court.net_x)


func home_x(side: int) -> float:
	var from_wall := float(cfg.player.home_x_from_wall)
	return from_wall if side == LEFT else court_width() - from_wall


## Points scored by a disc entering a goal at height y.
func zone_points(y: float) -> int:
	var t := clampf(y / court_height(), 0.0, 1.0)
	for zone in cfg.court.zones:
		if t >= float(zone.from) and t <= float(zone.to):
			return int(zone.points)
	return 3


## Stable fingerprint of the full match state; equal hashes mean equal games.
func state_hash() -> int:
	var parts: Array = [tick, phase, phase_ticks, scores, sets_won, set_number,
		sudden_death, set_ticks_left, winner, server,
		disc.state, disc.owner, disc.pos, disc.vel, disc.curve, disc.z,
		disc.thrower, disc.speed, disc.rally, disc.lob_to, disc.lob_tick]
	for p in players:
		parts.append_array([p.pos, p.holding, p.hold_ticks, p.dash_ticks,
			p.recovery_ticks, p.knock_vel, p.knock_ticks])
	return var_to_str(parts).hash()


# --- Simulation ------------------------------------------------------------

func step(inputs: Array) -> void:
	events.clear()
	tick += 1
	phase_ticks += 1

	match phase:
		Phase.MATCH_OVER:
			return
		Phase.POINT_PAUSE:
			if phase_ticks >= int(cfg.match.point_pause_ticks):
				_start_serve(server)
			return
		Phase.SET_PAUSE:
			if phase_ticks >= int(cfg.match.set_pause_ticks):
				_start_next_set()
			return

	for side in [LEFT, RIGHT]:
		_record_motion(players[side], inputs[side])
		_update_player(players[side], inputs[side])

	if phase == Phase.SERVE or phase == Phase.PLAY:
		_update_disc()

	if phase == Phase.SERVE or phase == Phase.PLAY:
		if set_ticks_left > 0:
			set_ticks_left -= 1
			if set_ticks_left == 0:
				_end_set()


func _update_player(p: PlayerState, input: Dictionary) -> void:
	if p.knock_ticks > 0:
		p.knock_ticks -= 1
		p.pos.x += p.knock_vel
		p.knock_vel *= float(cfg.knockback.decay)
		if p.holding and _behind_own_wall(p):
			# Knocked back into your own goal while holding the disc.
			_award_point(1 - p.side, zone_points(p.pos.y), "carried")
			return
		_clamp_to_half(p)
		return

	if p.holding:
		p.hold_ticks += 1
		if phase == Phase.SERVE and p.hold_ticks < int(cfg.match.serve_delay_ticks):
			return
		if input.get("b", false):
			_lob(p, input)
		elif input.get("a", false):
			_throw(p, input)
		elif p.hold_ticks >= _hold_limit(p):
			_throw(p, {"x": 0, "y": 0})
		return

	var speed_mult := float(p.character.speed)
	if p.dash_ticks > 0:
		p.dash_ticks -= 1
		p.pos += p.dash_dir * float(cfg.player.dash_speed) * speed_mult
		if p.dash_ticks == 0:
			p.recovery_ticks = int(cfg.player.dash_recovery_ticks)
	elif p.recovery_ticks > 0:
		p.recovery_ticks -= 1
	else:
		var move := Vector2(input.get("x", 0), input.get("y", 0))
		if move != Vector2.ZERO:
			move = move.normalized()
			if input.get("a", false):
				p.dash_dir = move
				p.dash_ticks = int(cfg.player.dash_ticks)
			else:
				p.pos += move * float(cfg.player.run_speed) * speed_mult
	_clamp_to_half(p)


func _update_disc() -> void:
	match disc.state:
		Disc.HELD:
			var holder := players[disc.owner]
			disc.pos = holder.pos + Vector2(forward(holder.side) * float(cfg.player.radius), 0)
			disc.z = 0.0
		Disc.FLYING:
			_update_flying()
		Disc.LOB:
			_update_lob()


func _update_flying() -> void:
	var r := float(cfg.court.disc_radius)
	disc.pos += disc.vel
	disc.vel.y += disc.curve
	# Side walls bounce. The curve is not flipped, so a disc curving into a
	# wall hugs it, and one curving away is sent back across the court.
	if disc.pos.y < r:
		disc.pos.y = r + (r - disc.pos.y)
		disc.vel.y = absf(disc.vel.y)
		events.append({"type": "bounce"})
	elif disc.pos.y > court_height() - r:
		disc.pos.y = (court_height() - r) - (disc.pos.y - (court_height() - r))
		disc.vel.y = -absf(disc.vel.y)
		events.append({"type": "bounce"})

	var defender := LEFT if disc.vel.x < 0 else RIGHT
	var p := players[defender]
	if p.knock_ticks == 0 and not p.holding \
			and p.pos.distance_to(disc.pos) <= float(cfg.player.catch_radius):
		_catch(p)
		return

	if disc.pos.x <= 0.0:
		_award_point(RIGHT, zone_points(disc.pos.y), "goal")
	elif disc.pos.x >= court_width():
		_award_point(LEFT, zone_points(disc.pos.y), "goal")


func _update_lob() -> void:
	disc.lob_tick += 1
	var flight := int(cfg.lob.flight_ticks)
	var t := float(disc.lob_tick) / float(flight)
	disc.pos = disc.lob_from.lerp(disc.lob_to, t)
	disc.z = 4.0 * float(cfg.lob.peak_height) * t * (1.0 - t)

	var receiver := players[1 - disc.thrower]
	if t > 0.5 and disc.z <= float(cfg.lob.catch_height) and not receiver.holding \
			and receiver.knock_ticks == 0 \
			and receiver.pos.distance_to(disc.pos) <= float(cfg.player.catch_radius):
		_catch(receiver)
		return

	if disc.lob_tick >= flight:
		_award_point(disc.thrower, int(cfg.match.miss_points), "miss")


func _catch(p: PlayerState) -> void:
	var was_lob := disc.state == Disc.LOB
	disc.state = Disc.HELD
	disc.owner = p.side
	disc.z = 0.0
	disc.rally += 1
	p.holding = true
	p.hold_ticks = 0
	p.serving = false
	p.dash_ticks = 0
	p.recovery_ticks = 0
	if not was_lob:
		var kb := float(cfg.knockback.base) * (disc.speed / float(cfg.throw.base_speed)) \
			* disc.power / float(p.character.weight)
		p.knock_vel = -forward(p.side) * kb
		p.knock_ticks = int(cfg.knockback.ticks)
	events.append({"type": "catch", "side": p.side, "lob": was_lob})


func _throw(p: PlayerState, input: Dictionary) -> void:
	var fwd := forward(p.side)
	var t: Dictionary = cfg.throw
	var curve_dir := 0 if p.serving else _detect_curve(p)
	var dir: Vector2
	disc.curve = 0.0
	if curve_dir != 0:
		var a := deg_to_rad(float(t.curve_angle_degrees))
		dir = Vector2(fwd * cos(a), curve_dir * sin(a))
	else:
		var a := deg_to_rad(float(t.angle_degrees)) * float(input.get("y", 0))
		dir = Vector2(fwd * cos(a), sin(a))

	var rally_mult := minf(1.0 + float(t.rally_speed_gain) * disc.rally, float(t.rally_speed_cap))
	var window := int(t.supersonic_window_ticks)
	var late := maxi(0, p.hold_ticks - window)
	var hold_mult := maxf(float(t.hold_decay_floor), 1.0 - float(t.hold_decay_per_tick) * late)
	var supersonic := not p.serving and p.hold_ticks <= window
	var speed := float(t.base_speed) * float(p.character.power) * rally_mult * hold_mult
	if supersonic:
		speed *= float(t.supersonic_mult)

	disc.vel = dir * speed
	if curve_dir != 0:
		disc.curve = -curve_dir * float(t.curve_accel) * (speed / float(t.base_speed))
	_release(p, Disc.FLYING, speed)
	disc.supersonic = supersonic
	events.append({"type": "throw", "side": p.side, "supersonic": supersonic,
		"curve": curve_dir != 0})


func _lob(p: PlayerState, input: Dictionary) -> void:
	var l: Dictionary = cfg.lob
	var depth := clampf(float(p.hold_ticks) / float(l.shallow_after_ticks), 0.0, 1.0)
	var deep_x := court_width() - float(l.deep_x_from_wall) if p.side == LEFT \
		else float(l.deep_x_from_wall)
	var shallow_x := net_x() + float(l.shallow_x_from_net) if p.side == LEFT \
		else net_x() - float(l.shallow_x_from_net)
	var target := Vector2(lerpf(deep_x, shallow_x, depth),
		p.pos.y + float(input.get("y", 0)) * float(l.aim_y_offset))
	var margin := float(cfg.player.radius)
	target.y = clampf(target.y, margin, court_height() - margin)

	disc.lob_from = disc.pos
	disc.lob_to = target
	disc.lob_tick = 0
	disc.vel = Vector2.ZERO
	disc.curve = 0.0
	_release(p, Disc.LOB, 0.0)
	disc.supersonic = false
	events.append({"type": "lob", "side": p.side})


func _release(p: PlayerState, state: int, speed: float) -> void:
	disc.state = state
	disc.thrower = p.side
	disc.speed = speed
	disc.power = float(p.character.power)
	p.holding = false
	p.hold_ticks = 0
	p.serving = false
	if phase == Phase.SERVE:
		phase = Phase.PLAY
		phase_ticks = 0


## Quarter-circle motions in numpad notation, relative to facing:
## 2-3-6 starts the disc downward and curves it up; 8-9-6 the reverse.
func _detect_curve(p: PlayerState) -> int:
	if _has_sequence(p.history, [2, 3, 6]):
		return 1
	if _has_sequence(p.history, [8, 9, 6]):
		return -1
	return 0


static func _has_sequence(history: Array[Vector2i], seq: Array) -> bool:
	var i := 0
	for entry in history:
		if entry.x == seq[i]:
			i += 1
			if i == seq.size():
				return true
	return false


func _record_motion(p: PlayerState, input: Dictionary) -> void:
	var rx := int(input.get("x", 0)) * forward(p.side)
	var y := int(input.get("y", 0))
	var code := 5 + rx - 3 * y  # numpad: 8 up, 2 down, 6 forward
	if p.history.is_empty() or p.history[-1].x != code:
		p.history.append(Vector2i(code, tick))
	var oldest := tick - int(cfg.throw.motion_window_ticks)
	while p.history.size() > 1 and p.history[1].y <= oldest:
		p.history.pop_front()


func _hold_limit(p: PlayerState) -> int:
	return int(cfg.player.serve_hold_limit_ticks) if p.serving else int(cfg.player.hold_limit_ticks)


func _behind_own_wall(p: PlayerState) -> bool:
	var r := float(cfg.player.radius)
	return p.pos.x - r <= 0.0 if p.side == LEFT else p.pos.x + r >= court_width()


func _clamp_to_half(p: PlayerState) -> void:
	var r := float(cfg.player.radius)
	if p.side == LEFT:
		p.pos.x = clampf(p.pos.x, r, net_x() - r)
	else:
		p.pos.x = clampf(p.pos.x, net_x() + r, court_width() - r)
	p.pos.y = clampf(p.pos.y, r, court_height() - r)


# --- Points, sets and match ------------------------------------------------

func _award_point(side: int, points: int, reason: String) -> void:
	scores[side] += points
	events.append({"type": "point", "side": side, "points": points, "reason": reason})
	server = 1 - side  # the player who was scored on serves next
	if sudden_death:
		_finish_match(side)
		return
	if scores[side] >= int(cfg.match.points_to_win_set):
		_end_set()
		return
	phase = Phase.POINT_PAUSE
	phase_ticks = 0
	_park_disc()


func _end_set() -> void:
	if scores[LEFT] == scores[RIGHT]:
		sets_won[LEFT] += 1
		sets_won[RIGHT] += 1
	elif scores[LEFT] > scores[RIGHT]:
		sets_won[LEFT] += 1
	else:
		sets_won[RIGHT] += 1
	events.append({"type": "set_end", "set": set_number, "scores": scores.duplicate()})

	var need := int(cfg.match.sets_to_win)
	var decided := sets_won[LEFT] >= need or sets_won[RIGHT] >= need \
		or set_number >= int(cfg.match.max_sets)
	if decided and sets_won[LEFT] != sets_won[RIGHT]:
		_finish_match(LEFT if sets_won[LEFT] > sets_won[RIGHT] else RIGHT)
		return
	if decided:
		sudden_death = true
	phase = Phase.SET_PAUSE
	phase_ticks = 0
	_park_disc()


func _start_next_set() -> void:
	set_number += 1
	scores = [0, 0]
	set_ticks_left = -1 if sudden_death else _set_length_ticks()
	_start_serve(LEFT if set_number % 2 == 1 else RIGHT)


func _finish_match(side: int) -> void:
	winner = side
	phase = Phase.MATCH_OVER
	phase_ticks = 0
	_park_disc()
	events.append({"type": "match_over", "winner": side})


func _start_serve(side: int) -> void:
	server = side
	phase = Phase.SERVE
	phase_ticks = 0
	for p in players:
		p.pos = Vector2(home_x(p.side), court_height() / 2.0)
		p.holding = false
		p.serving = false
		p.hold_ticks = 0
		p.dash_ticks = 0
		p.recovery_ticks = 0
		p.knock_ticks = 0
		p.knock_vel = 0.0
		p.history.clear()
	var s := players[side]
	s.holding = true
	s.serving = true
	disc.state = Disc.HELD
	disc.owner = side
	disc.thrower = -1
	disc.rally = 0
	disc.curve = 0.0
	disc.vel = Vector2.ZERO
	disc.supersonic = false
	_update_disc()


func _park_disc() -> void:
	disc.state = Disc.HELD
	disc.owner = server
	disc.vel = Vector2.ZERO
	disc.curve = 0.0
	disc.z = 0.0
	for p in players:
		p.holding = false
		p.knock_ticks = 0


func _set_length_ticks() -> int:
	return int(cfg.match.set_seconds) * 60
