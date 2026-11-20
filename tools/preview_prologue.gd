extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var movie = load("res://scenes/story_prologue.tscn").instantiate()
	root.add_child(movie)
	movie.set_physics_process(false)
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	DirAccess.make_dir_recursive_absolute("res://build/prologue-review")
	for index in [0,2,5,6,9,16,25,35,38,44,49,53]:
		movie.seek(float(movie.timeline.beats[index].start) + (2.0 if index != 35 else 1.0))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/prologue-review/beat-%02d.png" % index)
	print("PROLOGUE: %d beats, %.1f seconds; captured 12 shots" % [movie.timeline.beats.size(),movie.timeline.duration])
	movie.queue_free()
	await process_frame
	quit()
