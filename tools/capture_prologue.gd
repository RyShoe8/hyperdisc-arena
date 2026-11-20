## MovieWriter capture: --write-movie build/prologue-review/prologue.avi --fixed-fps 30
extends SceneTree
var movie: Node2D
var index := 0
var capture_time := 0.0
var excerpt := false
var spans := [[1.2, 8.0], [15.5, 21.0]]
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	movie = load("res://scenes/story_prologue.tscn").instantiate()
	root.add_child(movie)
	movie.set_physics_process(false)
	for n in range(ceili(float(movie.timeline.duration) * 30)):
		movie.seek(n / 30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		if n % 900 == 0:
			print("CAPTURE %d / %d seconds" % [n / 30, movie.timeline.duration])
	movie.queue_free()
	await process_frame
	quit()
