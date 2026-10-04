## Pure match rules for HyperDisc Arena. No nodes, no rendering, no wall-clock
## time: everything advances one fixed tick per step() call, driven only by
## the inputs passed in. Keeping it that way is what lets rollback netcode
## re-simulate matches later.
##
## Coordinates: x runs from the left back wall (0) to the right back wall
## (court width); y runs from the top wall (0) to the bottom wall (court
## height); z is height above the floor. Speeds are units per tick.
##
## An input is a Dictionary:
##   x, y          -1|0|1 absolute stick direction
##   a, b          throw/dash/block and lob/drop, pressed this tick
##   jump, slap    pressed this tick
##   a_down, b_down  held (for the A+B power toss)
## Missing keys count as released, so older callers keep working.
extends RefCounted

enum Phase { READY, SERVE, PLAY, POINT_PAUSE, SET_PAUSE, MATCH_OVER }
enum Disc { HELD, FLYING, AIR }
## What kind of airborne disc this is decides who may catch it and who
## scores if it lands.
enum Air { LOB, TOSS, DROP, REF, SUPERLOB }
## Flight programs for special throws. NONE is an ordinary throw.
enum Pattern { NONE, SNAKE, WALLBURN, ZIGZAG, LOOP, RICOCHET, CANNON, BUZZSAW }
## One-shot actions, for the view to animate. They never affect the rules.
enum Act { NONE, THROW, LOB, CATCH, BLOCK, SLAP, DROP, SPECIAL, SMASH, JUMP, POWER_TOSS, WHIFF }

const LEFT := 0
const RIGHT := 1
const PATTERN_NAMES := {
	"snake": Pattern.SNAKE, "wallburn": Pattern.WALLBURN, "zigzag": Pattern.ZIGZAG,
	"loop": Pattern.LOOP, "ricochet": Pattern.RICOCHET, "cannon": Pattern.CANNON,
}


class PlayerState:
	var side: int
	var character: Dictionary
	var pos := Vector2.ZERO
	var z := 0.0
	var vz := 0.0
	var holding := false
	var hold_ticks := 0
	var serving := false
	var dash_ticks := 0
	var dash_dir := Vector2.ZERO
	var recovery_ticks := 0
	var knock_vel := 0.0
	var knock_ticks := 0
	## Ticks spent standing under an incoming airborne disc.
	var charge := 0
	## Caught a disc after charging: the next throw can be a special.
	var charged := false
	var ex := 0
	var action: int = Act.NONE
	var action_ticks := 0
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
	var knock_mult := 1.0
	var supersonic := false
	var rally := 0
	var pattern: int = Pattern.NONE
	var pattern_ticks := 0
	var ex := false
	var base := Vector2.ZERO
	var air_kind: int = Air.LOB
	var air_from := Vector2.ZERO
	var air_to := Vector2.ZERO
	var air_from_z := 0.0
	var air_tick := 0
	var air_flight := 1
	var air_peak := 0.0


var cfg: Dictionary
var court: Dictionary
var zones: Array = []
var barriers: Array[Vector3] = []
var tick := 0
var phase: int = Phase.READY
var phase_ticks := 0
var freeze_ticks := 0
var scores: Array[int] = [0, 0]
var sets_won: Array[int] = [0, 0]
## Consecutive points per side, for the Stadium court's growing zone.
var streak: Array[int] = [0, 0]
var set_number := 1
var sudden_death := false
var set_ticks_left := 0
var winner := -1
var server := LEFT
var players: Array[PlayerState] = []
var disc := DiscState.new()
## Things that happened during the last step(), for the view and audio.
var events: Array[Dictionary] = []


func _init(balance: Dictionary, left_character: Dictionary, right_character: Dictionary,
		court_index := 0) -> void:
	cfg = balance
	court = cfg.courts[clampi(court_index, 0, cfg.courts.size() - 1)]
	if court.zones != "stadium":
		zones = cfg.zone_layouts[court.zones]
	for b in court.barriers:
		barriers.append(Vector3(float(b.x) * court_width(), float(b.y) * court_height(), float(b.r)))
	for side in [LEFT, RIGHT]:
		var p := PlayerState.new()
		p.side = side
		p.character = left_character if side == LEFT else right_character
		players.append(p)
	set_ticks_left = _set_length_ticks()
	_start_ready(LEFT)


