extends SceneTree
## Rectify photographed perspective into the physics court's exact screen corners.
## Coordinates in the calibration file are measured on a 512x288 reference.
const CourtProjection = preload("res://scripts/game/view/projection.gd")
func _initialize():
	var configs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/venues/calibration.json"))
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	for court in rules.courts:
		var id:String=court.id
		var config:Dictionary=configs[id]
		var proj=CourtProjection.new(court.width,court.height)
		var far:Vector2=proj.floor_point(proj.court_size)
		for reaction in ["watch","cheer"]:
			var source_path:="res://tools/art/venues/%s-%s.png"%[config.slug,reaction]
			if not FileAccess.file_exists(source_path):
				source_path="res://tools/art/venues/%s-watch.png"%config.slug
			var img:=Image.load_from_file(source_path)
			if img==null or img.is_empty(): quit(1);return
			var b:Array=config.get("cheer_bounds",config.bounds) if reaction=="cheer" else config.bounds
			var out:=Image.create_empty(1920,1080,false,Image.FORMAT_RGB8)
			img.convert(Image.FORMAT_RGB8)
			var h:=img.get_height()
			var w:=img.get_width()
			var dest:=[0,roundi(proj.origin.x),roundi(far.x),1920]
			for y in 1080:
				var sy:float
				if y<proj.origin.y:
					sy=lerpf(0,b[1],y/proj.origin.y)
				elif y<far.y:
					sy=lerpf(b[1],b[4],inverse_lerp(proj.origin.y,far.y,y))
				else:
					sy=lerpf(b[4],288,inverse_lerp(far.y,1080,y))
				var v:=clampf(inverse_lerp(b[1],b[4],sy),0,1)
				var cuts:=[0,roundi(lerpf(b[0],b[3],v)*w/512),roundi(lerpf(b[2],b[5],v)*w/512),w]
				for k in 3:
					var strip:=img.get_region(Rect2i(cuts[k],clampi(int(sy*h/288),0,h-1),cuts[k+1]-cuts[k],1))
					strip.resize(dest[k+1]-dest[k],1,Image.INTERPOLATE_NEAREST)
					out.blit_rect(strip,Rect2i(Vector2i.ZERO,strip.get_size()),Vector2i(dest[k],y))
			var path:=("res://build/venues/%s_pixel.png" if reaction=="watch" else "res://build/venues/%s_cheer.png")%id
			if out.save_png(ProjectSettings.globalize_path(path))!=OK: quit(1);return
		var boxes:=[]
		var bounds:Array=config.bounds
		for band in config.audience:
			var count:=int(band[4])
			for k in count:
				var x0:=lerpf(band[0],band[2],float(k)/count)
				var x1:=lerpf(band[0],band[2],float(k+1)/count)
				var tl:=project_art(Vector2(x0,band[1]),bounds,proj.origin,far)
				var br:=project_art(Vector2(x1,band[3]),bounds,proj.origin,far)
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
