## Prototype front end: a character/difficulty menu and the match itself,
## drawn with plain shapes. Runs the sim once per physics tick (60 Hz).
extends Node2D

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")

const BALANCE_PATH := "res://data/balance.json"
const COURT_OFFSET := Vector2(140, 110)
const DIFFICULTIES := ["easy", "normal", "hard"]

const COLOR_BG := Color("101626")
const COLOR_COURT := Color("1d3557")
const COLOR_LINE := Color("e9ecef")
const COLOR_ZONE_3 := Color("ffd166")
const COLOR_ZONE_5 := Color("ef476f")
const COLOR_P1 := Color("06d6a0")
const COLOR_P2 := Color("4cc9f0")
const COLOR_DISC := Color("ffffff")

var balance: Dictionary
var sim: MatchSim
var cpu: CpuPlayer
var in_menu := true
var character_index := 2
var difficulty_index := 1
var banner := ""
var banner_ticks := 0


func _ready() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	RenderingServer.set_default_clear_color(COLOR_BG)


func _physics_process(_delta: float) -> void:
	if in_menu:
		_menu_input()
	elif sim.phase == MatchSim.Phase.MATCH_OVER:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_a"):
			in_menu = true
	else:
		sim.step([InputSetup.read("p1"), cpu.think(sim)])
		_handle_events()
	if banner_ticks > 0:
		banner_ticks -= 1
	queue_redraw()


func _menu_input() -> void:
	var count: int = balance.characters.size()
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("p1_left"):
		character_index = posmod(character_index - 1, count)
	if Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("p1_right"):
		character_index = posmod(character_index + 1, count)
	if Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("p1_up"):
		difficulty_index = posmod(difficulty_index - 1, DIFFICULTIES.size())
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("p1_down"):
		difficulty_index = posmod(difficulty_index + 1, DIFFICULTIES.size())
	if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("p1_a"):
		_start_match()


func _start_match() -> void:
	var characters: Array = balance.characters
	var seed_value := int(Time.get_ticks_usec())
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var opponent: Dictionary = characters[rng.randi_range(0, characters.size() - 1)]
	sim = MatchSim.new(balance, characters[character_index], opponent)
	cpu = CpuPlayer.new(MatchSim.RIGHT, balance.cpu[DIFFICULTIES[difficulty_index]], seed_value)
	in_menu = false
	banner = ""


func _handle_events() -> void:
	for e in sim.events:
		match e.type:
			"throw":
				if e.supersonic:
					_show("SUPERSONIC!", 40)
			"point":
				var who := "P1" if e.side == MatchSim.LEFT else "CPU"
				var how: String = {"goal": "", "miss": " (miss)", "carried": " (carried in)"}[e.reason]
				_show("%s +%d%s" % [who, e.points, how], 80)
			"set_end":
				_show("SET %d OVER  %d - %d" % [e.set, e.scores[0], e.scores[1]], 140)
			"match_over":
				_show("%s WINS!" % ("P1" if e.winner == MatchSim.LEFT else "CPU"), 999999)


func _show(text: String, ticks: int) -> void:
	banner = text
	banner_ticks = ticks


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	if in_menu:
		_draw_menu()
		return
	_draw_court()
	_draw_players()
	_draw_disc()
	_draw_hud()


func _draw_menu() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(0, 160), "HYPERDISC ARENA", HORIZONTAL_ALIGNMENT_CENTER, 1280, 64, COLOR_LINE)
	draw_string(font, Vector2(0, 220), "prototype", HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, COLOR_ZONE_3)
	var c: Dictionary = balance.characters[character_index]
	draw_string(font, Vector2(0, 330), "<  %s  >" % c.name, HORIZONTAL_ALIGNMENT_CENTER, 1280, 40, COLOR_P1)
	draw_string(font, Vector2(0, 375), "speed %.2f   power %.2f   weight %.2f" % [c.speed, c.power, c.weight],
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 20, COLOR_LINE)
	draw_string(font, Vector2(0, 450), "CPU: %s" % DIFFICULTIES[difficulty_index].to_upper(),
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, COLOR_P2)
	draw_string(font, Vector2(0, 560),
		"Left/Right: character   Up/Down: difficulty   Enter or A: play",
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 18, COLOR_LINE)
	draw_string(font, Vector2(0, 600),
		"In game: WASD / stick to move or aim   J / A: throw, dash   K / B: lob   quarter-circle + throw: curve",
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 18, COLOR_LINE)


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
			var limit := float(balance.player.serve_hold_limit_ticks if p.serving else balance.player.hold_limit_ticks)
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


func _draw_hud() -> void:
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(140, 60), "P1  %d" % sim.scores[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 40, COLOR_P1)
	draw_string(font, Vector2(840, 60), "CPU  %d" % sim.scores[1], HORIZONTAL_ALIGNMENT_RIGHT, 300, 40, COLOR_P2)
	var timer := "SUDDEN DEATH" if sim.sudden_death else "%d" % ceili(sim.set_ticks_left / 60.0)
	draw_string(font, Vector2(0, 60), timer, HORIZONTAL_ALIGNMENT_CENTER, 1280, 40, COLOR_LINE)
	draw_string(font, Vector2(0, 92), "SET %d   sets %d - %d" % [sim.set_number, sim.sets_won[0], sim.sets_won[1]],
		HORIZONTAL_ALIGNMENT_CENTER, 1280, 20, COLOR_LINE)
	if banner_ticks > 0:
		draw_string(font, Vector2(0, 700), banner, HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, COLOR_ZONE_3)
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		draw_string(font, Vector2(0, 390), "Press Enter or A for the menu", HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, COLOR_LINE)