# --- Public helpers --------------------------------------------------------

static func forward(side: int) -> int:
	return 1 if side == LEFT else -1


func court_width() -> float:
	return float(court.width)


func court_height() -> float:
	return float(court.height)


func net_x() -> float:
	return court_width() / 2.0


func disc_radius() -> float:
	return float(cfg.disc_radius)


func home_x(side: int) -> float:
	var from_wall := float(cfg.player.home_x_from_wall)
	return from_wall if side == LEFT else court_width() - from_wall


func side_of(x: float) -> int:
	return LEFT if x < net_x() else RIGHT


func ex_full(side: int) -> bool:
	return players[side].ex >= int(cfg.ex.max)


## Goal zones on the wall defended by `defender`, as [{from, to, points}].
## Stadium zones depend on the attacker's scoring streak.
func zones_for(defender: int) -> Array:
	if court.zones != "stadium":
		return zones
	var s: Dictionary = cfg.stadium
	var half := minf(float(s.base_half_width) + float(s.growth_per_point) * streak[1 - defender],
		float(s.max_half_width))
	return [
		{"from": 0.0, "to": 0.5 - half, "points": 3},
		{"from": 0.5 - half, "to": 0.5 + half, "points": 5},
		{"from": 0.5 + half, "to": 1.0, "points": 3},
	]


## Points scored by a disc entering `defender`'s goal at height y.
func zone_points(y: float, defender := LEFT) -> int:
	var t := clampf(y / court_height(), 0.0, 1.0)
	for zone in zones_for(defender):
		if t >= float(zone.from) and t <= float(zone.to):
			return int(zone.points)
	return 3


## Where the airborne disc will land, or the disc's position otherwise.
func landing_spot() -> Vector2:
	return disc.air_to if disc.state == Disc.AIR else disc.pos


## Stable fingerprint of the full match state; equal hashes mean equal games.
func state_hash() -> int:
	var parts: Array = [tick, phase, phase_ticks, freeze_ticks, scores, sets_won, streak,
		set_number, sudden_death, set_ticks_left, winner, server,
		disc.state, disc.owner, disc.pos, disc.vel, disc.curve, disc.z, disc.thrower,
		disc.speed, disc.rally, disc.pattern, disc.pattern_ticks, disc.ex, disc.base,
		disc.air_kind, disc.air_to, disc.air_tick]
	for p in players:
		parts.append_array([p.pos, p.z, p.vz, p.holding, p.hold_ticks, p.dash_ticks,
			p.recovery_ticks, p.knock_vel, p.knock_ticks, p.charge, p.charged, p.ex])
	return var_to_str(parts).hash()


# --- Simulation ------------------------------------------------------------

func step(inputs: Array) -> void:
	events.clear()
	tick += 1
	if freeze_ticks > 0:
		# Hit-stop: the whole game holds for a beat on big impacts.
		freeze_ticks -= 1
		return
	phase_ticks += 1
	for p in players:
		p.action_ticks += 1

	match phase:
		Phase.MATCH_OVER:
			return
		Phase.READY:
			if phase_ticks == 1:
				events.append({"type": "ready", "set": set_number})
			if phase_ticks >= int(cfg.match.ready_ticks):
				_referee_toss()
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
	for side in [LEFT, RIGHT]:
		if phase != Phase.SERVE and phase != Phase.PLAY:
			break
		_update_player(players[side], inputs[side])

	if phase == Phase.SERVE or phase == Phase.PLAY:
		_update_disc()

	if phase == Phase.SERVE or phase == Phase.PLAY:
		if set_ticks_left > 0:
			set_ticks_left -= 1
			if set_ticks_left == 0:
				_end_set()


