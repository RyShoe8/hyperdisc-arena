## Front end: every screen (title, menus, character and court select, the
## VS splash, the match, pause, options, results) as one state machine.
## Runs the sim once per physics tick (60 Hz). Fully playable on controllers.
##
## Art: rendered by tools/blender (courts, characters, logo). Fonts: Bangers
## and Russo One (OFL), Kenney Future (CC0). Sound: Kenney Interface Sounds (CC0).
extends Node2D

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")
const UI := preload("res://scripts/game/ui/theme.gd")
const MatchView := preload("res://scripts/game/view/match_view.gd")

const BALANCE_PATH := "res://data/balance.json"
const SCREEN := Vector2(1920, 1080)
const DIFFICULTIES := ["easy", "normal", "hard"]
const PAUSE_OPTIONS := ["RESUME", "MOVE LIST", "OPTIONS", "QUIT TO MENU"]
const RESULT_OPTIONS := ["REMATCH", "CHARACTER SELECT", "MAIN MENU"]
const OPTION_TABS := ["GRAPHICS", "AUDIO", "CONTROLS", "MOVES"]
const COURT_NOTES := {
	"beach": "SMALL COURT  -  STANDARD ZONES",
	"lawn": "LARGE COURT  -  STANDARD ZONES",
	"tiled": "SMALL COURT  -  ZONES REVERSED: 5 AT THE EDGES",
	"concrete": "LARGE COURT  -  ZONES REVERSED, BARRIERS NEAR THE WALLS",
	"clay": "LARGE COURT  -  BARRIERS IN MID-COURT",
	"stadium": "LARGE COURT  -  THE 5-ZONE GROWS WITH EVERY STRAIGHT POINT",
}

enum Screen { TITLE, MAIN, SELECT, COURT, VS, MATCH, PAUSED, OPTIONS, RESULTS }

var balance: Dictionary
var sim: MatchSim
var view: MatchView
var cpu: CpuPlayer
var screen: int = Screen.TITLE
var screen_ticks := 0
var frame := 0
var versus := false

# Menu state
var main_index := 0
var pick: Array[int] = [0, 1]
var picked: Array[bool] = [false, false]
var select_step := 0    # CPU mode: 0 pick fighter, 1 pick opponent, 2 difficulty
var difficulty := 1
var court := 0
var pause_index := 0
var paused_by := 0
var result_index := 0
var options_tab := 0
var options_row := 0
var options_return: int = Screen.MAIN
var bind_player := 0
var bind_device := 0    # 0 controller, 1 keyboard
var show_moves := false
var toast := ""
var toast_ticks := 0
var stats: Array[Dictionary] = [{}, {}]
var last_second := -1

## Command-line demo mode (see _read_args): CPU plays both sides.
var demo := false
## Screenshot capture for reviewing builds: ticks to grab, where to save.
var shots: Array[int] = []
var shots_dir := ""
var cpu_left: CpuPlayer

var logo: Texture2D
var court_thumbs: Array[Texture2D] = []
var portraits: Array[Texture2D] = []
var select_art: Array[Texture2D] = []


func _ready() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	RenderingServer.set_default_clear_color(UI.NIGHT)
	UI.load_fonts()
	Controls.changed.connect(_on_controls_changed)
	logo = load("res://assets/logo/logo.png")
	for c in balance.courts:
		court_thumbs.append(load("res://assets/art/courts/%s.webp" % c.id))
	for c in balance.characters:
		portraits.append(load("res://assets/art/characters/%s_portrait.webp" % c.id))
		select_art.append(load("res://assets/art/characters/%s_select.webp" % c.id))
	_read_args()


## Developer shortcuts, passed after "--" on the command line:
##   --demo            CPU vs CPU match straight away (attract mode, screenshots)
##   --court=N --p1=N --p2=N --difficulty=N
##   --screen=title|main|select|court|vs|options|results
##   --shots=60,240,600 --out=C:/path   save screenshots at those ticks, then quit
##   --speed=N         run N times faster
func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=")
		var value := int(kv[1]) if kv.size() > 1 and kv[1].is_valid_int() else 0
		match kv[0]:
			"court":
				court = clampi(value, 0, balance.courts.size() - 1)
			"p1":
				pick[0] = clampi(value, 0, balance.characters.size() - 1)
			"p2":
				pick[1] = clampi(value, 0, balance.characters.size() - 1)
			"difficulty":
				difficulty = clampi(value, 0, 2)
			"demo":
				demo = true
			"speed":
				# Fast-forward (for capturing late-match screens).
				Engine.time_scale = maxf(1.0, value)
				Engine.max_physics_steps_per_frame = 8 * maxi(1, value)
			"shots":
				for t in kv[1].split(","):
					shots.append(int(t))
			"out":
				shots_dir = arg.trim_prefix("--out=")
			"screen":
				var names := {"title": Screen.TITLE, "main": Screen.MAIN, "select": Screen.SELECT,
					"court": Screen.COURT, "vs": Screen.VS, "options": Screen.OPTIONS}
				if kv.size() > 1 and names.has(kv[1]):
					_go(names[kv[1]])
	if demo:
		_start_match()


