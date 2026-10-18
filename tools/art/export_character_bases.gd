## One-time extraction of canonical pixels from the approved runtime atlas.
## Existing bases are immutable: replacing one requires an explicit new version.
extends SceneTree
const IDS := ["mick","tiffany","pete","steve","vanessa","keno"]
func _initialize() -> void:
	for id in IDS:
		var destination := "res://tools/art/characters/%s/base-v1" % id
		if FileAccess.file_exists(destination+"/base.png"):
			print("Preserving existing base: ",id)
			continue
		DirAccess.make_dir_recursive_absolute(destination)
		var base: String = "res://assets/art/characters/"+id
		var meta: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(base+".json"))
		var sheet:=Image.load_from_file(base+".webp")
		var cell:=int(meta.frame_size)
		var columns:=int(meta.columns)
		var names: Array[String]=["idle","run","throw","catch"]
		var reference:=Image.create(1024,1024,false,Image.FORMAT_RGBA8)
		var records: Array=[]
		for i in names.size():
			var frame:=int(meta.animations[names[i]].start)
			var region:=Rect2i((frame%columns)*cell,(frame/columns)*cell,cell,cell)
			var original:=sheet.get_region(region)
			var bounds:=original.get_used_rect()
			var crop:=original.get_region(bounds)
			assert(crop.get_width()>0 and crop.get_height()>0)
			if i==0:
				crop.save_png(destination+"/base.png")
			# Exact integer enlargement only: no repainting or interpolation.
			var factor:=maxi(1,mini(460/crop.get_width(),460/crop.get_height()))
			crop.resize(crop.get_width()*factor,crop.get_height()*factor,Image.INTERPOLATE_NEAREST)
			reference.blit_rect(crop,Rect2i(Vector2i.ZERO,crop.get_size()),Vector2i((i%2)*512+(512-crop.get_width())/2,(i/2)*512+480-crop.get_height()))
			records.append({"animation":names[i],"frame":frame,"bounds":[bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y]})
		reference.save_png(destination+"/reference.png")
		FileAccess.open(destination+"/origin.json",FileAccess.WRITE).store_string(JSON.stringify({"character":id,"source_atlas":base,"source_revision":"9422b2b","poses":records},"\t"))
		print("Saved canonical base: ",id)
	quit()
