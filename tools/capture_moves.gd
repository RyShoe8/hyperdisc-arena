## Run with Godot --path . --script tools/capture_moves.gd -- --out=ABSOLUTE_DIR
## Writes 30 fps PNG sequences. tools/encode_moves.py trims and encodes them.
extends SceneTree

const Session := preload("res://scripts/game/tutorial_session.gd")
const Demo := preload("res://scripts/game/move_demo.gd")
const UI := preload("res://scripts/game/ui/theme.gd")

var canvas: Node2D
var view
var output := ""

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	if output.is_empty():
		printerr("Pass --out=ABSOLUTE_DIR")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	canvas = Node2D.new()
	canvas.draw.connect(func():
		if view != null: view.draw(canvas))
	root.add_child(canvas)
	_record.call_deferred()

func _record() -> void:
	UI.load_fonts()
	# Settings' autoload may have restored a fullscreen window after _initialize.
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(960, 540)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await process_frame
	var view_script = load("res://scripts/game/view/match_view.gd")
	# Record art without random camera shake or unrelated music/UI activity.
	get_root().get_node("Settings").shake = 0
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var manifest := []
	var names: Array[String] = ["DEMO", "TRAINING PARTNER"]
	for lesson in Session.LESSONS.size():
		var session := Session.new(config)
		session.lesson = lesson
		session.reset()
		view = view_script.new(session.sim, ["mick", "tiffany"], names)
		var folder := output.path_join("%02d" % lesson)
		DirAccess.make_dir_recursive_absolute(folder)
		var complete_at := -1
		var frame := 0
		var inputs := []
		# 0.5 s lead-in, the successful action, then 1.5 s of follow-through.
		for tick in 300:
			var input := {}
			if tick >= 30:
				if not session.passed:
					input = Demo.input(session, tick - 29)
					session.step(input)
					if session.failed:
						printerr("Cannot record %s: %s" % [Session.LESSONS[lesson][0], session.feedback])
						quit(1)
						return
				else:
					session.sim.step([{}, {}])
				for e in session.sim.events: view.handle(e)
				if session.passed and complete_at < 0: complete_at = tick
			view.tick()
			if tick % 2 == 0:
				canvas.queue_redraw()
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				if image.get_size() != Vector2i(960, 540):
					image.resize(960, 540, Image.INTERPOLATE_LANCZOS)
				var error := image.save_png(folder.path_join("%04d.png" % frame))
				if error != OK:
					printerr("Frame capture failed: %d" % error)
					quit(1)
					return
				inputs.append(input)
				frame += 1
			if complete_at >= 0 and tick >= complete_at + 90: break
		if complete_at < 0:
			printerr("Demo never completed: %d" % lesson)
			quit(1)
			return
		manifest.append({"lesson": lesson, "name": Session.LESSONS[lesson][0], "frames": frame, "fps": 30, "inputs": inputs})
		print("RECORDED %02d %s (%d frames)" % [lesson, Session.LESSONS[lesson][0], frame])
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	quit()
