## Short comic balloons; every word remains available during automatic playback.
extends Node2D
const INK := Color("262137")
const PAPER := Color("fff4dc")
const FONT = preload("res://assets/fonts/Bangers-Regular.ttf")
const NAME_FONT = preload("res://assets/fonts/RussoOne-Regular.ttf")
var caption := Label.new()
var speaker_label := Label.new()
var pages: PackedStringArray = []
var source := ""
var speaker := ""
var page := 0
var bounds := Rect2()
var target := Vector2.ZERO
var on_left := true
var panel := StyleBoxFlat.new()

func _ready() -> void:
	panel.bg_color = PAPER
	panel.border_color = INK
	panel.set_border_width_all(4)
	panel.set_corner_radius_all(32)
	panel.shadow_color = Color(.07,.04,.12,.35)
	panel.shadow_size = 2
	panel.shadow_offset = Vector2(7,8)
	caption.add_theme_font_override("font",FONT)
	caption.add_theme_font_size_override("font_size",36)
	caption.add_theme_color_override("font_color",INK)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(caption)
	speaker_label.add_theme_font_override("font",NAME_FONT)
	speaker_label.add_theme_font_size_override("font_size",18)
	speaker_label.add_theme_color_override("font_color",Color("fff4dc"))
	add_child(speaker_label)

func set_line(text: String, who: String, progress: float, head: Vector2) -> void:
	visible = not text.is_empty()
	if not visible:
		return
	if text != source or speaker != who:
		source = text
		speaker = who
		on_left = head.x >= 960
		pages.clear()
		var chunk := ""
		for word in text.replace("\n"," ").split(" ",false):
			if chunk.length()+word.length()>115 and not chunk.is_empty():
				pages.append(chunk)
				chunk = ""
			chunk += (" " if not chunk.is_empty() else "")+word
		if not chunk.is_empty():
			pages.append(chunk)
	page = mini(int(clampf(progress,0,.9999)*pages.size()),pages.size()-1)
	caption.text = pages[page]
	caption.visible_characters = -1
	var width := 680.0 if caption.text.length()>75 else 560.0
	var height := 216.0 if caption.text.length()>75 else 166.0
	bounds = Rect2(clampf(head.x-width*.5,100,1820-width),96,width,height)
	target = Vector2(clampf(head.x,40,1880),clampf(head.y,120,920))
	caption.position = bounds.position+Vector2(28,31)
	caption.size = bounds.size-Vector2(56,49)
	speaker_label.text = who.to_upper()+("   %d / %d" % [page+1,pages.size()] if pages.size()>1 else "")
	speaker_label.position = bounds.position+Vector2(27,-8)
	queue_redraw()

func _draw() -> void:
	if not visible or bounds.size == Vector2.ZERO:
		return
	var corner := Vector2(clampf(target.x,bounds.position.x+40,bounds.end.x-40),bounds.end.y-8)
	var tip := target+Vector2(-20 if on_left else 20,-12)
	var tail := PackedVector2Array([corner+Vector2(-17,-15),tip,corner+Vector2(17,-15)])
	draw_colored_polygon(tail,INK)
	var inner := PackedVector2Array([corner+Vector2(-11,-15),tip.move_toward(corner,8),corner+Vector2(11,-15)])
	draw_colored_polygon(inner,PAPER)
	draw_style_box(panel,bounds)
	var name_size := NAME_FONT.get_string_size(speaker_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,18)
	draw_rect(Rect2(speaker_label.position-Vector2(12,4),name_size+Vector2(24,9)),INK)
