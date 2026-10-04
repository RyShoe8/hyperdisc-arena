## Front end: menu, match loop, pause, and all drawing and sound.
## Runs the sim once per physics tick (60 Hz). Fully playable on controllers.
##
## Art: Kenney Sports Pack and UI Pack; sound: Kenney Interface Sounds; font:
## Kenney Future. All CC0 (see assets/LICENSE-kenney.txt).
extends Node2D

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")

const BALANCE_PATH := "res://data/balance.json"
const SCREEN := Vector2(1280, 720)
const COURT_OFFSET := Vector2(140, 120)
const DIFFICULTIES := ["easy", "normal", "hard"]
const MODES := ["VS CPU", "VS PLAYER 2"]
const ROW_MODE := 0
const ROW_P1 := 1
const ROW_OPPONENT := 2
const ROW_COURT := 3
const ROW_START := 4
const PAUSE_OPTIONS := ["RESUME", "QUIT TO MENU"]

## Court surfaces, colours sampled from the Kenney Sports Pack ground sheets.
## Cosmetic for now; per-court rules (zones, barriers) come later.
const COURTS := [
	{"name": "LAWN", "surface": Color("2ecc71"), "stripe": Color("31d978"), "line": Color("ffffff")},
	{"name": "BEACH", "surface": Color("d9cca3"), "stripe": Color("d9cca3"), "line": Color("419fdd")},
	{"name": "CLAY", "surface": Color("d7773f"), "stripe": Color("dc7f48"), "line": Color("ffffff")},
	{"name": "ICE", "surface": Color("f5f6ff"), "stripe": Color("eceefc"), "line": Color("419fdd")},
	{"name": "CONCRETE", "surface": Color("89a4a6"), "stripe": Color("8eaaac"), "line": Color("ffffff")},
]
## Kenney character variant per balance.json character, in order.
const CHARACTER_SPRITES := [1, 2, 3, 4, 5, 9]
const SPRITE_SCALE := 2.4
const DISC_SCALE := 1.7

const COLOR_BG := Color("16213e")
const COLOR_TEXT := Color("f1f2f6")
const COLOR_DARK := Color("2f3542")
const COLOR_DIM := Color("a4b0be")
const COLOR_ZONE_3 := Color("ffd166")
const COLOR_ZONE_5 := Color("ef476f")
const COLOR_P1 := Color("e8603c")
const COLOR_P2 := Color("3c9ee8")
const COLOR_GOLD := Color("ffd166")

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
var court := 0
var pause_index := 0
var paused_by := 0
var banner := ""
var banner_ticks := 0
var toast := ""
var toast_ticks := 0
var frame := 0

# Visual effects that live only in the view, never in the sim.
var disc_spin := 0.0
var trail: Array[Vector2] = []
var shake := 0.0
var bursts: Array = []
var last_second := -1

var font: Font
var tex_disc: Texture2D
var tex_sprites := {}
var tex_arrow_left: Texture2D
var tex_arrow_right: Texture2D
var tex_star: Texture2D
var tex_star_empty: Texture2D
var box_button: StyleBoxTexture
var box_button_selected: StyleBoxTexture
var box_panel: StyleBoxTexture
var box_p1: StyleBoxTexture
var box_p2: StyleBoxTexture


func _ready() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	RenderingServer.set_default_clear_color(COLOR_BG)
	Controls.changed.connect(_on_controls_changed)
	_load_assets()


func _load_assets() -> void:
	font = load("res://assets/fonts/kenney_future.ttf")
	tex_disc = load("res://assets/sprites/disc.png")
	for team in ["red", "blue"]:
		for v in CHARACTER_SPRITES:
			tex_sprites["%s_%d" % [team, v]] = load("res://assets/sprites/characters/%s_%d.png" % [team, v])
	tex_arrow_left = load("res://assets/ui/arrow_left.png")
	tex_arrow_right = load("res://assets/ui/arrow_right.png")
	tex_star = load("res://assets/ui/star.png")
	tex_star_empty = load("res://assets/ui/star_empty.png")
	box_button = _box("res://assets/ui/button.png")
	box_button_selected = _box("res://assets/ui/button_selected.png")
	box_panel = _box("res://assets/ui/panel.png")
	box_p1 = _box("res://assets/ui/panel_p1.png")
	box_p2 = _box("res://assets/ui/panel_p2.png")


