## A character's rendered sprite sheet and its metadata (from
## tools/blender/make_characters.py): frame regions, the ground anchor, and
## per-frame hand and head positions for attaching the disc and markers.
extends RefCounted

var id: String
var sheet: Texture2D
var portrait: Texture2D
var select: Texture2D
var frame_size := 320
var columns := 8
var anchor := Vector2(160, 258)
var frames: Array = []
var animations := {}
var pixel_art := false
var portrait_face := Rect2(140,84,360,313)
var portrait_bust := Rect2(80,40,480,416)


func _init(character_id: String) -> void:
	id = character_id
	var base := "res://assets/art/characters/%s" % id
	sheet = load(base + ".webp")
	# The referee has a sprite sheet only.
	if ResourceLoader.exists(base + "_portrait.webp"):
		portrait = load(base + "_portrait.webp")
		select = load(base + "_select.webp")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	frame_size = int(meta.frame_size)
	columns = int(meta.columns)
	anchor = Vector2(meta.anchor[0], meta.anchor[1])
	frames = meta.frames
	animations = meta.animations
	pixel_art = bool(meta.get("pixel_art", false))
	if meta.has("portrait_face"):
		var crop: Array = meta.portrait_face
		portrait_face = Rect2(crop[0],crop[1],crop[2],crop[3])
	if meta.has("portrait_bust"):
		var crop: Array = meta.portrait_bust
		portrait_bust = Rect2(crop[0],crop[1],crop[2],crop[3])


## Frame index for an animation `ticks` physics ticks after it started.
func frame_for(anim: String, ticks: int) -> int:
	var a: Dictionary = animations.get(anim, animations["idle"])
	if a.has("ticks"):
		return int(a.start) + _held_frame(a.ticks, ticks, a.loop)
	var count := int(a.count)
	var step := int(floor(ticks * float(a.fps) / 60.0))
	var i := posmod(step, count) if a.loop else clampi(step, 0, count - 1)
	return int(a.start) + i


## Frames that each hold for their own number of ticks (key poses that
## hold, then snap to the next).
static func _held_frame(holds: Array, ticks: int, loop: bool) -> int:
	var total := 0
	for h in holds:
		total += int(h)
	var t := posmod(ticks, total) if loop else clampi(ticks, 0, total - 1)
	for i in holds.size():
		t -= int(holds[i])
		if t < 0:
			return i
	return holds.size() - 1


func region(frame: int) -> Rect2:
	return Rect2((frame % columns) * frame_size, (frame / columns) * frame_size, frame_size, frame_size)


## Offset from the anchor to a named point ("hand" or "head") in a frame.
func point(frame: int, which: String) -> Vector2:
	var p: Array = frames[frame][which]
	return Vector2(p[0], p[1]) - anchor


## Draws a frame with its ground anchor at `ground`, flipped to face left
## when needed, scaled, with an optional tint.
func draw(ci: CanvasItem, frame: int, ground: Vector2, facing_right: bool, scale: float,
		tint := Color.WHITE) -> void:
	var flip := 1.0 if facing_right else -1.0
	ci.draw_set_transform(ground, 0.0, Vector2(flip * scale, scale))
	ci.draw_texture_rect_region(sheet, Rect2(-anchor, Vector2(frame_size, frame_size)), region(frame), tint)
	ci.draw_set_transform(Vector2.ZERO)
