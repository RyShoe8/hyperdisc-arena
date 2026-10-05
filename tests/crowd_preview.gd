## Visual fixture for inspecting spectator poses without waiting for a win.
extends "res://scripts/game/main.gd"

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# A connected controller leaving must not interrupt this visual fixture.
	if screen == Screen.PAUSED:
		screen = Screen.MATCH
	if frame == 60 and view != null and view.pixel_spectators != null:
		view.pixel_spectators.handle({"type":"match_over"})
	if frame == 190 and "--capture-menu" in OS.get_cmdline_user_args():
		_go(Screen.MAIN)
