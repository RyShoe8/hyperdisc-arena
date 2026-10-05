## Packs generated, transparent pose grids into the existing character contract.
## This only crops, aligns and encodes artwork; it does not repaint it.
extends SceneTree

const CELL := 512
const ANCHOR := Vector2(256, 450)

func _initialize() -> void:
	for id in ["pete", "tiffany", "keno", "steve", "vanessa"]:
		pack_character(id)
	quit()

func pack_character(id: String) -> void:
	var base := "res://tools/art/%s_sources/" % id
	var atlas := Image.create(CELL * 8, CELL * 2, false, Image.FORMAT_RGBA8)
	var frames: Array = []
	var sources: Array[Image] = []
	var master_name := "design-v1.png" if id == "pete" else "design-v2.png"
	if id == "tiffany": master_name = "design-lifeguard-v2.png"
	var master := Image.load_from_file(base + master_name)
	var target_height := 275.0 if id == "keno" else (260.0 if id == "steve" else 250.0)
	sources.append(master.get_region(master.get_used_rect()))
	for spec in [["run-v1.png", 2], ["actions-v1.png", 3]]:
		var image := Image.load_from_file(base + spec[0])
		assert(image != null, "Missing source: " + id + " " + spec[0])
		var sheet_parts: Array[Image] = []
		var tallest := 0
		var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(base + spec[0].replace("-v1.png","-components.json")))
		assert(parts.size() == int(spec[1])*3)
		for part in parts:
			var b: Array = part.bounds
			var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
			for run in part.runs:
				crop.blit_rect(image,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
			tallest = maxi(tallest, crop.get_height())
			sheet_parts.append(crop)
		# Common scale per sequence preserves crouching and jump articulation.
		for crop in sheet_parts:
			var scale_factor := target_height / tallest
			crop.resize(roundi(crop.get_width()*scale_factor), roundi(crop.get_height()*scale_factor), Image.INTERPOLATE_NEAREST)
			sources.append(crop)
	var factor := target_height / sources[0].get_height()
	sources[0].resize(roundi(sources[0].get_width()*factor), roundi(target_height), Image.INTERPOLATE_NEAREST)
	for i in sources.size():
		var image: Image = sources[i]
		var size := Vector2(image.get_size())
		var foot := Vector2(size.x * 0.5, size.y)
		var pos := ANCHOR - foot
		assert(pos.x >= 0 and pos.x + size.x <= CELL)
		atlas.blit_rect(image, Rect2i(Vector2i.ZERO,image.get_size()), Vector2i((i%8)*CELL,(i/8)*CELL)+Vector2i(pos))
		var hand_uv := Vector2(0.77,0.43)
		if i == 7: hand_uv = Vector2(0.5,0.42)
		if i == 8: hand_uv = Vector2(0.94,0.35)
		if i == 9: hand_uv = Vector2(0.88,0.53)
		if i == 10 or i == 11: hand_uv = Vector2(0.9,0.40)
		if i == 12: hand_uv = Vector2(0.70,0.43)
		var hand := pos + size * hand_uv
		frames.append({"hand":[hand.x,hand.y],"head":[ANCHOR.x,pos.y],"air":i==14})
	var animations := {
		"idle":{"start":0,"count":1,"ticks":[60],"loop":true},
		"run":{"start":1,"count":6,"ticks":[7,4,5,7,4,5],"loop":true},
		"throw":{"start":7,"count":3,"ticks":[4,3,7],"loop":false},
		"catch":{"start":10,"count":3,"ticks":[2,3,5],"loop":false},
		"hold":{"start":12,"count":1,"ticks":[60],"loop":true},
		"dash":{"start":13,"count":1,"ticks":[16],"loop":false},
		"jump":{"start":14,"count":2,"ticks":[14,4],"loop":false}}
	for name in ["lob","slap","special"]: animations[name] = animations.throw.duplicate(true)
	animations.block = animations.catch.duplicate(true)
	animations.knock = animations.dash.duplicate(true)
	for name in ["charge","win","lose"]: animations[name] = animations.idle.duplicate(true)
	assert(atlas.save_webp("res://assets/art/characters/%s.webp" % id, true) == OK)
	var file := FileAccess.open("res://assets/art/characters/%s.json" % id,FileAccess.WRITE)
	file.store_string(JSON.stringify({"frame_size":CELL,"columns":8,"anchor":[ANCHOR.x,ANCHOR.y],"frames":frames,"animations":animations,"pixel_art":true,"portrait_face":[220 if id=="tiffany" else 180,84,360,313],"portrait_bust":[100,40,520,440]}," "))
	if FileAccess.file_exists(base + "portrait-v1.png"):
		var portrait := Image.load_from_file(base + "portrait-v1.png")
		portrait.resize(640,640,Image.INTERPOLATE_NEAREST)
		assert(portrait.save_webp("res://assets/art/characters/%s_portrait.webp" % id,true) == OK)
		var selected := Image.create(640,640,false,Image.FORMAT_RGBA8)
		var body := master.get_region(master.get_used_rect())
		var body_factor := 560.0 / maxf(body.get_width(),body.get_height())
		body.resize(roundi(body.get_width()*body_factor),roundi(body.get_height()*body_factor),Image.INTERPOLATE_NEAREST)
		selected.blit_rect(body,Rect2i(Vector2i.ZERO,body.get_size()),Vector2i((640-body.get_width())/2,600-body.get_height()))
		assert(selected.save_webp("res://assets/art/characters/%s_select.webp" % id,true) == OK)
	print("Packed ",id,": ",frames.size()," pixel frames")