## Nine-slice box from a Kenney UI button, so it stretches cleanly.
func _box(path: String) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = load(path)
	box.texture_margin_left = 12
	box.texture_margin_right = 12
	box.texture_margin_top = 12
	box.texture_margin_bottom = 16
	return box


func _physics_process(_delta: float) -> void:
	frame += 1
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
	shake = maxf(0.0, shake - 0.6)
	for b in bursts:
		b.age += 1
	bursts = bursts.filter(func(b): return b.age < 30)
	queue_redraw()


func _is_versus() -> bool:
	return mode == 1


# --- Menu ------------------------------------------------------------------

func _menu_input() -> void:
	# Any keyboard or controller can drive the menu.
	var nudge := Controls.menu_nudged(_is_versus())
	if nudge.y != 0:
		menu_row = posmod(menu_row + nudge.y, ROW_START + 1)
		Sfx.play("menu_move")
	if nudge.x != 0 and menu_row != ROW_START:
		_change_row(menu_row, nudge.x)
		Sfx.play("menu_move", 1.15)
	# Player 2 picks their own character in versus mode.
	if _is_versus() and Controls.has_pad(1) and Controls.nudged(1).x != 0:
		_change_row(ROW_OPPONENT, Controls.nudged(1).x)
		Sfx.play("menu_move", 1.15)
	var start_device := Controls.menu_pressed("start")
	var a_device := Controls.menu_pressed("a")
	if start_device != -1 or (a_device != -1 and menu_row == ROW_START):
		# Whoever starts the match is player 1.
		Controls.make_player_one(start_device if start_device != -1 else a_device)
		Sfx.play("menu_confirm")
		_start_match()
	elif a_device != -1:
		menu_row = ROW_START
		Sfx.play("menu_move")


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
		ROW_COURT:
			court = posmod(court + step, COURTS.size())


func _start_match() -> void:
	var characters: Array = balance.characters
	var seed_value := int(Time.get_ticks_usec())
	if _is_versus():
		cpu = null
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		p2_character = rng.randi_range(0, characters.size() - 1)
		cpu = CpuPlayer.new(MatchSim.RIGHT, balance.cpu[DIFFICULTIES[difficulty]], seed_value)
	sim = MatchSim.new(balance, characters[p1_character], characters[p2_character])
	screen = Screen.MATCH
	banner = ""
	banner_ticks = 0
	trail.clear()
	bursts.clear()
	last_second = -1


# --- Match -----------------------------------------------------------------

func _match_tick() -> void:
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		if Controls.menu_pressed("a") != -1 or Controls.menu_pressed("start") != -1:
			Sfx.play("menu_back")
			screen = Screen.MENU
		return
	for i in [0, 1] if _is_versus() else [0]:
		if Controls.pressed(i, "start"):
			_pause(i)
			return
	var right: Dictionary = Controls.input(1) if _is_versus() else cpu.think(sim)
	sim.step([Controls.input(0), right])
	_handle_events()
	_update_effects()


func _handle_events() -> void:
	for e in sim.events:
		match e.type:
			"throw":
				if e.supersonic:
					_show("SUPERSONIC!", 40)
					Sfx.play("supersonic")
					_rumble(e.side, 0.3, 0.0, 0.08)
				else:
					Sfx.play("throw", randf_range(0.95, 1.1))
			"lob":
				Sfx.play("lob")
			"catch":
				var knock := absf(sim.players[e.side].knock_vel)
				Sfx.play("catch", randf_range(0.9, 1.1), -2.0 + minf(knock, 6.0))
				_rumble(e.side, 0.4, clampf(knock / 8.0, 0.1, 1.0), 0.12)
				shake = maxf(shake, knock * 0.8)
			"bounce":
				Sfx.play("bounce", randf_range(0.9, 1.2), -6.0)
			"point":
				var how: String = {"goal": "", "miss": "  MISS", "carried": "  CARRIED IN"}[e.reason]
				_show("%s +%d%s" % [_side_name(e.side), e.points, how], 80)
				Sfx.play("miss" if e.reason == "miss" else "goal")
				_rumble(1 - e.side, 0.6, 0.8, 0.3)
				shake = 10.0
				bursts.append({"pos": sim.disc.pos, "age": 0,
					"color": COLOR_ZONE_5 if e.points == 5 else COLOR_ZONE_3})
			"set_end":
				_show("SET %d OVER   %d - %d" % [e.set, e.scores[0], e.scores[1]], 140)
				Sfx.play("set_end")
			"match_over":
				_show("%s WINS!" % _side_name(e.winner), 999999)
				Sfx.play("match_win")
				_rumble(e.winner, 0.5, 0.5, 0.6)


