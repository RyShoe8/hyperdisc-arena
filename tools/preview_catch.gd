## Reproducible visual fixture for the flying-disc catch boundary.
extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	root.get_node("Settings").show_catch_zones=true
	root.get_node("Settings").shake=0
	game.pick.assign([0,2])
	game._start_match()
	game.sim.phase=game.MatchSim.Phase.PLAY
	game.sim.disc.state=game.MatchSim.Disc.FLYING
	game.sim.disc.thrower=1
	game.sim.disc.vel=Vector2(-16,0)
	game.sim.players[0].pos=Vector2(300,300)
	game.sim.players[1].pos=Vector2(950,300)
	game.sim.disc.pos=Vector2(350,300)
	game.sim.players[0].holding=false
	game.sim.players[1].holding=false
	game.view.overlay={}
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fluid-preview/catch.png")
	root.get_node("Settings").show_catch_zones=false
	game.sim.players[0].dash_dir=Vector2.RIGHT
	game.sim.players[0].dash_ticks=3
	game.view.dive_age[0]=6
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/fluid-preview/dive.png")
	quit()
