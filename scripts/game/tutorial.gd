## Interactive front end for TutorialSession; the court uses the normal view.
extends RefCounted

const Session := preload("res://scripts/game/tutorial_session.gd")
const MatchView := preload("res://scripts/game/view/match_view.gd")
const UI := preload("res://scripts/game/ui/theme.gd")

var host: Node2D
var session: Session
var view: MatchView
var arena: Node2D
var ready := true
var countdown := 0
var settled := 0

func _init(main: Node2D) -> void:
	host = main
	arena = Node2D.new()
	arena.position = Vector2(18, 170)
	arena.scale = Vector2(0.67, 0.67)
	arena.draw.connect(_draw_arena)
	host.add_child(arena)
	arena.hide()

func open(at := -1) -> void:
	session = Session.new(host.balance)
	if at < 0:
		var progress := ConfigFile.new()
		progress.load("user://tutorial.cfg")
		at = int(progress.get_value("tutorial", "next_lesson", 0))
	session.lesson = clampi(at, 0, Session.LESSONS.size() - 1)
	_reset()
	host.online = false
	host._go(host.Screen.TUTORIAL)
	arena.show()

func _reset() -> void:
	session.reset()
	host.sim = session.sim
	view = MatchView.new(session.sim, ["mick", "tiffany"], ["YOU", "TRAINING PARTNER"])
	ready = true
	countdown = 0
	settled = 0
	arena.queue_redraw()

func tick() -> void:
	if Controls.pressed(0, "start"):
		arena.hide()
		host._go(host.Screen.MAIN)
		return
	if ready or session.passed or session.failed:
		settled += 1
		if session.passed and settled <= 90:
			# Let the successful move play out before holding the result.
			session.sim.step([{}, {}])
			for e in session.sim.events:
				view.handle(e)
				host._sound_for(e)
		if settled > 15 and Controls.pressed(0, "b"):
			_reset()
		elif settled > 15 and Controls.pressed(0, "a"):
			if session.passed:
				if session.advance():
					_save_progress(session.lesson)
					_reset()
				else:
					_save_progress(0)
					arena.hide()
					host._go(host.Screen.MAIN)
			else:
				if session.failed:
					_reset()
				ready = false
				countdown = 90
				settled = 0
		view.tick()
	elif countdown > 0:
		countdown -= 1
	else:
		session.step(Controls.input(0))
		for e in session.sim.events:
			view.handle(e)
			host._sound_for(e)
		view.tick()
		if session.passed:
			Sfx.play("menu_confirm")
			settled = 0
	arena.queue_redraw()

func _save_progress(lesson: int) -> void:
	var progress := ConfigFile.new()
	progress.set_value("tutorial", "next_lesson", lesson)
	progress.save("user://tutorial.cfg")

func _draw_arena() -> void:
	if view == null:
		return
	view.draw(arena)
	var s := session.sim
	var centre := s.players[0].pos
	var radius := float(s.cfg.player.catch_radius)
	var color := UI.CYAN
	if session.lesson == 0:
		centre = session.target
		radius = 35
	elif session.lesson in [11, 12, 13, 17]:
		radius = session.defence_radius()
		color = UI.YELLOW if session.timing().now else UI.CYAN
	elif s.disc.state == s.Disc.AIR:
		centre = s.disc.air_to
	# Project a real floor-space circle, showing exactly where the move works.
	var points := PackedVector2Array()
	for i in 65:
		points.append(view.proj.floor_point(centre + Vector2.from_angle(i * TAU / 64) * radius))
	arena.draw_polyline(points, color, 4, true)
	UI.text(arena, view.proj.floor_point(centre) + Vector2(0, 75),
		"MOVE HERE" if session.lesson == 0 else "MOVE RANGE" if session.lesson in [11, 12, 13, 17] else "LANDING RING" if s.disc.state == s.Disc.AIR else "YOUR FLOOR CIRCLE",
		24, color)

func _label(action: String) -> String:
	return Controls.label(0, action)