func _update_player(p: PlayerState, input: Dictionary) -> void:
	var pc: Dictionary = cfg.player
	# Airborne: gravity, drift, and smash or lob if holding.
	if p.z > 0.0 or p.vz > 0.0:
		p.vz -= float(pc.gravity)
		p.z += p.vz
		if p.z <= 0.0:
			p.z = 0.0
			p.vz = 0.0
			p.recovery_ticks = int(pc.landing_recovery_ticks)
			events.append({"type": "land", "side": p.side})
		if p.holding:
			p.hold_ticks += 1
			if input.get("a", false):
				_throw(p, input, true)
			elif input.get("b", false):
				_lob(p, input)
			return
		var drift := Vector2(input.get("x", 0), input.get("y", 0))
		if drift != Vector2.ZERO:
			p.pos += drift.normalized() * float(pc.run_speed) * float(p.character.speed) \
				* float(pc.air_control)
		_clamp_to_half(p)
		return

	if p.knock_ticks > 0:
		p.knock_ticks -= 1
		p.pos.x += p.knock_vel
		p.knock_vel *= float(cfg.knockback.decay)
		if p.holding and _behind_own_wall(p):
			# Knocked back into your own goal while holding the disc.
			_award_point(1 - p.side, zone_points(p.pos.y, p.side), "carried")
			return
		_clamp_to_half(p)
		return

	if p.holding:
		p.hold_ticks += 1
		if phase == Phase.SERVE and p.hold_ticks < int(cfg.match.serve_delay_ticks):
			return
		if input.get("slap", false) and ex_full(p.side):
			_special(p, true)
		elif input.get("b", false):
			_lob(p, input)
		elif input.get("a", false):
			if p.charged:
				_special(p, false)
			else:
				_throw(p, input, false)
		elif p.hold_ticks >= _hold_limit(p):
			_throw(p, {"x": 0, "y": 0}, false)
		return

	# Defensive moves against an incoming disc come before movement.
	if _try_defend(p, input):
		return

	var speed_mult := float(p.character.speed)
	if p.dash_ticks > 0:
		p.dash_ticks -= 1
		p.pos += p.dash_dir * float(pc.dash_speed) * speed_mult
		if p.dash_ticks == 0:
			p.recovery_ticks = int(pc.dash_recovery_ticks)
	elif p.recovery_ticks > 0:
		p.recovery_ticks -= 1
	else:
		var move := Vector2(input.get("x", 0), input.get("y", 0))
		if input.get("jump", false):
			p.vz = float(pc.jump_velocity)
			p.z = 0.001
			_act(p, Act.JUMP)
			events.append({"type": "jump", "side": p.side})
		elif move != Vector2.ZERO:
			move = move.normalized()
			if input.get("a", false):
				p.dash_dir = move
				p.dash_ticks = int(pc.dash_ticks)
				events.append({"type": "dash", "side": p.side})
			else:
				p.pos += move * float(pc.run_speed) * speed_mult
		elif input.get("slap", false):
			# A slap with nothing to hit leaves you open for a moment.
			p.recovery_ticks = int(cfg.defence.slap_whiff_recovery_ticks)
			_act(p, Act.WHIFF)
	_update_charge(p)
	_clamp_to_half(p)


## Block, slap, drop shot and power toss. Returns true if one happened.
func _try_defend(p: PlayerState, input: Dictionary) -> bool:
	if p.dash_ticks > 0 or p.recovery_ticks > 0:
		return false
	var d: Dictionary = cfg.defence
	var incoming := disc.state == Disc.FLYING and disc.thrower == 1 - p.side
	var dist := p.pos.distance_to(disc.pos)
	var power_toss: bool = (input.get("a", false) and input.get("b_down", false)) \
		or (input.get("b", false) and input.get("a_down", false))
	if power_toss and incoming and ex_full(p.side) and dist <= float(d.power_toss_radius) \
			and side_of(disc.pos.x) == p.side:
		p.ex = 0
		_air(Air.TOSS, disc.pos, Vector2(p.pos.x, p.pos.y), 0.0, p.side,
			int(cfg.air.toss_flight_ticks), float(cfg.air.toss_peak) * 1.2)
		_act(p, Act.POWER_TOSS)
		events.append({"type": "power_toss", "side": p.side})
		return true
	if not incoming:
		return false
	if input.get("slap", false) and dist <= float(d.slap_radius):
		_slap(p, input)
		return true
	if input.get("b", false) and dist <= float(d.slap_radius):
		_drop_shot(p)
		return true
	var move := Vector2(input.get("x", 0), input.get("y", 0))
	if input.get("a", false) and move == Vector2.ZERO and dist <= float(d.block_radius):
		_block(p)
		return true
	return false


