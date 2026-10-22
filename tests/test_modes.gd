extends SceneTree

const Sim = preload("res://scripts/sim/match_sim.gd")
const CPU = preload("res://scripts/sim/cpu_player.gd")
const Link = preload("res://scripts/net/loopback_transport.gd")
const Match = preload("res://scripts/net/online_match.gd")
var failures := 0
var balance: Dictionary

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)

func doubles(court := 0):
	return Sim.new(balance, balance.characters[0], balance.characters[1], court, [balance.characters[4], balance.characters[5]])

func _run() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var sim = doubles()
	check(sim.players.size() == 4, "four independent players")
	check(sim.players[2].side == 0 and sim.players[3].side == 1, "teammates share court sides")
	check(sim.players[0].pos != sim.players[2].pos, "teammates spawn in different lanes")
	sim.phase = Sim.Phase.PLAY
	sim.disc.state = Sim.Disc.FLYING
	sim.disc.thrower = 1
	sim.disc.pos = sim.players[2].pos + Vector2(50, 0)
	sim.disc.vel = Vector2(-10, 0)
	sim.step([{}, {}, {}, {}])
	check(sim.players[2].holding and sim.disc.owner == 2, "partner catches and owns disc independently")
	sim.players[2].knock_ticks = 0
	sim.freeze_ticks = 0
	sim.step([{}, {}, {"a": true}, {}])
	check(sim.disc.thrower == 0 and sim.disc.thrower_slot == 2, "partner throws toward opponent as Team A")
	check(sim.players[2].ex > 0 and sim.players[0].ex == 0, "power belongs to individual player")
	var saved: Dictionary = sim.save_state()
	var inputs := []
	for t in 120:
		var step := [{}, {}, {"y": t % 3 - 1}, {"x": t % 3 - 1}]
		inputs.append(step)
		sim.step(step)
	var sum: int = sim.state_checksum()
	sim.load_state(saved)
	for step in inputs:
		sim.step(step)
	check(sum == sim.state_checksum(), "doubles snapshots replay identically")
	for court in balance.courts.size():
		sim = doubles(court)
		var cpus := []
		for slot in 4:
			cpus.append(CPU.new(slot, balance.cpu.hard, 17 + slot))
		for t in 40000:
			var step := []
			for cpu in cpus:
				step.append(cpu.think(sim))
			sim.step(step)
			if sim.phase == Sim.Phase.MATCH_OVER:
				break
		check(sim.winner >= 0, "CPU doubles finishes on court %d" % court)
	var link: Array = Link.pair(4, 3, 0.06, 42)
	var host = Match.new(link[0], balance, true, "HOST")
	var guest = Match.new(link[1], balance, false, "GUEST")
	var peers := [host, guest]
	var configured := false
	var started := false
	for t in 2800:
		for side in 2:
			link[side].advance()
			peers[side].poll({"y": t % 3 - 1, "a": t % 17 == 0, "partner": {"x": t % 3 - 1, "jump": t % 31 == 0, "curve_high": t % 19 == 0}})
		if not configured and host.state == Match.State.LOBBY and guest.state == Match.State.LOBBY:
			host.configure_team(true, 4, true)
			guest.configure_team(true, 5, false)
			host.set_pick(0, true)
			guest.set_pick(1, true)
			configured = true
		if configured and not started and guest.doubles and not guest.local_locked:
			guest.set_pick(1, true)
		if not started and host.can_start() and host.remote_partner_pick == 5:
			host.start()
			started = true
	check(host.sim != null and guest.sim != null, "doubles lobby starts")
	if host.sim != null and guest.sim != null:
		check(host.sim.players.size() == 4 and guest.sim.players.size() == 4, "both peers use doubles")
		check(host.sim.players[2].character.id == guest.sim.players[2].character.id and host.sim.players[3].character.id == guest.sim.players[3].character.id, "all four character picks agree")
		check(not host.session.desynced and not guest.session.desynced, "doubles rollback stays synchronized with loss and jitter")
		var common: int = mini(host.session.last_remote_frame, guest.session.last_remote_frame)
		var f: int = (common / 60) * 60
		check(host.session.states.has(f) and guest.session.states.has(f), "both retained confirmed frame")
		if host.session.states.has(f) and guest.session.states.has(f):
			check(var_to_str(host.session.states[f]) == var_to_str(guest.session.states[f]), "confirmed doubles states match exactly")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	check(game._main_items() == ["STORY", "VS", "ONLINE", "TUTORIAL", "MIXTAPES", "OPTIONS", "QUIT"], "approved menu order")
	game.doubles = true
	game.pick.assign([0, 1])
	game._start_match()
	check(game.sim.players.size() == 4 and game.view.arts.size() == 4, "local doubles creates all four fighters")
	for t in 120:
		game._match_tick()
	game.story_round = 0
	var easy: Dictionary = game._story_difficulty()
	game.story_round = 4
	var later: Dictionary = game._story_difficulty()
	check(later.reaction_ticks < easy.reaction_ticks and later.aim_error < easy.aim_error and later.ex_chance > easy.ex_chance, "story difficulty improves reactions, accuracy and decisions")
	# Isolated save path keeps the user's actual Story run untouched.
	game.story_save_path = "res://.godot/test_story_progress.cfg"
	game.story_fighter = 0
	game.story_order.assign([1, 2, 3, 4, 5])
	game.story_round = 1
	game._save_story(2)
	game.story_round = 0
	check(game._load_story() and game.story_round == 2, "Story resumes the next opponent after a win")
	game.story_round = 1
	game._save_story()
	check(game._load_story() and game.story_round == 1, "Story preserves opponent for retry after loss")
	game._save_story(5)
	check(not game._load_story(), "finished Story does not resume beyond the roster")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game.story_save_path))
	game.story = false
	var controls = root.get_node("Controls")
	var original_pads: Array = controls.pads.duplicate()
	var devices := [1000, 1001, 1002, 1003]
	game._go(game.Screen.MAIN)
	for device in devices:
		controls.set_virtual_pad(device, "DualSense Wireless Controller", Vector2.ZERO, {})
	controls.pads.assign(devices)
	controls._physics_process(0.0)
	game.tutorial.open(3, devices[3])
	check(controls.pads[0] == devices[3] and controls.pads[3] == devices[0], "tutorial adopts selecting controller from slot four without duplicates")
	game.tutorial.ready = false
	game.tutorial.countdown = 0
	controls.set_virtual_pad(devices[3], "DualSense Wireless Controller", Vector2.UP, {JOY_BUTTON_A: true})
	controls._physics_process(0.0)
	game.tutorial.tick()
	check(not game.tutorial.session.sim.players[0].holding, "adopted controller can throw in tutorial")
	controls.set_virtual_pad(devices[3], "DualSense Wireless Controller", Vector2.ZERO, {})
	controls._physics_process(0.0)
	controls.pads.assign(devices)
	controls._physics_process(0.0)
	game.tutorial.open(0)
	game.tutorial.settled = 16
	controls.set_virtual_pad(devices[2], "DualSense Wireless Controller", Vector2.ZERO, {JOY_BUTTON_A: true})
	controls._physics_process(0.0)
	game.tutorial.tick()
	check(controls.pads[0] == devices[2] and not game.tutorial.ready, "Start Drill adopts a different controller at the ready screen")
	controls.set_virtual_pad(devices[2], "DualSense Wireless Controller", Vector2.RIGHT, {})
	controls._physics_process(0.0)
	game.tutorial.countdown = 0
	var before: float = game.tutorial.session.sim.players[0].pos.x
	game.tutorial.tick()
	check(game.tutorial.session.sim.players[0].pos.x > before, "adopted controller can move during drill")
	game._go(game.Screen.MAIN)
	for device in devices:
		controls.remove_virtual_pad(device)
	controls.pads.assign(original_pads)
	controls._physics_process(0.0)
	game._start_match()
	if "--visual" in OS.get_cmdline_user_args():
		var folder := ProjectSettings.globalize_path("res://.godot/mode_previews")
		DirAccess.make_dir_recursive_absolute(folder)
		for screen in [game.Screen.MAIN, game.Screen.SETUP, game.Screen.STORY_MENU, game.Screen.DOUBLES_GUIDE, game.Screen.MATCH]:
			game._go(screen)
			game.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder + "/screen_%d.png" % screen)
	for player in root.get_node("Sfx").get_children():
		if player is AudioStreamPlayer or player is AudioStreamPlayer2D:
			player.stop()
	game.queue_free()
	await process_frame
	print("MODE TESTS PASSED" if failures == 0 else "%d MODE TESTS FAILED" % failures)
	quit(0 if failures == 0 else 1)

