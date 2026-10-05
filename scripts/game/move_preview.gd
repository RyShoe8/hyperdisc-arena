## One decoder, one selected move. Clips are bundled with the game and silent.
extends RefCounted

const Session := preload("res://scripts/game/tutorial_session.gd")
const UI := preload("res://scripts/game/ui/theme.gd")
const CourtProjection := preload("res://scripts/game/view/projection.gd")

var host: Node2D
var player: VideoStreamPlayer
var selected := 0
var playing := -1
var active := false
var overlay: Node2D
var video_rect := Rect2()
var timelines: Array = []
var projection

func _init(main: Node2D) -> void:
	host = main
	projection = CourtProjection.new(float(main.balance.courts[0].width), float(main.balance.courts[0].height))
	player = VideoStreamPlayer.new()
	player.expand = true
	player.loop = true
	player.volume_db = -80
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.hide()
	host.add_child(player)
	overlay = Node2D.new()
	overlay.z_index = 1
	overlay.draw.connect(_draw_caption)
	overlay.hide()
	host.add_child(overlay)
	var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/moves/manifest.json"))
	if metadata is Array: timelines = metadata

func tick(visible: bool) -> void:
	active = visible
	if not active:
		if playing >= 0:
			player.stop()
			playing = -1
		player.hide()
		overlay.hide()
		return
	if playing != selected:
		player.stop()
		player.stream = load("res://assets/moves/%02d.ogv" % selected)
		playing = selected
		player.play()
	player.show()
	overlay.show()
	overlay.queue_redraw()

func select_move(direction: int) -> void:
	selected = posmod(selected + direction, Session.LESSONS.size())
	Sfx.play("menu_move")

func replay() -> void:
	player.stop()
	playing = -1

func draw(area: Rect2) -> void:
	UI.slant_panel(host, area, UI.DEEP, UI.CYAN, 30, 4)
	UI.text(host, Vector2(area.get_center().x, area.position.y + 72), "MOVE DEMONSTRATIONS", 56, UI.YELLOW, UI.display)
	for i in Session.LESSONS.size():
		var row := Rect2(area.position + Vector2(42, 100 + i * 28), Vector2(550, 27))
		if i == selected:
			UI.slant_panel(host, row, UI.PINK, UI.CYAN, 8, 2)
		UI.text(host, row.position + Vector2(18, 21), "%02d  %s" % [i + 1, Session.LESSONS[i][0]], 21, UI.WHITE if i == selected else UI.DIM, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	var video := Rect2(area.position + Vector2(630, 104), Vector2(910, 512))
	video_rect = video
	host.draw_rect(video.grow(4), UI.CYAN)
	host.draw_rect(video, UI.NIGHT)
	player.position = video.position
	player.size = video.size
	var text: String = Session.LESSONS[selected][1]
	for action in ["a", "b", "jump", "slap"]:
		text = text.replace("{" + action + "}", Controls.label(0, action))
	for pair in [["curve_ms", host.balance.throw.motion_window_ticks], ["lob_ms", host.balance.air.lob_shallow_after_ticks], ["quick_ms", host.balance.throw.supersonic_window_ticks], ["charge_ms", host.balance.charge.ticks_needed]]:
		text = text.replace("{" + pair[0] + "}", str(roundi(float(pair[1]) * 1000 / 60)))
	host.tutorial._paragraph(text, area.position + Vector2(635, 649), 910, 21)
	UI.text(host, area.position + Vector2(50, area.size.y - 23), "UP / DOWN: SELECT MOVE", 23, UI.CYAN, null, 0, HORIZONTAL_ALIGNMENT_LEFT)

func _draw_caption() -> void:
	if not active or timelines.size() <= selected or video_rect.size == Vector2.ZERO:
		return
	var clip: Dictionary = timelines[selected]
	var captions: Array = clip.get("captions", [])
	if captions.is_empty(): return
	var frame := clampi(int(player.stream_position * 30), 0, captions.size() - 1)
	var text: String = captions[frame].cue
	if selected == 0 or selected in [11, 12, 13, 17]:
		var centre := Vector2(350, 300) if selected == 0 else Vector2(220, 300)
		var radius := 35.0 if selected == 0 else float(host.balance.defence.block_radius) if selected == 11 else float(host.balance.defence.power_toss_radius) if selected == 17 else float(host.balance.defence.slap_radius)
		var ring := PackedVector2Array()
		for i in 65:
			var floor: Vector2 = projection.floor_point(centre + Vector2.from_angle(i * TAU / 64) * radius)
			ring.append(video_rect.position + floor * video_rect.size / Vector2(1920, 1080))
		overlay.draw_polyline(ring, UI.YELLOW if text == "PRESS NOW" else UI.CYAN, 2, true)
	# Keep a one-frame tap readable for 150 ms, starting at its real press time.
	for back in range(frame, maxi(-1, frame - 5), -1):
		var input: Dictionary = captions[back].input
		var parts: Array[String] = []
		var x := int(input.get("x", 0))
		var y := int(input.get("y", 0))
		if y != 0: parts.append("UP" if y < 0 else "DOWN")
		if x != 0: parts.append("LEFT" if x < 0 else "RIGHT")
		var button := false
		for action in ["a", "b", "jump", "slap"]:
			if input.get(action, false):
				parts.append(Controls.label(0, action))
				button = true
		if button or (back == frame and not parts.is_empty()):
			text = "BOT: " + " + ".join(parts)
			break
	var box := Rect2(video_rect.position + Vector2(140, video_rect.size.y - 68), Vector2(video_rect.size.x - 280, 47))
	UI.slant_panel(overlay, box, Color(UI.NIGHT, 0.95), UI.YELLOW, 12, 2)
	UI.text(overlay, box.position + Vector2(box.size.x / 2, 33), text, UI.fit_size(text, 25, box.size.x - 28), UI.YELLOW)