func _update_effects() -> void:
	var d := sim.disc
	if d.state == MatchSim.Disc.FLYING:
		disc_spin += d.vel.length() * 0.05 * signf(d.vel.x)
		trail.push_front(d.pos)
		if trail.size() > 10:
			trail.pop_back()
	else:
		trail.clear()
	# Countdown ticks for the last five seconds of a set.
	if sim.set_ticks_left > 0 and (sim.phase == MatchSim.Phase.PLAY or sim.phase == MatchSim.Phase.SERVE):
		var second := ceili(sim.set_ticks_left / 60.0)
		if second != last_second and second <= 5:
			Sfx.play("countdown", 1.0 + (5 - second) * 0.08)
		last_second = second


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
	Sfx.play("pause")


func _pause_input() -> void:
	var nudge := Controls.nudged(paused_by)
	if nudge.y != 0:
		pause_index = posmod(pause_index + nudge.y, PAUSE_OPTIONS.size())
		Sfx.play("menu_move")
	if Controls.pressed(paused_by, "start") or Controls.pressed(paused_by, "b"):
		screen = Screen.MATCH
		Sfx.play("menu_back")
	elif Controls.pressed(paused_by, "a"):
		screen = Screen.MATCH if pause_index == 0 else Screen.MENU
		Sfx.play("menu_confirm" if pause_index == 0 else "menu_back")


func _on_controls_changed(message: String) -> void:
	toast = message
	toast_ticks = 180
	Sfx.play("disconnect" if message.ends_with("disconnected") else "connect")
	# A controller dropping out mid-match pauses the game until it is back.
	if screen == Screen.MATCH and message.ends_with("disconnected"):
		_pause(0)


# --- Drawing helpers -------------------------------------------------------

func _text(pos: Vector2, text: String, size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_CENTER, width := -1.0) -> void:
	draw_string(font, pos, text, align, width, size, color)


## Centred text across the whole screen at height y.
func _ctext(y: float, text: String, size: int, color: Color) -> void:
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, SCREEN.x, size, color)


## Text centred inside a rectangle.
func _rtext(rect: Rect2, text: String, size: int, color: Color) -> void:
	var y := rect.position.y + rect.size.y / 2.0 + size * 0.36
	draw_string(font, Vector2(rect.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, size, color)


func _sprite_for(character_index: int, team: String) -> Texture2D:
	return tex_sprites["%s_%d" % [team, CHARACTER_SPRITES[character_index % CHARACTER_SPRITES.size()]]]


## Draws a character sprite centred at pos, facing right or (flipped) left.
func _draw_character(tex: Texture2D, pos: Vector2, facing_right: bool, scale: float,
		tint := Color.WHITE, rotation := 0.0) -> void:
	var size := tex.get_size() * scale
	draw_set_transform(pos, rotation, Vector2(1.0 if facing_right else -1.0, 1.0))
	draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
	draw_set_transform(Vector2.ZERO)


func _draw_shadow(pos: Vector2, radius: float, alpha := 0.25) -> void:
	draw_set_transform(pos, 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, alpha))
	draw_set_transform(Vector2.ZERO)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	if screen == Screen.MENU:
		_draw_menu()
	else:
		var offset := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.5
		_draw_court(offset)
		_draw_players(offset)
		_draw_disc(offset)
		_draw_bursts(offset)
		_draw_hud()
		if screen == Screen.PAUSED:
			_draw_pause()
	_draw_toast()