func _update_charge(p: PlayerState) -> void:
	if disc.state != Disc.AIR or side_of(disc.air_to.x) != p.side or p.z > 0.0 \
			or not _may_catch_air(p) \
			or p.pos.distance_to(disc.air_to) > float(cfg.charge.radius):
		p.charge = 0
		return
	p.charge += 1
	if p.charge == int(cfg.charge.ticks_needed):
		events.append({"type": "charge_ready", "side": p.side})


func _update_disc() -> void:
	match disc.state:
		Disc.HELD:
			var holder := players[disc.owner]
			disc.pos = holder.pos + Vector2(forward(holder.side) * float(cfg.player.radius), 0)
			disc.z = holder.z + 30.0
		Disc.FLYING:
			_update_flying()
		Disc.AIR:
			_update_air()


func _update_flying() -> void:
	var r := disc_radius()
	var h := court_height()
	var from := disc.pos
	disc.pattern_ticks += 1
	_move_by_pattern()

	# Side walls bounce. The curve is not flipped, so a disc curving into a
	# wall hugs it, and one curving away is sent back across the court.
	if disc.pos.y < r:
		disc.pos.y = r + (r - disc.pos.y)
		disc.vel.y = absf(disc.vel.y)
		_on_wall()
	elif disc.pos.y > h - r:
		disc.pos.y = (h - r) - (disc.pos.y - (h - r))
		disc.vel.y = -absf(disc.vel.y)
		_on_wall()

	for b in barriers:
		var centre := Vector2(b.x, b.y)
		var gap := disc.pos - centre
		if gap.length() < b.z + r and gap.length() > 0.0:
			var n := gap.normalized()
			disc.pos = centre + n * (b.z + r)
			if disc.vel.dot(n) < 0.0:
				disc.vel = disc.vel.bounce(n)
				disc.base = disc.pos
			events.append({"type": "barrier"})

	var defender := 1 - disc.thrower
	if side_of(disc.pos.x) == disc.thrower and disc.vel.x * forward(disc.thrower) < 0.0:
		# Deflected back off a barrier: the thrower has to deal with it.
		defender = disc.thrower
	var p := players[defender]
	# Test the whole path travelled this tick, not just where the disc ended
	# up: fast throws move further per tick than the catch circle is wide.
	var touch := Geometry2D.get_closest_point_to_segment(p.pos, from, disc.pos)
	if p.knock_ticks == 0 and not p.holding and side_of(touch.x) == defender \
			and p.pos.distance_to(touch) <= float(cfg.player.catch_radius):
		_catch(p)
		return

	if disc.pos.x <= 0.0:
		_award_point(RIGHT, zone_points(disc.pos.y, LEFT), "goal")
	elif disc.pos.x >= court_width():
		_award_point(LEFT, zone_points(disc.pos.y, RIGHT), "goal")


func _move_by_pattern() -> void:
	var s: Dictionary = cfg.special
	var fwd := forward(disc.thrower)
	var t := disc.pattern_ticks
	var r := disc_radius()
	match disc.pattern:
		Pattern.SNAKE:
			var amp := float(s.snake_amplitude) * court_height()
			disc.pos.x += fwd * disc.speed
			var y := disc.base.y + amp * sin(t * float(s.snake_frequency))
			disc.vel.y = y - disc.pos.y
			disc.pos.y = clampf(y, r, court_height() - r)
		Pattern.WALLBURN:
			disc.pos += disc.vel
			if disc.vel.y != 0.0:
				# On reaching a wall, hug it and accelerate down the line.
				if disc.pos.y <= r or disc.pos.y >= court_height() - r:
					disc.pos.y = clampf(disc.pos.y, r, court_height() - r)
					disc.vel = Vector2(fwd * disc.speed, 0.0)
			else:
				var cap := disc.speed * float(s.wallburn_max_mult)
				disc.vel.x = fwd * minf(absf(disc.vel.x) * float(s.wallburn_accel), cap)
		Pattern.ZIGZAG:
			if t % int(s.zigzag_ticks) == 0:
				disc.vel.y = -disc.vel.y
			disc.pos += disc.vel
		Pattern.LOOP:
			var radius := float(s.loop_radius)
			var a := t * float(s.loop_angular_speed)
			disc.base.x += fwd * disc.speed * float(s.loop_forward_mult)
			var target := disc.base + Vector2(fwd * sin(a) * radius, -(1.0 - cos(a)) * radius * signf(disc.vel.y + 0.001))
			target.y = clampf(target.y, r, court_height() - r)
			disc.pos = target
		Pattern.CANNON:
			var cap := disc.speed * float(s.cannon_max_mult)
			disc.vel = disc.vel.normalized() * minf(disc.vel.length() * float(s.cannon_accel), cap)
			disc.pos += disc.vel
		_:
			disc.pos += disc.vel
			disc.vel.y += disc.curve


