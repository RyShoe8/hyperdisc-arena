## Its baseline and tailgate are shared with the rescue blocking and prop path.
extends Node2D
const ART = preload("res://assets/art/story/rescue-truck.png")
var driving := false
var time := 0.0
const SIZE := Vector2(1080,360)

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _draw() -> void:
	draw_set_transform(Vector2(0,-12),0,Vector2(1,.1))
	draw_circle(Vector2.ZERO,490,Color(.14,.09,.18,.23))
	draw_set_transform(Vector2.ZERO)
	var bounce := sin(time*15)*.8 if driving else 0.0
	draw_texture_rect(ART,Rect2(Vector2(-540,-360+bounce),SIZE),false)
	if driving:
		# Restrained tread/hub rotation; the body never wobbles or changes scale.
		for x in [-282,349]:
			var hub := Vector2(x,-66+bounce)
			for i in range(4):
				var direction := Vector2.from_angle(time*9+i*PI/2)
				draw_line(hub+direction*8,hub+direction*20,Color(.94,.86,.72,.6),2)
		for i in range(9):
			var p := Vector2(-420-i*25-fposmod(time*35,25),-12-i*4)
			draw_circle(p,10+i*2,Color(.9,.65,.43,.12-i*.01))