func _draw_menu() -> void:
	_ctext(110, "HYPERDISC", 72, COLOR_TEXT)
	_ctext(170, "ARENA", 40, COLOR_GOLD)

	var c1: Dictionary = balance.characters[p1_character]
	var opponent := ""
	if _is_versus():
		opponent = "P2  " + str(balance.characters[p2_character].name).to_upper()
	else:
		opponent = "CPU  " + DIFFICULTIES[difficulty].to_upper()
	var rows := [
		MODES[mode],
		"P1  " + str(c1.name).to_upper(),
		opponent,
		"COURT  " + COURTS[court].name,
		"START",
	]
	var width := 460.0
	for i in rows.size():
		var rect := Rect2(Vector2((SCREEN.x - width) / 2.0, 215 + i * 74), Vector2(width, 60))
		var selected := i == menu_row
		draw_style_box(box_button_selected if selected else box_button, rect)
		_rtext(rect, rows[i], 24, COLOR_DARK)
		if selected and i != ROW_START:
			var pulse := sin(frame * 0.15) * 4.0
			draw_texture(tex_arrow_left, rect.position + Vector2(-46 - pulse, 12))
			draw_texture(tex_arrow_right, rect.position + Vector2(rect.size.x + 14 + pulse, 12))

	# Character previews either side of the menu.
	var p1_tex := _sprite_for(p1_character, "red")
	_draw_shadow(Vector2(250, 420), 40, 0.3)
	_draw_character(p1_tex, Vector2(250, 400), true, 5.0)
	_text(Vector2(130, 500), "P1", 22, COLOR_P1, HORIZONTAL_ALIGNMENT_CENTER, 240)
	_text(Vector2(130, 530), "SPD %.1f  PWR %.1f  WGT %.1f" % [c1.speed, c1.power, c1.weight],
		13, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, 240)
	if _is_versus():
		var c2: Dictionary = balance.characters[p2_character]
		_draw_shadow(Vector2(1030, 420), 40, 0.3)
		_draw_character(_sprite_for(p2_character, "blue"), Vector2(1030, 400), false, 5.0)
		_text(Vector2(910, 500), "P2", 22, COLOR_P2, HORIZONTAL_ALIGNMENT_CENTER, 240)
		_text(Vector2(910, 530), "SPD %.1f  PWR %.1f  WGT %.1f" % [c2.speed, c2.power, c2.weight],
			13, COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, 240)

	_ctext(620, "%s CHOOSE    %s START    %s THROW / DASH    %s LOB    QUARTER-CIRCLE + %s CURVE" % [
		Controls.label(0, "move"), Controls.label(0, "a"), Controls.label(0, "a"),
		Controls.label(0, "b"), Controls.label(0, "a")], 14, COLOR_TEXT)
	_ctext(648, "P1: %s      P2: %s" % [Controls.pad_name(0), Controls.pad_name(1)], 13, COLOR_DIM)
	if not Controls.has_pad(0):
		_ctext(672, "NO CONTROLLER FOUND. PLUG ONE IN (IN A BROWSER, ALSO PRESS A BUTTON ON IT).", 12, COLOR_GOLD)
	_ctext(704, Controls.diagnostics(), 11, COLOR_DIM)


func _draw_court(offset: Vector2) -> void:
	var c: Dictionary = COURTS[court]
	var w := sim.court_width()
	var h := sim.court_height()
	var origin := COURT_OFFSET + offset
	# Surface with mown stripes, then the outer border.
	draw_rect(Rect2(origin - Vector2(14, 14), Vector2(w + 28, h + 28)), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(origin, Vector2(w, h)), c.surface)
	var stripe := 50.0
	var x := 0.0
	var i := 0
	while x < w:
		if i % 2 == 1:
			draw_rect(Rect2(origin + Vector2(x, 0), Vector2(minf(stripe, w - x), h)), c.stripe)
		x += stripe
		i += 1
	var line: Color = c.line
	draw_rect(Rect2(origin, Vector2(w, h)), line, false, 4.0)
	# Centre circle and service lines, as on the Kenney court sheets.
	var centre := origin + Vector2(sim.net_x(), h / 2.0)
	draw_arc(centre, 70, 0, TAU, 48, line, 3.0)
	for side in [-1, 1]:
		var lx: float = sim.net_x() + side * 250.0
		draw_line(origin + Vector2(lx, 0), origin + Vector2(lx, h), Color(line, 0.5), 2.0)
	# Net: a translucent band with posts.
	var net_top := origin + Vector2(sim.net_x(), 0)
	draw_rect(Rect2(net_top - Vector2(4, 0), Vector2(8, h)), Color(1, 1, 1, 0.35))
	var y := 0.0
	while y < h:
		draw_line(net_top + Vector2(0, y), net_top + Vector2(0, minf(y + 14, h)), Color.WHITE, 3.0)
		y += 24
	for post_y in [-10.0, h + 10.0]:
		draw_circle(net_top + Vector2(0, post_y), 9, COLOR_DARK)
		draw_circle(net_top + Vector2(0, post_y), 6, Color("dfe4ea"))
	# Goal zones on both back walls, with their point values.
	for zone in balance.court.zones:
		var points := int(zone.points)
		var color := COLOR_ZONE_5 if points == 5 else COLOR_ZONE_3
		var y0 := float(zone.from) * h
		var y1 := float(zone.to) * h
		for gx in [-16.0, w]:
			var r := Rect2(origin + Vector2(gx, y0 + 2), Vector2(16, y1 - y0 - 4))
			draw_rect(r, color)
			draw_rect(r, Color(0, 0, 0, 0.25), false, 2.0)
			_rtext(r, str(points), 12, COLOR_DARK)