func _on_wall() -> void:
	if disc.pattern == Pattern.SNAKE or disc.pattern == Pattern.LOOP:
		disc.base.y = disc.pos.y
	events.append({"type": "bounce"})


func _update_air() -> void:
	disc.air_tick += 1
	var t := float(disc.air_tick) / float(disc.air_flight)
	disc.pos = disc.air_from.lerp(disc.air_to, t)
	disc.z = lerpf(disc.air_from_z, 0.0, t) + 4.0 * disc.air_peak * t * (1.0 - t)

	var half := side_of(disc.pos.x)
	var p := players[half]
	if _may_catch_air(p) and not p.holding and p.knock_ticks == 0 \
			and p.pos.distance_to(disc.pos) <= float(cfg.player.catch_radius):
		var grounded := p.z <= 0.0 and t > 0.5 and disc.z <= float(cfg.air.catch_height)
		var in_air := p.z > 0.0 and absf(disc.z - (p.z + 40.0)) <= float(cfg.player.jump_reach)
		if grounded or in_air:
			_catch(p)
			return

	if disc.air_tick < disc.air_flight:
		return
	var landed_on := side_of(disc.air_to.x)
	match disc.air_kind:
		Air.REF:
			_give_serve(landed_on)
		Air.SUPERLOB:
			# The super lob lands and spins on toward the goal like a buzzsaw.
			disc.state = Disc.FLYING
			disc.z = 0.0
			disc.pattern = Pattern.BUZZSAW
			disc.pattern_ticks = 0
			disc.speed = float(cfg.air.buzzsaw_speed) * float(players[disc.thrower].character.power)
			disc.vel = Vector2(forward(disc.thrower) * disc.speed, 0.0)
			disc.knock_mult = float(cfg.special.knock_mult)
			events.append({"type": "buzzsaw", "side": disc.thrower})
		_:
			_award_point(1 - landed_on, int(cfg.match.miss_points), "miss")


## The thrower can't catch their own lob, drop shot or super lob.
func _may_catch_air(p: PlayerState) -> bool:
	if disc.state != Disc.AIR:
		return false
	match disc.air_kind:
		Air.LOB, Air.DROP, Air.SUPERLOB:
			return p.side != disc.thrower
	return true


func _catch(p: PlayerState) -> void:
	var was_air := disc.state == Disc.AIR
	var was_special := disc.pattern != Pattern.NONE
	var speed := disc.vel.length() if disc.state == Disc.FLYING else 0.0
	p.charged = was_air and p.charge >= int(cfg.charge.ticks_needed) and disc.air_kind != Air.REF
	p.charge = 0
	disc.state = Disc.HELD
	disc.owner = p.side
	disc.rally += 1
	disc.pattern = Pattern.NONE
	p.holding = true
	p.hold_ticks = 0
	p.serving = was_air and disc.air_kind == Air.REF
	p.dash_ticks = 0
	p.recovery_ticks = 0
	if not was_air:
		var kb := float(cfg.knockback.base) * (speed / float(cfg.throw.base_speed)) \
			* disc.power * disc.knock_mult / float(p.character.weight)
		p.knock_vel = -forward(p.side) * kb
		p.knock_ticks = int(cfg.knockback.ticks)
		var hs: Dictionary = cfg.hitstop
		if was_special:
			freeze_ticks = int(hs.special_catch_ticks)
		elif speed >= float(hs.fast_catch_speed):
			freeze_ticks = int(hs.fast_catch_ticks)
	_gain_ex(p, int(cfg.ex.gain_catch))
	_act(p, Act.CATCH)
	events.append({"type": "catch", "side": p.side, "air": was_air, "special": was_special,
		"speed": speed, "charged": p.charged})
	if phase == Phase.PLAY and p.serving:
		phase = Phase.SERVE
		phase_ticks = 0