func draw() -> void:
	UI.outrun_background(host, host.SCREEN, host.frame / 60.0, 0.25)
	var lesson: Array = Session.LESSONS[session.lesson]
	UI.text(host, Vector2(55, 72), "HOW TO PLAY", 58, UI.YELLOW, UI.display, 0, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(host, Vector2(1860, 66), "LESSON %02d / %02d" % [session.lesson + 1, Session.LESSONS.size()], 30, UI.CYAN, null, 0, HORIZONTAL_ALIGNMENT_RIGHT)
	UI.meter(host, Rect2(55, 103, 1805, 14), (session.lesson + (1 if session.passed else 0)) / float(Session.LESSONS.size()), UI.CYAN, Session.LESSONS.size())
	UI.slant_panel(host, Rect2(1335, 150, 535, 830), UI.DEEP, UI.CYAN, 15, 3)
	UI.text(host, Vector2(1365, 207), lesson[0], UI.fit_size(lesson[0], 44, 470, UI.display), UI.YELLOW, UI.display, 0, HORIZONTAL_ALIGNMENT_LEFT)
	var instructions: String = lesson[1]
	for action in ["a", "b", "jump", "slap"]:
		instructions = instructions.replace("{" + action + "}", _label(action))
	for pair in [["curve_ms", session.balance.throw.motion_window_ticks], ["lob_ms", session.balance.air.lob_shallow_after_ticks], ["quick_ms", session.balance.throw.supersonic_window_ticks], ["charge_ms", session.balance.charge.ticks_needed]]:
		instructions = instructions.replace("{" + pair[0] + "}", str(roundi(float(pair[1]) * 1000 / 60)))
	_paragraph(instructions, Vector2(1365, 253), 475, 25)
	_controller(Vector2(1600, 520))
	var cue: Dictionary = session.timing()
	var text: String = cue.text
	if ready: text = "READ FIRST. START WHEN READY."
	elif countdown > 0: text = "GET READY  %.1f s" % (countdown / 60.0)
	elif session.passed: text = "MOVE COMPLETE"
	elif session.failed: text = "TRY AGAIN"
	var color := UI.YELLOW if cue.now else UI.CYAN
	UI.text(host, Vector2(1600, 735), text, UI.fit_size(text, 29, 470), color)
	UI.meter(host, Rect2(1370, 759, 465, 18), float(cue.value) if not ready else 0, color)
	if session.lesson == 5:
		_curve_sequence()
	elif session.lesson in [8, 9, 19]:
		_paragraph("Jump window: %.2f-%.2f s after GO.\nStay on the ring; the cue assumes you stay there." % [session.jump_window.x / 60.0, session.jump_window.y / 60.0], Vector2(1365, 817), 475, 22)
	elif session.lesson == 10:
		_paragraph("Catch > finish knockback > tap throw.\nThe quick-return clock counts held ticks, not hitstop or knockback.", Vector2(1365, 817), 475, 22)
	else:
		_paragraph("You play on the LEFT. The cyan ring shows the real floor position.\nTap = press and release. Hold = keep it down.", Vector2(1365, 817), 475, 22)
	var status := "%s START DRILL" % _label("a")
	if session.passed:
		status = "%s NEXT LESSON   %s REPLAY" % [_label("a"), _label("b")]
		if session.lesson == Session.LESSONS.size() - 1:
			status = "ALL MOVES COMPLETE!   %s FINISH" % _label("a")
	elif session.failed:
		status = "%s RETRY DRILL" % _label("a")
		_paragraph(session.feedback, Vector2(65, 945), 1220, 27)
	elif not ready:
		status = "COMPLETE THE MOVE TO UNLOCK THE NEXT LESSON"
	UI.text(host, Vector2(655, 1008), status, UI.fit_size(status, 30, 1240), UI.WHITE)
	UI.text(host, Vector2(1860, 1050), "%s EXIT TUTORIAL" % _label("start"), 24, UI.DIM, null, 0, HORIZONTAL_ALIGNMENT_RIGHT)

func _paragraph(text: String, pos: Vector2, width: float, size: int) -> void:
	var y := pos.y
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var candidate := word if line.is_empty() else line + " " + word
			if UI.text_width(candidate, size) > width and not line.is_empty():
				UI.text(host, Vector2(pos.x, y), line, size, UI.WHITE, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
				y += size + 10
				line = word
			else:
				line = candidate
		UI.text(host, Vector2(pos.x, y), line, size, UI.WHITE, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
		y += size + 10

func _controller(centre: Vector2) -> void:
	# Physical locations use the actual bindings, including shoulder remaps.
	var body := PackedVector2Array([centre + Vector2(-220, -75), centre + Vector2(-130, -108), centre + Vector2(130, -108), centre + Vector2(220, -75), centre + Vector2(230, 100), centre + Vector2(165, 117), centre + Vector2(100, 50), centre + Vector2(-100, 50), centre + Vector2(-165, 117), centre + Vector2(-230, 100)])
	host.draw_colored_polygon(body, UI.NIGHT)
	body.append(body[0])
	host.draw_polyline(body, UI.PURPLE, 5, true)
	var action: String = Session.LESSONS[session.lesson][2]
	if session.lesson in [8, 9, 19] and session.stage == 0: action = "jump"
	var lit: bool = ready or (not session.passed and not session.failed and countdown == 0 and session.timing().now)
	var required: Array = Controls.bindings[0].pad.get(action, [])
	if session.lesson == 17:
		required = required.duplicate()
		required.append_array(Controls.bindings[0].pad.b)
	var locations := {JOY_BUTTON_A: Vector2(130, 20), JOY_BUTTON_B: Vector2(177, -27), JOY_BUTTON_X: Vector2(83, -27), JOY_BUTTON_Y: Vector2(130, -74), JOY_BUTTON_LEFT_SHOULDER: Vector2(-170, -118), JOY_BUTTON_RIGHT_SHOULDER: Vector2(180, -118)}
	for button in locations:
		var pos: Vector2 = centre + locations[button]
		var active: bool = lit and button in required
		host.draw_circle(pos, 32, UI.YELLOW if active else UI.DEEP)
		host.draw_arc(pos, 33, 0, TAU, 40, UI.YELLOW if active else UI.CYAN, 2, true)
		var label := Controls.button_name(button, Controls.is_playstation(0))
		UI.text(host, pos + Vector2(0, 7), label, UI.fit_size(label, 22, 60), UI.INK if active else UI.WHITE)
	var stick := centre + Vector2(-128, -18)
	host.draw_circle(stick, 49, UI.DEEP)
	host.draw_arc(stick, 49, 0, TAU, 40, UI.CYAN, 3, true)
	var direction := Vector2(session.last_input.get("x", 0), session.last_input.get("y", 0))
	if ready and session.lesson in [0, 1]:
		direction = Vector2.RIGHT
	elif ready and session.lesson in [2, 3, 4]:
		direction = Vector2.UP
	if ready and session.lesson == 5:
		var dirs := [Vector2.DOWN, Vector2(1, 1).normalized(), Vector2.RIGHT]
		direction = dirs[(host.frame / 20) % 3]
	if direction != Vector2.ZERO:
		host.draw_line(stick, stick + direction.normalized() * 43, UI.CYAN, 4, true)
	host.draw_circle(stick + direction.normalized() * 24, 20, UI.YELLOW if action == "move" or session.lesson in [1, 3, 4, 5] else UI.DIM)
	UI.text(host, centre + Vector2(0, 163), "%s  +  %s" % [_label("move"), _label(action)] if session.lesson in [1, 3, 4, 5] else "%s + %s" % [_label("a"), _label("b")] if session.lesson == 17 else "NO BUTTON - MOVE TO CATCH" if action == "move" else _label(action), 23, UI.WHITE)
	if not Controls.using_pad[0]:
		UI.text(host, centre + Vector2(0, 130), "KEYBOARD ACTIVE - PROMPTS USE YOUR KEYS", 17, UI.DIM)

func _curve_sequence() -> void:
	var index := 0
	for entry in session.sim.players[0].history:
		if index < 3 and entry.x == [2, 3, 6][index]: index += 1
	for i in 3:
		var r := Rect2(1370 + i * 155, 807, 140, 48)
		UI.button(host, r, ["DOWN", "DOWN-RIGHT", "RIGHT"][i], index > i, host.frame, 18)
	_paragraph("Complete all 3 directions, then throw.\nYellow steps show your recorded stick motion.", Vector2(1365, 893), 475, 22)
