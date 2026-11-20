extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(3200,1400)
	root.content_scale_size = Vector2i(3200,1400)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var beach = load("res://scripts/story/beach_stage.gd").new()
	root.add_child(beach)
	var foreground = load("res://scripts/story/tower_foreground.gd").new()
	root.add_child(foreground)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://build/story-cast/beach-set.png")
	beach.queue_free()
	foreground.queue_free()
	await process_frame
	quit()
