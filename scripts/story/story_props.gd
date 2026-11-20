extends Node2D
var time := 0.0
var beats: Array
var cast: Dictionary = {}
const DISC = preload("res://assets/art/disc/hyperdisc.png")
const TOWEL = preload("res://assets/art/story/rescue-towel.png")
var disc_region := Rect2()

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	disc_region = Rect2(DISC.get_image().get_used_rect())

func mouth() -> Vector2:
	var dog: Node2D = cast.tango
	if dog.anchors.has("jaw"):
		return dog.attachment_point("jaw")+Vector2(10,0)*dog.scale
	return dog.attachment_point("hand_front")+Vector2(18,2)*dog.scale

func hand(id: String) -> Vector2:
	return cast[id].attachment_point("hand_front")

func at(index: int) -> float:
	return float(beats[index].start)

func ball_position() -> Vector2:
	var ball := Vector2(725, 848)
	if time < 1.3:
		ball = hand("mick")
	elif time < 3.25:
		var p := (time - 1.3) / 1.95
		ball = Vector2(620,685).lerp(Vector2(1222.8,608.1),p)+Vector2(0,-4*145*p*(1-p))
	elif time < 7.4:
		ball = mouth()
	elif time < 8.1:
		var p := (time-7.4)/.7
		ball = Vector2(805,727).lerp(Vector2(805,848),p*p)
	elif time >= at(7):
		ball = Vector2(1325, 855)
	if time >= at(39):
		ball = Vector2(1535, 836).lerp(Vector2(1430, 859), clampf((time - at(39)) / 3, 0, 1))
	return ball

func disc_position() -> Vector2:
	var flight := time-at(35)
	if time >= at(36):
		return Vector2(1640,622.3).lerp(Vector2(1540,468),clampf((time-at(36))/.18,0,1))
	if flight > 1.6:
		return Vector2(2212.4,683.5).lerp(Vector2(1640,622.3),clampf((flight-1.6)/2.4,0,1))
	return hand("keno")

func _draw() -> void:
	if beats.is_empty():
		return
	var ball := ball_position()
	if time < at(44):
		draw_circle(ball,9,Color("526c36"))
		draw_circle(ball-Vector2(1,1),7,Color("d5ed77"))
		draw_arc(ball,6,.5+time,PI+time,8,Color("ffffcd"),2)
		draw_rect(Rect2(ball+Vector2(-4,-4),Vector2(3,2)),Color("f5ffb8"))
	if time >= at(32) and time < at(36) + 0.18:
		var disc := disc_position()
		var flight := time - at(35)
		# Spin markings inside the disc's plane, never the flattened plane itself.
		var squash := .48 if flight>1.6 else .72
		var spin := Transform2D(time*10,Vector2.ZERO)
		for layer in [3.0,1.5,0.0]:
			draw_set_transform_matrix(Transform2D(0,Vector2(1,squash),0,disc+Vector2(0,layer))*spin)
			draw_texture_rect_region(DISC,Rect2(-30,-30,60,60),disc_region,Color.WHITE if layer==0 else Color("7d658c"))
		draw_set_transform(disc,0,Vector2(1,squash))
		draw_arc(Vector2.ZERO,29,PI*1.2,PI*1.75,9,Color("d0ffff"),2)
		draw_set_transform(Vector2.ZERO)
		if flight > 1.6:
			for i in range(5):
				var p := disc + Vector2(34+i*11,12+i*8)
				draw_line(p,p+Vector2(12,8),Color(.5,1,1,.45-i*.08),2)
	var impact := time - at(36)
	if impact >= 0 and impact < 1.6:
		for i in range(16):
			var p := Vector2(1540, 468) + Vector2((i - 8) * 40, -180 - i % 4 * 30) * impact + Vector2(0, 220 * impact * impact)
			draw_line(p, p + Vector2(6, 5).rotated(i + impact * 4), Color("fff0c5"), 4)
	# A covered, breathing silhouette keeps the rescue readable and non-graphic.
	if time >= at(36) and time < at(44) + 1.8:
		var center := Vector2(1490,865)
		draw_set_transform(center,0,Vector2(1,.22))
		draw_circle(Vector2.ZERO,68,Color("d5b78f"))
		draw_set_transform(Vector2.ZERO)
		var breath := sin(time*1.7)*.6
		draw_texture_rect(TOWEL,Rect2(center+Vector2(-90,-42-breath),Vector2(180,52+breath)),false)
	if time >= at(44) + 1.8 and time < at(45):
		var p := clampf((time - at(44) - 1.8) / (at(45) - at(44) - 2.6), 0, 1)
		var lift := clampf((time - at(44) - 1.8) / .65,0,1)
		var center := Vector2(1490,850).lerp(Vector2(1655+p*290,740),lift)
		# Final lift reaches the bed at the tailgate; it cannot float through cab.
		center.y -= clampf((time-at(45)+.8)/.8,0,1)*24
		draw_texture_rect(TOWEL,Rect2(center+Vector2(-100,-30),Vector2(200,68)),false)
	if time >= at(44):
		draw_arc(Vector2(1438, 805), 13, .3, 5.9, 22, Color("46cbd2"), 5)
		draw_circle(Vector2(1445, 817), 5, Color("f8d469"))
