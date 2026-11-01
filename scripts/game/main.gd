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
const OnlineScreens := preload("res://scripts/game/online_screens.gd")
const QrCode := preload("res://scripts/game/ui/qr_code.gd")
const MixtapeScreen := preload("res://scripts/game/mixtape_screen.gd")
const Tutorial := preload("res://scripts/game/tutorial.gd")
const MovePreview := preload("res://scripts/game/move_preview.gd")
## Options > Controls rows before the per-action bindings.
const CONTROL_HEADER_ROWS := 5

const BALANCE_PATH := "res://data/balance.json"
const SCREEN := Vector2(1920, 1080)
const DIFFICULTIES := ["easy", "normal", "hard"]
const PAUSE_OPTIONS := ["RESUME", "MOVE LIST", "OPTIONS", "QUIT TO MENU"]
const RESULT_OPTIONS := ["REMATCH", "CHARACTER SELECT", "MAIN MENU"]
const OPTION_TABS := ["GRAPHICS", "AUDIO", "CONTROLS", "MOVES"]
const COURT_NOTES := {
	"beach": "TIMBER COURT  -  MAKE A DIVE SAVE TO WAKE THE PIER",
	"lawn": "ROOFTOP PARTY  -  CURVE SHOTS DRIVE THE DJ METERS",
	"tiled": "5 AT THE EDGES  -  SLAPS AND BLOCKS LIGHT THE MARQUEE",
	"concrete": "5 AT THE EDGES  -  BANK OFF THE LIT WALL STRIP",
	"clay": "LOADING YARD  -  OPEN COURT, STANDARD SCORING ZONES",
	"stadium": "CHAMPIONSHIP COURT  -  SCORING STREAKS GROW THE 5-ZONE",
}

enum Screen { TITLE, MAIN, SELECT, COURT, VS, MATCH, PAUSED, OPTIONS, RESULTS,
	ONLINE, ONLINE_WAIT, ONLINE_JOIN, ONLINE_LOBBY, ONLINE_SIGNIN, ONLINE_FRIENDS, ONLINE_ROOM, MIXTAPE, TUTORIAL, SETUP, STORY_MENU, TRAINING, DOUBLES_GUIDE, LAN_BROWSER,
	ONLINE_ADD_FRIEND, ONLINE_LEADERBOARD, STORY_LADDER, ENTRANCE }

var balance: Dictionary
var sim: MatchSim
var view: MatchView
var cpu: CpuPlayer
var screen: int = Screen.TITLE
var screen_ticks := 0
var frame := 0
var versus := false
var doubles := false
var story := false
var story_fighter := 0
const STORY_IDS := ["alex", "jimmy", "jason", "vanessa", "steve", "keno"]
const STORY_COURTS := [3, 1, 4, 0, 2, 5]
const STORY_CHAPTERS := ["Happy Hour of Reckoning", "Raise the Roof", "NightTrain Has No Brakes", "Heavy Lifting", "Subject to Approval", "Final Approach"]
const STORY_REWARDS := ["ALEX ALOHA", "JIMMY NAVIO", "JASON NIGHTTRAIN", "VANESSA TRUNKS", "PETE PELICAN", "KENO DICE + TANGO"]
const STORY_VENUES := ["The Leaky Tiki", "Boardwalk Rooftop", "The Last Stop", "Muscle Pier", "HyperDome Arcade Lounge", "The HyperDome"]
const STORY_TIPS := ["Catch, aim and use the walls.", "Bend a curve past Jimmy.", "Return quickly before Jason can set up.", "Mix lobs with a full-meter special.", "Defend with slaps, pop-ups and drop shots.", "Use everything you learned."]
const UNLOCK_WINS := {"mick":0, "steve":0, "tiffany":0, "alex":1, "jimmy":2, "jason":3, "vanessa":4, "pete":5, "keno":6, "tango":6}
var league_save_path := "user://league.cfg"
var story_wins := 0

func available(index: int) -> bool:
	return index >= 0 and index < balance.characters.size() and story_wins >= int(UNLOCK_WINS.get(balance.characters[index].id, 99))

func _story_ladder() -> Array[int]:
	var result: Array[int] = []
	for id in STORY_IDS:
		for i in balance.characters.size():
			if balance.characters[i].id == id:
				result.append(i)
	return result

func _award_story(wins: int) -> void:
	if wins <= story_wins:
		return
	story_wins = wins
	var cfg := ConfigFile.new()
	cfg.set_value("league", "wins", wins)
	cfg.save(league_save_path)

var story_round := 0
var story_order: Array[int] = []
var story_menu_index := 0
var setup_return: int = Screen.MAIN
var training_index := 0
var setup_row := 0      # format screen: 0 singles, 1 doubles
## Match select (every mode but Story): who has locked in, and what player 1
## is choosing once the humans have: "pick", "cpu" (CPU characters, one slot
## at a time) or "difficulty".
var slot_locked: Array[bool] = [false, false, false, false]
var setup_phase := "pick"
var cpu_turn := -1
var slot_picks: Array[int] = [0, 1, 2, 3]
# Simulation slots alternate sides: 0/2 = Team A, 1/3 = Team B.
var slot_controls: Array[int] = [0, -1, -1, -1]
var match_cpus: Array = []
var story_save_path := "user://story.cfg"
## True while playing (or in the results of) an online match.
var online := false
var net: OnlineScreens
var tapes: MixtapeScreen
var tutorial: Tutorial
var move_preview: MovePreview

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
var _crowd_on := false
## The phone controller QR overlay is open (Options > Controls).
var phone_overlay := false
var _qr  # QrCode for the current join link
var _qr_text := ""
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
	var cfg := ConfigFile.new()
	if cfg.load(league_save_path) == OK:
		story_wins = clampi(int(cfg.get_value("league", "wins", 0)), 0, 6)
	RenderingServer.set_default_clear_color(UI.NIGHT)
	UI.load_fonts()
	Controls.changed.connect(_on_controls_changed)
	net = OnlineScreens.new(self)
	tapes = MixtapeScreen.new(self)
	tutorial = Tutorial.new(self)
	move_preview = MovePreview.new(self)
	logo = load("res://assets/logo/logo.png")
	for c in balance.courts:
		var pixel_path := "res://assets/art/courts/%s_pixel.png" % c.id
		court_thumbs.append(load(pixel_path if ResourceLoader.exists(pixel_path) else "res://assets/art/courts/%s.webp" % c.id))
	for c in balance.characters:
		portraits.append(load("res://assets/art/characters/%s_portrait.webp" % c.id))
		select_art.append(load("res://assets/art/characters/%s_select.webp" % c.id))
	_read_args()


## Developer shortcuts, passed after "--" on the command line:
##   --demo            CPU vs CPU match straight away (attract mode, screenshots)
##   --court=N --p1=N --p2=N --difficulty=N
##   --screen=title|main|select|court|vs|options|results|online|friends|lan|add_friend
##                     (--tab=N picks the options tab)
##   --shots=60,240,600 --out=C:/path   save screenshots at those ticks, then quit
##   --speed=N         run N times faster
##   --host[=port] / --join=address   start online play straight away (LAN)
##   --host-room / --join-room=CODE    the same through a PlayBound Connect room
##   --playbound-api=URL               another PlayBound server (tests, staging)
##   --phone           open Options > Controls > Phone as controller (QR code)
##   --bot             the CPU plays this side online and picks automatically
##   --name=NAME --netlag=MS --netloss=PERCENT --quit-after-match
func _read_args() -> void:
	var online_start := ""
	var open_phone := false
	var room := ""
	var tutorial_lesson := -1
	for arg in OS.get_cmdline_user_args():
		var kv: PackedStringArray = arg.trim_prefix("--").split("=")
		var value := int(kv[1]) if kv.size() > 1 and kv[1].is_valid_int() else 0
		match kv[0]:
			"tutorial":
				tutorial_lesson = value
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
			"host":
				online_start = "host"
				if value > 0:
					Settings.host_port = value
			"join":
				online_start = "join"
				Settings.last_address = arg.trim_prefix("--join=")
			"host-room":
				online_start = "host_room"
			"join-room":
				online_start = "join_room"
				room = arg.trim_prefix("--join-room=")
			"bot":
				net.bot = true
				net.bot_court = court
			"name":
				Settings.player_name = arg.trim_prefix("--name=").to_upper().left(16)
			"netlag":
				net.net_lag = value
			"netloss":
				net.net_loss = value / 100.0
			"quit-after-match":
				net.quit_after_match = true
			"tab":
				options_tab = clampi(value, 0, OPTION_TABS.size() - 1)
			"phone":
				open_phone = true
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
					"court": Screen.COURT, "vs": Screen.VS, "options": Screen.OPTIONS, "online": Screen.ONLINE,
					"friends": Screen.ONLINE_FRIENDS, "mixtape": Screen.MIXTAPE}
				if kv.size() > 1 and names.has(kv[1]):
					_go(names[kv[1]])
				elif kv.size() > 1 and kv[1] in ["select_doubles", "setup"]:
					if kv[1] == "setup":
						setup_return = Screen.MAIN
						_go(Screen.SETUP)
					else:
						_open_local_setup(true, [0, -1, 1, -1], Screen.MAIN)
				elif kv.size() > 1 and kv[1] == "lan":
					net.open_lan()
				elif kv.size() > 1 and kv[1] == "add_friend":
					net.open_add_friend()
				elif kv.size() > 1 and kv[1] == "lobby":
					net.open_browser()
				elif kv.size() > 1 and kv[1] == "leaderboard":
					net.open_leaderboard()
	if demo:
		_start_match()
	if tutorial_lesson >= 0:
		tutorial.open(tutorial_lesson)
	if net.bot:
		net.bot_court = court
	if online_start == "host":
		net.host()
	elif online_start == "join":
		net._connect(Settings.last_address)
	elif online_start == "host_room":
		net.host_room()
	elif online_start == "join_room":
		net.join_room(room)
	if open_phone:
		_open_options(Screen.MAIN)
		options_tab = OPTION_TABS.find("CONTROLS")
		options_row = 4
		_open_phone_overlay()


