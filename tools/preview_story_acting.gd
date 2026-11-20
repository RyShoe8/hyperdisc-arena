extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/story_rigby.json"))
	root.size = Vector2i(1600,900)
	root.content_scale_size = Vector2i(1600,900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	RenderingServer.set_default_clear_color(Color("3b344b"))
	var script = load("res://scripts/story/story_actor.gd")
	var actors: Array = []
	for i in 10:
		var actor = script.new()
		actor.setup(data.ids[i],data.cast[data.ids[i]])
		actor.position = Vector2(150+(i%5)*320,420+(i/5)*440)
		actor.scale = Vector2.ONE*1.4
		root.add_child(actor)
		actors.append(actor)
	for anim in ["listen","speak","laugh","kneel","resolve"]:
		for i in actors.size():
			actors[i].sample(anim if data.ids[i]!="tango" else "wag",1.0)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/prologue-review/acting-%s.png" % anim)
	quit()