func _throw(p: PlayerState, input: Dictionary, smash: bool) -> void:
	var fwd := forward(p.side)
	var t: Dictionary = cfg.throw
	var curve_dir := 0 if p.serving or smash else _detect_curve(p)
	var dir: Vector2
	disc.curve = 0.0
	if curve_dir != 0:
		var a := deg_to_rad(float(t.curve_angle_degrees))
		dir = Vector2(fwd * cos(a), curve_dir * sin(a))
	else:
		var angle := float(t.smash_angle_degrees if smash else t.angle_degrees)
		var a := deg_to_rad(angle) * float(input.get("y", 0))
		dir = Vector2(fwd * cos(a), sin(a))

	var rally_mult := minf(1.0 + float(t.rally_speed_gain) * disc.rally, float(t.rally_speed_cap))
	var window := int(t.supersonic_window_ticks)
	var late := maxi(0, p.hold_ticks - window)
	var hold_mult := maxf(float(t.hold_decay_floor), 1.0 - float(t.hold_decay_per_tick) * late)
	var supersonic := not p.serving and not smash and p.hold_ticks <= window
	var speed := float(t.base_speed) * float(p.character.power) * rally_mult * hold_mult
	if supersonic:
		speed *= float(t.supersonic_mult)
	if smash:
		speed *= float(t.smash_mult)

	_launch(p, dir * speed, speed, Pattern.NONE)
	if curve_dir != 0:
		disc.curve = -curve_dir * float(t.curve_accel) * (speed / float(t.base_speed))
	disc.supersonic = supersonic or smash
	_gain_ex(p, int(cfg.ex.gain_supersonic if supersonic else cfg.ex.gain_throw))
	_act(p, Act.SMASH if smash else Act.THROW)
	events.append({"type": "throw", "side": p.side, "supersonic": supersonic,
		"curve": curve_dir != 0, "smash": smash})


## The character's special throw; `ex` makes it the gauge-powered version.
func _special(p: PlayerState, ex: bool) -> void:
	var s: Dictionary = cfg.special
	var fwd := forward(p.side)
	var pattern: int = PATTERN_NAMES.get(p.character.get("special", "cannon"), Pattern.CANNON)
	var speed := float(cfg.throw.base_speed) * float(p.character.power) * float(s.speed_mult)
	var knock := float(s.knock_mult)
	if ex:
		speed *= float(s.ex_speed_mult)
		knock = float(s.ex_knock_mult)
		p.ex = 0
	var aim := float(_stick_y(p))
	var dir := Vector2(fwd, 0)
	match pattern:
		Pattern.ZIGZAG:
			var a := deg_to_rad(float(s.zigzag_angle_degrees))
			dir = Vector2(fwd * cos(a), (aim if aim != 0.0 else 1.0) * sin(a))
		Pattern.WALLBURN:
			var toward := aim if aim != 0.0 else (-1.0 if p.pos.y < court_height() / 2.0 else 1.0)
			dir = Vector2(fwd * 0.55, toward * 0.83).normalized()
		Pattern.RICOCHET:
			speed *= float(s.ricochet_speed_mult)
			var a := deg_to_rad(float(s.ricochet_angle_degrees))
			dir = Vector2(fwd * cos(a), (aim if aim != 0.0 else 1.0) * sin(a))
		Pattern.CANNON:
			knock = maxf(knock, float(s.cannon_knock_mult))
			dir = Vector2(fwd, aim * 0.15).normalized()
			speed *= float(s.cannon_start_mult)
		Pattern.LOOP:
			dir = Vector2(fwd, aim if aim != 0.0 else -1.0)
	_launch(p, dir * speed, speed, pattern)
	disc.base = disc.pos
	disc.knock_mult = knock
	disc.ex = ex
	disc.supersonic = true
	p.charged = false
	freeze_ticks = int(s.launch_freeze_ticks)
	_act(p, Act.SPECIAL)
	events.append({"type": "special", "side": p.side, "ex": ex, "pattern": pattern,
		"name": str(p.character.get("special_name", "SPECIAL"))})


