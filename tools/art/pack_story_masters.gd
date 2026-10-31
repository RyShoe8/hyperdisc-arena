extends SceneTree
# Register illustrated poses on the same ground plane as the original cast.
func _initialize():
	var source := Image.load_from_file("res://tools/art/characters/story-masters.png")
	var rows := [[0,265,350,700,1150],[265,526,350,700,1150],[526,807,350,700,1162],[807,1024,350,700,1155]]
	for row in 4:
		var id: String = ["alex","jimmy","jason","tango"][row]
		var spec: Array = rows[row]
		var cuts := [0,spec[2],spec[3],spec[4],1536]
		var frames := []
		var sheet := Image.create_empty(2048,512,false,Image.FORMAT_RGBA8)
		var folder := "res://tools/art/characters/%s/base-v1/" % id
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
		var base := "res://assets/art/characters/"+id
		var scale_factor := 1.0
		var reference := Image.create_empty(1024,1024,false,Image.FORMAT_RGBA8)
		for col in 4:
			var pose := source.get_region(Rect2i(cuts[col],spec[0],cuts[col+1]-cuts[col],spec[1]-spec[0]))
			for y in pose.get_height():
				for x in pose.get_width():
					var c := pose.get_pixel(x,y)
					if c.a < 0.5:
						pose.set_pixel(x,y,Color.TRANSPARENT)
			pose=pose.get_region(pose.get_used_rect())
			if col==0:
				scale_factor=(190.0 if row==3 else 300.0)/pose.get_height()
				pose.save_png(folder+"base.png")
			pose.resize(roundi(pose.get_width()*scale_factor),roundi(pose.get_height()*scale_factor),Image.INTERPOLATE_NEAREST)
			var off := Vector2i(256-pose.get_width()/2,450-pose.get_height())
			sheet.blit_rect(pose,Rect2i(Vector2i.ZERO,pose.get_size()),Vector2i(512*col,0)+off)
			reference.blit_rect(pose,Rect2i(Vector2i.ZERO,pose.get_size()),Vector2i(512*(col%2),512*(col/2))+off)
			frames.append({"head":[256+(75 if row==3 else 10),off.y+25],"hand":[256+pose.get_width()*(0.38 if col!=2 else 0.47),off.y+pose.get_height()*0.35],"air":false})
			if col==0:
				var select:=Image.create_empty(800,1000,false,Image.FORMAT_RGBA8)
				var figure:=pose.duplicate() as Image
				figure.resize(roundi(figure.get_width()*2.15),roundi(figure.get_height()*2.15),Image.INTERPOLATE_NEAREST)
				select.blit_rect(figure,Rect2i(Vector2i.ZERO,figure.get_size()),Vector2i(400-figure.get_width()/2,900-figure.get_height()))
				select.save_webp(base+"_select.webp",false)
				var portrait:=Image.create_empty(640,640,false,Image.FORMAT_RGBA8)
				portrait.blit_rect(figure,Rect2i(Vector2i.ZERO,figure.get_size()),Vector2i(320-figure.get_width()/2,55))
				portrait.save_webp(base+"_portrait.webp",false)
		reference.save_png(folder+"reference.png")
		sheet.save_webp(base+".webp",false)
		var anim:={}
		for key in ["idle","hold","charge","win","lose","run","dash","jump","throw","lob","special","slap","catch","block","knock"]:
			var idx:=0
			if key in ["run","dash","jump"]: idx=1
			if key in ["throw","lob","special","slap"]: idx=2
			if key in ["catch","block","knock","win"]: idx=3
			anim[key]={"start":idx,"count":1,"loop":false,"fps":10}
		anim.run={"start":0,"count":2,"loop":true,"fps":8}
		FileAccess.open(base+".json",FileAccess.WRITE).store_string(JSON.stringify({"frame_size":512,"columns":4,"anchor":[256,450],"frames":frames,"animations":anim,"pixel_art":true},"  "))
	quit()
