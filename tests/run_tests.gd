## Headless rules tests. Run from the project folder:
##   godot --headless --script res://tests/run_tests.gd
## Exits with code 1 if any test fails.
extends SceneTree

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")
const ControlsScript := preload("res://scripts/game/controls.gd")

const IDLE := {"x": 0, "y": 0, "a": false, "b": false}

var balance: Dictionary
var failures := 0
var current := ""


func _init() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	# A script that fails to compile can't be instantiated; without this guard
	# every test would just log errors and the run would still "pass".
	for script in [MatchSim, CpuPlayer, ControlsScript]:
		if not script.can_instantiate():
			printerr("FAIL: %s does not compile" % script.resource_path)
			quit(1)
			return
	for test in [
		"test_courts_are_bigger_than_before",
		"test_set_opens_with_referee_toss",
		"test_centre_goal_scores_5",
		"test_edge_goal_scores_3",
		"test_reversed_zones_on_tiled",
		"test_stadium_zone_grows_with_streak",
		"test_defender_catches_disc",
		"test_fast_disc_cannot_skip_the_catch_circle",
		"test_catch_knocks_light_player_back",
		"test_uncaught_lob_scores_miss_points",
		"test_lob_caught_under_marker",
		"test_jump_catches_lob_in_the_air",
		"test_smash_from_the_air",
		"test_conceding_player_serves",
		"test_hold_limit_forces_throw",
		"test_instant_throw_is_supersonic",
		"test_quarter_circle_curves",
		"test_block_pops_disc_up",
		"test_uncaught_block_toss_scores_for_opponent",
		"test_slap_returns_disc_instantly",
		"test_drop_shot_lands_behind_net",
		"test_charged_catch_fires_special",
		"test_every_special_crosses_the_court",
		"test_wall_burner_hugs_wall",
		"test_full_ex_gauge_fires_ex_shot",
		"test_power_toss",
		"test_barrier_deflects_disc",
		"test_thrower_can_catch_barrier_rebound",
		"test_special_catch_freezes_game",
		"test_set_ends_at_15_points",
		"test_drawn_set_awards_both",
		"test_tied_match_goes_to_sudden_death",
		"test_cpu_match_is_deterministic",
		"test_cpu_match_finishes",
		"test_cpu_matches_finish_on_every_court",
		"test_stick_snaps_to_8_directions",
		"test_playstation_controllers_detected",
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


func new_sim(court := 0, left := 0, right := 0) -> MatchSim:
	return MatchSim.new(balance, balance.characters[left], balance.characters[right], court)


func press(extra: Dictionary) -> Dictionary:
	var input := IDLE.duplicate()
	input.merge(extra, true)
	return input


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
	sim.disc.pattern = MatchSim.Pattern.NONE
	sim.disc.thrower = thrower
	sim.disc.speed = vel.length()
	sim.disc.power = 1.0
	sim.disc.knock_mult = 1.0


## Gives `side` the disc mid-rally (not a serve), ready to throw.
func hold(sim: MatchSim, side: int) -> MatchSim.PlayerState:
	sim.phase = MatchSim.Phase.PLAY
	for p in sim.players:
		p.holding = false
		p.serving = false
	var p := sim.players[side]
	p.holding = true
	p.hold_ticks = 0
	sim.disc.state = MatchSim.Disc.HELD
	sim.disc.owner = side
	return p


func run(sim: MatchSim, ticks: int, left := IDLE, right := IDLE) -> void:
	for i in ticks:
		sim.step([left, right])


func run_until_serve(sim: MatchSim) -> void:
	for i in 600:
		if sim.phase == MatchSim.Phase.SERVE:
			return
		sim.step([IDLE, IDLE])


func test_courts_are_bigger_than_before() -> void:
	for c in balance.courts:
		check(float(c.width) > 1000.0 and float(c.height) > 560.0,
			"%s should be bigger than the old 1000x560 court" % c.id)


func test_set_opens_with_referee_toss() -> void:
	var sim := new_sim()
	check(sim.phase == MatchSim.Phase.READY, "a set starts in READY")
	run(sim, int(balance.match.ready_ticks))
	check(sim.disc.state == MatchSim.Disc.AIR and sim.disc.air_kind == MatchSim.Air.REF,
		"after READY the referee tosses the disc in")
	run_until_serve(sim)
	check(sim.players[MatchSim.LEFT].holding and sim.players[MatchSim.LEFT].serving,
		"set 1 toss goes to the left player as a serve")
	check(Array(sim.scores) == [0, 0], "the referee toss never scores")


func test_centre_goal_scores_5() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, sim.court_height() / 2.0), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10)
	check(sim.scores[MatchSim.RIGHT] == 5, "expected 5, got %d" % sim.scores[MatchSim.RIGHT])