func _lob(p: PlayerState, input: Dictionary) -> void:
	var a: Dictionary = cfg.air
	var depth := clampf(float(p.hold_ticks) / float(a.lob_shallow_after_ticks), 0.0, 1.0)
	var deep_x := court_width() - float(a.lob_deep_x_from_wall) if p.side == LEFT \
		else float(a.lob_deep_x_from_wall)
	var shallow_x := net_x() + float(a.lob_shallow_x_from_net) if p.side == LEFT \
		else net_x() - float(a.lob_shallow_x_from_net)
	var target := Vector2(lerpf(deep_x, shallow_x, depth),
		p.pos.y + float(input.get("y", 0)) * float(a.lob_aim_y_offset))
	var margin := float(cfg.player.radius)
	target.y = clampf(target.y, margin, court_height() - margin)
	var superlob := p.charged
	p.charged = false
	_air(Air.SUPERLOB if superlob else Air.LOB, disc.pos, target, disc.z, p.side,
		int(a.superlob_flight_ticks if superlob else a.lob_flight_ticks),
		float(a.superlob_peak if superlob else a.lob_peak))
	_release(p)
	_gain_ex(p, int(cfg.ex.gain_throw))
	_act(p, Act.LOB)
	events.append({"type": "lob", "side": p.side, "super": superlob})


func _slap(p: PlayerState, input: Dictionary) -> void:
	var d: Dictionary = cfg.defence
	var fwd := forward(p.side)
	var rx := int(input.get("x", 0)) * fwd
	var y := float(input.get("y", 0))
	var angle := 0.0
	if y != 0.0:
		angle = float(d.slap_steep_degrees if rx < 0 else d.slap_narrow_degrees)
	var a := deg_to_rad(angle)
	var dir := Vector2(fwd * cos(a), y * sin(a))
	var speed := maxf(disc.vel.length() * float(d.slap_speed_mult),
		float(cfg.throw.base_speed) * float(p.character.power))
	disc.rally += 1
	_launch(p, dir * speed, speed, Pattern.NONE)
	disc.supersonic = true
	_gain_ex(p, int(cfg.ex.gain_slap))
	_act(p, Act.SLAP)
	events.append({"type": "slap", "side": p.side})


func _drop_shot(p: PlayerState) -> void:
	var a: Dictionary = cfg.air
	var target := Vector2(net_x() + forward(p.side) * float(a.drop_x_from_net), p.pos.y)
	_air(Air.DROP, disc.pos, target, 0.0, p.side, int(a.drop_flight_ticks), float(a.drop_peak))
	_act(p, Act.DROP)
	events.append({"type": "drop", "side": p.side})


func _block(p: PlayerState) -> void:
	var a: Dictionary = cfg.air
	var target := Vector2(p.pos.x + forward(p.side) * float(a.toss_forward), p.pos.y)
	_air(Air.TOSS, disc.pos, target, 0.0, p.side, int(a.toss_flight_ticks), float(a.toss_peak))
	_gain_ex(p, int(cfg.ex.gain_block))
	_act(p, Act.BLOCK)
	events.append({"type": "block", "side": p.side})


## Puts the disc in the air from `from` to `to`; `by` is who sent it there.
func _air(kind: int, from: Vector2, to: Vector2, from_z: float, by: int, flight: int, peak: float) -> void:
	disc.state = Disc.AIR
	disc.air_kind = kind
	disc.air_from = from
	disc.air_to = to
	disc.air_from_z = from_z
	disc.air_tick = 0
	disc.air_flight = maxi(flight, 1)
	disc.air_peak = peak
	disc.thrower = by
	disc.vel = Vector2.ZERO
	disc.curve = 0.0
	disc.pattern = Pattern.NONE
	disc.supersonic = false
	disc.ex = false
	if phase == Phase.SERVE:
		phase = Phase.PLAY
		phase_ticks = 0


func _launch(p: PlayerState, vel: Vector2, speed: float, pattern: int) -> void:
	disc.vel = vel
	disc.curve = 0.0
	disc.pattern = pattern
	disc.pattern_ticks = 0
	disc.knock_mult = 1.0
	disc.ex = false
	disc.z = 0.0
	disc.pos.y = clampf(disc.pos.y, disc_radius(), court_height() - disc_radius())
	disc.state = Disc.FLYING
	disc.thrower = p.side
	disc.speed = speed
	disc.power = float(p.character.power)
	_release(p)


func _release(p: PlayerState) -> void:
	disc.thrower = p.side
	p.holding = false
	p.hold_ticks = 0
	p.serving = false
	if phase == Phase.SERVE:
		phase = Phase.PLAY
		phase_ticks = 0


