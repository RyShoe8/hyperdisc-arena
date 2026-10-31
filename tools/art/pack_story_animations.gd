extends SceneTree
## Pack the two accepted 4x4 animation sheets for each challenger.
func _initialize():
	for id in ["alex","jimmy","jason","tango"]:
		if not pack(id):
			quit(1)
			return
	quit()

func pack(id: String) -> bool:
	var base := "res://assets/art/characters/"+id
	var folder := "res://tools/art/characters/"+id+"/"
	var meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+".json"))
	var cell:=512
	var atlas:=Image.create_empty(8*cell,4*cell,false,Image.FORMAT_RGBA8)
	meta.frames=[]
	meta.columns=8
	for j in 2:
		var dir:=folder+"jobs/"+("movement-v1/" if j==0 else "actions-v1/")
		var job:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir+"job.json"))
		if job.status!="accepted" or FileAccess.get_sha256(dir+"candidate.png")!=job.accepted_sha256 or FileAccess.get_sha256(folder+"base-v1/base.png")!=job.base_sha256 or FileAccess.get_sha256(folder+"base-v1/reference.png")!=job.reference_sha256:
			push_error("Unreviewed art: "+dir)
			return false
		var source:=Image.load_from_file(dir+"candidate.png")
		var parts:Array=JSON.parse_string(FileAccess.get_file_as_string(dir+"components.json"))
		if parts.size()!=16:
			return false
		var scale_factor:=1.0
		for i in 16:
			var b:Array=parts[i].bounds
			var pose:=Image.create_empty(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
			for run in parts[i].runs:
				pose.blit_rect(source,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
			if i==0:
				scale_factor=(155.0 if id=="tango" else 265.0)/pose.get_height()
			var scale_here:=minf(scale_factor,490.0/pose.get_width())
			pose.resize(maxi(1,roundi(pose.get_width()*scale_here)),maxi(1,roundi(pose.get_height()*scale_here)),Image.INTERPOLATE_NEAREST)
			var off:=Vector2i(256-pose.get_width()/2,450-pose.get_height())
			var f:=16*j+i
			atlas.blit_rect(pose,Rect2i(Vector2i.ZERO,pose.get_size()),Vector2i(f%8*cell,f/8*cell)+off)
			var hand:=Vector2(off)+Vector2(pose.get_size())*(Vector2(0.85,0.23) if id=="tango" else Vector2(0.68,0.43))
			meta.frames.append({"hand":[hand.x,hand.y],"head":[hand.x if id=="tango" else 256,off.y+16],"air":false})
	var defs:={"run":[0,4,true],"run_up":[4,4,true],"run_down":[8,4,true],"dash":[12,4,false],"idle":[16,4,true],"throw":[20,4,false],"catch":[24,4,false],"win":[28,4,false],"hold":[27,1,true],"knock":[12,1,true],"lose":[12,1,true],"charge":[21,1,true]}
	for key in defs:
		var d:Array=defs[key]
		meta.animations[key]={"start":d[0],"count":d[1],"loop":d[2],"fps":(5 if key in ["idle","win"] else 15)}
	for key in ["lob","special","slap"]:
		meta.animations[key]=meta.animations.throw
	meta.animations.block=meta.animations.catch
	meta.animations.jump=meta.animations.dash
	if atlas.save_webp(base+".webp",false)!=OK:
		return false
	FileAccess.open(base+".json",FileAccess.WRITE).store_string(JSON.stringify(meta,"  "))
	return true