func _physics_process(_delta: float) -> void:
	frame += 1
	if not shots.is_empty() and frame >= shots[0]:
		_take_shot(shots.pop_front())
	screen_ticks += 1
	toast_ticks = maxi(0, toast_ticks - 1)
	match screen:
		Screen.TITLE:
			_title_input()
		Screen.MAIN:
			_main_input()
		Screen.SELECT:
			_select_input()
		Screen.COURT:
			_court_input()
		Screen.VS:
			_vs_input()
		Screen.MATCH:
			_match_tick()
		Screen.PAUSED:
			_pause_input()
		Screen.OPTIONS:
			_options_input()
		Screen.RESULTS:
			_results_input()
	queue_redraw()


func _take_shot(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%05d.png" % [shots_dir if shots_dir != "" else OS.get_user_data_dir(), tick])
	if shots.is_empty():
		get_tree().quit()


func _go(to: int) -> void:
	screen = to
	screen_ticks = 0


func _back_pressed() -> bool:
	return Controls.menu_pressed("b") != -1


func _confirm_device() -> int:
	var d := Controls.menu_pressed("a")
	return d if d != -1 else Controls.menu_pressed("start")


# --- Title and main menu ---------------------------------------------------

func _title_input() -> void:
	if screen_ticks < 20:
		return
	var device := _confirm_device()
	if device == -1 and Controls.anything_pressed():
		device = -2
	if device != -1:
		Controls.make_player_one(device)
		Sfx.play("menu_confirm")
		_go(Screen.MAIN)


func _main_items() -> Array:
	var items := ["VS CPU", "VS PLAYER 2", "OPTIONS"]
	if not OS.has_feature("web"):
		items.append("QUIT")
	return items


func _main_input() -> void:
	var items := _main_items()
	var n := Controls.menu_nudged()
	if n.y != 0:
		main_index = posmod(main_index + n.y, items.size())
		Sfx.play("menu_move")
	if _back_pressed():
		Sfx.play("menu_back")
		_go(Screen.TITLE)
		return
	if _confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match items[main_index]:
		"VS CPU":
			versus = false
			_open_select()
		"VS PLAYER 2":
			versus = true
			_open_select()
		"OPTIONS":
			_open_options(Screen.MAIN)
		"QUIT":
			get_tree().quit()


# --- Character select ------------------------------------------------------

func _open_select() -> void:
	picked = [false, false]
	select_step = 0
	_go(Screen.SELECT)


func _grid_move(i: int, n: Vector2i) -> int:
	var count: int = balance.characters.size()
	var cols := 3
	var x := i % cols
	var y := i / cols
	x = posmod(x + n.x, cols)
	y = posmod(y + n.y, ceili(count / float(cols)))
	return mini(y * cols + x, count - 1)


func _select_input() -> void:
	if versus:
		for p in [0, 1]:
			var n := Controls.nudged(p)
			if p == 0 and n == Vector2i.ZERO and not Controls.has_pad(1):
				n = Vector2i.ZERO
			if not picked[p] and n != Vector2i.ZERO:
				pick[p] = _grid_move(pick[p], n)
				Sfx.play("menu_move", 1.0 + p * 0.1)
			if Controls.pressed(p, "a") and not picked[p]:
				picked[p] = true
				Sfx.play("menu_confirm")
			elif Controls.pressed(p, "b"):
				if picked[p]:
					picked[p] = false
					Sfx.play("menu_back")
				elif p == 0:
					Sfx.play("menu_back")
					_go(Screen.MAIN)
					return
		if picked[0] and picked[1] and screen_ticks > 10:
			_go(Screen.COURT)
		return

	var n := Controls.menu_nudged()
	match select_step:
		0, 1:
			var who := select_step
			if n != Vector2i.ZERO:
				pick[who] = _grid_move(pick[who], n)
				Sfx.play("menu_move")
			if _confirm_device() != -1:
				Sfx.play("menu_confirm")
				select_step += 1
			elif _back_pressed():
				Sfx.play("menu_back")
				if select_step == 0:
					_go(Screen.MAIN)
				else:
					select_step -= 1
		2:
			if n.x != 0:
				difficulty = posmod(difficulty + n.x, DIFFICULTIES.size())
				Sfx.play("menu_move")
			if _confirm_device() != -1:
				Sfx.play("menu_confirm")
				_go(Screen.COURT)
			elif _back_pressed():
				Sfx.play("menu_back")
				select_step = 1


# --- Court select and VS splash --------------------------------------------

func _court_input() -> void:
	var n := Controls.menu_nudged()
	if n.x != 0:
		court = posmod(court + n.x, balance.courts.size())
		Sfx.play("menu_move")
	if _confirm_device() != -1 and screen_ticks > 8:
		Sfx.play("menu_confirm")
		_go(Screen.VS)
	elif _back_pressed():
		Sfx.play("menu_back")
		picked = [false, false]
		select_step = 0 if versus else 2
		_go(Screen.SELECT)


func _vs_input() -> void:
	if screen_ticks == 1:
		Sfx.play("supersonic", 0.8)
	if screen_ticks > 150 or (screen_ticks > 30 and _confirm_device() != -1):
		_start_match()


# --- Match -----------------------------------------------------------------

func _names() -> Array[String]:
	if demo:
		return ["CPU", "CPU"]
	return ["P1", "P2" if versus else "CPU"]


func _start_match() -> void:
	var characters: Array = balance.characters
	var seed_value := int(Time.get_ticks_usec())
	cpu = null if versus else CpuPlayer.new(MatchSim.RIGHT, balance.cpu[DIFFICULTIES[difficulty]], seed_value)
	cpu_left = CpuPlayer.new(MatchSim.LEFT, balance.cpu.hard, seed_value + 7) if demo else null
	sim = MatchSim.new(balance, characters[pick[0]], characters[pick[1]], court)
	view = MatchView.new(sim, [characters[pick[0]].id, characters[pick[1]].id], _names())
	stats = [{}, {}]
	last_second = -1
	_go(Screen.MATCH)


func _match_tick() -> void:
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		view.tick()
		if sim.phase_ticks > 150 or (sim.phase_ticks > 40 and _confirm_device() != -1):
			result_index = 0
			Sfx.play("menu_confirm")
			_go(Screen.RESULTS)
		else:
			sim.step([{}, {}])
		return
	for i in [0, 1] if versus else [0]:
		if Controls.pressed(i, "start"):
			_pause(i)
			return
	var right: Dictionary = Controls.input(1) if versus else cpu.think(sim)
	var left: Dictionary = cpu_left.think(sim) if demo else Controls.input(0)
	sim.step([left, right])
	for e in sim.events:
		view.handle(e)
		_sound_for(e)
		_count(e)
	view.tick()
	_countdown_beeps()


func _count(e: Dictionary) -> void:
	if not e.has("side"):
		return
	var s: Dictionary = stats[e.side]
	s[e.type] = int(s.get(e.type, 0)) + 1
	if e.type == "catch":
		s["best_rally"] = maxi(int(s.get("best_rally", 0)), sim.disc.rally)


func _sound_for(e: Dictionary) -> void:
	match e.type:
		"ready":
			Sfx.play("countdown", 0.8)
		"go":
			Sfx.play("menu_confirm", 1.2)
		"throw":
			if e.supersonic or e.smash:
				Sfx.play("supersonic", 1.1 if e.smash else 1.0)
				_rumble(e.side, 0.3, 0.0, 0.08)
			else:
				Sfx.play("throw", randf_range(0.95, 1.1))
		"special":
			Sfx.play("supersonic", 0.7)
			Sfx.play("goal", 1.4, -6.0)
			_rumble(e.side, 0.6, 0.6, 0.25)
		"lob", "drop":
			Sfx.play("lob", 0.85 if e.type == "drop" else 1.0)
		"slap":
			Sfx.play("supersonic", 1.3)
		"block", "power_toss":
			Sfx.play("catch", 1.3)
		"jump":
			Sfx.play("lob", 1.5, -8.0)
		"land":
			Sfx.play("bounce", 0.7, -10.0)
		"catch":
			var knock := absf(sim.players[e.side].knock_vel)
			Sfx.play("catch", randf_range(0.9, 1.1), -2.0 + minf(knock, 6.0))
			_rumble(e.side, 0.4, clampf(knock / 8.0, 0.1, 1.0), 0.12)
		"bounce", "barrier":
			Sfx.play("bounce", randf_range(0.9, 1.2), -6.0)
		"charge_ready":
			Sfx.play("connect", 1.3)
		"ex_ready":
			Sfx.play("menu_confirm", 1.4, -4.0)
		"buzzsaw":
			Sfx.play("supersonic", 0.6)
		"point":
			Sfx.play("miss" if e.reason == "miss" else "goal")
			_rumble(1 - e.side, 0.6, 0.8, 0.3)
		"set_end":
			Sfx.play("set_end")
		"match_over":
			Sfx.play("match_win")
			_rumble(e.winner, 0.5, 0.5, 0.6)


func _countdown_beeps() -> void:
	if sim.set_ticks_left > 0 and (sim.phase == MatchSim.Phase.PLAY or sim.phase == MatchSim.Phase.SERVE):
		var second := ceili(sim.set_ticks_left / 60.0)
		if second != last_second and second <= 5:
			Sfx.play("countdown", 1.0 + (5 - second) * 0.08)
		last_second = second


func _rumble(side: int, weak: float, strong: float, seconds: float) -> void:
	if side == MatchSim.LEFT or versus:
		Controls.rumble(side, weak, strong, seconds)


# --- Pause, results, options -----------------------------------------------

func _pause(player: int) -> void:
	paused_by = player
	pause_index = 0
	show_moves = false
	Sfx.play("pause")
	_go(Screen.PAUSED)


func _pause_input() -> void:
	if show_moves:
		if Controls.pressed(paused_by, "b") or Controls.pressed(paused_by, "a") or Controls.pressed(paused_by, "start"):
			show_moves = false
			Sfx.play("menu_back")
		return
	var n := Controls.nudged(paused_by)
	if n.y != 0:
		pause_index = posmod(pause_index + n.y, PAUSE_OPTIONS.size())
		Sfx.play("menu_move")
	if Controls.pressed(paused_by, "start") or Controls.pressed(paused_by, "b"):
		Sfx.play("menu_back")
		_go(Screen.MATCH)
	elif Controls.pressed(paused_by, "a"):
		match PAUSE_OPTIONS[pause_index]:
			"RESUME":
				Sfx.play("menu_confirm")
				_go(Screen.MATCH)
			"MOVE LIST":
				show_moves = true
				Sfx.play("menu_confirm")
			"OPTIONS":
				Sfx.play("menu_confirm")
				_open_options(Screen.PAUSED)
			"QUIT TO MENU":
				Sfx.play("menu_back")
				_go(Screen.MAIN)


func _results_input() -> void:
	var n := Controls.menu_nudged()
	if n.y != 0:
		result_index = posmod(result_index + n.y, RESULT_OPTIONS.size())
		Sfx.play("menu_move")
	if screen_ticks < 40 or _confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match RESULT_OPTIONS[result_index]:
		"REMATCH":
			_go(Screen.VS)
		"CHARACTER SELECT":
			_open_select()
		"MAIN MENU":
			_go(Screen.MAIN)


func _open_options(return_to: int) -> void:
	options_return = return_to
	options_tab = 0
	options_row = 0
	_go(Screen.OPTIONS)


func _option_rows() -> Array:
	match OPTION_TABS[options_tab]:
		"GRAPHICS":
			return [
				["DISPLAY", Settings.WINDOW_MODES[Settings.window_mode]],
				["VSYNC", "ON" if Settings.vsync else "OFF"],
				["SCREEN SHAKE", Settings.SHAKE_LEVELS[Settings.shake]],
				["EFFECTS", Settings.EFFECT_LEVELS[Settings.effects]],
				["RETRO SCANLINES", "ON" if Settings.scanlines else "OFF"],
				["SHOW FPS", "ON" if Settings.show_fps else "OFF"],
			]
		"AUDIO":
			return [
				["MASTER VOLUME", "%d%%" % roundi(Settings.master_volume * 100)],
				["EFFECTS VOLUME", "%d%%" % roundi(Settings.sfx_volume * 100)],
			]
		"CONTROLS":
			var rows := [["PLAYER", "P%d" % (bind_player + 1)],
				["DEVICE", "CONTROLLER" if bind_device == 0 else "KEYBOARD"]]
			var kind := "pad" if bind_device == 0 else "keys"
			for action in Controls.ACTIONS:
				var codes: Array = Controls.bindings[bind_player][kind][action]
				var names := []
				for c in codes:
					names.append(Controls.button_name(c, Controls.is_playstation(bind_player))
						if kind == "pad" else Controls.key_name(c))
				rows.append([Controls.ACTION_NAMES[action], " / ".join(names)])
			rows.append(["RESET TO DEFAULTS", ""])
			return rows
	return []


func _options_input() -> void:
	if Controls.capturing():
		return
	if Controls.capture_finished():
		Controls.end_capture()
		Sfx.play("menu_confirm")
		Settings.save()
		return
	var n := Controls.menu_nudged()
	if Controls.menu_pressed("slap") != -1 or (n.x != 0 and options_row == -1):
		pass
	var rows := _option_rows()
	# Shoulder-style tab switching: jump / slap buttons, or left/right on the tab row.
	if Controls.menu_pressed("jump") != -1:
		_switch_tab(-1)
		return
	if Controls.menu_pressed("slap") != -1:
		_switch_tab(1)
		return
	if n.y != 0:
		var count := rows.size() + 1  # row -1 is the tab bar
		options_row = posmod(options_row + 1 + n.y, count) - 1
		Sfx.play("menu_move")
	if options_row == -1 and n.x != 0:
		_switch_tab(n.x)
		return
	if _back_pressed():
		Settings.save()
		Sfx.play("menu_back")
		_go(options_return)
		return
	if options_row < 0 or options_row >= rows.size():
		return
	var confirm := _confirm_device() != -1
	var step := n.x if n.x != 0 else (1 if confirm else 0)
	if step == 0:
		return
	match OPTION_TABS[options_tab]:
		"GRAPHICS":
			match options_row:
				0:
					Settings.window_mode = posmod(Settings.window_mode + step, Settings.WINDOW_MODES.size())
				1:
					Settings.vsync = not Settings.vsync
				2:
					Settings.shake = posmod(Settings.shake + step, Settings.SHAKE_LEVELS.size())
				3:
					Settings.effects = posmod(Settings.effects + step, Settings.EFFECT_LEVELS.size())
				4:
					Settings.scanlines = not Settings.scanlines
				5:
					Settings.show_fps = not Settings.show_fps
			Settings.apply()
		"AUDIO":
			var delta := 0.1 * signf(step) if n.x != 0 else 0.0
			if options_row == 0:
				Settings.master_volume = clampf(Settings.master_volume + delta, 0.0, 1.0)
			else:
				Settings.sfx_volume = clampf(Settings.sfx_volume + delta, 0.0, 1.0)
			Settings.apply()
		"CONTROLS":
			if options_row == 0:
				bind_player = posmod(bind_player + step, 2)
			elif options_row == 1:
				bind_device = posmod(bind_device + step, 2)
			elif options_row == rows.size() - 1:
				if confirm:
					Controls.reset_bindings()
					toast_msg("CONTROLS RESET TO DEFAULTS")
			elif confirm:
				var action: String = Controls.ACTIONS[options_row - 2]
				Controls.capture(bind_player, "pad" if bind_device == 0 else "keys", action)
	Settings.save()
	Sfx.play("menu_move", 1.15)


func _switch_tab(step: int) -> void:
	options_tab = posmod(options_tab + step, OPTION_TABS.size())
	options_row = -1
	Sfx.play("menu_move", 0.9)


func toast_msg(text: String) -> void:
	toast = text
	toast_ticks = 150


func _on_controls_changed(message: String) -> void:
	toast_msg(message.to_upper())
	Sfx.play("disconnect" if message.ends_with("disconnected") else "connect")
	# A controller dropping out mid-match pauses the game until it is back.
	if screen == Screen.MATCH and message.ends_with("disconnected"):
		_pause(0)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	match screen:
		Screen.TITLE:
			_draw_title()
		Screen.MAIN:
			_draw_main()
		Screen.SELECT:
			_draw_select()
		Screen.COURT:
			_draw_court_select()
		Screen.VS:
			_draw_vs()
		Screen.MATCH:
			view.draw(self)
		Screen.PAUSED:
			view.draw(self)
			_draw_pause()
		Screen.OPTIONS:
			if options_return == Screen.PAUSED:
				view.draw(self)
				draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.03, 0.0, 0.1, 0.8))
			else:
				UI.outrun_background(self, SCREEN, frame / 60.0, 0.45)
			_draw_options()
		Screen.RESULTS:
			_draw_results()
	_draw_toast()
	if Settings.scanlines:
		UI.scanlines(self, SCREEN)
	if Settings.show_fps:
		UI.text(self, Vector2(1900, 1070), "%d FPS" % Engine.get_frames_per_second(), 22, UI.YELLOW,
			UI.ui, 3, HORIZONTAL_ALIGNMENT_RIGHT)


