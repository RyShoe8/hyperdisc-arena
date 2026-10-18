## Append directional cycles; retain all existing moves and their indices.
extends SceneTree
var jobs: Dictionary
func _initialize() -> void:
	jobs=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/characters/directional-release.json"))
	# Preflight every character before modifying ANY atlas.
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		var folder: String = "res://tools/art/characters/%s/jobs/%s/" % [id,jobs[id]]
		if not FileAccess.file_exists(folder+"job.json"):
			push_error("Missing reviewed animation job: "+id)
			quit(1)
			return
		var job: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder+"job.json"))
		var reference: String = "res://tools/art/characters/%s/base-v1/" % id
		if job.status != "accepted" or job.accepted_sha256 != FileAccess.get_sha256(folder+job.candidate) or job.base_sha256 != FileAccess.get_sha256(reference+"base.png") or job.reference_sha256 != FileAccess.get_sha256(reference+"reference.png") or not FileAccess.file_exists(folder+"components.json"):
			push_error("Animation has not passed identity review and extraction: "+id)
			quit(1)
			return
	for id in ["mick","pete","tiffany","keno","steve","vanessa","referee"]:
		pack(id)
	quit()

func pack(id: String) -> void:
	var base := "res://assets/art/characters/" + id
	var source := "res://tools/art/%s_sources/" % id
	var image_name := "turn-v1.png"
	var parts_name := "turn-components.json"
	if id != "referee":
		source = "res://tools/art/characters/%s/jobs/%s/" % [id,jobs[id]]
		image_name = "candidate.png"
		parts_name = "components.json"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+".json"))
	var old := Image.load_from_file(base+".webp")
	var start := int(meta.get("turn_start", meta.frames.size()))
	meta.frames = meta.frames.slice(0,start)
	meta.turn_start = start
	var cell := int(meta.frame_size)
	var columns := int(meta.columns)
	var anchor := Vector2(meta.anchor[0],meta.anchor[1])
	var count := 8 if id == "referee" else 16
	var atlas := Image.create(cell*columns,cell*ceili(float(start+count)/columns),false,Image.FORMAT_RGBA8)
	atlas.blit_rect(old,Rect2i(0,0,old.get_width(),mini(old.get_height(),atlas.get_height())),Vector2i.ZERO)
	var sheet := Image.load_from_file(source+image_name)
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(source+parts_name))
	assert(parts.size()==count)
	var tallest := 0
	for i in (3 if id == "referee" else count):
		tallest = maxi(tallest,parts[i].bounds[3]-parts[i].bounds[1]+1)
	var height := 210.0 if id == "referee" else (275.0 if id=="keno" else (260.0 if id=="steve" else 250.0))
	var scale_factor := height/tallest
	for i in count:
		if id != "referee" and i % 8 == 0:
			var direction_height := 0
			for j in range(i,i+8):
				direction_height=maxi(direction_height,parts[j].bounds[3]-parts[j].bounds[1]+1)
			scale_factor=height/direction_height
		var b: Array = parts[i].bounds
		var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in parts[i].runs:
			crop.blit_rect(sheet,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		crop.resize(roundi(crop.get_width()*scale_factor),roundi(crop.get_height()*scale_factor),Image.INTERPOLATE_NEAREST)
		var size := Vector2(crop.get_size())
		var pos := anchor-Vector2(size.x*0.5,size.y)
		# Keep the referee's body planted while her arm extends to the right.
		if id == "referee" and i in [5,7]: pos.x -= 22
		assert(pos.x>=0 and pos.y>=0 and pos.x+size.x<=cell)
		var f := start+i
		atlas.fill_rect(Rect2i((f%columns)*cell,(f/columns)*cell,cell,cell),Color.TRANSPARENT)
		atlas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i((f%columns)*cell,(f/columns)*cell)+Vector2i(pos))
		var hand := pos+size*Vector2(0.8,0.45)
		meta.frames.append({"hand":[hand.x,hand.y],"head":[anchor.x,pos.y],"air":false})
	if id == "referee":
		meta.animations.center={"start":start,"count":1,"ticks":[60],"loop":true}
		meta.animations.idle={"start":start+1,"count":2,"ticks":[45,35],"loop":true}
		meta.animations.focus={"start":start+3,"count":1,"ticks":[30],"loop":true}
		meta.animations.lob={"start":start+4,"count":2,"ticks":[8,22],"loop":false}
		meta.animations.win={"start":start+6,"count":2,"ticks":[18,36],"loop":false}
	else:
		meta.animations.run_up={"start":start,"count":8,"ticks":[4,4,4,4,4,4,4,4],"loop":true}
		meta.animations.run_down={"start":start+8,"count":8,"ticks":[4,4,4,4,4,4,4,4],"loop":true}
	assert(atlas.save_webp(base+".webp",true)==OK)
	FileAccess.open(base+".json",FileAccess.WRITE).store_string(JSON.stringify(meta," "))
	print("Packed directional animation: ",id," ",meta.frames.size()," frames")