func _gain_ex(p: PlayerState, amount: int) -> void:
	var was_full := ex_full(p.side)
	p.ex = mini(p.ex + amount, int(cfg.ex.max))
	if not was_full and ex_full(p.side):
		events.append({"type": "ex_ready", "side": p.side})


func _act(p: PlayerState, action: int) -> void:
	p.action = action
	p.action_ticks = 0


func _stick_y(p: PlayerState) -> int:
	if p.history.is_empty():
		return 0
	var code: int = p.history[-1].x
	return 1 if code <= 3 else (-1 if code >= 7 else 0)


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
	for b in barriers:
		var centre := Vector2(b.x, b.y)
		var gap := p.pos - centre
		var reach := b.z + r
		if gap.length() < reach:
			p.pos = centre + (gap.normalized() if gap.length() > 0.0 else Vector2.DOWN) * reach


# --- Points, sets and match ------------------------------------------------

func _award_point(side: int, points: int, reason: String) -> void:
	scores[side] += points
	streak[side] += 1
	streak[1 - side] = 0
	_gain_ex(players[1 - side], int(cfg.ex.gain_conceded))
	events.append({"type": "point", "side": side, "points": points, "reason": reason,
		"pos": disc.pos, "scores": scores.duplicate()})
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
	events.append({"type": "set_end", "set": set_number, "scores": scores.duplicate(),
		"sets_won": sets_won.duplicate()})

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
	streak = [0, 0]
	set_ticks_left = -1 if sudden_death else _set_length_ticks()
	_start_ready(LEFT if set_number % 2 == 1 else RIGHT)


func _finish_match(side: int) -> void:
	winner = side
	phase = Phase.MATCH_OVER
	phase_ticks = 0
	_park_disc()
	events.append({"type": "match_over", "winner": side})


func _reset_players() -> void:
	for p in players:
		p.pos = Vector2(home_x(p.side), court_height() / 2.0)
		p.z = 0.0
		p.vz = 0.0
		p.holding = false
		p.serving = false
		p.hold_ticks = 0
		p.dash_ticks = 0
		p.recovery_ticks = 0
		p.knock_ticks = 0
		p.knock_vel = 0.0
		p.charge = 0
		p.charged = false
		p.action = Act.NONE
		p.history.clear()


## Start of a set: players line up, READY / GO, then the referee tosses in.
func _start_ready(side: int) -> void:
	server = side
	phase = Phase.READY
	phase_ticks = 0
	_reset_players()
	disc.state = Disc.HELD
	disc.owner = side
	disc.rally = 0
	disc.pattern = Pattern.NONE
	disc.pos = Vector2(net_x(), court_height() + 40.0)
	disc.z = 0.0


## The referee at the net lobs the disc to the server's spot.
func _referee_toss() -> void:
	phase = Phase.PLAY
	phase_ticks = 0
	var from := Vector2(net_x(), court_height())
	var to := Vector2(home_x(server) + forward(server) * 40.0, court_height() / 2.0)
	var a: Dictionary = cfg.air
	_air(Air.REF, from, to, 40.0, 1 - server, int(a.ref_flight_ticks), float(a.ref_peak))
	events.append({"type": "go", "set": set_number})


func _give_serve(side: int) -> void:
	var p := players[side]
	disc.state = Disc.HELD
	disc.owner = side
	p.holding = true
	p.serving = true
	p.hold_ticks = 0
	p.dash_ticks = 0
	phase = Phase.SERVE
	phase_ticks = 0
	_update_disc()


func _start_serve(side: int) -> void:
	server = side
	_reset_players()
	disc.rally = 0
	disc.curve = 0.0
	disc.vel = Vector2.ZERO
	disc.supersonic = false
	disc.pattern = Pattern.NONE
	_give_serve(side)


func _park_disc() -> void:
	disc.state = Disc.HELD
	disc.owner = server
	disc.vel = Vector2.ZERO
	disc.curve = 0.0
	disc.z = 0.0
	disc.pattern = Pattern.NONE
	for p in players:
		p.holding = false
		p.knock_ticks = 0
		p.charge = 0


func _set_length_ticks() -> int:
	return int(cfg.match.set_seconds) * 60
