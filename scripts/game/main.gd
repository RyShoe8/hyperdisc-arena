## Prototype front end: menu, match loop, pause and placeholder drawing.
## Runs the sim once per physics tick (60 Hz). Fully playable on controllers.
extends Node2D

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")

const BALANCE_PATH := "res://data/balance.json"
const COURT_OFFSET := Vector2(140, 110)
const DIFFICULTIES := ["easy", "normal", "hard"]
const MODES := ["VS CPU", "VS PLAYER 2"]
const ROW_MODE := 0
const ROW_P1 := 1
const ROW_OPPONENT := 2
const ROW_START := 3
const PAUSE_OPTIONS := ["RESUME", "QUIT TO MENU"]

const COLOR_BG := Color("101626")
const COLOR_COURT := Color("1d3557")
const COLOR_LINE := Color("e9ecef")
const COLOR_DIM := Color("8d99ae")
const COLOR_ZONE_3 := Color("ffd166")
const COLOR_ZONE_5 := Color("ef476f")
const COLOR_P1 := Color("06d6a0")
const COLOR_P2 := Color("4cc9f0")
const COLOR_DISC := Color("ffffff")

enum Screen { MENU, MATCH, PAUSED }

var balance: Dictionary
var sim: MatchSim
var cpu: CpuPlayer
var screen: int = Screen.MENU
var mode := 0
var menu_row := ROW_START
var p1_character := 2
var p2_character := 3
var difficulty := 1
var pause_index := 0
var paused_by := 0
var banner := ""
var banner_ticks := 0
var toast := ""
var toast_ticks := 0


func _ready() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	RenderingServer.set_default_clear_color(COLOR_BG)
	Controls.changed.connect(_on_controls_changed)


func _physics_process(_delta: float) -> void:
	match screen:
		Screen.MENU:
			_menu_input()
		Screen.PAUSED:
			_pause_input()
		Screen.MATCH:
			_match_tick()
	if banner_ticks > 0:
		banner_ticks -= 1
	if toast_ticks > 0:
		toast_ticks -= 1
	queue_redraw()


func _is_versus() -> bool:
	return mode == 1


# --- Menu ------------------------------------------------------------------

func _menu_input() -> void:
	var nudge := Controls.nudged(0)
	if nudge.y != 0:
		menu_row = posmod(menu_row + nudge.y, ROW_START + 1)
	if nudge.x != 0:
		_change_row(menu_row, nudge.x)
	# Player 2 picks their own character in versus mode.
	if _is_versus() and Controls.nudged(1).x != 0:
		_change_row(ROW_OPPONENT, Controls.nudged(1).x)
	if Controls.pressed(0, "a") or Controls.pressed(0, "start"):
		if menu_row == ROW_START or Controls.pressed(0, "start"):
			_start_match()
		else:
			menu_row = ROW_START


func _change_row(row: int, step: int) -> void:
	var count: int = balance.characters.size()
	match row:
		ROW_MODE:
			mode = posmod(mode + step, MODES.size())
		ROW_P1:
			p1_character = posmod(p1_character + step, count)
		ROW_OPPONENT:
			if _is_versus():
				p2_character = posmod(p2_character + step, count)
			else:
				difficulty = posmod(difficulty + step, DIFFICULTIES.size())


func _start_match() -> void:
	var characters: Array = balance.characters
	var seed_value := int(Time.get_ticks_usec())
	var opponent: Dictionary
	if _is_versus():
		opponent = characters[p2_character]
		cpu = null
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		opponent = characters[rng.randi_range(0, characters.size() - 1)]
		cpu = CpuPlayer.new(MatchSim.RIGHT, balance.cpu[DIFFICULTIES[difficulty]], seed_value)
	sim = MatchSim.new(balance, characters[p1_character], opponent)
	screen = Screen.MATCH
	banner = ""
	banner_ticks = 0


# --- Match -----------------------------------------------------------------

func _match_tick() -> void:
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		if Controls.any_pressed("a") or Controls.any_pressed("start"):
			screen = Screen.MENU
		return
	for i in [0, 1] if _is_versus() else [0]:
		if Controls.pressed(i, "start"):
			_pause(i)
			return
	var right: Dictionary = Controls.input(1) if _is_versus() else cpu.think(sim)
	sim.step([Controls.input(0), right])
	_handle_events()


