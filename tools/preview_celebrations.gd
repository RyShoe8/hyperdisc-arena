extends SceneTree
var canvas: Node2D
var arts: Array = []
var ticks := 0
func _initialize() -> void:
	_run.call_deferred()
func _draw() -> void:
	canvas.draw_rect(Rect2(0,0,1440,900),Color("171727"))
	for i in arts.size():
		var ground := Vector2(240+(i%3)*480,390+(i/3)*430)
		var art = arts[i]
		art.draw(canvas,art.frame_for("win",ticks),ground,true,1.0)
func _run() -> void:
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	canvas=Node2D.new()
	root.add_child(canvas)
	canvas.draw.connect(_draw)
	for id in ["mick","pete","tiffany","steve","vanessa","keno"]:
		arts.append(load("res://scripts/game/view/character_art.gd").new(id))
	DirAccess.make_dir_recursive_absolute("res://build/celebrations")
	for i in 150:
		ticks=i
		canvas.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		if i in [0,20,40,60,90]:
			root.get_texture().get_image().save_png("res://build/celebrations/frame_%d.png" % i)
	quit()