func _physics_process(_delta: float) -> void:
	frame += 1
	move_preview.tick(((screen == Screen.PAUSED and show_moves) or (screen == Screen.OPTIONS and OPTION_TABS[options_tab] == "MOVES")) and not net.invite_modal_active() and not phone_overlay)
	if not shots.is_empty() and frame >= shots[0]:
		_take_shot(shots.pop_front())
	screen_ticks += 1
	var crowd := screen in [Screen.VS, Screen.ENTRANCE, Screen.MATCH, Screen.PAUSED]
	if crowd != _crowd_on:
		_crowd_on = crowd
		Sfx.set_crowd(crowd)
	Sfx.set_location(balance.courts[court].id if crowd else "")
	toast_ticks = maxi(0, toast_ticks - 1)
	if net.invite_modal_active():
		net.invite_input()
		queue_redraw()
		return
	match screen:
		Screen.TUTORIAL:
			tutorial.tick()
		Screen.TITLE:
			_title_input()
		Screen.MAIN:
			_main_input()
		Screen.MIXTAPE:
			tapes.input()
		Screen.TRAINING:
			if Controls.menu_nudged().y != 0:
				training_index = 1 - training_index
			if _back_pressed():
				_go(Screen.MAIN)
			elif _confirm_device() != -1:
				if training_index == 0:
					tutorial.open(-1, _confirm_device())
				else:
					_go(Screen.DOUBLES_GUIDE)
		Screen.DOUBLES_GUIDE:
			if _back_pressed() or _confirm_device() != -1:
				_go(Screen.TRAINING)
		Screen.SETUP:
			_setup_input()
		Screen.STORY_MENU:
			_story_menu_input()
		Screen.STORY_LADDER:
			if _back_pressed():
				_go(Screen.STORY_MENU)
			elif screen_ticks > 210 or (screen_ticks > 70 and _confirm_device() != -1):
				_go(Screen.VS)
		Screen.ENTRANCE:
			if online:
				net.entrance_tick()
			else:
				view.tick()
				view.entrance_ticks = screen_ticks
				if screen_ticks >= MatchView.INTRO_TICKS or (screen_ticks > 90 and _confirm_device() != -1):
					view.entrance_ticks = -1
					_go(Screen.MATCH)
		Screen.SELECT:
			_select_input()
		Screen.COURT:
			_court_input()
		Screen.VS:
			if online:
				net.vs_tick()
			else:
				_vs_input()
		Screen.MATCH:
			if online:
				net.match_tick()
			else:
				_match_tick()
		Screen.PAUSED:
			_pause_input()
		Screen.OPTIONS:
			_options_input()
		Screen.RESULTS:
			if online:
				net.results_input()
			else:
				_results_input()
		Screen.ONLINE:
			net.menu_input()
		Screen.ONLINE_WAIT:
			net.wait_input()
		Screen.ONLINE_JOIN:
			net.join_input()
		Screen.ONLINE_LOBBY:
			net.lobby_input()
		Screen.ONLINE_SIGNIN:
			net.signin_input()
		Screen.ONLINE_FRIENDS:
			net.friends_input()
		Screen.ONLINE_ROOM:
			net.browser_input()
		Screen.LAN_BROWSER:
			net.lan_input()
		Screen.ONLINE_ADD_FRIEND:
			net.add_friend_input()
		Screen.ONLINE_LEADERBOARD:
			net.leaderboard_input()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	net.handle_text(event)


func _take_shot(tick: int) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shot_%05d.png" % [shots_dir if shots_dir != "" else OS.get_user_data_dir(), tick])
	if shots.is_empty():
		get_tree().quit()


func _go(to: int) -> void:
	Controls.reset_menu_navigation()
	if move_preview != null:
		move_preview.tick(false)
	if tutorial != null and to != Screen.TUTORIAL:
		tutorial.arena.hide()
	screen = to
	screen_ticks = 0
	if to in [Screen.TITLE, Screen.MAIN, Screen.ONLINE, Screen.ONLINE_LOBBY, Screen.RESULTS]:
		Mixtape.menu_music()
	if to == Screen.VS and not online:
		Mixtape.local_music()


## Back in menus: B (K), Escape or Backspace.
func _back_pressed() -> bool:
	return Controls.menu_pressed("b") != -1 or Controls.menu_key("back")


## Select in menus: A (J), Enter, Space, or a controller's Start. Returns
## the controller that pressed it, -2 for the keyboard, -1 for nothing.
func _confirm_device() -> int:
	var d := Controls.menu_pressed("a")
	if d != -1:
		return d
	if Controls.menu_key("confirm"):
		return -2
	return Controls.menu_pad_pressed("start")


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
	var items := ["STORY", "QUICK MATCH", "MULTIPLAYER", "TUTORIAL", "MIXTAPES", "OPTIONS"]
	if not OS.has_feature("web"):
		items.append("QUIT")
	return items


func _main_input() -> void:
	if Controls.menu_pad_pressed("start") != -1:
		_open_options(Screen.MAIN)
		return
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
		"TUTORIAL":
			training_index = 0
			_go(Screen.TRAINING)
		"STORY":
			story_menu_index = 0 if _load_story() else 1
			_go(Screen.STORY_MENU)
		"QUICK MATCH":
			setup_row = 0
			setup_return = Screen.MAIN
			_go(Screen.SETUP)
		"MULTIPLAYER":
			if OS.has_feature("web"):
				toast_msg("ONLINE AND LAN PLAY NEED THE DESKTOP VERSION")
			else:
				net.menu_index = 0
				_go(Screen.ONLINE)
		"MIXTAPES":
			tapes.open()
		"OPTIONS":
			_open_options(Screen.MAIN)
		"QUIT":
			Online.quit_game()


# --- Character select ------------------------------------------------------

func _open_select() -> void:
	picked = [false, false]
	select_step = 0
	_go(Screen.SELECT)


func _grid_move(i: int, n: Vector2i) -> int:
	var count: int = balance.characters.size()
	var cols := 5
	var x := i % cols
	var y := i / cols
	x = posmod(x + n.x, cols)
	y = posmod(y + n.y, ceili(count / float(cols)))
	return mini(y * cols + x, count - 1)


func _select_input() -> void:
	_match_select_input()


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
		if not story:
			# Back to the last choice made: difficulty, or the players' picks.
			if _cpu_slots().is_empty():
				setup_phase = "pick"
				slot_locked[0] = false
			else:
				setup_phase = "difficulty"
		_go(Screen.SELECT)


func _vs_input() -> void:
	if screen_ticks == 1:
		Sfx.play("supersonic", 0.8)
	if screen_ticks > 150 or (screen_ticks > 30 and _confirm_device() != -1):
		_start_match()
		view.entrance_ticks = 0
		_go(Screen.ENTRANCE)


# --- Match -----------------------------------------------------------------

func _names() -> Array[String]:
	if demo:
		return ["CPU", "CPU"]
	return ["P1", "P2" if versus else "CPU"]