func _handle_events() -> void:
	for e in sim.events:
		match e.type:
			"throw":
				if e.supersonic:
					_show("SUPERSONIC!", 40)
					_rumble(e.side, 0.3, 0.0, 0.08)
			"catch":
				var knock := absf(sim.players[e.side].knock_vel)
				_rumble(e.side, 0.4, clampf(knock / 8.0, 0.1, 1.0), 0.12)
			"bounce":
				pass
			"point":
				var how: String = {"goal": "", "miss": " (miss)", "carried": " (carried in)"}[e.reason]
				_show("%s +%d%s" % [_side_name(e.side), e.points, how], 80)
				_rumble(1 - e.side, 0.6, 0.8, 0.3)
			"set_end":
				_show("SET %d OVER  %d - %d" % [e.set, e.scores[0], e.scores[1]], 140)
			"match_over":
				_show("%s WINS!" % _side_name(e.winner), 999999)
				_rumble(e.winner, 0.5, 0.5, 0.6)


func _rumble(side: int, weak: float, strong: float, seconds: float) -> void:
	if side == MatchSim.LEFT or _is_versus():
		Controls.rumble(side, weak, strong, seconds)


func _side_name(side: int) -> String:
	if side == MatchSim.LEFT:
		return "P1"
	return "P2" if _is_versus() else "CPU"


func _show(text: String, ticks: int) -> void:
	banner = text
	banner_ticks = ticks


# --- Pause and controller changes -----------------------------------------

func _pause(player: int) -> void:
	paused_by = player
	pause_index = 0
	screen = Screen.PAUSED


func _pause_input() -> void:
	var nudge := Controls.nudged(paused_by)
	if nudge.y != 0:
		pause_index = posmod(pause_index + nudge.y, PAUSE_OPTIONS.size())
	if Controls.pressed(paused_by, "start") or Controls.pressed(paused_by, "b"):
		screen = Screen.MATCH
	elif Controls.pressed(paused_by, "a"):
		screen = Screen.MATCH if pause_index == 0 else Screen.MENU


func _on_controls_changed(message: String) -> void:
	toast = message
	toast_ticks = 180
	# A controller dropping out mid-match pauses the game until it is back.
	if screen == Screen.MATCH and message.ends_with("disconnected"):
		_pause(0)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	if screen == Screen.MENU:
		_draw_menu(font)
	else:
		_draw_court()
		_draw_players()
		_draw_disc()
		_draw_hud(font)
		if screen == Screen.PAUSED:
			_draw_pause(font)
	_draw_footer(font)


func _text(font: Font, y: float, text: String, size: int, color: Color) -> void:
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1280, size, color)


func _draw_menu(font: Font) -> void:
	_text(font, 130, "HYPERDISC ARENA", 64, COLOR_LINE)
	_text(font, 175, "prototype", 22, COLOR_ZONE_3)

	var c1: Dictionary = balance.characters[p1_character]
	var rows := [
		"MODE   <  %s  >" % MODES[mode],
		"P1   <  %s  >" % c1.name,
		"P2   <  %s  >" % balance.characters[p2_character].name if _is_versus()
			else "CPU   <  %s  >" % DIFFICULTIES[difficulty].to_upper(),
		"START",
	]
	var row_y := [260, 325, 415, 480]
	for i in rows.size():
		var selected := i == menu_row
		var color := COLOR_ZONE_3 if selected else COLOR_LINE
		_text(font, row_y[i], ("> %s <" % rows[i]) if selected else rows[i], 34, color)
	_text(font, 360, "speed %.2f   power %.2f   weight %.2f" % [c1.speed, c1.power, c1.weight], 16, COLOR_DIM)

	_text(font, 560, "P1: %s        P2: %s" % [Controls.pad_name(0), Controls.pad_name(1)], 18, COLOR_DIM)
	_text(font, 595, "%s: choose   %s or Enter: start   %s: throw / dash   %s: lob   quarter-circle + %s: curve" % [
		Controls.label(0, "move"), Controls.label(0, "a"), Controls.label(0, "a"),
		Controls.label(0, "b"), Controls.label(0, "a")], 18, COLOR_LINE)
	if not Controls.has_pad(0):
		_text(font, 630, "No controller found. Plug one in (in a browser, also press a button on it).",
			16, COLOR_DIM)