func test_edge_goal_scores_3() -> void:
	var sim := new_sim()
	sim.players[MatchSim.RIGHT].pos = Vector2(sim.court_width() - 400, sim.court_height() - 60)
	fly(sim, Vector2(sim.court_width() - 40, 60), Vector2(10, 0), MatchSim.LEFT)
	run(sim, 10)
	check(sim.scores[MatchSim.LEFT] == 3, "expected 3, got %d" % sim.scores[MatchSim.LEFT])


func test_reversed_zones_on_tiled() -> void:
	var sim := new_sim(2)
	check(sim.court.id == "tiled", "court 2 is Tiled")
	check(sim.zone_points(20.0) == 5, "Tiled edges are worth 5")
	check(sim.zone_points(sim.court_height() / 2.0) == 3, "Tiled middle is worth 3")


func test_stadium_zone_grows_with_streak() -> void:
	var sim := new_sim(5)
	var y := sim.court_height() * 0.36
	check(sim.zone_points(y, MatchSim.RIGHT) == 3, "the stadium 5-zone starts small")
	sim.streak = [3, 0] as Array[int]
	check(sim.zone_points(y, MatchSim.RIGHT) == 5, "three straight points grow the 5-zone")
	check(sim.zone_points(y, MatchSim.LEFT) == 3, "only the scorer's target zone grows")


func test_defender_catches_disc() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(150, 300)
	fly(sim, Vector2(260, 300), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 12)
	check(p.holding, "left player should be holding the disc")
	check(sim.disc.state == MatchSim.Disc.HELD, "disc should be held")
	check(Array(sim.scores) == [0, 0], "no points expected")


func test_fast_disc_cannot_skip_the_catch_circle() -> void:
	# A 40-unit-per-tick disc clipping the edge of the catch circle: checked
	# only at the end of each tick it would land either side of the circle.
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	var r := float(balance.player.catch_radius)
	p.pos = Vector2(300, 300)
	fly(sim, Vector2(360, 300 + r - 3), Vector2(-40, 0), MatchSim.RIGHT)  # samples at x=320 and 280 both miss
	run(sim, 3)
	check(p.holding, "a fast disc passing through the edge of the catch circle is caught")


func test_catch_knocks_light_player_back() -> void:
	var distances := []
	for c in [1, 5]:  # Tiffany (light) vs Power B (heavy)
		var sim := new_sim(0, c, c)
		var p := sim.players[MatchSim.LEFT]
		p.pos = Vector2(220, 300)
		fly(sim, Vector2(320, 300), Vector2(-16, 0), MatchSim.RIGHT)
		run(sim, 40)
		distances.append(220.0 - p.pos.x)
	check(distances[0] > 0.0, "catch should push the catcher back")
	check(distances[0] > distances[1], "light character should slide further than heavy (%s)" % [distances])


func test_uncaught_lob_scores_miss_points() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(500, 40)  # far from the landing spot
	hold(sim, MatchSim.RIGHT)
	sim.step([IDLE, press({"b": true, "y": 1})])
	check(sim.disc.state == MatchSim.Disc.AIR, "B should lob")
	run(sim, int(balance.air.lob_flight_ticks) + 2)
	check(sim.scores[MatchSim.RIGHT] == int(balance.match.miss_points),
		"expected miss points, got %s" % [sim.scores])