func _hint(text: String) -> void:
	UI.text(self, Vector2(960, 1050), text, 26, UI.DIM, UI.ui, 4)


func _a() -> String:
	return Controls.label(0, "a")


func _b() -> String:
	return Controls.label(0, "b")


func _draw_title() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0)
	var bob := sin(frame * 0.05) * 8.0
	var size := logo.get_size() * 0.9
	draw_texture_rect(logo, Rect2(Vector2((SCREEN.x - size.x) / 2.0, 110 + bob), size), false)
	if (frame / 30) % 2 == 0:
		UI.text(self, Vector2(960, 800), "PRESS ANY BUTTON", 64, UI.YELLOW, UI.display, 7,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(self, Vector2(960, 1050), "A PLAYBOUND EXCLUSIVE  -  TEST BUILD", 24, UI.WHITE, UI.ui, 4)


func _draw_main() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	var size := logo.get_size() * 0.55
	draw_texture_rect(logo, Rect2(Vector2((SCREEN.x - size.x) / 2.0, 40), size), false)
	var items := _main_items()
	for i in items.size():
		var r := Rect2(Vector2(660, 560 + i * 104), Vector2(600, 84))
		UI.button(self, r, items[i], i == main_index, frame, 40)
	_hint("%s SELECT     %s BACK" % [_a(), _b()])


func _draw_select() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.55)
	var title := "SELECT YOUR PLAYER"
	if not versus:
		title = ["SELECT YOUR PLAYER", "SELECT YOUR OPPONENT", "SELECT DIFFICULTY"][select_step]
	UI.slant_panel(self, Rect2(560, 26, 800, 90), UI.YELLOW, UI.INK, 30, 5)
	UI.text(self, Vector2(960, 98), title, 64, UI.INK, UI.display, 2)

	var chars: Array = balance.characters
	var cell := Vector2(210, 210)
	var grid_origin := Vector2(960 - cell.x * 1.5 - 10, 230)
	for i in chars.size():
		var pos := grid_origin + Vector2((i % 3) * (cell.x + 10), (i / 3) * (cell.y + 10))
		var r := Rect2(pos, cell)
		draw_rect(r.grow(4), UI.INK)
		draw_rect(r, Color("2a1250"))
		draw_texture_rect_region(portraits[i], r, Rect2(100, 40, 440, 440))
		for who in [0, 1]:
			if pick[who] != i:
				continue
			if not versus and who == 1 and select_step == 0:
				continue
			var c := UI.P1 if who == 0 else UI.P2
			var flash: bool = (frame / 6) % 2 == 0 or picked[who] or (not versus and select_step > who)
			if flash:
				draw_rect(r.grow(4 + who * 6), c, false, 7)
			var tag := "P1" if who == 0 else ("P2" if versus else "CPU")
			UI.text(self, pos + Vector2(14 if who == 0 else cell.x - 14, 40), tag, 32, c, UI.display, 4,
				HORIZONTAL_ALIGNMENT_LEFT if who == 0 else HORIZONTAL_ALIGNMENT_RIGHT)
		UI.text(self, pos + Vector2(cell.x / 2, cell.y - 12), str(chars[i].name).to_upper(), 22,
			Color.WHITE, UI.ui, 4)

	for who in [0, 1]:
		if not versus and who == 1 and select_step == 0:
			continue
		_draw_fighter_card(who, chars[pick[who]])

	if not versus and select_step == 2:
		var r := Rect2(Vector2(660, 720), Vector2(600, 90))
		UI.button(self, r, "<  CPU %s  >" % DIFFICULTIES[difficulty].to_upper(), true, frame, 42)
	if versus:
		for who in [0, 1]:
			if picked[who]:
				UI.text(self, Vector2(400 if who == 0 else 1520, 980), "READY!", 60, UI.YELLOW,
					UI.display, 6)
		_hint("EACH PLAYER: STICK TO CHOOSE, %s TO LOCK IN, %s TO CHANGE" % [_a(), _b()])
	else:
		_hint("%s CONFIRM     %s BACK" % [_a(), _b()])


