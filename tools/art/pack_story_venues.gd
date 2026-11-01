extends SceneTree
## Preserve source aspect and spectator proportions; runtime projects onto the authored floor.
## Coordinates in the calibration file are measured on a 512x288 reference.
func _initialize():
	var configs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/venues/calibration.json"))
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/venues"))
	FileAccess.open("res://data/court_layouts.json",FileAccess.WRITE).store_string(JSON.stringify(configs,"  "))
	for court in rules.courts:
		var id:String=court.id
		var config:Dictionary=configs[id]
		var source_path := "res://tools/art/venues/%s-empty.png" % config.slug
		var img := Image.load_from_file(source_path)
		if img == null or img.is_empty():
			quit(1)
			return
		img.resize(1920,1080,Image.INTERPOLATE_NEAREST)
		if img.save_png(ProjectSettings.globalize_path("res://build/venues/%s_pixel.png" % id)) != OK:
			quit(1)
			return
		var boxes:=[]
		for band in config.audience:
			var count:=int(band[4])
			for k in count:
				var x0:=lerpf(band[0],band[2],float(k)/count)
				var x1:=lerpf(band[0],band[2],float(k+1)/count)
				var tl:=Vector2(x0,band[1])*3.75
				var br:=Vector2(x1,band[3])*3.75
				boxes.append([roundi(tl.x),roundi(tl.y),maxi(1,roundi(br.x-tl.x)),maxi(1,roundi(br.y-tl.y))])
		var groups_file := FileAccess.open(ProjectSettings.globalize_path("res://build/venues/%s_groups.json"%id),FileAccess.WRITE)
		if groups_file == null:
			push_error("Cannot write groups: "+str(FileAccess.get_open_error()))
			quit(1)
			return
		groups_file.store_string(JSON.stringify(boxes))
		print("Registered ",court.name)
	quit()

func project_art(q:Vector2,b:Array,a:Vector2,z:Vector2)->Vector2:
	var v:=clampf(inverse_lerp(b[1],b[4],q.y),0,1)
	var left:=lerpf(b[0],b[3],v)
	var right:=lerpf(b[2],b[5],v)
	var x:=remap(q.x,left,right,a.x,z.x)
	if q.x<left: x=remap(q.x,0,left,0,a.x)
	elif q.x>right: x=remap(q.x,right,512,z.x,1920)
	var y:=lerpf(a.y,z.y,v)
	if q.y<b[1]: y=remap(q.y,0,b[1],0,a.y)
	elif q.y>b[4]: y=remap(q.y,b[4],288,z.y,1080)
	return Vector2(x,y)
