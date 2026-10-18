## Find low-change seams between authored audience poses. Keep animation
## groups in their original seats, avoiding arbitrary sprite-grid cuts.
extends SceneTree
func _initialize() -> void:
	for id in ["beach","lawn","tiled","concrete","clay","stadium"]:
		var crowd = load("res://scripts/game/view/pixel_crowd.gd").new(id)
		crowd.sections.clear()
		crowd._build_sections(id)
		var images: Array[Image] = []
		for pose in ["watch","clap","cheer","surprise"]:
			var path: String = "res://assets/art/courts/%s_pixel.png" % id if pose == "watch" else "res://assets/art/crowds/%s_%s.png" % [id,pose]
			var im := Image.load_from_file(path)
			im.resize(1920,1080,Image.INTERPOLATE_NEAREST)
			images.append(im)
		var groups: Array = []
		for section in crowd.sections:
			var vertical: bool = section.size.x < 300
			var length := int(section.size.y if vertical else section.size.x)
			var across := int(section.size.x if vertical else section.size.y)
			var energy := PackedFloat32Array()
			energy.resize(length)
			for along in length:
				var total := 0.0
				for cross in range(0,across,2):
					var p := Vector2i(section.position)+ (Vector2i(cross,along) if vertical else Vector2i(along,cross))
					var base := images[0].get_pixelv(p)
					for i in range(1,4):
						var c := images[i].get_pixelv(p)
						total += absf(c.r-base.r)+absf(c.g-base.g)+absf(c.b-base.b)
				energy[along]=total
			var cuts: Array[int]=[0]
			var spacing := 110 if vertical else 125
			for target in range(spacing,length-40,spacing):
				var best := target
				var score := INF
				for candidate in range(maxi(cuts[-1]+50,target-25),mini(length-30,target+26)):
					var cost := 0.0
					for n in range(maxi(0,candidate-2),mini(length,candidate+3)): cost += energy[n]
					if cost < score:
						score=cost
						best=candidate
				cuts.append(best)
			cuts.append(length)
			for i in cuts.size()-1:
				var start: Vector2 = section.position + (Vector2(0,cuts[i]) if vertical else Vector2(cuts[i],0))
				var size := Vector2(section.size.x,cuts[i+1]-cuts[i]) if vertical else Vector2(cuts[i+1]-cuts[i],section.size.y)
				groups.append([start.x,start.y,size.x,size.y])
		assert(groups.size()<=64)
		FileAccess.open("res://assets/art/crowds/%s_groups.json" % id,FileAccess.WRITE).store_string(JSON.stringify(groups))
		print(id,": ",groups.size()," independent audience groups")
	quit()