func _start_match() -> void:
	online = false
	if story:
		pick = [story_fighter, story_order[story_round]]
		slot_picks[0] = pick[0]
		slot_picks[1] = pick[1]
	var characters: Array = balance.characters
	var seed_value := int(Time.get_ticks_usec())
	cpu = null if versus else CpuPlayer.new(MatchSim.RIGHT, balance.cpu[DIFFICULTIES[difficulty]], seed_value)
	cpu_left = CpuPlayer.new(MatchSim.LEFT, balance.cpu.hard, seed_value + 7) if demo else null
	sim = MatchSim.new(balance, characters[pick[0]], characters[pick[1]], court)
	match_cpus.clear()
	if doubles and not story:
		sim = MatchSim.new(balance, characters[slot_picks[0]], characters[slot_picks[1]], court,
			[characters[slot_picks[2]], characters[slot_picks[3]]])
	var ids: Array = []
	var labels: Array[String] = []
	for i in sim.players.size():
		ids.append(sim.players[i].character.id)
		var controller := 0 if story and i == 0 else (-1 if story else slot_controls[i])
		labels.append("CPU %d" % (i + 1) if controller < 0 else "P%d" % (controller + 1))
		var params: Dictionary = _story_difficulty() if story else balance.cpu[DIFFICULTIES[difficulty]]
		match_cpus.append(CpuPlayer.new(i, params, seed_value + i * 7) if controller < 0 else null)
	view = MatchView.new(sim, ids, labels)
	stats = [{}, {}]
	last_second = -1
	_go(Screen.MATCH)


func _match_tick() -> void:
	if sim.phase == MatchSim.Phase.MATCH_OVER:
		view.tick()
		if sim.phase_ticks > MatchView.CELEBRATION_TICKS or (sim.phase_ticks > MatchView.CELEBRATION_SKIP_TICKS and _confirm_device() != -1):
			result_index = 0
			if story and sim.winner == 0:
				_award_story(story_round + 1)
				_save_story(story_round + 1)
			Sfx.play("menu_confirm")
			_go(Screen.RESULTS)
		else:
			sim.step([{}, {}, {}, {}])
		return
	var inputs: Array = []
	for i in sim.players.size():
		var controller := 0 if story and i == 0 else (-1 if story else slot_controls[i])
		if controller >= 0 and Controls.pressed(controller, "start"):
			_pause(controller)
			return
		inputs.append(match_cpus[i].think(sim) if match_cpus[i] != null else Controls.input(controller))
	if demo:
		inputs[0] = cpu_left.think(sim)
	sim.step(inputs)
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
	var pan := _side_pan(int(e.get("side", 0)))
	# Throws, power throws and specials use the thrower's own sounds.
	var who: String = str(sim.players[int(e.get("player", e.get("side", 0)))].character.get("id", ""))
	match e.type:
		"ready":
			Sfx.play("countdown", 0.8)
		"ref_toss":
			Sfx.play("lob", 0.8, -6.0)
		"go":
			Sfx.play("whistle", 1.15, -6.0)
		"throw":
			if e.supersonic or e.smash:
				Sfx.play("supersonic", 1.08 if e.smash else 1.0, 0.0, pan, who)
				_rumble(e.side, 0.7, 0.45, 0.14)
			else:
				Sfx.play("throw", 1.0, 0.0, pan, who)
				_rumble(e.side, 0.5, 0.2, 0.1)
		"special":
			Sfx.play("special", 1.0, 0.0, pan, who)
			_rumble(e.side, 1.0, 1.0, 0.35)
		"lob", "drop":
			Sfx.play("lob", 0.8 if e.type == "drop" else 0.95, 0.0, pan)
			_rumble(e.side, 0.35, 0.1, 0.1)
		"slap":
			Sfx.play("slap", 1.0, 0.0, pan, who)
			_rumble(e.side, 0.6, 0.45, 0.12)
		"block", "power_toss":
			Sfx.play("block", 1.0, 0.0, pan)
			_rumble(e.side, 0.6, 0.7, 0.14)
		"dash":
			_rumble(e.side, 0.4, 0.15, 0.1)
		"utility":
			Sfx.play("lob", 1.4, -10.0, pan)
		"land":
			Sfx.play("land", 1.0, 0.0, pan)
		"catch":
			# Harder catches (more knockback) hit harder.
			var knock := absf(sim.players[int(e.get("player", e.side))].knock_vel)
			Sfx.play("catch", 1.0 - minf(knock, 6.0) * 0.02, -3.0 + minf(knock, 6.0), pan)
			_rumble(e.side, 0.7, clampf(0.3 + knock / 6.0, 0.3, 1.0), 0.16)
		"bounce":
			Sfx.play("bounce", 1.0, -2.0, _court_pan(sim.disc.pos.x))
		"barrier":
			Sfx.play("net", 1.0, 0.0, _court_pan(sim.disc.pos.x))
		"charge_ready":
			Sfx.play("connect", 1.3, -4.0, pan)
		"ex_ready":
			Sfx.play("menu_confirm", 1.4, -4.0, pan)
		"buzzsaw":
			Sfx.play("power_whoosh", 0.7, -2.0, pan)
		"point":
			# e.side scored: the disc went in on the other side.
			Sfx.play("miss" if e.reason == "miss" else "goal", 1.0, 0.0, _side_pan(1 - int(e.side)) * 0.5)
			_rumble(1 - e.side, 0.9, 1.0, 0.4)
		"set_end":
			Sfx.play("set_end")
			Mixtape.next_round()
		"match_over":
			Sfx.play("match_win")
			_rumble(e.winner, 0.8, 0.8, 0.7)


## Stereo position of a player's side of the court.
func _side_pan(side: int) -> float:
	return -0.6 if side == MatchSim.LEFT else 0.6


## Stereo position of a point on the court (x in court units).
func _court_pan(x: float) -> float:
	return clampf(x / maxf(sim.court_width(), 1.0) * 2.0 - 1.0, -1.0, 1.0) * 0.8


func _countdown_beeps() -> void:
	if sim.set_ticks_left > 0 and (sim.phase == MatchSim.Phase.PLAY or sim.phase == MatchSim.Phase.SERVE):
		var second := ceili(sim.set_ticks_left / 60.0)
		if second != last_second and second <= 5:
			Sfx.play("countdown", 1.0 + (5 - second) * 0.08)
		last_second = second


func _rumble(side: int, weak: float, strong: float, seconds: float) -> void:
	if online:
		var o = net.om()
		if o != null and side == o.local_side:
			_rumble_feel(0, weak, strong, seconds)
			if o.doubles and o.local_partner_human:
				_rumble_feel(1, weak, strong, seconds)
		return
	for slot in sim.players.size():
		var controller := 0 if story and slot == 0 else (-1 if story else slot_controls[slot])
		if sim.players[slot].side == side and controller >= 0:
			_rumble_feel(controller, weak, strong, seconds)


## Rumble scaled by Options > Controls > Rumble. Pulses shorter than about a
## tenth of a second barely register on most controllers, so short ones are
## stretched to that.
func _rumble_feel(player: int, weak: float, strong: float, seconds: float) -> void:
	var level := Settings.rumble_level
	if level == 0:
		return
	var gain := 1.0 if level == 1 else 1.6
	Controls.rumble(player, minf(weak * gain, 1.0), minf(strong * gain, 1.0),
		maxf(seconds, 0.1) * (1.0 if level == 1 else 1.3))


# --- Pause, results, options -----------------------------------------------

func _pause(player: int) -> void:
	paused_by = player
	pause_index = 0
	show_moves = false
	Sfx.play("pause")
	_go(Screen.PAUSED)