func test_lob_caught_under_marker() -> void:
	var sim := new_sim()
	var receiver := sim.players[MatchSim.LEFT]
	hold(sim, MatchSim.RIGHT)
	sim.step([IDLE, press({"b": true})])
	receiver.pos = sim.disc.air_to
	run(sim, int(balance.air.lob_flight_ticks))
	check(receiver.holding, "receiver standing on the marker should catch the lob")
	check(receiver.charged, "standing under the lob should charge a special")
	check(Array(sim.scores) == [0, 0], "no points expected, got %s" % [sim.scores])


func test_jump_catches_lob_in_the_air() -> void:
	var sim := new_sim()
	var receiver := sim.players[MatchSim.LEFT]
	hold(sim, MatchSim.RIGHT)
	sim.step([IDLE, press({"b": true})])
	# Wait until the lob is coming down over the receiver at jump height.
	var caught_in_air := false
	for i in int(balance.air.lob_flight_ticks):
		receiver.pos = sim.disc.pos
		var jump := sim.disc.z < 140.0 and sim.disc.z > 60.0 and receiver.z <= 0.0 \
			and sim.disc.air_tick > sim.disc.air_flight / 2
		sim.step([press({"jump": jump}), IDLE])
		if receiver.holding:
			caught_in_air = receiver.z > 0.0
			break
	check(receiver.holding, "a jumping player should catch the lob")
	check(caught_in_air, "the catch should happen in the air")


func test_smash_from_the_air() -> void:
	var sim := new_sim()
	var p := hold(sim, MatchSim.LEFT)
	p.z = 40.0
	p.vz = 2.0
	sim.step([press({"a": true}), IDLE])
	check(sim.disc.state == MatchSim.Disc.FLYING, "A in the air should smash")
	var normal := float(balance.throw.base_speed) * float(p.character.power)
	check(sim.disc.speed > normal * 1.2, "a smash is faster than a normal throw")


func test_conceding_player_serves() -> void:
	var sim := new_sim()
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, 300), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10 + int(balance.match.point_pause_ticks))
	check(sim.phase == MatchSim.Phase.SERVE, "should be back to serve")
	check(sim.players[MatchSim.LEFT].holding, "left player conceded, so left serves")


func test_hold_limit_forces_throw() -> void:
	var sim := new_sim()
	run_until_serve(sim)
	run(sim, int(balance.player.serve_hold_limit_ticks) + 1)
	check(sim.disc.state == MatchSim.Disc.FLYING, "serve should auto-throw at the hold limit")


func test_instant_throw_is_supersonic() -> void:
	var sim := new_sim()
	hold(sim, MatchSim.LEFT)
	sim.step([press({"a": true}), IDLE])
	var fast := sim.disc.speed
	check(sim.disc.supersonic, "instant throw should be supersonic")

	var slow_sim := new_sim()
	var q := hold(slow_sim, MatchSim.LEFT)
	q.hold_ticks = 80
	slow_sim.step([press({"a": true}), IDLE])
	check(not slow_sim.disc.supersonic, "late throw should not be supersonic")
	check(fast > slow_sim.disc.speed * 1.5, "late throw should be much slower (%.1f vs %.1f)" % [fast, slow_sim.disc.speed])


func test_quarter_circle_curves() -> void:
	var sim := new_sim()
	run_until_serve(sim)
	run(sim, int(balance.match.serve_delay_ticks))
	sim.step([press({"y": 1}), IDLE])
	sim.step([press({"x": 1, "y": 1}), IDLE])
	sim.step([press({"x": 1, "a": true}), IDLE])
	check(is_zero_approx(sim.disc.curve), "serve should not curve")

	var rally := new_sim()
	hold(rally, MatchSim.LEFT)
	rally.step([press({"y": 1}), IDLE])
	rally.step([press({"x": 1, "y": 1}), IDLE])
	rally.step([press({"x": 1, "a": true}), IDLE])
	check(rally.disc.vel.y > 0.0, "2-3-6 curve should start downward")
	check(rally.disc.curve < 0.0, "2-3-6 curve should bend upward")


