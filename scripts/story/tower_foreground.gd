## Occlusion geometry samples the original painting exactly; actors can stand
## behind the near rail while remaining in front of the far rail and building.
extends Node2D
const ART = preload("res://assets/art/story/beach-sunset.png")
const FONT = preload("res://assets/fonts/Bangers-Regular.ttf")
const SET_RECT := Rect2(-350,-100,3900,1300)
var broken_sign := 0.0

func painted_polygon(points: Array) -> void:
	var vertices := PackedVector2Array()
	var uvs := PackedVector2Array()
	for p in points:
		var uv: Vector2 = p/ART.get_size()
		uvs.append(uv)
		vertices.append(SET_RECT.position+uv*SET_RECT.size)
	draw_polygon(vertices,PackedColorArray([Color.WHITE]),uvs,ART)

func strip(x: float,y: float,w: float,h: float) -> void:
	painted_polygon([Vector2(x,y),Vector2(x+w,y),Vector2(x+w,y+h),Vector2(x,y+h)])

func _draw() -> void:
	# Near handrail and its three supporting posts, not the gaps between them.
	painted_polygon([Vector2(642,425),Vector2(864,275),Vector2(878,279),Vector2(651,437)])
	strip(701,397,12,112)
	strip(765,359,13,99)
	strip(844,298,12,90)
	# Near stringer and landing edge hide the lower leg only where wood exists.
	painted_polygon([Vector2(696,488),Vector2(884,351),Vector2(884,370),Vector2(706,508)])
	strip(884,347,423,24)
	strip(858,275,449,10)
	strip(884,309,102,9)
	strip(1125,309,182,9)
	for x in [886,934,981,1127,1244,1300]:
		strip(x,281,9,66)
	strip(987,286,139,59)
	# The sign lives in this depth plane, in front of Tiffany on the platform.
	for half in [0,1]:
		var fall := Vector2((-18 if half==0 else 25)*broken_sign,broken_sign*(140+half*35))
		draw_set_transform(Vector2(1540+(half-.5)*108,468)+fall,broken_sign*(-.7 if half==0 else .5))
		draw_rect(Rect2(-54,-32,108,64),Color("674b51"))
		draw_rect(Rect2(-51,-29,102,58),Color("f3d9b4"))
		draw_string(FONT,Vector2(-42,12),"LIFE" if half==0 else "GUARD",HORIZONTAL_ALIGNMENT_LEFT,-1,30,Color("a73944"))
	draw_set_transform(Vector2.ZERO)