func _pause_input() -> void:
	if show_moves:
		var move_direction := Controls.nudged(paused_by)
		if move_direction.y != 0:
			move_preview.select_move(move_direction.y)
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
		result_index = posmod(result_index + n.y, _result_options().size())
		Sfx.play("menu_move")
	if screen_ticks < 40 or _confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match _result_options()[result_index]:
		"NEXT OPPONENT":
			story_round += 1
			_save_story()
			_prepare_story()
		"RETRY":
			_prepare_story()
		"FINISH STORY":
			story_round = story_order.size()
			_save_story()
			_go(Screen.MAIN)
		"REMATCH":
			_go(Screen.VS)
		"CHARACTER SELECT":
			_open_local_setup(doubles, slot_controls.duplicate(), Screen.MAIN)
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
				["VSYNC", Settings.VSYNC_MODES[Settings.vsync_mode]],
				["SCREEN SHAKE", Settings.SHAKE_LEVELS[Settings.shake]],
				["EFFECTS", Settings.EFFECT_LEVELS[Settings.effects]],
				["RETRO SCANLINES", "ON" if Settings.scanlines else "OFF"],
				["SHOW FPS", "ON" if Settings.show_fps else "OFF"],
				["SHOW CATCH ZONES", "ON" if Settings.show_catch_zones else "OFF"],
			]
		"AUDIO":
			return [
				["MASTER VOLUME", "%d%%" % roundi(Settings.master_volume * 100)],
				["EFFECTS VOLUME", "%d%%" % roundi(Settings.sfx_volume * 100)],
				["MUSIC VOLUME", "%d%%" % roundi(Mixtape.music_volume * 100)],
			]
		"CONTROLS":
			var rows := [["PLAYER", "P%d" % (bind_player + 1)],
				["DEVICE", "CONTROLLER" if bind_device == 0 else "KEYBOARD"],
				["BUTTON LABELS", _label_style_text()],
				["RUMBLE", Settings.RUMBLE_LEVELS[Settings.rumble_level]],
				["PHONE AS CONTROLLER", _phone_row_text()]]
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
	if phone_overlay:
		_phone_overlay_input()
		return
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
	if Controls.menu_pressed("utility") != -1:
		_switch_tab(-1)
		return
	if Controls.menu_pressed("slap") != -1:
		_switch_tab(1)
		return
	if n.y != 0:
		if OPTION_TABS[options_tab] == "MOVES":
			move_preview.select_move(n.y)
			return
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
		"MOVES":
			move_preview.replay()
		"GRAPHICS":
			match options_row:
				0:
					Settings.window_mode = posmod(Settings.window_mode + step, Settings.WINDOW_MODES.size())
				1:
					Settings.vsync_mode = posmod(Settings.vsync_mode + step, Settings.VSYNC_MODES.size())
				2:
					Settings.shake = posmod(Settings.shake + step, Settings.SHAKE_LEVELS.size())
				3:
					Settings.effects = posmod(Settings.effects + step, Settings.EFFECT_LEVELS.size())
				4:
					Settings.scanlines = not Settings.scanlines
				5:
					Settings.show_fps = not Settings.show_fps
				6:
					Settings.show_catch_zones = not Settings.show_catch_zones
			Settings.apply()
		"AUDIO":
			var delta := 0.1 * signf(step) if n.x != 0 else 0.0
			if options_row == 0:
				Settings.master_volume = clampf(Settings.master_volume + delta, 0.0, 1.0)
			elif options_row == 1:
				Settings.sfx_volume = clampf(Settings.sfx_volume + delta, 0.0, 1.0)
			else:
				Mixtape.set_volume(Mixtape.music_volume + delta)
			Settings.apply()
		"CONTROLS":
			if options_row == 0:
				bind_player = posmod(bind_player + step, Controls.PLAYERS)
			elif options_row == 1:
				bind_device = posmod(bind_device + step, 2)
			elif options_row == 2:
				Settings.button_labels = posmod(Settings.button_labels + step, Settings.LABEL_STYLES.size())
			elif options_row == 3:
				Settings.rumble_level = posmod(Settings.rumble_level + step, Settings.RUMBLE_LEVELS.size())
				_rumble_feel(bind_player, 0.7, 0.6, 0.2)
			elif options_row == 4:
				if confirm:
					_open_phone_overlay()
					return
			elif options_row == rows.size() - 1:
				if confirm:
					Controls.reset_bindings()
					toast_msg("CONTROLS RESET TO DEFAULTS")
			elif confirm:
				var action: String = Controls.ACTIONS[options_row - CONTROL_HEADER_ROWS]
				Controls.capture(bind_player, "pad" if bind_device == 0 else "keys", action)
	Settings.save()
	Sfx.play("menu_move", 1.15)


func _phone_row_text() -> String:
	if not _phones_supported():
		return "NOT IN THE BROWSER"
	var n: int = Online.phones.connected_count()
	if n > 0:
		return "%d CONNECTED" % n
	return "SHOW QR CODE"


func _phones_supported() -> bool:
	return not OS.has_feature("web") and ClassDB.class_exists("WebRTCPeerConnection")


func _open_phone_overlay() -> void:
	if not _phones_supported():
		toast_msg("PHONE CONTROLLERS NEED THE DESKTOP GAME")
		return
	phone_overlay = true
	Sfx.play("menu_confirm")
	if not Online.phones.active():
		Online.phones.start()


func _phone_overlay_input() -> void:
	if _back_pressed():
		# Phones stay connected after closing; the slot keeps working.
		phone_overlay = false
		Sfx.play("menu_back")
	elif Controls.menu_pressed("slap") != -1 and Online.phones.active():
		Online.phones.stop()
		phone_overlay = false
		Sfx.play("menu_back")
		toast_msg("PHONE CONTROLLERS DISCONNECTED")
	elif _confirm_device() != -1 and not Online.phones.active() and not Online.phones.starting:
		Online.phones.start()  # retry after an error


## "AUTO (PLAYSTATION)" etc.: what Auto picked for this player's controller.
func _label_style_text() -> String:
	var style: String = Settings.LABEL_STYLES[Settings.button_labels]
	if Settings.button_labels == 0:
		style += "  (%s)" % ("PLAYSTATION" if Controls.is_playstation(bind_player) else "XBOX")
	return style


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
		if online:
			net.leave_menu = true  # online matches can't pause
		else:
			_pause(0)


# --- Drawing ---------------------------------------------------------------

func _draw() -> void:
	preload("res://scripts/game/view/pixel_crowd.gd").hide_all()
	match screen:
		Screen.TUTORIAL:
			tutorial.draw()
		Screen.TITLE:
			_draw_title()
		Screen.MAIN:
			_draw_main()
		Screen.MIXTAPE:
			tapes.draw()
		Screen.TRAINING:
			UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
			UI.text(self, Vector2(960, 220), "TUTORIAL", 90, UI.YELLOW, UI.display, 5)
			for i in 2:
				UI.button(self, Rect2(560, 450 + i * 100, 800, 75), "INTERACTIVE MOVE LESSONS" if i == 0 else "DOUBLES BASICS", training_index == i, frame, 36)
			_hint("%s SELECT     %s BACK" % [_a(), _b()])
		Screen.DOUBLES_GUIDE:
			_draw_doubles_guide()
		Screen.SETUP:
			_draw_setup()
		Screen.STORY_MENU:
			_draw_story_menu()
		Screen.STORY_LADDER:
			_draw_story_ladder()
		Screen.ENTRANCE:
			view.draw(self)
			if not online:
				_hint("%s SKIP INTRO" % _a())
		Screen.SELECT:
			_draw_select()
		Screen.COURT:
			_draw_court_select()
		Screen.VS:
			_draw_vs()
		Screen.MATCH:
			view.draw(self)
			if online and net.leave_menu:
				net.draw_leave_menu()
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
		Screen.ONLINE:
			net.draw_menu()
		Screen.ONLINE_WAIT:
			net.draw_wait()
		Screen.ONLINE_JOIN:
			net.draw_join()
		Screen.ONLINE_LOBBY:
			net.draw_lobby()
		Screen.ONLINE_SIGNIN:
			net.draw_signin()
		Screen.ONLINE_FRIENDS:
			net.draw_friends()
		Screen.ONLINE_ROOM:
			net.draw_browser()
		Screen.LAN_BROWSER:
			net.draw_lan()
		Screen.ONLINE_ADD_FRIEND:
			net.draw_add_friend()
		Screen.ONLINE_LEADERBOARD:
			net.draw_leaderboard()
	if net.invite_modal_active():
		net.draw_invite()
	_draw_toast()
	if screen in [Screen.MATCH, Screen.PAUSED] and not (screen == Screen.PAUSED and show_moves) and not Mixtape.now_playing.is_empty():
		# Bottom centre, between the two power throw meters.
		var song := "NOW PLAYING  %s - %s" % [str(Mixtape.now_playing.get("title", "")).left(32),
			str(Mixtape.now_playing.get("artist", "")).left(22)]
		var size := 22
		while size > 14 and UI.text_width(song, size) > 880:
			size -= 1
		# A white tag behind it so it reads over any court.
		var w := UI.text_width(song, size) + 56
		UI.slant_panel(self, Rect2(Vector2(960 - w / 2.0, 1028), Vector2(w, 36)), Color(1, 1, 1, 0.92), UI.CYAN, 12, 3)
		UI.text(self, Vector2(960, 1054), song, size, UI.INK, null, 0)
	if Settings.scanlines:
		UI.scanlines(self, SCREEN)
	if Settings.show_fps:
		UI.text(self, Vector2(1900, 1070), "%d FPS" % Engine.get_frames_per_second(), 22, UI.YELLOW,
			UI.ui, 3, HORIZONTAL_ALIGNMENT_RIGHT)


func _hint(text: String) -> void:
	UI.text(self, Vector2(960, 1050), text, 26, UI.DIM, UI.ui, 4)


## Menu select / back labels: the controller's buttons, or Enter and Esc on
## the keyboard.
func _a() -> String:
	return Controls.label(0, "a") if Controls.using_pad[0] else "ENTER"


