## Reconstruct exact input/timing captions from the same deterministic recording.
## Godot --headless --path . --script tools/build_move_timelines.gd -- --out=CAPTURE_DIR
extends SceneTree

const Session := preload("res://scripts/game/tutorial_session.gd")
const Demo := preload("res://scripts/game/move_demo.gd")

func _init() -> void:
	var output := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = arg.trim_prefix("--out=")
	var path := output.path_join("manifest.json")
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not manifest is Array:
		printerr("Missing recording manifest")
		quit(1)
		return
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	for clip in manifest:
		var session := Session.new(config)
		session.lesson = int(clip.lesson)
		session.reset()
		var captions := []
		var pending := {}
		for tick in int(clip.frames) * 2:
			var cue := "WATCH THE BOT"
			var input := {}
			if tick >= 30:
				cue = session.timing().text
				if not session.passed:
					input = Demo.input(session, tick - 29)
					session.step(input)
				else:
					cue = "MOVE COMPLETE"
					session.sim.step([{}, {}])
			for action in ["a", "b", "jump", "slap"]:
				if input.get(action, false): pending[action] = true
			if input.get("x", 0) != 0 or input.get("y", 0) != 0:
				pending["x"] = input.get("x", 0)
				pending["y"] = input.get("y", 0)
			if tick % 2 == 0:
				captions.append({"cue": cue, "input": pending.duplicate()})
				pending.clear()
		clip.erase("inputs")
		clip["captions"] = captions
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(manifest, "\t"))
	print("Built exact input/timing captions for %d clips" % manifest.size())
	quit()
