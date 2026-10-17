## Append new run and dive drawings to existing atlases, keeping other moves.
extends SceneTree
const CELL := 512
const ANCHOR := Vector2(256,450)
func _initialize() -> void:
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		pack(id)
	quit()

func pack(id: String) -> void:
	var base := "res://assets/art/characters/" + id
	var source := "res://tools/art/%s_sources/" % id
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+".json"))
	var old := Image.load_from_file(base+".webp")
	var start := int(meta.get("fluid_start", meta.frames.size()))
	meta.frames = meta.frames.slice(0,start)
	meta.fluid_start = start
	var atlas := Image.create(CELL*8,CELL*ceili((start+18)/8.0),false,Image.FORMAT_RGBA8)
	atlas.blit_rect(old,Rect2i(0,0,old.get_width(),mini(old.get_height(),atlas.get_height())),Vector2i.ZERO)
	var sheet := Image.load_from_file(source+"fluid-v1.png")
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(source+"fluid-components.json"))
	assert(parts.size()==18)
	var tallest := 0
	for i in 12:
		tallest = maxi(tallest,parts[i].bounds[3]-parts[i].bounds[1]+1)
	var height := 275.0 if id=="keno" else (260.0 if id=="steve" else 250.0)
	var scale_factor := height/tallest
	for i in 18:
		var b: Array = parts[i].bounds
		var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in parts[i].runs:
			crop.blit_rect(sheet,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		crop.resize(roundi(crop.get_width()*scale_factor),roundi(crop.get_height()*scale_factor),Image.INTERPOLATE_NEAREST)
		var size := Vector2(crop.get_size())
		var pos := ANCHOR-Vector2(size.x*0.5,size.y)
		# The extended airborne pose has clear ground beneath its body.
		if i==13: pos.y-=15
		if i==14: pos.y-=45
		assert(pos.x>=0 and pos.y>=0 and pos.x+size.x<=CELL)
		var f := start+i
		atlas.fill_rect(Rect2i((f%8)*CELL,(f/8)*CELL,CELL,CELL),Color.TRANSPARENT)
		atlas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i((f%8)*CELL,(f/8)*CELL)+Vector2i(pos))
		var hand := pos+size*Vector2(0.88,0.4)
		meta.frames.append({"hand":[hand.x,hand.y],"head":[ANCHOR.x,pos.y],"air":i in [13,14]})
	meta.animations.run={"start":start,"count":12,"ticks":[3,2,3,3,2,3,3,2,3,3,2,3],"loop":true}
	meta.animations.dash={"start":start+12,"count":6,"ticks":[2,3,4,2,3,2],"loop":false}
	assert(atlas.save_webp(base+".webp",true)==OK)
	FileAccess.open(base+".json",FileAccess.WRITE).store_string(JSON.stringify(meta," "))
	print("Packed fluid animation: ",id," ",meta.frames.size()," frames")
