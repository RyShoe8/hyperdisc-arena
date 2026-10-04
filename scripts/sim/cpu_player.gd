## Computer opponent. It only reads the match state and produces the same
## input Dictionary a human controller would, so the rules never special-case
## the CPU. Tunables come from balance.json "cpu".<difficulty>.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")

enum Defence { NONE, SLAP, BLOCK, DROP, POWER_TOSS }

var side: int
var params: Dictionary
var rng := RandomNumberGenerator.new()

var _plan: Array[Dictionary] = []
var _hold_wait := -1
var _target := Vector2.ZERO
var _refresh := 0
var _aim_offset := 0.0
## Decisions are rolled once per incoming disc, keyed by its identity.
var _disc_key := ""
var _defence: int = Defence.NONE
var _will_jump := false


func _init(cpu_side: int, difficulty: Dictionary, seed_value: int = 1) -> void:
	side = cpu_side
	params = difficulty
	rng.seed = seed_value


func think(sim: MatchSim) -> Dictionary:
	var me: MatchSim.PlayerState = sim.players[side]
	if sim.phase != MatchSim.Phase.SERVE and sim.phase != MatchSim.Phase.PLAY:
		_plan.clear()
		_hold_wait = -1
		return _idle()

	if not _plan.is_empty():
		return _plan.pop_front()

	if me.holding:
		return _think_holding(sim, me)
	_hold_wait = -1
	return _think_defending(sim, me)


func _think_holding(sim: MatchSim, me: MatchSim.PlayerState) -> Dictionary:
	if me.knock_ticks > 0:
		return _idle()
	if me.z > 0.0:
		return _press({"a": true, "y": rng.randi_range(-1, 1)})  # smash from the air
	if _hold_wait < 0:
		_hold_wait = rng.randi_range(int(params.hold_min), int(params.hold_max))
	if _hold_wait > 0:
		_hold_wait -= 1
		return _idle()
	_hold_wait = -1

	var fwd := MatchSim.forward(side)
	var aim := rng.randi_range(-1, 1)
	if sim.ex_full(side) and rng.randf() < float(params.ex_chance):
		return _press({"slap": true, "y": aim})
	if me.charged and rng.randf() < float(params.special_chance):
		return _press({"a": true, "y": aim})
	var roll := rng.randf()
	if roll < float(params.lob_chance):
		return _press({"b": true, "y": aim})
	if roll < float(params.lob_chance) + float(params.curve_chance):
		# Quarter-circle 2-3-6 or 8-9-6, then throw on the last frame.
		var y := -1 if rng.randf() < 0.5 else 1
		_plan = [
			{"x": fwd, "y": y, "a": false, "b": false},
			{"x": fwd, "y": 0, "a": true, "b": false},
		]
		return {"x": 0, "y": y, "a": false, "b": false}
	return _press({"a": true, "y": aim})


func _think_defending(sim: MatchSim, me: MatchSim.PlayerState) -> Dictionary:
	var disc: MatchSim.DiscState = sim.disc
	var incoming := disc.state == MatchSim.Disc.FLYING and disc.thrower != side
	var air_to_me := disc.state == MatchSim.Disc.AIR and sim.side_of(disc.air_to.x) == side \
		and (disc.thrower != side or disc.air_kind == MatchSim.Air.TOSS or disc.air_kind == MatchSim.Air.REF)
	_roll_decisions(disc)

	if incoming:
		var dist := me.pos.distance_to(disc.pos)
		var d: Dictionary = sim.cfg.defence
		match _defence:
			Defence.POWER_TOSS:
				if sim.ex_full(side) and dist <= float(d.power_toss_radius) and sim.side_of(disc.pos.x) == side:
					_defence = Defence.NONE
					return _press({"a": true, "b_down": true})
			Defence.SLAP:
				if dist <= float(d.slap_radius) * 0.9:
					_defence = Defence.NONE
					return _press({"slap": true, "x": -MatchSim.forward(side) * rng.randi_range(0, 1),
						"y": rng.randi_range(-1, 1)})
			Defence.DROP:
				if dist <= float(d.slap_radius) * 0.9:
					_defence = Defence.NONE
					return _press({"b": true})
			Defence.BLOCK:
				if dist <= float(d.block_radius) * 0.85:
					_defence = Defence.NONE
					return _press({"a": true})

	if air_to_me and _will_jump and me.z <= 0.0:
		# Jump to snatch a lob before it lands, when it passes overhead.
		if me.pos.distance_to(disc.pos) < float(sim.cfg.player.catch_radius) \
				and disc.z > 50.0 and disc.z < 150.0:
			_will_jump = false
			return _press({"jump": true})

	_refresh -= 1
	if _refresh <= 0:
		_refresh = int(params.reaction_ticks)
		if air_to_me:
			_target = disc.air_to if not _will_jump else disc.pos.lerp(disc.air_to, 0.5)
		elif incoming:
			_target = Vector2(sim.home_x(side), _predict_y(sim, me.pos.x) + _aim_offset)
		else:
			_target = Vector2(sim.home_x(side), lerpf(sim.court_height() / 2.0, disc.pos.y, 0.5))

	var delta := _target - me.pos
	var dead_zone := 6.0
	var x := 0 if absf(delta.x) < dead_zone else int(signf(delta.x))
	var y := 0 if absf(delta.y) < dead_zone else int(signf(delta.y))
	var dash := (incoming or air_to_me) and delta.length() > float(params.dash_distance)
	return {"x": x, "y": y, "a": dash, "b": false}


func _roll_decisions(disc: MatchSim.DiscState) -> void:
	var key := "%d:%d:%d" % [disc.rally, disc.state, disc.thrower]
	if key == _disc_key:
		return
	_disc_key = key
	_aim_offset = rng.randf_range(-1.0, 1.0) * float(params.aim_error)
	_defence = Defence.NONE
	_will_jump = disc.state == MatchSim.Disc.AIR and rng.randf() < float(params.jump_chance)
	if disc.state != MatchSim.Disc.FLYING or disc.thrower == side:
		return
	var roll := rng.randf()
	var chances := [
		[Defence.POWER_TOSS, float(params.power_toss_chance)],
		[Defence.SLAP, float(params.slap_chance)],
		[Defence.BLOCK, float(params.block_chance)],
		[Defence.DROP, float(params.drop_chance)],
	]
	for c in chances:
		if roll < c[1]:
			_defence = c[0]
			return
		roll -= c[1]


## Where the disc will cross x = target_x, following wall bounces but
## ignoring curve and special paths (the CPU's imperfect read).
func _predict_y(sim: MatchSim, target_x: float) -> float:
	var disc: MatchSim.DiscState = sim.disc
	if is_zero_approx(disc.vel.x):
		return disc.pos.y
	var ticks := (target_x - disc.pos.x) / disc.vel.x
	if ticks < 0:
		return disc.pos.y
	var r := sim.disc_radius()
	var span := sim.court_height() - 2.0 * r
	var y := disc.pos.y - r + disc.vel.y * ticks
	y = fposmod(y, 2.0 * span)
	if y > span:
		y = 2.0 * span - y
	return y + r


func _press(extra: Dictionary) -> Dictionary:
	var input := _idle()
	input.merge(extra, true)
	return input


func _idle() -> Dictionary:
	return {"x": 0, "y": 0, "a": false, "b": false}