func _draw_court() -> void:
	var w := sim.court_width()
	var h := sim.court_height()
	draw_rect(Rect2(COURT_OFFSET, Vector2(w, h)), COLOR_COURT)
	draw_rect(Rect2(COURT_OFFSET, Vector2(w, h)), COLOR_LINE, false, 3.0)
	var net := COURT_OFFSET + Vector2(sim.net_x(), 0)
	draw_line(net, net + Vector2(0, h), COLOR_LINE, 4.0)
	for zone in balance.court.zones:
		var color := COLOR_ZONE_5 if int(zone.points) == 5 else COLOR_ZONE_3
		var y0 := float(zone.from) * h
		var y1 := float(zone.to) * h
		for x in [-10.0, w]:
			draw_rect(Rect2(COURT_OFFSET + Vector2(x, y0), Vector2(10, y1 - y0)), color)


func _draw_players() -> void:
	var r := float(balance.player.radius)
	for p in sim.players:
		var color := COLOR_P1 if p.side == MatchSim.LEFT else COLOR_P2
		if p.knock_ticks > 0:
			color = color.lightened(0.5)
		var rect := Rect2(COURT_OFFSET + p.pos - Vector2(r, r), Vector2(r, r) * 2.0)
		draw_rect(rect, color)
		if p.holding:
			var limit := float(balance.player.serve_hold_limit_ticks if p.serving
				else balance.player.hold_limit_ticks)
			var left := 1.0 - float(p.hold_ticks) / limit
			draw_rect(Rect2(rect.position + Vector2(0, -10), Vector2(rect.size.x * left, 5)), COLOR_ZONE_3)


func _draw_disc() -> void:
	var d := sim.disc
	var r := float(balance.court.disc_radius)
	var ground := COURT_OFFSET + d.pos
	if d.state == MatchSim.Disc.LOB:
		draw_arc(COURT_OFFSET + d.lob_to, r * 1.6, 0, TAU, 24, COLOR_ZONE_5, 2.0)
		draw_circle(ground, r, Color(0, 0, 0, 0.35))
	var color := COLOR_ZONE_3 if d.supersonic and d.state == MatchSim.Disc.FLYING else COLOR_DISC
	draw_circle(ground - Vector2(0, d.z), r, color)


func _draw_hud(font: Font) -> void:
	draw_string(font, Vector2(140, 60), "P1  %d" % sim.scores[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 40, COLOR_P1)
	draw_string(font, Vector2(840, 60), "%s  %d" % [_side_name(MatchSim.RIGHT), sim.scores[1]],
		HORIZONTAL_ALIGNMENT_RIGHT, 300, 40, COLOR_P2)
	var timer := "SUDDEN DEATH" if sim.sudden_death else "%d" % ceili(sim.set_ticks_left / 60.0)
	_text(font, 60, timer, 40, COLOR_LINE)
	_text(font, 92, "SET %d   sets %d - %d" % [sim.set_number, sim.sets_won[0], sim.sets_won[1]], 20, COLOR_LINE)
	if banner_ticks > 0:
		_text(font, 700, banner, 30, COLOR_ZONE_3)
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		_text(font, 390, "Press %s for the menu" % Controls.label(0, "a"), 24, COLOR_LINE)


func _draw_pause(font: Font) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0, 0, 0, 0.6))
	_text(font, 280, "PAUSED (P%d)" % (paused_by + 1), 48, COLOR_LINE)
	for i in PAUSE_OPTIONS.size():
		var selected := i == pause_index
		_text(font, 360 + i * 56, ("> %s <" % PAUSE_OPTIONS[i]) if selected else PAUSE_OPTIONS[i],
			32, COLOR_ZONE_3 if selected else COLOR_LINE)


func _draw_footer(font: Font) -> void:
	if toast_ticks > 0:
		_text(font, 30, toast, 20, COLOR_ZONE_3)