func test_block_pops_disc_up() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(200, 300)
	fly(sim, Vector2(280, 300), Vector2(-12, 0), MatchSim.RIGHT)
	sim.step([press({"a": true}), IDLE])
	check(sim.disc.state == MatchSim.Disc.AIR and sim.disc.air_kind == MatchSim.Air.TOSS,
		"A standing still as the disc arrives blocks it into the air")
	run(sim, int(balance.air.toss_flight_ticks))
	check(p.holding, "the blocker standing still catches their own toss")
	check(p.charged, "and is charged for a special")


func test_uncaught_block_toss_scores_for_opponent() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(200, 300)
	fly(sim, Vector2(280, 300), Vector2(-12, 0), MatchSim.RIGHT)
	sim.step([press({"a": true}), IDLE])
	run(sim, int(balance.air.toss_flight_ticks) + 2, press({"y": 1}))
	check(sim.scores[MatchSim.RIGHT] == int(balance.match.miss_points),
		"a toss landing on your own side gives the opponent 2 (got %s)" % [sim.scores])


func test_slap_returns_disc_instantly() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(200, 300)
	fly(sim, Vector2(290, 300), Vector2(-14, 0), MatchSim.RIGHT)
	sim.step([press({"slap": true}), IDLE])
	check(not p.holding, "a slap never catches")
	check(sim.disc.state == MatchSim.Disc.FLYING and sim.disc.thrower == MatchSim.LEFT
		and sim.disc.vel.x > 0.0, "the slap sends the disc straight back")


func test_drop_shot_lands_behind_net() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(200, 300)
	sim.players[MatchSim.RIGHT].pos = Vector2(sim.court_width() - 60, 40)
	fly(sim, Vector2(290, 300), Vector2(-14, 0), MatchSim.RIGHT)
	sim.step([press({"b": true}), IDLE])
	check(sim.disc.state == MatchSim.Disc.AIR and sim.disc.air_kind == MatchSim.Air.DROP, "B as the disc arrives is a drop shot")
	check(sim.disc.air_to.x > sim.net_x() and sim.disc.air_to.x < sim.net_x() + 150.0,
		"the drop lands just over the net")
	run(sim, int(balance.air.drop_flight_ticks) + 2)
	check(sim.scores[MatchSim.LEFT] == int(balance.match.miss_points), "an unanswered drop shot scores 2")


func test_charged_catch_fires_special() -> void:
	var sim := new_sim()
	var receiver := sim.players[MatchSim.LEFT]
	hold(sim, MatchSim.RIGHT)
	sim.step([IDLE, press({"b": true})])
	receiver.pos = sim.disc.air_to
	run(sim, int(balance.air.lob_flight_ticks))
	check(receiver.charged, "should be charged")
	sim.step([press({"a": true}), IDLE])
	check(sim.disc.pattern == MatchSim.Pattern.LOOP, "Mick's special is the Danger Zone loop")
	check(sim.freeze_ticks > 0, "a special launch freezes the game for a beat")
	check(not receiver.charged, "the charge is spent")


func test_every_special_crosses_the_court() -> void:
	for i in balance.characters.size():
		var sim := new_sim(1, i, 0)
		var p := hold(sim, MatchSim.LEFT)
		p.charged = true
		sim.players[MatchSim.RIGHT].pos = Vector2(sim.court_width() - 30, 30)  # out of the way
		sim.step([press({"a": true}), IDLE])
		var crossed := false
		for t in 400:
			sim.step([IDLE, IDLE])
			if sim.scores[MatchSim.LEFT] > 0:
				crossed = true
				break
		check(crossed, "%s's special should reach the far goal" % balance.characters[i].id)


func test_wall_burner_hugs_wall() -> void:
	var sim := new_sim(1, 3, 0)  # Speed B throws the wall burner
	var p := hold(sim, MatchSim.LEFT)
	p.pos.y = 200.0
	p.charged = true
	sim.players[MatchSim.RIGHT].pos = Vector2(sim.court_width() - 30, sim.court_height() - 30)
	sim.step([press({"a": true, "y": -1}), IDLE])
	var on_wall := 0
	for t in 120:
		sim.step([IDLE, IDLE])
		if sim.disc.state != MatchSim.Disc.FLYING:
			break
		if sim.disc.pos.y <= sim.disc_radius() + 0.5:
			on_wall += 1
	check(on_wall > 10, "the wall burner should run along the top wall (%d ticks)" % on_wall)


