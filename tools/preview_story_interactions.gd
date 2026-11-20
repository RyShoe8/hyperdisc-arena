extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var movie = load("res://scenes/story_prologue.tscn").instantiate()
	root.add_child(movie)
	movie.set_physics_process(false)
	movie.ambience.stop()
	movie.score.stop()
	for entry in [[6,1.2,"stairs-top"],[6,2.1,"stairs-mid"],[6,3.2,"stairs-bottom"],[15,3.2,"vanessa-contact"],[32,3.5,"throw-distance"],[35,.4,"recognition"],[35,1.6,"release"],[35,2.6,"flight"],[35,3.85,"interception"]]:
		movie.seek(float(movie.timeline.beats[entry[0]].start)+float(entry[1]))
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/prologue-review/%s.png"%entry[2])
		if entry[0]==6:
			print(entry[2]," hand=",movie.props.hand("tiffany"))
		if entry[2]=="release":
			print("RELEASE hand=",movie.props.hand("keno")," mick head=",movie.props.cast.mick.attachment_point("head"))
	movie.queue_free()
	await process_frame
	quit()
