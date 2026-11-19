extends SceneTree
func _initialize():
	for id in ["alex","jimmy","jason","tango"]:
		var img := Image.load_from_file(ProjectSettings.globalize_path("res://tools/art/characters/%s/portrait-v1.png" % id))
		if img == null or not img.detect_alpha():
			push_error("Portrait requires transparent background: "+id)
			quit(1)
			return
		img.resize(640,640,Image.INTERPOLATE_LANCZOS)
		if img.save_webp(ProjectSettings.globalize_path("res://assets/art/characters/%s_portrait.webp" % id),false) != OK:
			quit(1)
			return
		var figure := Image.load_from_file("res://tools/art/characters/%s/select-v1.png" % id)
		if figure == null or not figure.detect_alpha():
			push_error("Missing transparent select illustration: "+id)
			quit(1)
			return
		figure = figure.get_region(figure.get_used_rect())
		var scale := minf(556.0/figure.get_width(), (348.0 if id == "tango" else 560.0)/figure.get_height())
		figure.resize(roundi(figure.get_width()*scale),roundi(figure.get_height()*scale),Image.INTERPOLATE_LANCZOS)
		var card := Image.create_empty(640,640,false,Image.FORMAT_RGBA8)
		card.blit_rect(figure,Rect2i(Vector2i.ZERO,figure.get_size()),Vector2i(320-figure.get_width()/2,600-figure.get_height()))
		if card.save_webp("res://assets/art/characters/%s_select.webp" % id,true) != OK:
			quit(1)
			return
	quit()
