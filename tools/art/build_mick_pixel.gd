## Packs approved pixel studies into the game's atlas. No artistic repainting.
extends SceneTree

const BASE := "res://tools/art/mick_sources/"
const CELL := 512
const ANCHOR := Vector2(256, 450)
var atlas := Image.create(CELL * 8, CELL * 3, false, Image.FORMAT_RGBA8)
var frames: Array = []
var animations := {}

func _initialize() -> void:
	var masks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "action-components.json"))
	for key in ["idle-v2", "catch-v3", "throw-v2", "dash-v2", "jump-v2"]:
		var source := Image.load_from_file(BASE + key + "-strip.png")
		var parts: Array = masks[key]
		var factor := 100.0
		for part in parts:
			var b: Array = part.bounds
			factor = minf(factor, 250.0 / (b[3] - b[1] + 1))
			factor = minf(factor, 460.0 / (2 * maxf(part.anchor[0] - b[0], b[2] - part.anchor[0]) + 1))
		var start := frames.size()
		for i in parts.size():
			var part: Dictionary = parts[i]
			var b: Array = part.bounds
			var crop := Image.create(b[2]-b[0]+1, b[3]-b[1]+1, false, Image.FORMAT_RGBA8)
			for run in part.runs:
				crop.blit_rect(source, Rect2i(run[1],run[0],run[2],1), Vector2i(run[1]-b[0],run[0]-b[1]))
			# Jump altitude comes from simulation; anchor each pose to its feet.
			var foot := Vector2(part.anchor[0]-b[0], part.anchor[1]-b[1])
			var hand_uv := Vector2(0.83, 0.43)
			if key == "catch-v3":
				hand_uv = [Vector2(0.91,0.22),Vector2(0.95,0.24),Vector2(0.73,0.29)][i]
			elif key == "throw-v2":
				hand_uv = [Vector2(0.53,0.36),Vector2(0.96,0.22),Vector2(0.95,0.56)][i]
			var size := Vector2(crop.get_size())
			var head := ANCHOR + (Vector2(size.x * 0.55, 0) - foot) * factor
			var hand := ANCHOR + (size * hand_uv - foot) * factor
			crop.resize(maxi(1,roundi(size.x*factor)),maxi(1,roundi(size.y*factor)),Image.INTERPOLATE_NEAREST)
			place(crop, ANCHOR - foot * factor, hand, head)
		var name: String = key.split("-")[0]
		var holds: Array = {"idle":[24,24,24],"catch":[2,3,5],"throw":[4,3,7],"dash":[3,7,6],"jump":[2,14,4]}[name]
		animations[name] = {"start":start,"count":3,"loop":name == "idle","ticks":holds}
	var run_start := frames.size()
	var runs := [["contact-a.png",650,1218],["compression-a-v2.png",650,1213],["passing-a-v4.png",620,1223],["contact-b-v4.png",650,1203],["compression-b-v4.png",660,1202],["passing-b-v6.png",650,1209]]
	for spec in runs:
		var img := Image.load_from_file(BASE + spec[0])
		var factor := 0.205
		img.resize(roundi(img.get_width()*factor),roundi(img.get_height()*factor),Image.INTERPOLATE_NEAREST)
		place(img, ANCHOR-Vector2(spec[1],spec[2])*factor,ANCHOR+Vector2(45,-115),ANCHOR+Vector2(0,-245))
	animations.run = {"start":run_start,"count":6,"loop":true,"ticks":[7,4,5,7,4,5]}
	animations.hold = {"start":animations.catch.start+2,"count":1,"loop":true,"ticks":[60]}
	for name in ["lob","slap","special"]:
		animations[name] = animations.throw.duplicate(true)
	animations.block = animations.catch.duplicate(true)
	for name in ["charge","win","lose"]:
		animations[name] = animations.idle.duplicate(true)
	animations.knock = animations.dash.duplicate(true)
	atlas.save_webp("res://assets/art/characters/mick.webp", true)
	var meta := {"frame_size":CELL,"columns":8,"anchor":[ANCHOR.x,ANCHOR.y],"frames":frames,"animations":animations,"pixel_art":true}
	var file := FileAccess.open("res://assets/art/characters/mick.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(meta," "))
	print("Packed Mick pixel atlas: ", frames.size(), " frames")
	quit()

func place(img: Image, pos: Vector2, hand: Vector2, head: Vector2) -> void:
	var index := frames.size()
	var origin := Vector2i((index%8)*CELL,(index/8)*CELL)
	assert(pos.x>=0 and pos.y>=0 and pos.x+img.get_width()<=CELL and pos.y+img.get_height()<=CELL, "Sprite exceeds atlas cell")
	atlas.blit_rect(img,Rect2i(Vector2i.ZERO,img.get_size()),origin+Vector2i(pos))
	frames.append({"hand":[hand.x,hand.y],"head":[head.x,head.y],"air":false})