func _draw_players(offset: Vector2) -> void:
	var characters := [p1_character, p2_character]
	for p in sim.players:
		var pos := COURT_OFFSET + offset + p.pos
		var team := "red" if p.side == MatchSim.LEFT else "blue"
		var tint := Color.WHITE
		if p.knock_ticks > 0:
			tint = Color(1.6, 1.6, 1.6)
		elif p.recovery_ticks > 0:
			tint = Color(0.85, 0.85, 0.85)
		_draw_shadow(pos + Vector2(0, 30), 26)
		# Dashing leans the sprite into the dash.
		var lean := 0.0
		if p.dash_ticks > 0:
			lean = p.dash_dir.y * 0.35 * (1 if p.side == MatchSim.LEFT else -1)
		_draw_character(_sprite_for(characters[p.side], team), pos, p.side == MatchSim.LEFT,
			SPRITE_SCALE, tint, lean)
		# Hold timer above a player holding the disc.
		if p.holding and sim.phase != MatchSim.Phase.MATCH_OVER:
			var limit := float(balance.player.serve_hold_limit_ticks if p.serving
				else balance.player.hold_limit_ticks)
			var left := clampf(1.0 - float(p.hold_ticks) / limit, 0.0, 1.0)
			var bar := Rect2(pos + Vector2(-26, -52), Vector2(52, 7))
			draw_rect(bar, Color(0, 0, 0, 0.5))
			draw_rect(Rect2(bar.position, Vector2(bar.size.x * left, bar.size.y)),
				COLOR_GOLD if left > 0.3 else COLOR_ZONE_5)
		# Player marker so you can find yourself instantly.
		var marker_color := COLOR_P1 if p.side == MatchSim.LEFT else COLOR_P2
		var tip := pos + Vector2(0, -62)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, -12), tip + Vector2(8, -12)]), marker_color)


func _draw_disc(offset: Vector2) -> void:
	var d := sim.disc
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		return
	var origin := COURT_OFFSET + offset
	var ground := origin + d.pos
	var size := tex_disc.get_size() * DISC_SCALE
	# Supersonic trail.
	if d.supersonic and d.state == MatchSim.Disc.FLYING:
		for i in trail.size():
			var a := 0.5 * (1.0 - float(i) / trail.size())
			draw_circle(origin + trail[i], size.x * 0.5 * (1.0 - i * 0.06), Color(COLOR_GOLD, a))
	if d.state == MatchSim.Disc.LOB:
		var target := origin + d.lob_to
		var pulse := 1.0 + sin(frame * 0.3) * 0.12
		draw_arc(target, 22 * pulse, 0, TAU, 32, COLOR_ZONE_5, 3.0)
		draw_line(target - Vector2(8, 0), target + Vector2(8, 0), COLOR_ZONE_5, 2.0)
		draw_line(target - Vector2(0, 8), target + Vector2(0, 8), COLOR_ZONE_5, 2.0)
	_draw_shadow(ground + Vector2(0, 6), size.x * 0.45 * (1.0 - d.z / 400.0), 0.3)
	var top := ground - Vector2(0, d.z)
	var scale_up := 1.0 + d.z / 300.0  # a lobbed disc looks closer to the camera
	draw_set_transform(top, disc_spin, Vector2.ONE * scale_up)
	draw_texture_rect(tex_disc, Rect2(-size / 2.0, size), false,
		COLOR_GOLD if d.supersonic and d.state == MatchSim.Disc.FLYING else Color.WHITE)
	draw_set_transform(Vector2.ZERO)