func _draw_fighter_card(who: int, c: Dictionary) -> void:
	var left: bool = who == 0
	var x := 40.0 if left else 1480.0
	var col := UI.P1 if left else UI.P2
	var art: Texture2D = select_art[pick[who]]
	var bob := sin(frame * 0.06 + who) * 6.0
	draw_set_transform(Vector2(x + 200, 600 + bob), 0.0, Vector2(1.0 if left else -1.0, 1.0) * 0.76)
	draw_texture(art, Vector2(-400, -500))
	draw_set_transform(Vector2.ZERO)
	var panel := Rect2(Vector2(x, 820), Vector2(400, 200))
	UI.slant_panel(self, panel, Color("120826"), col, 24, 4)
	UI.text(self, panel.position + Vector2(200, 50), str(c.name).to_upper(), 40, col, UI.display, 5)
	UI.text(self, panel.position + Vector2(200, 84), "%s  -  %s" % [str(c.archetype).to_upper(),
		str(c.special_name)], 22, Color.WHITE, UI.ui, 3)
	var bars := [["SPEED", (float(c.speed) - 0.7) / 0.8], ["POWER", (float(c.power) - 0.6) / 0.85]]
	for i in bars.size():
		var y := panel.position.y + 112 + i * 40
		UI.text(self, Vector2(panel.position.x + 30, y + 22), bars[i][0], 22, Color.WHITE, UI.ui, 3,
			HORIZONTAL_ALIGNMENT_LEFT)
		UI.meter(self, Rect2(Vector2(panel.position.x + 150, y + 2), Vector2(220, 22)),
			clampf(bars[i][1], 0.08, 1.0), UI.YELLOW if i == 0 else UI.ZONE_5, 8)


