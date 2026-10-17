extends SceneTree
const UI = preload("res://scripts/game/ui/theme.gd")
var canvas: Node2D
var arts := []
var tick := 0
var output := "res://build/fluid-preview"
func _initialize() -> void:
	_setup.call_deferred()
func _setup() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.get_node("Mixtape").music_volume = 0
	UI.load_fonts()
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		arts.append(load("res://scripts/game/view/character_art.gd").new(id))
	canvas = Node2D.new()
	root.add_child(canvas)
	canvas.draw.connect(_draw)
	DirAccess.make_dir_recursive_absolute(output)
	process_frame.connect(_tick)
func _tick() -> void:
	tick += 1
	canvas.queue_redraw()
	if tick in [25,140,155]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output+"/frame_%d.png" % tick)
	if tick == 240: quit()
func _draw() -> void:
	canvas.draw_rect(Rect2(0,0,1920,1080),UI.NIGHT)
	var dive := tick>=120
	UI.text(canvas,Vector2(960,65),"DIVING SAVE — SLOW MOTION" if dive else "12-FRAME RUN CYCLES",50,UI.YELLOW,UI.display,3)
	for i in 6:
		var ground := Vector2(320+(i%3)*640,490+(i/3)*490)
		var art=arts[i]
		var anim := "dash" if dive else "run"
		var phase := int((tick-120)/6.0)%16 if dive else tick*2
		canvas.draw_line(ground-Vector2(230,0),ground+Vector2(230,0),UI.DIM,2)
		art.draw(canvas,art.frame_for(anim,phase),ground,true,1.25)
		UI.text(canvas,ground+Vector2(0,48),art.id.to_upper(),30,Color.WHITE,UI.ui,2)