func test_full_ex_gauge_fires_ex_shot() -> void:
	var sim := new_sim()
	var p := hold(sim, MatchSim.LEFT)
	p.ex = int(balance.ex.max)
	sim.step([press({"slap": true}), IDLE])
	check(sim.disc.ex and sim.disc.pattern != MatchSim.Pattern.NONE, "slap with a full gauge fires the EX shot")
	check(p.ex == 0, "the EX shot empties the gauge")
	check(sim.disc.knock_mult >= float(balance.special.ex_knock_mult), "EX shots hit hardest")


func test_power_toss() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(150, 300)
	p.ex = int(balance.ex.max)
	fly(sim, Vector2(400, 300), Vector2(-12, 0), MatchSim.RIGHT)
	sim.step([press({"a": true, "b_down": true}), IDLE])
	check(sim.disc.state == MatchSim.Disc.AIR and sim.disc.air_kind == MatchSim.Air.TOSS, "A+B flips the disc up")
	check(p.ex == 0, "power toss spends the gauge")


func test_barrier_deflects_disc() -> void:
	var sim := new_sim(4)
	check(sim.barriers.size() == 2, "Clay has two barriers")
	var b := sim.barriers[0]
	sim.players[MatchSim.LEFT].pos = Vector2(60, 40)
	fly(sim, Vector2(b.x + 120, b.y), Vector2(-12, 0), MatchSim.RIGHT)
	run(sim, 12)
	check(sim.disc.vel.x > 0.0, "a disc hitting a barrier head-on bounces back")


func test_thrower_can_catch_barrier_rebound() -> void:
	var sim := new_sim(4)
	var b := sim.barriers[0]
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(b.x - 160, b.y)
	fly(sim, Vector2(b.x - 100, b.y), Vector2(12, 0), MatchSim.LEFT)
	run(sim, 30)
	check(p.holding, "a serve that bounces straight back off a barrier can be caught by the thrower")
	check(Array(sim.scores) == [0, 0], "no own goal (got %s)" % [sim.scores])


func test_special_catch_freezes_game() -> void:
	var sim := new_sim()
	var p := sim.players[MatchSim.LEFT]
	p.pos = Vector2(200, 300)
	fly(sim, Vector2(260, 300), Vector2(-14, 0), MatchSim.RIGHT)
	sim.disc.pattern = MatchSim.Pattern.CANNON
	sim.disc.knock_mult = 2.0
	run(sim, 6)
	check(p.holding, "special caught")
	check(sim.freeze_ticks > 0, "catching a special triggers hit-stop")


func test_set_ends_at_15_points() -> void:
	var sim := new_sim()
	sim.scores = [12, 0] as Array[int]
	sim.players[MatchSim.RIGHT].pos = Vector2(sim.court_width() - 400, sim.court_height() - 40)
	fly(sim, Vector2(sim.court_width() - 40, 60), Vector2(10, 0), MatchSim.LEFT)
	run(sim, 10)
	check(Array(sim.sets_won) == [1, 0], "left should win set 1 at 15, got %s" % [sim.sets_won])
	run(sim, int(balance.match.set_pause_ticks) + 1)
	check(sim.set_number == 2 and Array(sim.scores) == [0, 0], "set 2 should start fresh")
	check(sim.phase == MatchSim.Phase.READY, "set 2 opens with READY")

	var close := new_sim()
	close.scores = [10, 12] as Array[int]
	close.players[MatchSim.RIGHT].pos = Vector2(close.court_width() - 400, close.court_height() - 40)
	fly(close, Vector2(close.court_width() - 40, 60), Vector2(10, 0), MatchSim.LEFT)
	run(close, 10)
	check(Array(close.sets_won) == [0, 0], "13-12 is not a set win")