func _b() -> String:
	return Controls.label(0, "b") if Controls.using_pad[0] else "ESC"


func _draw_title() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0)
	var bob := sin(frame * 0.05) * 8.0
	var size := logo.get_size() * minf(1560.0 / logo.get_width(), 560.0 / logo.get_height())
	draw_texture_rect(logo, Rect2(Vector2((SCREEN.x - size.x) / 2.0, 110 + bob), size), false)
	if (frame / 30) % 2 == 0:
		UI.text(self, Vector2(960, 800), "PRESS ANY BUTTON", 64, UI.YELLOW, UI.display, 7,
			HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(self, Vector2(960, 1050), "A PLAYBOUND EXCLUSIVE  -  TEST BUILD", 24, UI.WHITE, UI.ui, 4)


func _draw_main() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	# Keep the full logo above the first button, including its transparent canvas.
	var size := logo.get_size() * minf(1320.0 / logo.get_width(), 420.0 / logo.get_height())
	draw_texture_rect(logo, Rect2(Vector2((SCREEN.x - size.x) / 2.0, 40), size), false)
	var items := _main_items()
	for i in items.size():
		var r := Rect2(Vector2(660, 450 + i * 72), Vector2(600, 60))
		UI.button(self, r, items[i], i == main_index, frame, 40)
	_hint("%s SELECT     %s BACK     %s OPTIONS" % [_a(), _b(), Controls.label(0, "start")])

	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	UI.text(self, Vector2(24, SCREEN.y - 40), "v" + version, 24, UI.DIM,
		UI.ui, 3, HORIZONTAL_ALIGNMENT_LEFT)


func _draw_select() -> void:
	_draw_match_select()


func _draw_fighter_card(who: int, c: Dictionary, index := -1) -> void:
	var left: bool = who == 0
	var x := 40.0 if left else 1480.0
	var col := UI.P1 if left else UI.P2
	var art: Texture2D = select_art[pick[who] if index < 0 else index]
	var bob := sin(frame * 0.06 + who) * 6.0
	draw_set_transform(Vector2(x + 200, 600 + bob), 0.0, Vector2(1.0 if left else -1.0, 1.0) * 0.76)
	draw_texture(art, Vector2(-400, -500), Color.WHITE if available(pick[who] if index < 0 else index) else Color.BLACK)
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


func _draw_court_select(hint := "") -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.55)
	UI.slant_panel(self, Rect2(610, 26, 700, 90), UI.YELLOW, UI.INK, 30, 5)
	UI.text(self, Vector2(960, 98), "SELECT COURT", 64, UI.INK, UI.display, 2)
	var big := Rect2(Vector2(480, 170), Vector2(960, 540))
	draw_rect(big.grow(8), UI.INK)
	draw_texture_rect(court_thumbs[court], big, false)
	draw_rect(big.grow(4), UI.CYAN, false, 5)
	var c: Dictionary = balance.courts[court]
	UI.text(self, Vector2(960, 800), str(c.name), UI.fit_size(str(c.name), 96, 1730, UI.display), UI.PINK, UI.display, 8, HORIZONTAL_ALIGNMENT_CENTER,
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
	_hint(hint if hint != "" else "%s CONFIRM     %s BACK" % [_a(), _b()])


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
	UI.text(self, Vector2(960, 80), STORY_VENUES[story_round] if story else court_name, 48, Color.WHITE, UI.display, 6)

	if story:
		UI.text(self, Vector2(960, 160), "CHAPTER %d  |  %s" % [story_round + 2, STORY_CHAPTERS[story_round].to_upper()], 36, UI.YELLOW, UI.ui, 3)
		UI.text(self, Vector2(960, 220), STORY_TIPS[story_round], 32, Color.WHITE, UI.ui, 4)
	elif doubles:
		UI.text(self, Vector2(960, 160), "DOUBLES  |  TEAM A vs TEAM B", 40, UI.YELLOW, UI.ui, 3)
		UI.text(self, Vector2(960, 930), "%s + %s   VS   %s + %s" % [balance.characters[slot_picks[0]].name, balance.characters[slot_picks[2]].name, balance.characters[slot_picks[1]].name, balance.characters[slot_picks[3]].name], 28, Color.WHITE, UI.ui, 3)


func _draw_pause() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.03, 0.0, 0.1, 0.65))
	if show_moves:
		_draw_move_list(Rect2(Vector2(160, 160), Vector2(1600, 800)))
		_hint("%s / %s BACK" % [_a(), _b()])
		return
	UI.text(self, Vector2(960, 330), "PAUSED", 110, UI.YELLOW, UI.display, 9, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)
	UI.text(self, Vector2(960, 380), "P%d" % (paused_by + 1), 34, UI.P1 if paused_by == 0 else UI.P2,
		UI.ui, 4)
	for i in PAUSE_OPTIONS.size():
		UI.button(self, Rect2(Vector2(710, 440 + i * 96), Vector2(500, 78)), PAUSE_OPTIONS[i],
			i == pause_index, frame, 36)


func _draw_move_list(area: Rect2) -> void:
	move_preview.draw(area)


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
		_draw_move_list(Rect2(160, 250, 1600, 740))
	else:
		UI.slant_panel(self, area, Color(0.07, 0.02, 0.16, 0.92), UI.PURPLE, 30, 4)
		var rows := _option_rows()
		var row_step := mini(70, int((area.size.y - 100) / rows.size()))
		# Long lists (the controls) get slimmer rows so they still fit.
		var row_h := mini(64, row_step - 2)
		var font := mini(30, row_h - 18)
		var base := row_h - 20
		for i in rows.size():
			var y := area.position.y + 40 + i * row_step
			var on: bool = i == options_row
			var row := Rect2(Vector2(area.position.x + 60, y), Vector2(area.size.x - 120, row_h))
			if on:
				UI.slant_panel(self, row, Color(UI.PINK, 0.35), UI.CYAN, 16, 3)
			UI.text(self, Vector2(row.position.x + 40, y + base), rows[i][0], font, Color.WHITE, UI.ui, 4,
				HORIZONTAL_ALIGNMENT_LEFT)
			var value: String = rows[i][1]
			if Controls.capturing() and on:
				value = "PRESS A %s..." % ("BUTTON" if bind_device == 0 else "KEY")
			elif on and value != "":
				value = "<  %s  >" % value if OPTION_TABS[options_tab] != "CONTROLS" or i < 4 else value
				if OPTION_TABS[options_tab] == "CONTROLS" and i == 4:
					value = "%s  >" % rows[i][1]
			UI.text(self, Vector2(row.end.x - 40, y + base), value, font, UI.YELLOW, UI.ui, 4,
				HORIZONTAL_ALIGNMENT_RIGHT)
		if OPTION_TABS[options_tab] == "GRAPHICS" and OS.has_feature("web"):
			UI.text(self, Vector2(960, area.end.y - 30), "DISPLAY AND VSYNC ARE SET BY THE BROWSER", 24,
				UI.DIM, UI.ui, 3)
		if OPTION_TABS[options_tab] == "CONTROLS":
			UI.text(self, Vector2(960, area.end.y - 18), "PICK AN ACTION AND PRESS %s, THEN THE NEW BUTTON" % _a(),
				24, UI.DIM, UI.ui, 3)
	if phone_overlay:
		_draw_phone_overlay()
		return
	if OPTION_TABS[options_tab] == "MOVES":
		_hint("UP / DOWN PICK MOVE     %s REPLAY     %s / %s SWITCH TAB     %s BACK" % [_a(), Controls.label(0, "utility"), Controls.label(0, "slap"), _b()])
		return
	_hint("%s / %s SWITCH TAB     %s CHANGE     %s BACK" % [Controls.label(0, "utility"),
		Controls.label(0, "slap"), _a(), _b()])


