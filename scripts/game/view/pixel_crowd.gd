## Cosmetic spectator reactions. Never changes simulation or rollback state.
extends RefCounted

var sheet: Texture2D
var reaction := "watch"
var ticks_left := 0
var clock := 0
var priority := 0

func _init() -> void:
	sheet = load("res://assets/art/courts/pixel_spectators.png")

func tick() -> void:
	clock += 1
	ticks_left = maxi(0, ticks_left - 1)
	if ticks_left == 0:
		reaction = "watch"
		priority = 0

func handle(event: Dictionary) -> void:
	match event.type:
		"point":
			_react("cheer", 150, 3)
		"set_end":
			_react("cheer", 240, 4)
		"match_over":
			_react("victory", 480, 5)
		"special", "block", "power_toss":
			_react("surprise", 55, 2)
		"catch":
			_react("clap", 45, 1)
		"throw", "slap":
			_react("clap", 24, 1)

func _react(kind: String, duration: int, importance: int) -> void:
	if importance < priority and ticks_left > 0:
		return
	reaction = kind
	ticks_left = duration
	priority = importance

func pose_for(index: int) -> int:
	var beat := posmod(clock / 7 + index * 3, 4)
	match reaction:
		"clap": return 1 if beat % 2 == 0 else 0
		"cheer": return 2 if beat < 3 else 1
		"victory": return 2 if beat % 2 == 0 else 1
		"surprise": return 3 if beat < 3 else 0
	return 0

func draw(ci: CanvasItem) -> void:
	if sheet == null:
		return
	var cell := sheet.get_size() / Vector2(4, 3)
	var seats: Array[Vector2] = []
	# Front spectator rows remain outside every court's playing rectangle.
	for x in [420, 500, 580, 660, 1260, 1340, 1420, 1500]:
		seats.append(Vector2(x, 145))
	for y in [350, 490, 630, 770]:
		seats.append(Vector2(60, y))
		seats.append(Vector2(1860, y))
	for x in [400, 500, 600, 700, 1220, 1320, 1420, 1520]:
		seats.append(Vector2(x, 1030))
	for i in seats.size():
		var pose := pose_for(i)
		var height := 72.0 if i >= 8 else 60.0
		var width := height * cell.x / cell.y
		var bob := -2.0 if pose == 2 and posmod(clock / 7 + i, 2) == 0 else 0.0
		var target := Rect2(seats[i] - Vector2(width/2,height) + Vector2(0,bob),Vector2(width,height))
		ci.draw_texture_rect_region(sheet,target,Rect2(Vector2(pose*cell.x,(i%3)*cell.y),cell))
