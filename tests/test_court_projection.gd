extends SceneTree

func _initialize() -> void:
	var layouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/court_layouts.json"))
	var CourtProjection = load("res://scripts/game/view/projection.gd")
	for id in layouts:
		var layout: Dictionary = layouts[id]
		var projection = CourtProjection.new(1200,700,id)
		for side in 2:
			for vertex in layout.wall_edges[side]:
				var depth := inverse_lerp(float(layout.bounds[1]),float(layout.bounds[4]),float(vertex[1]))*700.0
				var mapped: Vector2 = projection.floor_point(Vector2(side*1200,depth))
				assert(mapped.distance_to(Vector2(vertex[0],vertex[1])*3.75)<0.01,"Collision boundary must follow authored wall: "+id)
			for interval in [[0,210],[210,490],[490,700]]:
				var polygon: PackedVector2Array = projection.goal_strip(side,interval[0],interval[1])
				assert(not Geometry2D.triangulate_polygon(polygon).is_empty(),"Scoring strip must remain drawable across wall corners: "+id)
		for depth in range(0,701,10):
			assert(is_equal_approx(projection.floor_point(Vector2(600,depth)).x,960.0),"Court center must stay on illustrated divider: "+id)
	print("COURT PROJECTION TESTS PASSED")
	quit()
