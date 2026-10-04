## Computer opponent. It only reads the match state and produces the same
## input Dictionary a human controller would, so the rules never special-case
## the CPU. Tunables come from balance.json "cpu".<difficulty>.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")

var side: int
var params: Dictionary
var rng := RandomNumberGenerator.new()

var _plan: Array[Dictionary] = []
var _hold_wait := -1
var _target := Vector2.ZERO
var _refresh := 0
var _aim_offset := 0.0
var _last_disc_dir := 0


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
	if _hold_wait < 0:
		_hold_wait = rng.randi_range(int(params.hold_min), int(params.hold_max))
	if _hold_wait > 0:
		_hold_wait -= 1
		return _idle()
	_hold_wait = -1

	var fwd := MatchSim.forward(side)
	var roll := rng.randf()
	if roll < float(params.lob_chance):
		return {"x": 0, "y": rng.randi_range(-1, 1), "a": false, "b": true}
	if roll < float(params.lob_chance) + float(params.curve_chance):
		# Quarter-circle 2-3-6 or 8-9-6, then throw on the last frame.
		var up := rng.randf() < 0.5
		var y := -1 if up else 1
		_plan = [
			{"x": fwd, "y": y, "a": false, "b": false},
			{"x": fwd, "y": 0, "a": true, "b": false},
		]
		return {"x": 0, "y": y, "a": false, "b": false}
	return {"x": 0, "y": rng.randi_range(-1, 1), "a": true, "b": false}


func _think_defending(sim: MatchSim, me: MatchSim.PlayerState) -> Dictionary:
	var disc: MatchSim.DiscState = sim.disc
	var incoming := false
	var dir := 0

	if disc.state == MatchSim.Disc.FLYING:
		dir = signi(int(signf(disc.vel.x)))
		incoming = dir == -MatchSim.forward(side)
	if dir != _last_disc_dir:
		_last_disc_dir = dir
		_aim_offset = rng.randf_range(-1.0, 1.0) * float(params.aim_error)

	_refresh -= 1
	if _refresh <= 0:
		_refresh = int(params.reaction_ticks)
		if disc.state == MatchSim.Disc.LOB and disc.thrower != side:
			_target = disc.lob_to
		elif incoming:
			_target = Vector2(sim.home_x(side), _predict_y(sim, me.pos.x) + _aim_offset)
		else:
			_target = Vector2(sim.home_x(side), lerpf(sim.court_height() / 2.0, disc.pos.y, 0.5))

	var delta := _target - me.pos
	var dead_zone := 6.0
	var x := 0 if absf(delta.x) < dead_zone else int(signf(delta.x))
	var y := 0 if absf(delta.y) < dead_zone else int(signf(delta.y))
	var dash := (incoming or disc.state == MatchSim.Disc.LOB) \
		and delta.length() > float(params.dash_distance)
	return {"x": x, "y": y, "a": dash, "b": false}


## Where the disc will cross x = target_x, following wall bounces but
## ignoring curve (the CPU's imperfect read of a curve shot).
func _predict_y(sim: MatchSim, target_x: float) -> float:
	var disc: MatchSim.DiscState = sim.disc
	if is_zero_approx(disc.vel.x):
		return disc.pos.y
	var ticks := (target_x - disc.pos.x) / disc.vel.x
	if ticks < 0:
		return disc.pos.y
	var r := float(sim.cfg.court.disc_radius)
	var span := sim.court_height() - 2.0 * r
	var y := disc.pos.y - r + disc.vel.y * ticks
	y = fposmod(y, 2.0 * span)
	if y > span:
		y = 2.0 * span - y
	return y + r


func _idle() -> Dictionary:
	return {"x": 0, "y": 0, "a": false, "b": false}
