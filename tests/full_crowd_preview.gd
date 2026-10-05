extends Node2D

var crowd: RefCounted
var background: Texture2D

func _ready() -> void:
	var out := "res://build/pixel-test/full-crowd"
	DirAccess.make_dir_recursive_absolute(out)
	var courts := ["beach","lawn","tiled","concrete","clay","stadium"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preview-court="):
			courts = [arg.get_slice("=",1)]
	for court in courts:
		background = load("res://assets/art/courts/%s_pixel.png" % court)
		crowd = load("res://scripts/game/view/pixel_crowd.gd").new(court)
		for mode in ["idle","cheer"]:
			if mode == "cheer": crowd.handle({"type":"point"})
			for tick in 45: crowd.tick()
			queue_redraw()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/%s-%s.png" % [out,court,mode])
	get_tree().quit()

func _draw() -> void:
	if background == null: return
	crowd.draw(self)
