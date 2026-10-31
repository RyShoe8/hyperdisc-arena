extends SceneTree
func _initialize(): _run.call_deferred()
func _run():
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	root.size=Vector2i(960,540)
	DirAccess.make_dir_recursive_absolute("res://build/venues")
	for i in 6:
		game.court=i
		game.story=false
		game._start_match()
		for n in 80: game.view.tick()
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/venues/%d.png"%i)
		game.view.handle({"type":"match_over","winner":0})
		for n in 45: game.view.tick()
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/venues/%d-cheer.png"%i)
	quit()
