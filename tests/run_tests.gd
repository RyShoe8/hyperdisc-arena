## Headless rules tests. Run from the project folder:
##   godot --headless --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.
extends SceneTree

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")

const IDLE := {"x": 0, "y": 0, "a": false, "b": false}

var balance: Dictionary
var failures := 0
var current := ""


func _init() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	for test in [
		"test_centre_goal_scores_5",
		"test_edge_goal_scores_3",
		"test_defender_catches_disc",
		"test_catch_knocks_light_player_back",
		"test_uncaught_lob_scores_miss_points",
		"test_lob_caught_under_marker",
		"test_conceding_player_serves",
		"test_hold_limit_forces_throw",
		"test_instant_throw_is_supersonic",
		"test_quarter_circle_curves",
		"test_set_ends_at_12_points",
		"test_drawn_set_awards_both",
		"test_tied_match_goes_to_sudden_death",
		"test_cpu_match_is_deterministic",
		"test_cpu_match_finishes",
	]:
		current = test
		call(test)
	print("" if failures == 0 else "")
	print("ALL TESTS PASSED" if failures == 0 else "%d FAILURE(S)" % failures)
	quit(1 if failures > 0 else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL %s: %s" % [current, message])


func new_sim() -> MatchSim:
	var c: Dictionary = balance.characters[2]
	return MatchSim.new(balance, c, c)


## Puts the sim mid-rally with a disc flying from `pos` at `vel`.
func fly(sim: MatchSim, pos: Vector2, vel: Vector2, thrower: int) -> void:
	sim.phase = MatchSim.Phase.PLAY
	for p in sim.players:
		p.holding = false
		p.serving = false
	sim.disc.state = MatchSim.Disc.FLYING
	sim.disc.pos = pos
	sim.disc.vel = vel
	sim.disc.curve = 0.0
	sim.disc.thrower = thrower
	sim.disc.speed = vel.length()
	sim.disc.power = 1.0


func run(sim: MatchSim, ticks: int, left := IDLE, right := IDLE) -> void:
	for i in ticks:
		sim.step([left, right])


func test_centre_goal_scores_5() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, sim.court_height() / 2.0), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10)
	check(sim.scores[MatchSim.RIGHT] == 5, "expected 5, got %d" % sim.scores[MatchSim.RIGHT])


func test_edge_goal_scores_3() -> void:
	var sim := new_sim()
	sim.players[MatchSim.RIGHT].pos = Vector2(600, 500)
	fly(sim, Vector2(960, 60), Vector2(10, 0), MatchSim.LEFT)
	run(sim, 10)
	check(sim.scores[MatchSim.LEFT] == 3, "expected 3, got %d" % sim.scores[MatchSim.LEFT])


func test_defender_catches_disc() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(150, 280)
	fly(sim, Vector2(260, 280), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 12)
	check(p.holding, "left player should be holding the disc")
	check(sim.disc.state == MatchSim.Disc.HELD, "disc should be held")
	check(Array(sim.scores) == [0, 0], "no points expected")


func test_catch_knocks_light_player_back() -> void:
	var light: Dictionary = balance.characters[0]
	var heavy: Dictionary = balance.characters[5]
	var distances := []
	for c in [light, heavy]:
		var sim := MatchSim.new(balance, c, c)
		var p := sim.players[MatchSim.LEFT]
		p.pos = Vector2(200, 280)
		fly(sim, Vector2(300, 280), Vector2(-14, 0), MatchSim.RIGHT)
		run(sim, 30)
		distances.append(200.0 - p.pos.x)
	check(distances[0] > 0.0, "catch should push the catcher back")
	check(distances[0] > distances[1], "light character should slide further than heavy (%s)" % [distances])


func test_uncaught_lob_scores_miss_points() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(450, 40)  # far from the landing spot
	var thrower := sim.players[MatchSim.RIGHT]
	sim.phase = MatchSim.Phase.PLAY
	sim.players[MatchSim.LEFT].holding = false
	thrower.holding = true
	thrower.serving = false
	sim.disc.owner = MatchSim.RIGHT
	sim.disc.state = MatchSim.Disc.HELD
	sim.step([IDLE, {"x": 0, "y": 1, "a": false, "b": true}])
	check(sim.disc.state == MatchSim.Disc.LOB, "B should lob")
	run(sim, int(balance.lob.flight_ticks) + 2)
	check(sim.scores[MatchSim.RIGHT] == int(balance.match.miss_points),
		"expected miss points, got %s" % [sim.scores])


func test_lob_caught_under_marker() -> void:
	var sim := new_sim()
	var thrower := sim.players[MatchSim.RIGHT]
	var receiver := sim.players[MatchSim.LEFT]
	sim.phase = MatchSim.Phase.PLAY
	receiver.holding = false
	thrower.holding = true
	thrower.serving = false
	sim.disc.owner = MatchSim.RIGHT
	sim.step([IDLE, {"x": 0, "y": 0, "a": false, "b": true}])
	receiver.pos = sim.disc.lob_to
	run(sim, int(balance.lob.flight_ticks))
	check(receiver.holding, "receiver standing on the marker should catch the lob")
	check(Array(sim.scores) == [0, 0], "no points expected, got %s" % [sim.scores])


func test_conceding_player_serves() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, 280), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10 + int(balance.match.point_pause_ticks))
	check(sim.phase == MatchSim.Phase.SERVE, "should be back to serve")
	check(sim.players[MatchSim.LEFT].holding, "left player conceded, so left serves")


