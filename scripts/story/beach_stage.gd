## Painted environment with deterministic surf, glints, birds and a breakable sign.
extends Node2D
var time := 0.0
var broken_sign := 0.0
const ART = preload("res://assets/art/story/beach-sunset.png")
const FONT = preload("res://assets/fonts/Bangers-Regular.ttf")
const SET_RECT := Rect2(-350, -100, 3900, 1300)
const SIGN := Vector2(1540, 468)
var painted_set: Sprite2D
var surf: ShaderMaterial

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	painted_set = Sprite2D.new()
	painted_set.texture = ART
	painted_set.centered = false
	painted_set.position = SET_RECT.position
	painted_set.scale = SET_RECT.size/ART.get_size()
	painted_set.show_behind_parent = true
	surf = ShaderMaterial.new()
	surf.shader = preload("res://scripts/story/beach_surf.gdshader")
	painted_set.material = surf
	add_child(painted_set)

func set_time(value: float) -> void:
	time = value
	if surf != null:
		surf.set_shader_parameter("cinematic_time",time)
	queue_redraw()

func _draw() -> void:
	# Overscan only: never cover the shader-driven set with a flat rectangle.
	draw_rect(Rect2(-3000,1200,9000,1500),Color("e4a16e"))
	for i in range(48):
		var x := 160.0 + (i*137)%2650
		if x > 790 and x < 1990:
			continue
		var y := 461.0 + (i*19)%75
		var a := maxf(0.0,sin(time*1.1+i*2.7))*.3
		draw_rect(Rect2(x,y,3+i%9,2),Color(1,.91,.66,a))
	for i in range(4):
		var p := Vector2(fposmod(i*730.0+time*(8+i),3800)-250,220+i%3*42)
		var wing := sin(time*3.2+i)*3
		draw_polyline(PackedVector2Array([p+Vector2(-6,wing),p+Vector2(0,2),p+Vector2(6,wing)]),Color("5c5275"),2)