func _draw_phone_overlay() -> void:
	draw_rect(Rect2(Vector2.ZERO, SCREEN), Color(0.03, 0.0, 0.1, 0.88))
	var panel := Rect2(Vector2(150, 110), Vector2(1620, 840))
	UI.slant_panel(self, panel, Color("1a0b38"), UI.CYAN, 34, 6)
	UI.text(self, Vector2(960, 205), "PHONE AS CONTROLLER", 72, UI.YELLOW, UI.display, 7, HORIZONTAL_ALIGNMENT_CENTER,
		-1.0, true)
	var phones = Online.phones
	var box := Rect2(Vector2(260, 270), Vector2(560, 560))
	if phones.active():
		if _qr_text != phones.join_url():
			_qr_text = phones.join_url()
			_qr = QrCode.encode(_qr_text)
		if _qr != null:
			_draw_qr(_qr, box)
	else:
		draw_rect(box, Color("120826"))
		var msg: String = phones.error if phones.error != "" and not phones.starting 			else "GETTING A CODE" + ".".repeat(1 + (frame / 20) % 3)
		_fit_text(box.get_center() + Vector2(0, 12), msg, 30, UI.CYAN, UI.ui, box.size.x - 60,
			HORIZONTAL_ALIGNMENT_CENTER)
	# Right column: stays inside the panel's slanted right edge.
	var x := 900.0
	var w := panel.end.x - 60.0 - x
	var steps := ["1.  SCAN THE QR CODE WITH YOUR PHONE'S CAMERA",
		"2.  THE PLAYBOUND CONTROLLER OPENS IN ITS BROWSER",
		"3.  NO APP OR ACCOUNT NEEDED"]
	for i in steps.size():
		_fit_text(Vector2(x, 330 + i * 54), steps[i], 30, Color.WHITE, UI.ui, w)
	_fit_text(Vector2(x, 530), "NO CAMERA?  GO TO  PLAYBOUND.CLUB/C  AND TYPE", 26, UI.DIM, UI.ui, w)
	UI.text(self, Vector2(x, 612), phones.join_code() if phones.active() else "------", 76, UI.YELLOW, UI.display,
		7, HORIZONTAL_ALIGNMENT_LEFT)
	var n: int = phones.connected_count()
	var status := "WAITING FOR A PHONE" + ".".repeat(1 + (frame / 20) % 3)
	if n > 0:
		var slots := []
		for i in Controls.PLAYERS:
			if Controls.has_pad(i) and Controls.is_virtual(Controls.pads[i]):
				slots.append("PLAYER %d" % (i + 1))
		status = "%d PHONE%s CONNECTED" % [n, "" if n == 1 else "S"]
		if not slots.is_empty():
			status += ":  " + ", ".join(slots)
	_fit_text(Vector2(x, 720), status, 32, Color("39ff88") if n > 0 else UI.CYAN, UI.ui, w)
	_fit_text(Vector2(x, 770), "A PHONE TAKES A FREE PLAYER SLOT, LIKE PLUGGING IN A PAD", 24, UI.DIM, UI.ui, w)
	var hint := "%s DONE (PHONES STAY CONNECTED)" % _b()
	if phones.active():
		hint += "     %s DISCONNECT PHONES" % Controls.label(0, "slap")
	elif phones.error != "":
		hint = "%s TRY AGAIN     %s BACK" % [_a(), _b()]
	_hint(hint)


