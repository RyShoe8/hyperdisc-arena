extends SceneTree
func _initialize():
	for id in ["alex","jimmy","jason","tango"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/art/characters/%s/portrait-v1.png" % id))
		if img == null or not img.detect_alpha():
			push_error("Portrait requires transparent background: "+id)
			quit(1)
			return
		img.resize(640,640,Image.INTERPOLATE_NEAREST)
		if img.save_webp(ProjectSettings.globalize_path("res://assets/art/characters/%s_portrait.webp" % id),false) != OK:
			quit(1)
			return
	quit()
