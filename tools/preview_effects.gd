## Deterministic rendered fixture: all six players, vertical turns, ref and crowds.
extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	root.get_node("Settings").shake=0
	DirAccess.make_dir_recursive_absolute("res://build/effects-preview")
	for pair in 1:
		game.court=[0,2,5][pair]
		game.pick.assign([pair*2,pair*2+1])
		game._start_match()
		game.sim.phase=game.MatchSim.Phase.PLAY
		game.sim.disc.state=game.MatchSim.Disc.FLYING
		game.sim.disc.vel=Vector2(23,0)
		for p in game.sim.players:
			p.holding=false
			p.action_ticks=100
		game.view.overlay={}
		for tick in 180:
			for side in 2:
				var p=game.sim.players[side]
				p.pos=Vector2(300+side*600,300+sin(tick*0.035+side*PI)*110)
			game.sim.disc.pos=Vector2(600+sin(tick*0.055)*400,300)
			if tick in [20, 70, 130]:
				game.view._burst(game.sim.disc.pos, Color("ffb347"), 1.2)
				game.view._ring(game.sim.players[0].pos, Color("50eaff"), 0.8)
				game.view._dust(game.sim.players[1].pos, 1.0)
			if tick==55:
				game.view.pixel_spectators.handle({"type":"point","side":pair%2})
				game.view._referee("win",pair%2==1)
			if tick==125:
				game.sim.server=pair%2
				game.view.handle({"type":"go"})
				game.view.overlay={}
			game.view.tick()
			game.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			if tick in [25,75,135]:
				root.get_texture().get_image().save_png("res://build/effects-preview/pair_%d_%d.png" % [pair,tick])
	quit()