func _draw_court_select() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.55)
	UI.slant_panel(self, Rect2(610, 26, 700, 90), UI.YELLOW, UI.INK, 30, 5)
	UI.text(self, Vector2(960, 98), "SELECT COURT", 64, UI.INK, UI.display, 2)
	var big := Rect2(Vector2(480, 170), Vector2(960, 540))
	draw_rect(big.grow(8), UI.INK)
	draw_texture_rect(court_thumbs[court], big, false)
	draw_rect(big.grow(4), UI.CYAN, false, 5)
	var c: Dictionary = balance.courts[court]
	UI.text(self, Vector2(960, 800), str(c.name), 96, UI.PINK, UI.display, 8, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)
	UI.text(self, Vector2(960, 856), COURT_NOTES.get(c.id, ""), 28, Color.WHITE, UI.ui, 4)
	var arrow := sin(frame * 0.2) * 8.0
	UI.text(self, Vector2(400 - arrow, 470), "<", 120, UI.YELLOW, UI.display, 8)
	UI.text(self, Vector2(1520 + arrow, 470), ">", 120, UI.YELLOW, UI.display, 8)
	for i in balance.courts.size():
		var r := Rect2(Vector2(960 - 3 * 150 + i * 150 + 5, 900), Vector2(140, 79))
		draw_texture_rect(court_thumbs[i], r, false, Color(1, 1, 1, 1.0 if i == court else 0.45))
		if i == court:
			draw_rect(r.grow(3), UI.YELLOW, false, 4)
	_hint("%s CONFIRM     %s BACK" % [_a(), _b()])


