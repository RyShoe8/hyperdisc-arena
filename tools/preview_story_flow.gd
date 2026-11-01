extends SceneTree
func _initialize(): run.call_deferred()
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	root.size = Vector2i(960,540)
	DirAccess.make_dir_recursive_absolute("res://build/story-flow")
	game.story_order = game._story_ladder()
	game.story_fighter = 0
	game.story_round = 2
	game._prepare_story()
	for t in [25,80]:
		game.screen_ticks = t
		await capture(game,"ladder_%d" % t)
	game._go(game.Screen.VS)
	game.screen_ticks = 60
	await capture(game,"versus")
	game._start_match()
	game._go(game.Screen.ENTRANCE)
	for t in [30,100,170]:
		game.view.entrance_ticks = t
		game.screen_ticks = t
		await capture(game,"entrance_%d" % t)
	game.view.entrance_ticks = -1
	game._go(game.Screen.MATCH)
	await capture(game,"ready")
	game.queue_free()
	await process_frame
	quit()
func capture(game,tag):
	game.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/story-flow/%s.png" % tag)
