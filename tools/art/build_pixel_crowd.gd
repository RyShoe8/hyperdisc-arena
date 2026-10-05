extends SceneTree

func _initialize() -> void:
	var source := Image.load_from_file("res://tools/art/spectator-source.png")
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/spectator-components.json"))
	assert(parts.size() == 12)
	var atlas := Image.create(768,768,false,Image.FORMAT_RGBA8)
	var factor := 100.0
	for part in parts:
		var b: Array = part.bounds
		factor = minf(factor, 228.0 / (b[3]-b[1]+1))
		factor = minf(factor, 176.0 / (b[2]-b[0]+1))
	for i in parts.size():
		var p: Dictionary = parts[i]
		var b: Array = p.bounds
		var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in p.runs:
			crop.blit_rect(source,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		crop.resize(roundi(crop.get_width()*factor),roundi(crop.get_height()*factor),Image.INTERPOLATE_NEAREST)
		var at := Vector2i((i%4)*192+96-crop.get_width()/2,(i/4)*256+244-crop.get_height())
		atlas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),at)
	assert(atlas.save_png("res://assets/art/courts/pixel_spectators.png") == OK)
	print("Packed 12 spectator poses")
	quit()