func _draw_vs() -> void:
	var t := screen_ticks
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("0f3d7a"))
	UI.starburst(self, Vector2(960, 540), 300, 1400, 28, Color("2de2e6"), t * 0.004)
	UI.starburst(self, Vector2(960, 540), 200, 900, 28, Color("8ff7ff"), -t * 0.006)
	var slide := clampf(t / 14.0, 0.0, 1.0)
	for who in [0, 1]:
		var left: bool = who == 0
		var x := lerpf(-500.0 if left else 2420.0, 430.0 if left else 1490.0, slide)
		draw_set_transform(Vector2(x, 560), 0.0, Vector2(1.0 if left else -1.0, 1.0) * 1.25)
		draw_texture(portraits[pick[who]], Vector2(-320, -320))
		draw_set_transform(Vector2.ZERO)
		var c: Dictionary = balance.characters[pick[who]]
		UI.slant_panel(self, Rect2(Vector2(x - 300, 900), Vector2(600, 90)), Color("120826"),
			UI.P1 if left else UI.P2, 26, 5)
		UI.text(self, Vector2(x, 964), str(c.name).to_upper(), 56, Color.WHITE, UI.display, 6)
	if t > 10:
		var pop := 1.0 + maxf(0.0, 1.0 - (t - 10) / 8.0) * 0.8
		UI.text(self, Vector2(960, 640), "VS", int(300 * pop), Color("7b2cbf"), UI.display, 16,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	var court_name: String = balance.courts[court].name
	UI.text(self, Vector2(960, 80), court_name + " COURT", 48, Color.WHITE, UI.display, 6)


func _draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.03, 0.0, 0.1, 0.65))
	if show_moves:
		_draw_move_list(Rect2(Vector2(360, 140), Vector2(1200, 800)))
		_hint("%s / %s BACK" % [_a(), _b()])
		return
	UI.text(self, Vector2(960, 330), "PAUSED", 110, UI.YELLOW, UI.display, 9, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)
	UI.text(self, Vector2(960, 380), "P%d" % (paused_by + 1), 34, UI.P1 if paused_by == 0 else UI.P2,
		UI.ui, 4)
	for i in PAUSE_OPTIONS.size():
		UI.button(self, Rect2(Vector2(710, 440 + i * 96), Vector2(500, 78)), PAUSE_OPTIONS[i],
			i == pause_index, frame, 36)


