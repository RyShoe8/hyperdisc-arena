## Maps court coordinates (x, y on the floor, z up) to screen pixels using
## the same camera the Blender court renders use (data/projection.json), so
## everything the game draws lines up with the background art.
extends RefCounted

var screen := Vector2(1920, 1080)
var scale := 1.19
var floor_y := 1.0   # screen pixels per unit of court depth
var wall_z := 0.6    # screen pixels per unit of height, for scenery
var air_z := 1.3     # screen pixels per unit of height, for the disc and jumps
var origin := Vector2.ZERO
var court_size := Vector2.ZERO
var wall_height := 70.0
var panel_depth := 64.0


func _init(court_width: float, court_height: float) -> void:
	var p: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/projection.json"))
	screen = Vector2(float(p.screen_width), float(p.screen_height))
	scale = float(p.scale)
	var pitch := deg_to_rad(float(p.pitch_degrees))
	floor_y = scale * sin(pitch)
	wall_z = scale * cos(pitch)
	air_z = scale * float(p.air_scale)
	wall_height = float(p.wall_height)
	panel_depth = float(p.goal_panel_depth)
	court_size = Vector2(court_width, court_height)
	origin = Vector2(screen.x / 2.0 - court_width * scale / 2.0,
		float(p.floor_centre_screen_y) - court_height * floor_y / 2.0)


## A point on the floor (z = 0).
func floor_point(pos: Vector2) -> Vector2:
	return origin + Vector2(pos.x * scale, pos.y * floor_y)


## A point above the floor, using the exaggerated height of gameplay objects.
func air_point(pos: Vector2, z: float) -> Vector2:
	return floor_point(pos) - Vector2(0, z * air_z)


## A point above the floor at true scenery scale (walls, barriers, posts).
func scenery_point(pos: Vector2, z: float) -> Vector2:
	return floor_point(pos) - Vector2(0, z * wall_z)


## The four screen corners of a strip on one goal panel, between court
## depths y0 and y1. side 0 = left wall, 1 = right wall. inset trims the
## strip away from the panel's bottom and top edges (0..1).
func goal_strip(side: int, y0: float, y1: float, inset := 0.12) -> PackedVector2Array:
	var x := 0.0 if side == 0 else court_size.x
	var out := -1.0 if side == 0 else 1.0
	var d0 := panel_depth * inset
	var d1 := panel_depth * (1.0 - inset)
	var a := scenery_point(Vector2(x + out * d0, y0), d0)
	var b := scenery_point(Vector2(x + out * d1, y0), d1)
	var c := scenery_point(Vector2(x + out * d1, y1), d1)
	var d := scenery_point(Vector2(x + out * d0, y1), d0)
	return PackedVector2Array([a, b, c, d])
