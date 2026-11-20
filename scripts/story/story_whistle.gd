## This prop shares its wearer's depth, so the near rail can pass in front of it.
extends Node2D
var props: Node2D

func refresh() -> void:
	visible = props.time < props.at(36)
	z_index = props.cast[owner_id()].z_index + 1
	queue_redraw()

func owner_id() -> String:
	return "keno" if props.time >= props.at(7)+.7 and props.time < props.at(25)+1.0 else "tiffany"

func _draw() -> void:
	var owner := owner_id()
	var tiff: Node2D = props.cast.tiffany
	var neck: Vector2 = tiff.attachment_point("neck") if tiff.anchors.has("neck") else tiff.attachment_point("head")+Vector2(0,18)*tiff.scale
	var worn: bool = owner=="tiffany" and (props.time<props.at(7) or props.time>=props.at(26))
	var pendant: Vector2 = neck+Vector2(6,28)*tiff.scale if worn else props.hand(owner)+Vector2(0,20)
	if worn:
		# A little weight and follow-through, rather than a rigid floating icon.
		pendant.x += sin(props.time*3.1)*1.2
		draw_polyline(PackedVector2Array([neck+Vector2(-8,2)*tiff.scale,pendant,neck+Vector2(9,1)*tiff.scale]),Color("503841"),2)
	else:
		draw_polyline(PackedVector2Array([pendant+Vector2(-3,-20),pendant+Vector2(-8,10),pendant+Vector2(4,13)]),Color("503841"),2)
	draw_rect(Rect2(pendant+Vector2(-4,-2),Vector2(10,6)),Color("d8dee1"))
	draw_rect(Rect2(pendant+Vector2(3,-3),Vector2(7,3)),Color("ffffde"))