func _move_list() -> Array:
	var a := Controls.label(0, "a")
	var b := Controls.label(0, "b")
	var j := Controls.label(0, "jump")
	var s := Controls.label(0, "slap")
	var mv := Controls.label(0, "move")
	return [
		["MOVE", mv], ["DASH / DIVE", "%s + %s" % [mv, a]], ["THROW", "%s (aim up / down)" % a],
		["CURVE", "QUARTER-CIRCLE + %s" % a], ["SUPERSONIC", "THROW THE INSTANT YOU CATCH"],
		["LOB", "%s (hold longer = shorter)" % b], ["JUMP / AIR CATCH", j], ["SMASH", "%s IN THE AIR" % a],
		["BLOCK (POP UP)", "%s STANDING STILL AS IT ARRIVES" % a], ["SLAP SHOT", "%s AS IT ARRIVES" % s],
		["DROP SHOT", "%s AS IT ARRIVES" % b], ["SPECIAL", "STAND ON THE MARKER, CATCH, %s" % a],
		["SUPER LOB", "WHEN CHARGED, %s" % b], ["EX SHOT", "EX GAUGE FULL, %s" % s],
		["POWER TOSS", "EX GAUGE FULL, %s + %s" % [a, b]],
	]


func _draw_move_list(area: Rect2) -> void:
	UI.slant_panel(self, area, Color("120826"), UI.CYAN, 30, 5)
	UI.text(self, Vector2(area.get_center().x, area.position.y + 76), "MOVE LIST", 64, UI.YELLOW,
		UI.display, 6)
	var moves := _move_list()
	for i in moves.size():
		var y := area.position.y + 136 + i * 42
		UI.text(self, Vector2(area.position.x + 80, y), moves[i][0], 26, UI.CYAN, UI.ui, 3,
			HORIZONTAL_ALIGNMENT_LEFT)
		UI.text(self, Vector2(area.position.x + 450, y), moves[i][1], 26, Color.WHITE, UI.ui, 3,
			HORIZONTAL_ALIGNMENT_LEFT)