func test_hold_limit_forces_throw() -> void:
	var sim := new_sim()
	run(sim, int(balance.player.serve_hold_limit_ticks) + 1)
	check(sim.disc.state == MatchSim.Disc.FLYING, "serve should auto-throw at the hold limit")


func test_instant_throw_is_supersonic() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(150, 280)
	fly(sim, Vector2(200, 280), Vector2(-9, 0), MatchSim.RIGHT)
	run(sim, 20)  # catch, then wait out the knockback
	check(p.holding, "should hold the disc")
	p.hold_ticks = 0
	sim.step([{"x": 0, "y": 0, "a": true, "b": false}, IDLE])
	var fast := sim.disc.speed
	check(sim.disc.supersonic, "instant throw should be supersonic")

	var slow_sim := new_sim()
	var q := slow_sim.players[MatchSim.LEFT]
	q.pos = Vector2(150, 280)
	fly(slow_sim, Vector2(200, 280), Vector2(-9, 0), MatchSim.RIGHT)
	run(slow_sim, 20)
	q.hold_ticks = 80
	slow_sim.step([{"x": 0, "y": 0, "a": true, "b": false}, IDLE])
	check(not slow_sim.disc.supersonic, "late throw should not be supersonic")
	check(fast > slow_sim.disc.speed * 1.5, "late throw should be much slower (%.1f vs %.1f)" % [fast, slow_sim.disc.speed])


func test_quarter_circle_curves() -> void:
	var sim := new_sim()
	run(sim, int(balance.match.serve_delay_ticks))
	sim.step([{"x": 0, "y": 1, "a": false, "b": false}, IDLE])
	sim.step([{"x": 1, "y": 1, "a": false, "b": false}, IDLE])
	sim.step([{"x": 1, "y": 0, "a": true, "b": false}, IDLE])
	# Serves are never curved; this checks the serve rule first.
	check(is_zero_approx(sim.disc.curve), "serve should not curve")

	var rally := new_sim()
	var p := rally.players[MatchSim.LEFT]
	p.pos = Vector2(150, 280)
	fly(rally, Vector2(200, 280), Vector2(-9, 0), MatchSim.RIGHT)
	run(rally, 20)
	rally.step([{"x": 0, "y": 1, "a": false, "b": false}, IDLE])
	rally.step([{"x": 1, "y": 1, "a": false, "b": false}, IDLE])
	rally.step([{"x": 1, "y": 0, "a": true, "b": false}, IDLE])
	check(rally.disc.vel.y > 0.0, "2-3-6 curve should start downward")
	check(rally.disc.curve < 0.0, "2-3-6 curve should bend upward")


func test_set_ends_at_12_points() -> void:
	var sim := new_sim()
	sim.scores = [10, 0] as Array[int]
	sim.players[MatchSim.RIGHT].pos = Vector2(600, 500)
	fly(sim, Vector2(960, 60), Vector2(10, 0), MatchSim.LEFT)
	run(sim, 10)
	check(Array(sim.sets_won) == [1, 0], "left should win set 1, got %s" % [sim.sets_won])
	run(sim, int(balance.match.set_pause_ticks) + 1)
	check(sim.set_number == 2 and Array(sim.scores) == [0, 0], "set 2 should start fresh")


func test_drawn_set_awards_both() -> void:
	var sim := new_sim()
	sim.scores = [5, 5] as Array[int]
	sim.set_ticks_left = 1
	run(sim, 1)
	check(Array(sim.sets_won) == [1, 1], "drawn set gives both a set, got %s" % [sim.sets_won])


func test_tied_match_goes_to_sudden_death() -> void:
	var sim := new_sim()
	sim.sets_won = [1, 1] as Array[int]
	sim.set_number = 3
	sim.scores = [4, 4] as Array[int]
	sim.set_ticks_left = 1
	run(sim, 1)
	check(sim.sudden_death, "2-2 after set 3 should go to sudden death")
	run(sim, int(balance.match.set_pause_ticks) + 1)
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, 280), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10)
	check(sim.phase == MatchSim.Phase.MATCH_OVER and sim.winner == MatchSim.RIGHT,
		"first point in sudden death wins")


func cpu_match(seed_value: int, ticks: int) -> MatchSim:
	var sim := MatchSim.new(balance, balance.characters[1], balance.characters[4])
	var a := CpuPlayer.new(MatchSim.LEFT, balance.cpu.hard, seed_value)
	var b := CpuPlayer.new(MatchSim.RIGHT, balance.cpu.normal, seed_value + 1)
	for i in ticks:
		sim.step([a.think(sim), b.think(sim)])
		if sim.phase == MatchSim.Phase.MATCH_OVER:
			break
	return sim


func test_cpu_match_is_deterministic() -> void:
	var one := cpu_match(42, 2000)
	var two := cpu_match(42, 2000)
	check(one.state_hash() == two.state_hash(), "same seed and inputs must give the same state")


func test_cpu_match_finishes() -> void:
	var sim := cpu_match(7, 60 * 60 * 10)
	check(sim.phase == MatchSim.Phase.MATCH_OVER, "a CPU-vs-CPU match should finish within 10 minutes")
	print("cpu match: winner %d, sets %s, ticks %d" % [sim.winner, sim.sets_won, sim.tick])