## Text shrunk (never grown) to fit max_width.
func _fit_text(pos: Vector2, text: String, size: int, color: Color, font: Font, max_width: float,
		align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := UI.text_width(text, size, font)
	var fitted := size if width <= max_width else maxi(12, int(size * max_width / width))
	UI.text(self, pos, text, fitted, color, font, maxi(2, fitted / 8), align)


## Dark modules on white with the standard 4-module quiet zone.
func _draw_qr(qr, box: Rect2) -> void:
	var cells: int = qr.size + 8
	var px := floorf(box.size.x / cells)
	var side := px * cells
	var origin := box.position + (box.size - Vector2(side, side)) / 2.0
	draw_rect(Rect2(origin, Vector2(side, side)), Color.WHITE)
	for y in qr.size:
		for x in qr.size:
			if qr.dark(x, y):
				draw_rect(Rect2(origin + Vector2(x + 4, y + 4) * px, Vector2(px, px)), Color.BLACK)


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
	if story:
		var title := "STORY COMPLETE!" if sim.winner == 0 and story_round + 1 == story_order.size() else "STORY  %d / %d" % [story_round + 1, story_order.size()]
		UI.text(self, Vector2(960, 80), title, 50, UI.YELLOW, UI.display, 4)
		if sim.winner == 0:
			UI.text(self, Vector2(960, 155), "PLAYABLE: " + STORY_REWARDS[story_round], 32, UI.CYAN, UI.ui, 4)
			if story_round == 5:
				UI.text(self, Vector2(960, 210), "LEAGUE INVITATION: RANKED QUICK MATCH IS OPEN", 30, UI.YELLOW, UI.ui, 4)
	if doubles:
		for side in [0, 1]:
			var team := "%s + %s" % [sim.players[side].character.name, sim.players[side + 2].character.name]
			UI.text(self, Vector2(470 if side == 0 else 1450, 860), team, UI.fit_size(team, 32, 700, UI.ui), Color.WHITE, UI.ui, 4)
	if online:
		net.draw_results_menu()
	elif t > 40:
		for i in _result_options().size():
			UI.button(self, Rect2(Vector2(760, 660 + i * 84), Vector2(400, 68)), _result_options()[i],
				i == result_index, frame, 28)


func _draw_toast() -> void:
	if toast_ticks <= 0:
		return
	var alpha := clampf(toast_ticks / 30.0, 0.0, 1.0)
	var r := Rect2(Vector2(560, 960), Vector2(800, 64))
	UI.slant_panel(self, r, Color(0.05, 0.0, 0.12, 0.85 * alpha), Color(UI.CYAN, alpha), 20, 3)
	UI.text(self, Vector2(960, 1003), toast, 26, Color(UI.YELLOW, alpha), UI.ui, 4)


func _result_options() -> Array:
	if not story:
		return RESULT_OPTIONS
	if sim.winner != 0:
		return ["RETRY", "MAIN MENU"]
	return ["NEXT OPPONENT" if story_round + 1 < story_order.size() else "FINISH STORY", "MAIN MENU"]


func _save_story(next_round := -1) -> void:
	var save := ConfigFile.new()
	save.set_value("story", "fighter", story_fighter)
	save.set_value("story", "round", story_round if next_round < 0 else next_round)
	save.set_value("story", "order", story_order)
	save.save(story_save_path)


func _load_story() -> bool:
	var save := ConfigFile.new()
	if save.load(story_save_path) != OK:
		return false
	var fighter := int(save.get_value("story", "fighter", -1))
	var round_index := int(save.get_value("story", "round", -1))
	var order = save.get_value("story", "order", [])
	if fighter < 0 or fighter >= balance.characters.size() or not order is Array or fighter != 0 or order != _story_ladder():
		return false
	var seen := [fighter]
	for opponent in order:
		if not opponent is int or opponent < 0 or opponent >= balance.characters.size() or opponent in seen:
			return false
		seen.append(opponent)
	if round_index < 0 or round_index >= order.size():
		return false
	story_fighter = fighter
	story_round = round_index
	story_order.assign(order)
	return true


func _prepare_story() -> void:
	story = true
	doubles = false
	versus = false
	pick = [story_fighter, story_order[story_round]]
	court = STORY_COURTS[story_round]
	_go(Screen.STORY_LADDER)


func _story_difficulty() -> Dictionary:
	var params: Dictionary = balance.cpu.easy.duplicate(true)
	# Small, predictable steps. No opponent-specific spikes in reaction or specials.
	var progress := clampf(story_round / 5.0, 0.0, 1.0) * 0.30
	for key in balance.cpu.easy:
		if balance.cpu.easy[key] is float or balance.cpu.easy[key] is int:
			var value := lerpf(float(balance.cpu.easy[key]), float(balance.cpu.normal[key]), progress)
			params[key] = roundi(value) if balance.cpu.easy[key] is int else value
	return params


func _story_menu_input() -> void:
	var n := Controls.menu_nudged()
	if n.y != 0:
		story_menu_index = posmod(story_menu_index + n.y, 2)
	if _back_pressed():
		_go(Screen.MAIN)
	elif _confirm_device() != -1:
		if story_menu_index == 0:
			if _load_story():
				_prepare_story()
		else:
			story_fighter = 0
			story_round = 0
			story_order = _story_ladder()
			_save_story()
			_prepare_story()


func _draw_story_menu() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	UI.text(self, Vector2(960, 200), "STORY", 100, UI.YELLOW, UI.display, 5)
	var save := ConfigFile.new()
	var resumable: bool = save.load(story_save_path) == OK and save.get_value("story", "order", []) == _story_ladder() and int(save.get_value("story", "round", -1)) < STORY_IDS.size()
	UI.text(self, Vector2(960, 320), "WIN SIX MATCHES AS MICK TO ENTER THE HYPERDISC ARENA LEAGUE.", 30, Color.WHITE, UI.ui, 3)
	var items := ["CONTINUE" if resumable else "NO SAVED RUN", "NEW STORY"]
	for i in items.size():
		UI.button(self, Rect2(560, 420 + i * 100, 800, 75), items[i], story_menu_index == i, frame, 36)
	_hint("%s SELECT     %s BACK" % [_a(), _b()])


func _setup_slots() -> Array:
	return [0, 2, 1, 3] if doubles else [0, 1]


func _setup_input() -> void:
	var n := Controls.menu_nudged()
	if n.y != 0 or n.x != 0:
		setup_row = 1 - setup_row
		Sfx.play("menu_move")
	if _back_pressed():
		Sfx.play("menu_back")
		_go(setup_return)
	elif _confirm_device() != -1:
		Sfx.play("menu_confirm")
		_open_local_setup(setup_row == 1, [0, -1, -1, -1], Screen.SETUP)


func _draw_setup() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	UI.text(self, Vector2(960, 200), "QUICK MATCH", 110, UI.YELLOW, UI.display, 6)
	var items := ["SINGLES  1v1", "DOUBLES  2v2"]
	var notes := ["ONE-OFF MATCH: ONE PLAYER EACH SIDE", "ONE-OFF MATCH: TWO PLAYERS EACH SIDE, ONE TEAM SCORE"]
	for i in items.size():
		UI.button(self, Rect2(560, 420 + i * 110, 800, 80), items[i], setup_row == i, frame, 40)
	UI.text(self, Vector2(960, 700), notes[setup_row], 28, UI.CYAN, UI.ui, 3)
	UI.text(self, Vector2(960, 750), "FRIENDS JOIN ON THE NEXT SCREEN; EMPTY SLOTS ARE PLAYED BY THE CPU", 26, Color.WHITE, UI.ui, 3)
	_hint("%s SELECT     %s BACK" % [_a(), _b()])


func _draw_doubles_guide() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	UI.text(self, Vector2(960, 150), "DOUBLES BASICS", 80, UI.YELLOW, UI.display, 5)
	var lines := ["TWO PLAYERS PER SIDE. ONE DISC. ONE TEAM SCORE.",
		"COVER DIFFERENT LANES: ONE HIGH, ONE LOW.",
		"THE FIRST PLAYER TO REACH THE DISC CATCHES IT.",
		"WHEN YOUR PARTNER GOES FOR THE CATCH, COVER THE OPEN SPACE.",
		"MOVE THROUGH YOUR TEAMMATE FREELY. ALL YOUR MOVES STILL WORK.",
		"EACH PLAYER HAS THEIR OWN POWER METER.",
		"QUICK MATCH: ASSIGN PLAYERS OR CPUs TO ANY TEAM SLOT.",
		"ONLINE: TWO MACHINES, EACH WITH A LOCAL OR CPU PARTNER."]
	for i in lines.size():
		UI.text(self, Vector2(960, 310 + i * 75), lines[i], 30, UI.CYAN if i % 2 == 0 else Color.WHITE, UI.ui, 3)
	_hint("%s / %s BACK" % [_a(), _b()])


## Opens the match select: the character grid with every slot's card. The
## given controllers sit in slots 0-3 (-1 = CPU); more players join with
## START.
func _open_local_setup(team_match: bool, controllers: Array, return_to: int) -> void:
	story = false
	online = false
	doubles = team_match
	slot_controls.assign(controllers)
	if not doubles:
		slot_controls[2] = -1
		slot_controls[3] = -1
	slot_locked.assign([false, false, false, false])
	setup_phase = "pick"
	cpu_turn = -1
	setup_return = return_to
	_go(Screen.SELECT)


## Slots played by the CPU, in pick order.
func _cpu_slots() -> Array:
	return _setup_slots().filter(func(slot): return slot_controls[slot] < 0)


## A player's slot, or -1.
func _slot_of(controller: int) -> int:
	for slot in _setup_slots():
		if slot_controls[slot] == controller:
			return slot
	return -1


func _match_select_input() -> void:
	var slots := _setup_slots()
	match setup_phase:
		"pick":
			# More players join with START, taking the first CPU slot (the
			# other side first, then partners).
			for controller in range(1, Controls.PLAYERS):
				if Controls.pressed(controller, "start") and _slot_of(controller) < 0:
					for slot in [1, 2, 3] if doubles else [1]:
						if slot_controls[slot] < 0:
							slot_controls[slot] = controller
							slot_locked[slot] = false
							Sfx.play("menu_confirm")
							break
			for slot in slots:
				var c: int = slot_controls[slot]
				if c < 0:
					continue
				var confirm: bool = Controls.pressed(c, "a") or (c == 0 and Controls.menu_key("confirm"))
				var back: bool = Controls.pressed(c, "b") or (c == 0 and Controls.menu_key("back"))
				if slot_locked[slot]:
					if back:
						slot_locked[slot] = false
						Sfx.play("menu_back")
					continue
				var n := Controls.nudged(c)
				if n != Vector2i.ZERO:
					slot_picks[slot] = _grid_move(slot_picks[slot], n)
					Sfx.play("menu_move", 1.0 + slot * 0.05)
				if confirm and not available(slot_picks[slot]):
					toast_msg("UNLOCK THIS PLAYER IN STORY MODE")
				elif confirm:
					slot_locked[slot] = true
					Sfx.play("menu_confirm")
				elif back:
					Sfx.play("menu_back")
					if c == 0:
						_go(setup_return)
						return
					slot_controls[slot] = -1  # leave: a CPU takes the slot
				elif doubles and c != 0 and Controls.pressed(c, "utility"):
					# Switch teams: into a free slot on the other side.
					for other in ([1, 3] if slot % 2 == 0 else [0, 2]):
						if slot_controls[other] < 0:
							slot_controls[other] = c
							slot_controls[slot] = -1
							slot_picks[other] = slot_picks[slot]
							Sfx.play("menu_move")
							break
			var humans := slots.filter(func(slot): return slot_controls[slot] >= 0)
			if not humans.is_empty() and humans.all(func(slot): return slot_locked[slot]) and screen_ticks > 10:
				var cpus := _cpu_slots()
				if cpus.is_empty():
					_to_court()
				else:
					setup_phase = "cpu"
					cpu_turn = cpus[0]
		"cpu":
			var n := Controls.menu_nudged()
			if n != Vector2i.ZERO:
				slot_picks[cpu_turn] = _grid_move(slot_picks[cpu_turn], n)
				Sfx.play("menu_move")
			var cpus := _cpu_slots()
			var at := cpus.find(cpu_turn)
			if _confirm_device() != -1 and not available(slot_picks[cpu_turn]):
				toast_msg("UNLOCK THIS PLAYER IN STORY MODE")
			elif _confirm_device() != -1:
				Sfx.play("menu_confirm")
				if at + 1 < cpus.size():
					cpu_turn = cpus[at + 1]
				else:
					setup_phase = "difficulty"
			elif _back_pressed():
				Sfx.play("menu_back")
				if at > 0:
					cpu_turn = cpus[at - 1]
				else:
					setup_phase = "pick"
					slot_locked[_slot_of(0)] = false
		"difficulty":
			var n := Controls.menu_nudged()
			if n.x != 0:
				difficulty = posmod(difficulty + n.x, DIFFICULTIES.size())
				Sfx.play("menu_move")
			if _confirm_device() != -1:
				Sfx.play("menu_confirm")
				_to_court()
			elif _back_pressed():
				Sfx.play("menu_back")
				setup_phase = "cpu"
				cpu_turn = _cpu_slots()[-1]


func _to_court() -> void:
	pick = [slot_picks[0], slot_picks[1]]
	versus = slot_controls[1] >= 0
	_go(Screen.COURT)


## The character grid with every slot's outline and tag, shared by local and
## online setup. slots: [{slot, pick, label, color, flash}].
func _draw_select_grid(slots: Array) -> void:
	var chars: Array = balance.characters
	var cell := Vector2(140, 140)
	var gap := 28
	UI.text(self, Vector2(960, 585), "UNLOCK SILHOUETTES IN STORY MODE", 22, UI.DIM, UI.ui, 3)
	var grid_origin := Vector2(960 - cell.x * 2.5 - 2 * gap, 230)
	for i in chars.size():
		var pos := grid_origin + Vector2((i % 5) * (cell.x + gap), (i / 5) * (cell.y + gap))
		var r := Rect2(pos, cell)
		draw_rect(r.grow(4), UI.INK)
		draw_rect(r, Color("2a1250"))
		if available(i):
			draw_texture_rect_region(portraits[i], r, Rect2(100, 40, 440, 440))
		else:
			draw_texture_rect_region(select_art[i], r, Rect2(0, 100, 800, 800), Color.BLACK)
		UI.text(self, pos + Vector2(cell.x / 2, cell.y - 12), str(chars[i].name).to_upper() if available(i) else "STORY LOCK", 17,
			Color.WHITE, UI.ui, 4)
	# Outlines after every portrait so neighbouring tiles can't cover them;
	# each slot on a tile gets its own ring and a tag in its own corner.
	var on_tile := {}
	for entry in slots:
		var i: int = entry.pick
		if i < 0:
			continue
		var k: int = on_tile.get(i, 0)
		on_tile[i] = k + 1
		var pos := grid_origin + Vector2((i % 5) * (cell.x + gap), (i / 5) * (cell.y + gap))
		var r := Rect2(pos, cell)
		if not entry.flash or (frame / 6) % 2 == 0:
			draw_rect(r.grow(4 + k * 6), entry.color, false, 7)
		var corner: Vector2 = [Vector2(14, 40), Vector2(cell.x - 14, 40), Vector2(14, 80), Vector2(cell.x - 14, 80)][k % 4]
		UI.text(self, pos + corner, entry.label, 28, entry.color, UI.display, 4,
			HORIZONTAL_ALIGNMENT_LEFT if k % 2 == 0 else HORIZONTAL_ALIGNMENT_RIGHT)


## A fighter card for doubles: two per side, smaller. row 0 top, 1 bottom.
func _draw_mini_card(left: bool, row: int, index: int, col: Color, tag: String, ready: bool) -> void:
	var c: Dictionary = balance.characters[index]
	var x := 40.0 if left else 1480.0
	var top := 150.0 + row * 420.0
	var bob := sin(frame * 0.06 + row + (0 if left else 2)) * 4.0
	draw_set_transform(Vector2(x + 200, top + 175 + bob), 0.0, Vector2(1.0 if left else -1.0, 1.0) * 0.36)
	draw_texture(select_art[index], Vector2(-400, -500), Color.WHITE if available(index) else Color.BLACK)
	draw_set_transform(Vector2.ZERO)
	var panel := Rect2(Vector2(x, top + 230), Vector2(400, 150))
	UI.slant_panel(self, panel, Color("120826"), col, 20, 4)
	UI.text(self, panel.position + Vector2(24, 40), tag, 26, col, UI.display, 4, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(self, panel.position + Vector2(220, 40), str(c.name).to_upper(), 30, Color.WHITE, UI.display, 4)
	var bars := [["SPEED", (float(c.speed) - 0.7) / 0.8], ["POWER", (float(c.power) - 0.6) / 0.85]]
	for i in bars.size():
		var y := panel.position.y + 62 + i * 36
		UI.text(self, Vector2(panel.position.x + 30, y + 20), bars[i][0], 20, Color.WHITE, UI.ui, 3,
			HORIZONTAL_ALIGNMENT_LEFT)
		UI.meter(self, Rect2(Vector2(panel.position.x + 150, y + 2), Vector2(220, 20)),
			clampf(bars[i][1], 0.08, 1.0), UI.YELLOW if i == 0 else UI.ZONE_5, 8)
	if ready:
		UI.text(self, Vector2(x + 200, top + 215), "READY!", 40, UI.YELLOW, UI.display, 5)


## An empty slot while players pick: a CPU unless someone joins.
func _draw_open_slot(centre: Vector2, col: Color) -> void:
	var panel := Rect2(centre - Vector2(190, 70), Vector2(380, 140))
	UI.slant_panel(self, panel, Color(0.07, 0.03, 0.15, 0.85), col, 20, 4)
	UI.text(self, centre + Vector2(0, -8), "CPU", 44, col, UI.display, 5)
	var blink := (frame / 30) % 2 == 0
	UI.text(self, centre + Vector2(0, 40), "PRESS START TO JOIN" if blink else "PICKED AFTER PLAYERS", 22,
		Color.WHITE, UI.ui, 3)


## Slot colours: team A pink shades, team B cyan shades.
func _slot_color(slot: int) -> Color:
	var base := UI.P1 if slot % 2 == 0 else UI.P2
	return base if slot < 2 else base.lightened(0.45)


func _slot_tag(slot: int) -> String:
	return "CPU" if slot_controls[slot] < 0 else "P%d" % (slot_controls[slot] + 1)


func _draw_match_select() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.55)
	var title := "SELECT YOUR PLAYER" if not doubles else "SELECT YOUR PLAYERS"
	if setup_phase == "cpu":
		var team_mate := cpu_turn % 2 == _slot_of(0) % 2
		title = "SELECT CPU PARTNER" if team_mate else "SELECT CPU OPPONENT"
	elif setup_phase == "difficulty":
		title = "SELECT DIFFICULTY"
	UI.slant_panel(self, Rect2(510, 26, 900, 90), UI.YELLOW, UI.INK, 30, 5)
	UI.text(self, Vector2(960, 98), title, 60, UI.INK, UI.display, 2)
	UI.text(self, Vector2(960, 160), "DOUBLES 2v2" if doubles else "SINGLES 1v1", 30, UI.CYAN, UI.ui, 3)
	var slots := _setup_slots()
	var grid := []
	for slot in slots:
		var choosing: bool = (setup_phase == "pick" and slot_controls[slot] >= 0 and not slot_locked[slot]) \
			or (setup_phase == "cpu" and slot == cpu_turn)
		var shown: bool = slot_controls[slot] >= 0 or setup_phase != "pick"
		if shown:
			grid.append({"slot": slot, "pick": slot_picks[slot], "label": _slot_tag(slot),
				"color": _slot_color(slot), "flash": choosing})
	_draw_select_grid(grid)
	if doubles:
		for slot in slots:
			var cpu_waiting: bool = slot_controls[slot] < 0 and setup_phase == "pick"
			if cpu_waiting:
				_draw_open_slot(Vector2(240 if slot % 2 == 0 else 1680, 360 + (slot / 2) * 420), _slot_color(slot))
				continue
			_draw_mini_card(slot % 2 == 0, slot / 2, slot_picks[slot], _slot_color(slot), _slot_tag(slot),
				slot_locked[slot])
	else:
		for slot in slots:
			if slot_controls[slot] < 0 and setup_phase == "pick":
				_draw_open_slot(Vector2(240 if slot == 0 else 1680, 560), _slot_color(slot))
				continue
			pick[slot] = slot_picks[slot]
			_draw_fighter_card(slot, balance.characters[slot_picks[slot]], slot_picks[slot])
			if slot_locked[slot]:
				UI.text(self, Vector2(240 if slot == 0 else 1680, 790), "READY!", 56, UI.YELLOW, UI.display, 6)
	if setup_phase == "difficulty":
		UI.button(self, Rect2(Vector2(660, 720), Vector2(600, 90)), "<  CPU %s  >" % DIFFICULTIES[difficulty].to_upper(),
			true, frame, 42)
	var open_slots := _cpu_slots().size()
	if setup_phase == "pick":
		var join := "     P2-P4: PRESS START TO JOIN" if open_slots > 0 else ""
		var swap := "     %s: SWITCH TEAM" % Controls.label(1, "utility") if doubles else ""
		_hint("STICK: CHOOSE     %s LOCK IN     %s BACK%s%s" % [_a(), _b(), join, swap])
	else:
		_hint("%s CONFIRM     %s BACK" % [_a(), _b()])




func _draw_story_ladder() -> void:
	UI.outrun_background(self, SCREEN, frame / 60.0, 0.25)
	UI.text(self, Vector2(960,110), "ROAD TO THE HYPERDOME", 76, UI.YELLOW, UI.display, 4)
	UI.text(self, Vector2(960,170), "WIN %d OF 6  |  %s" % [story_round+1, STORY_VENUES[story_round].to_upper()], 28, Color.WHITE, UI.ui, 2)
	for i in 6:
		var y := 820.0-i*105.0
		var active := i == story_round
		var box := Rect2(610,y-60,940,88)
		UI.slant_panel(self,box,Color("17112e"),UI.YELLOW if active else UI.DIM,16,3)
		var name: String = balance.characters[story_order[i]].name
		UI.text(self,Vector2(680,y),"%d" % [i+1],40,UI.YELLOW,UI.display,2)
		UI.text(self,Vector2(1080,y),name.to_upper(),38,Color.WHITE if active else UI.DIM,UI.display,2)
		if i < story_round:
			UI.text(self,Vector2(1450,y),"WIN",24,UI.CYAN,UI.ui,1)
	var step := smoothstep(0.0,1.0,clampf((screen_ticks-25)/55.0,0,1))
	var rank := lerpf(float(maxi(0,story_round-1)),float(story_round),step)
	var y := 820.0-rank*105.0
	draw_texture_rect(portraits[story_fighter],Rect2(410,y-85,140,140),false)
	UI.text(self,Vector2(555,y),">",50,UI.YELLOW,UI.display,2)
	UI.text(self,Vector2(960,950),STORY_TIPS[story_round],30,Color.WHITE,UI.ui,2)
	_hint("%s CONTINUE    %s BACK" % [_a(),_b()])