func _draw_options() -> void:
	UI.text(self, Vector2(960, 110), "OPTIONS", 100, UI.YELLOW, UI.display, 8, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)
	for i in OPTION_TABS.size():
		var r := Rect2(Vector2(360 + i * 310, 150), Vector2(290, 70))
		var on: bool = i == options_tab
		UI.slant_panel(self, r, UI.PINK if on else Color("2a1250"),
			UI.CYAN if (on and options_row == -1) else UI.PURPLE, 20, 4)
		UI.text(self, Vector2(r.get_center().x, r.position.y + 48), OPTION_TABS[i], 32,
			Color.WHITE if on else UI.DIM, UI.ui, 4)
	var area := Rect2(Vector2(360, 250), Vector2(1200, 740))
	if OPTION_TABS[options_tab] == "MOVES":
		_draw_move_list(area)
	else:
		UI.slant_panel(self, area, Color(0.07, 0.02, 0.16, 0.92), UI.PURPLE, 30, 4)
		var rows := _option_rows()
		for i in rows.size():
			var y := area.position.y + 50 + i * 76
			var on: bool = i == options_row
			var row := Rect2(Vector2(area.position.x + 60, y), Vector2(area.size.x - 120, 64))
			if on:
				UI.slant_panel(self, row, Color(UI.PINK, 0.35), UI.CYAN, 16, 3)
			UI.text(self, Vector2(row.position.x + 40, y + 44), rows[i][0], 30, Color.WHITE, UI.ui, 4,
				HORIZONTAL_ALIGNMENT_LEFT)
			var value: String = rows[i][1]
			if Controls.capturing() and on:
				value = "PRESS A %s..." % ("BUTTON" if bind_device == 0 else "KEY")
			elif on and value != "":
				value = "<  %s  >" % value if OPTION_TABS[options_tab] != "CONTROLS" or i < 2 else value
			UI.text(self, Vector2(row.end.x - 40, y + 44), value, 30, UI.YELLOW, UI.ui, 4,
				HORIZONTAL_ALIGNMENT_RIGHT)
		if OPTION_TABS[options_tab] == "GRAPHICS" and OS.has_feature("web"):
			UI.text(self, Vector2(960, area.end.y - 30), "DISPLAY AND VSYNC ARE SET BY THE BROWSER", 24,
				UI.DIM, UI.ui, 3)
		if OPTION_TABS[options_tab] == "CONTROLS":
			UI.text(self, Vector2(960, area.end.y - 30), "PICK AN ACTION AND PRESS %s, THEN THE NEW BUTTON" % _a(),
				24, UI.DIM, UI.ui, 3)
	_hint("%s / %s SWITCH TAB     %s CHANGE     %s BACK" % [Controls.label(0, "jump"),
		Controls.label(0, "slap"), _a(), _b()])


func _draw_results() -> void:
	var t := screen_ticks
	var w := sim.winner
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color("0f3d7a"))
	# Diagonal split, winner on their side.
	var split := PackedVector2Array([Vector2(1060, 0), Vector2(1920, 0), Vector2(1920, 1080), Vector2(860, 1080)])
	draw_colored_polygon(split, Color("3d1a6e"))
	draw_line(Vector2(1060, 0), Vector2(860, 1080), UI.YELLOW, 10)
	UI.slant_panel(self, Rect2(Vector2(700, 420), Vector2(520, 220)), Color("120826"), UI.YELLOW, 30, 5)
	for side in [0, 1]:
		var left: bool = side == 0
		var won: bool = side == w
		var x := 470.0 if left else 1450.0
		draw_set_transform(Vector2(x, 560), 0.0, Vector2(1.0 if left else -1.0, 1.0) * 1.1)
		draw_texture(portraits[pick[side]], Vector2(-320, -320), Color(1, 1, 1) if won else Color(0.55, 0.5, 0.65))
		draw_set_transform(Vector2.ZERO)
		var label := "WIN" if won else "LOSE"
		UI.text(self, Vector2(x, 1000), label, 150, UI.YELLOW if won else UI.DIM, UI.display, 12,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
		var s: Dictionary = stats[side]
		var lines := ["THROWS  %d" % (int(s.get("throw", 0)) + int(s.get("slap", 0))),
			"CATCHES  %d" % int(s.get("catch", 0)), "SPECIALS  %d" % int(s.get("special", 0)),
			"SCORES  %d" % int(s.get("point", 0))]
		for i in lines.size():
			UI.text(self, Vector2(x, 150 + i * 44), lines[i], 32, Color.WHITE, UI.ui, 4)
	UI.text(self, Vector2(960, 470), "SET COUNTS", 44, Color.WHITE, UI.display, 5)
	UI.text(self, Vector2(960, 590), "%d - %d" % [sim.sets_won[0], sim.sets_won[1]], 130, UI.YELLOW,
		UI.ui, 10, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	if t > 40:
		for i in RESULT_OPTIONS.size():
			UI.button(self, Rect2(Vector2(760, 660 + i * 84), Vector2(400, 68)), RESULT_OPTIONS[i],
				i == result_index, frame, 28)


func _draw_toast() -> void:
	if toast_ticks <= 0:
		return
	var alpha := clampf(toast_ticks / 30.0, 0.0, 1.0)
	var r := Rect2(Vector2(560, 960), Vector2(800, 64))
	UI.slant_panel(self, r, Color(0.05, 0.0, 0.12, 0.85 * alpha), Color(UI.CYAN, alpha), 20, 3)
	UI.text(self, Vector2(960, 1003), toast, 26, Color(UI.YELLOW, alpha), UI.ui, 4)
