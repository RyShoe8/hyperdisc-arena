## Packs the six original referee poses into the existing character contract.
extends SceneTree

func _initialize() -> void:
	var source := Image.load_from_file("res://tools/art/referee-source.png")
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/referee-components.json"))
	assert(parts.size() == 6)
	var atlas := Image.create(1920,320,false,Image.FORMAT_RGBA8)
	var factor := 100.0
	var frames: Array = []
	for p in parts:
		var b: Array = p.bounds
		factor = minf(factor,250.0/(b[3]-b[1]+1))
		factor = minf(factor,260.0/(b[2]-b[0]+1))
	for i in parts.size():
		var p: Dictionary = parts[i]
		var b: Array = p.bounds
		var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in p.runs:
			crop.blit_rect(source,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		var feet := Vector2(p.anchor[0]-b[0],p.anchor[1]-b[1])*factor
		crop.resize(roundi(crop.get_width()*factor),roundi(crop.get_height()*factor),Image.INTERPOLATE_NEAREST)
		var pos := Vector2(160,285)-feet
		assert(pos.x>=0 and pos.y>=0 and pos.x+crop.get_width()<=320 and pos.y+crop.get_height()<=320)
		atlas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i(i*320,0)+Vector2i(pos))
		frames.append({"hand":[190,160],"head":[160,pos.y],"air":false})
	assert(atlas.save_webp("res://assets/art/characters/referee.webp",true)==OK)
	var file := FileAccess.open("res://assets/art/characters/referee.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"frame_size":320,"columns":6,"anchor":[160,285],"pixel_art":true,"frames":frames,"animations":{
		"idle":{"start":0,"count":2,"ticks":[30,30],"loop":true},
		"lob":{"start":2,"count":2,"ticks":[6,12],"loop":false},
		"win":{"start":4,"count":2,"ticks":[14,14],"loop":true}}}," "))
	print("Packed six referee poses")
	quit()