func test_drawn_set_awards_both() -> void:
	var sim := new_sim()
	run_until_serve(sim)
	sim.scores = [5, 5] as Array[int]
	sim.set_ticks_left = 1
	run(sim, 1)
	check(Array(sim.sets_won) == [1, 1], "drawn set gives both a set, got %s" % [sim.sets_won])


func test_tied_match_goes_to_sudden_death() -> void:
	var sim := new_sim()
	run_until_serve(sim)
	sim.sets_won = [1, 1] as Array[int]
	sim.set_number = 3
	sim.scores = [4, 4] as Array[int]
	sim.set_ticks_left = 1
	run(sim, 1)
	check(sim.sudden_death, "2-2 after set 3 should go to sudden death")
	run(sim, int(balance.match.set_pause_ticks) + 1)
	sim.players[MatchSim.LEFT].pos = Vector2(400, 50)
	fly(sim, Vector2(40, 300), Vector2(-10, 0), MatchSim.RIGHT)
	run(sim, 10)
	check(sim.phase == MatchSim.Phase.MATCH_OVER and sim.winner == MatchSim.RIGHT,
		"first point in sudden death wins")


func cpu_match(seed_value: int, ticks: int, court := 0) -> MatchSim:
	var sim := MatchSim.new(balance, balance.characters[seed_value % 6],
		balance.characters[(seed_value + 3) % 6], court)
	var a := CpuPlayer.new(MatchSim.LEFT, balance.cpu.hard, seed_value)
	var b := CpuPlayer.new(MatchSim.RIGHT, balance.cpu.normal, seed_value + 1)
	for i in ticks:
		sim.step([a.think(sim), b.think(sim)])
		if sim.phase == MatchSim.Phase.MATCH_OVER:
			break
	return sim


func test_cpu_match_is_deterministic() -> void:
	var one := cpu_match(42, 3000)
	var two := cpu_match(42, 3000)
	check(one.state_hash() == two.state_hash(), "same seed and inputs must give the same state")


func test_cpu_match_finishes() -> void:
	var sim := cpu_match(7, 60 * 60 * 12)
	check(sim.phase == MatchSim.Phase.MATCH_OVER, "a CPU-vs-CPU match should finish within 12 minutes")
	print("cpu match: winner %d, sets %s, ticks %d" % [sim.winner, sim.sets_won, sim.tick])


func test_cpu_matches_finish_on_every_court() -> void:
	for court in balance.courts.size():
		var sim := cpu_match(100 + court, 60 * 60 * 12, court)
		check(sim.phase == MatchSim.Phase.MATCH_OVER, "CPU match on %s should finish" % balance.courts[court].id)
		print("  %s: winner %d sets %s in %ds" % [balance.courts[court].id, sim.winner, sim.sets_won, sim.tick / 60])


func test_stick_snaps_to_8_directions() -> void:
	var cases := {
		Vector2(1, 0): Vector2i(1, 0),
		Vector2(0.9, 0.45): Vector2i(1, 1),  # 26 degrees: diagonal wins over a strict axis check
		Vector2(0.95, 0.2): Vector2i(1, 0),
		Vector2(-0.7, -0.7): Vector2i(-1, -1),
		Vector2(0, -1): Vector2i(0, -1),
		Vector2(-0.3, 0.95): Vector2i(0, 1),
		Vector2.ZERO: Vector2i.ZERO,
	}
	for v in cases:
		var got := ControlsScript.snap8(v)
		check(got == cases[v], "snap8(%s) = %s, expected %s" % [v, got, cases[v]])


func test_playstation_controllers_detected() -> void:
	# Browser ids, desktop (SDL) names and the Sony vendor id all count.
	check(ControlsScript.looks_like_playstation(
		"Standard Gamepad Mapping DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)"),
		"DualSense in a browser")
	check(ControlsScript.looks_like_playstation("PS5 Controller"), "DualSense on desktop")
	check(ControlsScript.looks_like_playstation("Standard Gamepad Mapping", 0x054C), "any Sony vendor id")
	check(not ControlsScript.looks_like_playstation("Xbox Series X Controller", 0x045E), "Xbox pad")
	check(not ControlsScript.looks_like_playstation("Standard Gamepad Mapping"), "unknown pad")