func _draw_bursts(offset: Vector2) -> void:
	for b in bursts:
		var t := float(b.age) / 30.0
		var color: Color = b.color
		draw_arc(COURT_OFFSET + offset + b.pos, 20 + t * 90, 0, TAU, 40, Color(color, 1.0 - t), 6.0 * (1.0 - t) + 1.0)


func _draw_hud() -> void:
	var p1_rect := Rect2(Vector2(140, 22), Vector2(300, 70))
	var p2_rect := Rect2(Vector2(840, 22), Vector2(300, 70))
	draw_style_box(box_p1, p1_rect)
	draw_style_box(box_p2, p2_rect)
	_rtext(Rect2(p1_rect.position + Vector2(14, -4), Vector2(150, 70)), "P1", 22, COLOR_TEXT)
	_rtext(Rect2(p1_rect.position + Vector2(150, -4), Vector2(140, 70)), str(sim.scores[0]), 38, COLOR_TEXT)
	_rtext(Rect2(p2_rect.position + Vector2(10, -4), Vector2(140, 70)), str(sim.scores[1]), 38, COLOR_TEXT)
	_rtext(Rect2(p2_rect.position + Vector2(136, -4), Vector2(150, 70)), _side_name(MatchSim.RIGHT), 22, COLOR_TEXT)

	# Sets won as stars under each score.
	var need := int(balance.match.sets_to_win)
	for side in [0, 1]:
		var base := (p1_rect if side == 0 else p2_rect).position + Vector2(110, 74)
		for i in need:
			var tex := tex_star if sim.sets_won[side] > i else tex_star_empty
			draw_texture_rect(tex, Rect2(base + Vector2(i * 30, 0), Vector2(24, 24)), false)

	var timer_rect := Rect2(Vector2(560, 22), Vector2(160, 70))
	draw_style_box(box_panel, timer_rect)
	var seconds := ceili(sim.set_ticks_left / 60.0)
	var timer := "SD" if sim.sudden_death else str(seconds)
	var timer_color := COLOR_ZONE_5 if not sim.sudden_death and seconds <= 5 else COLOR_DARK
	_rtext(Rect2(timer_rect.position + Vector2(0, -8), timer_rect.size), timer, 34, timer_color)
	_rtext(Rect2(timer_rect.position + Vector2(0, 22), timer_rect.size),
		"SUDDEN DEATH" if sim.sudden_death else "SET %d" % sim.set_number, 11, COLOR_DARK)

	if banner_ticks > 0:
		var pop := 1.0 + maxf(0.0, (banner_ticks - 70) / 10.0) * 0.3 if banner_ticks < 9999 else 1.0
		var size := int(40 * pop)
		_ctext(392 + 2, banner, size, Color(0, 0, 0, 0.5))
		_ctext(392, banner, size, COLOR_GOLD)
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		_ctext(450, "PRESS %s FOR THE MENU" % Controls.label(0, "a"), 20, COLOR_TEXT)


func _draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0, 0, 0, 0.6))
	var panel := Rect2(Vector2(440, 220), Vector2(400, 280))
	draw_style_box(box_panel, panel)
	_ctext(290, "PAUSED  (P%d)" % (paused_by + 1), 34, COLOR_DARK)
	for i in PAUSE_OPTIONS.size():
		var rect := Rect2(Vector2(490, 330 + i * 76), Vector2(300, 60))
		draw_style_box(box_button_selected if i == pause_index else box_button, rect)
		_rtext(rect, PAUSE_OPTIONS[i], 22, COLOR_DARK)


func _draw_toast() -> void:
	if toast_ticks <= 0:
		return
	var alpha := clampf(toast_ticks / 30.0, 0.0, 1.0)
	var rect := Rect2(Vector2(340, 640), Vector2(600, 52))
	draw_rect(rect, Color(0, 0, 0, 0.7 * alpha))
	_rtext(rect, toast.to_upper(), 16, Color(COLOR_GOLD, alpha))
