## Append reviewed celebrations, retaining existing move indices.
extends SceneTree
var jobs: Dictionary
func _initialize() -> void:
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]: jobs[id]="celebration-v1"
	jobs["vanessa"]="celebration-v2"
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
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		pack(id)
	quit()

func pack(id: String) -> void:
	var base := "res://assets/art/characters/" + id
	var source := "res://tools/art/characters/%s/jobs/%s/" % [id,jobs[id]]
	var image_name := "candidate.png"
	var parts_name := "components.json"
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(base+".json"))
	var old := Image.load_from_file(base+".webp")
	var start := int(meta.get("celebration_start", meta.frames.size()))
	meta.frames = meta.frames.slice(0,start)
	meta.celebration_start = start
	var cell := int(meta.frame_size)
	var columns := int(meta.columns)
	var anchor := Vector2(meta.anchor[0],meta.anchor[1])
	var count := 8
	var atlas := Image.create(cell*columns,cell*ceili(float(start+count)/columns),false,Image.FORMAT_RGBA8)
	atlas.blit_rect(old,Rect2i(0,0,old.get_width(),mini(old.get_height(),atlas.get_height())),Vector2i.ZERO)
	var sheet := Image.load_from_file(source+image_name)
	var parts: Array = JSON.parse_string(FileAccess.get_file_as_string(source+parts_name))
	assert(parts.size()==count)
	# Scale from the first crouched neutral pose, not the raised hands.
	# All frames share one scale so the body never shrinks during a gesture.
	var first: Array = parts[0].bounds
	var height := 275.0 if id=="keno" else (260.0 if id=="steve" else 250.0)
	var scale_factor := height / float(first[3]-first[1]+1)
	for i in count:
		var b: Array = parts[i].bounds
		var crop := Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in parts[i].runs:
			crop.blit_rect(sheet,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		crop.resize(roundi(crop.get_width()*scale_factor),roundi(crop.get_height()*scale_factor),Image.INTERPOLATE_NEAREST)
		var size := Vector2(crop.get_size())
		var foot_x: float = (parts[i].anchor[0] - b[0]) * scale_factor
		var pos := anchor-Vector2(foot_x,size.y)
		# Keep the referee's body planted while her arm extends to the right.
		if id == "referee" and i in [5,7]: pos.x -= 22
		assert(pos.x>=0 and pos.y>=0 and pos.x+size.x<=cell)
		var f := start+i
		atlas.fill_rect(Rect2i((f%columns)*cell,(f/columns)*cell,cell,cell),Color.TRANSPARENT)
		atlas.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i((f%columns)*cell,(f/columns)*cell)+Vector2i(pos))
		var hand := pos+size*Vector2(0.8,0.45)
		meta.frames.append({"hand":[hand.x,hand.y],"head":[anchor.x,pos.y],"air":false})
	meta.animations.win={"start":start,"count":8,"ticks":[8,7,7,12,9,10,12,25],"loop":false}
	assert(atlas.save_webp(base+".webp",true)==OK)
	FileAccess.open(base+".json",FileAccess.WRITE).store_string(JSON.stringify(meta," "))
	print("Packed celebration: ",id," ",meta.frames.size()," frames")
