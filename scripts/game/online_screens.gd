## The online screens: the online menu (name, host, join), waiting for a
## connection, typing an address, the lobby where both players pick, and
## the online match loop. main.gd hands control here for these screens.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")
const MatchView := preload("res://scripts/game/view/match_view.gd")
const OnlineMatch := preload("res://scripts/net/online_match.gd")
const UdpTransport := preload("res://scripts/net/udp_transport.gd")
const UI := preload("res://scripts/game/ui/theme.gd")

const MENU := ["NAME", "HOST GAME", "JOIN GAME", "PLAYBOUND", "BACK"]
const ONLINE_RESULTS := ["REMATCH", "LEAVE"]

var m  # main.gd
var menu_index := 1
var typing := {}        # {field, value} while a text field is being edited
var lobby_row := 0      # 0 character grid, 1 court (host, once locked)
var leave_menu := false
var leave_index := 0
var vs_ticks := 0
var announced_rematch := false

## Developer / test automation (see main.gd _read_args).
var bot := false
var bot_cpu: CpuPlayer
var bot_court := 0
var net_lag := 0
var net_loss := 0.0
var quit_after_match := false


func _init(main_node) -> void:
	m = main_node


func om() -> OnlineMatch:
	return Online.current


# --- Text entry --------------------------------------------------------------

## Keyboard text entry for the name and address fields. Returns true if the
## event was used.
func handle_text(event: InputEvent) -> bool:
	if typing.is_empty() or not (event is InputEventKey) or not event.pressed:
		return false
	var limit := 16 if typing.field == "name" else 64
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_finish_typing(true)
		KEY_ESCAPE:
			_finish_typing(false)
		KEY_BACKSPACE:
			typing.value = typing.value.left(maxi(typing.value.length() - 1, 0))
		_:
			if event.ctrl_pressed and event.keycode == KEY_V:
				typing.value = (typing.value + DisplayServer.clipboard_get().strip_edges()).left(limit)
			elif event.unicode >= 32 and event.unicode < 127:
				var ch := char(event.unicode)
				if typing.field == "name":
					ch = ch.to_upper()
				typing.value = (typing.value + ch).left(limit)
	m.get_viewport().set_input_as_handled()
	return true


func _finish_typing(keep: bool) -> void:
	var field: String = typing.field
	var value: String = typing.value.strip_edges()
	typing = {}
	if not keep:
		Sfx.play("menu_back")
		if field == "address":
			m._go(m.Screen.ONLINE)
		return
	Sfx.play("menu_confirm")
	if field == "name":
		Settings.player_name = value if value != "" else "PLAYER"
		Settings.save()
	elif field == "address" and value != "":
		Settings.last_address = value
		Settings.save()
		_connect(value)


# --- Online menu ---------------------------------------------------------------

func menu_input() -> void:
	if not typing.is_empty():
		return
	var n := Controls.menu_nudged()
	if n.y != 0:
		menu_index = posmod(menu_index + n.y, MENU.size())
		Sfx.play("menu_move")
	if m._back_pressed():
		Sfx.play("menu_back")
		m._go(m.Screen.MAIN)
		return
	if m._confirm_device() == -1:
		return
	match MENU[menu_index]:
		"NAME":
			Sfx.play("menu_confirm")
			typing = {"field": "name", "value": Settings.player_name}
		"HOST GAME":
			Sfx.play("menu_confirm")
			host()
		"JOIN GAME":
			Sfx.play("menu_confirm")
			typing = {"field": "address", "value": Settings.last_address}
			m._go(m.Screen.ONLINE_JOIN)
		"PLAYBOUND":
			Online.playbound.sign_in()
			m.toast_msg(Online.last_error if Online.last_error != "" else "PLAYBOUND SIGN-IN COMING SOON")
		"BACK":
			Sfx.play("menu_back")
			m._go(m.Screen.MAIN)


func host() -> void:
	Online.close()
	Online.host(Settings.host_port, net_lag, net_loss)
	_after_connect_attempt()


func _connect(address: String) -> void:
	Online.close()
	Online.join(address, net_lag, net_loss)
	_after_connect_attempt()


func _after_connect_attempt() -> void:
	if Online.current == null:
		m.toast_msg(Online.last_error if Online.last_error != "" else "COULDN'T START ONLINE PLAY")
		m._go(m.Screen.ONLINE)
		return
	lobby_row = 0
	m._go(m.Screen.ONLINE_WAIT)


func join_input() -> void:
	# All handled by text entry; Escape cancels back to the menu.
	pass


# --- Waiting for a connection ------------------------------------------------

func wait_input() -> void:
	var o := om()
	if o == null:
		m._go(m.Screen.ONLINE)
		return
	o.poll({})
	if o.state == OnlineMatch.State.LOBBY:
		Sfx.play("connect")
		m.toast_msg("CONNECTED TO %s" % o.remote_name)
		_enter_lobby()
	elif o.state == OnlineMatch.State.FAILED:
		_fail(o.failure)
	elif m._back_pressed():
		Sfx.play("menu_back")
		Online.close()
		m._go(m.Screen.ONLINE)


func _enter_lobby() -> void:
	var o := om()
	lobby_row = 0
	announced_rematch = false
	if bot:
		o.set_pick(m.pick[o.local_side], false)
	else:
		o.set_pick(o.local_pick, false)
	m._go(m.Screen.ONLINE_LOBBY)


func _fail(reason: String) -> void:
	Sfx.play("disconnect")
	m.toast_msg(reason)
	Online.close()
	if bot:
		print("ONLINE_FAILED %s" % reason)
		m.get_tree().quit(1)
	m._go(m.Screen.ONLINE)


# --- Lobby -----------------------------------------------------------------------

func lobby_input() -> void:
	var o := om()
	if o == null:
		m._go(m.Screen.ONLINE)
		return
	o.poll({})
	if o.state == OnlineMatch.State.FAILED:
		_fail(o.failure)
		return
	if o.state == OnlineMatch.State.PLAYING:
		_start_online_match()
		return
	if bot:
		_bot_lobby(o)
		return
	var n := Controls.menu_nudged()
	if lobby_row == 0:
		if not o.local_locked and n != Vector2i.ZERO:
			o.set_pick(m._grid_move(o.local_pick, n), false)
			Sfx.play("menu_move")
		if m._confirm_device() != -1 and not o.local_locked:
			o.set_pick(o.local_pick, true)
			Sfx.play("menu_confirm")
			if o.is_host:
				lobby_row = 1
		elif m._back_pressed():
			if o.local_locked:
				o.set_pick(o.local_pick, false)
				Sfx.play("menu_back")
			else:
				Sfx.play("menu_back")
				Online.close()
				m._go(m.Screen.ONLINE)
	else:
		if n.x != 0:
			o.set_court(posmod(o.court + n.x, m.balance.courts.size()))
			Sfx.play("menu_move")
		if m._confirm_device() != -1:
			if o.can_start():
				Sfx.play("menu_confirm")
				o.start()
			else:
				m.toast_msg("WAITING FOR %s TO PICK" % o.remote_name)
		elif m._back_pressed():
			lobby_row = 0
			o.set_pick(o.local_pick, false)
			Sfx.play("menu_back")


func _bot_lobby(o: OnlineMatch) -> void:
	if m.screen_ticks == 30:
		o.set_court(bot_court)
		o.set_pick(m.pick[o.local_side], true)
	if m.screen_ticks > 60 and o.can_start():
		o.start()


# --- Online match ---------------------------------------------------------------

func _start_online_match() -> void:
	var o := om()
	m.sim = o.sim
	m.court = o.court
	var ids := _ids(o)
	var names: Array[String] = [o.local_name if o.is_host else o.remote_name,
		o.remote_name if o.is_host else o.local_name]
	m.view = MatchView.new(o.sim, ids, names)
	m.stats.assign([{}, {}])
	m.last_second = -1
	m.online = true
	m.pick.assign([_index_of(o.sim.players[0].character), _index_of(o.sim.players[1].character)])
	leave_menu = false
	vs_ticks = 0
	bot_cpu = CpuPlayer.new(o.local_side, m.balance.cpu.hard, int(Time.get_ticks_usec())) if bot else null
	Online.service.set_presence("in_match")
	m._go(m.Screen.VS)


func _ids(o: OnlineMatch) -> Array:
	return [str(o.sim.players[0].character.id), str(o.sim.players[1].character.id)]


func _index_of(character: Dictionary) -> int:
	for i in m.balance.characters.size():
		if m.balance.characters[i].id == character.id:
			return i
	return 0


## The VS splash in an online match keeps the connection and sim running
## (the opening READY covers it) so both players stay in step.
func vs_tick() -> void:
	vs_ticks += 1
	_step(true)
	if vs_ticks > 100:
		m._go(m.Screen.MATCH)


func match_tick() -> void:
	var o := om()
	if o == null:
		m._go(m.Screen.ONLINE)
		return
	if leave_menu:
		_leave_menu_input()
	elif Controls.pressed(0, "start"):
		leave_menu = true
		leave_index = 0
		Sfx.play("pause")
	_step(leave_menu)
	if o.state == OnlineMatch.State.FAILED:
		_fail(o.failure)
		return
	if o.session != null and o.session.desynced and m.toast_ticks <= 0:
		m.toast_msg("DESYNC DETECTED AT FRAME %d" % o.session.desync_frame)
	if o.match_settled() and o.sim.phase_ticks > 150:
		if bot:
			_bot_report(o)
		m.result_index = 0
		Sfx.play("menu_confirm")
		Online.service.set_presence("online")
		m._go(m.Screen.RESULTS)


## One online tick: send our input, maybe roll back, step, show events.
func _step(idle: bool) -> void:
	var o := om()
	if o == null:
		return
	var input: Dictionary = {}
	if bot and bot_cpu != null and o.sim != null:
		input = bot_cpu.think(o.sim)
	elif not idle:
		input = Controls.input(0)
	var events := o.poll(input)
	if bot and o.session != null and o.session.frame % 1200 == 1:
		print("ONLINE_PROGRESS frame=%d score=%s sets=%s rollbacks=%d desync=%s" % [o.session.frame,
			o.sim.scores, o.sim.sets_won, o.session.stats.rollbacks, o.session.desynced])
	for e in events:
		m.view.handle(e)
		m._sound_for(e)
		m._count(e)
	if m.view != null:
		m.view.tick()
	m._countdown_beeps()


func _leave_menu_input() -> void:
	var n := Controls.nudged(0)
	if n.y != 0:
		leave_index = posmod(leave_index + n.y, 2)
		Sfx.play("menu_move")
	if Controls.pressed(0, "start") or Controls.pressed(0, "b"):
		leave_menu = false
		Sfx.play("menu_back")
	elif Controls.pressed(0, "a"):
		if leave_index == 0:
			leave_menu = false
			Sfx.play("menu_confirm")
		else:
			Sfx.play("menu_back")
			Online.close()
			m.online = false
			m._go(m.Screen.ONLINE)


func results_input() -> void:
	var o := om()
	if o != null:
		o.poll({})
		if o.state == OnlineMatch.State.FAILED:
			_fail(o.failure)
			return
		if o.state == OnlineMatch.State.LOBBY:
			# The opponent asked for a rematch.
			m.toast_msg("%s WANTS A REMATCH" % o.remote_name)
			_enter_lobby()
			return
	var n := Controls.menu_nudged()
	if n.y != 0:
		m.result_index = posmod(m.result_index + n.y, ONLINE_RESULTS.size())
		Sfx.play("menu_move")
	if m.screen_ticks < 40 or m._confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	if ONLINE_RESULTS[m.result_index] == "REMATCH" and o != null:
		o.request_rematch()
		_enter_lobby()
	else:
		Online.close()
		m.online = false
		m._go(m.Screen.ONLINE)


func _bot_report(o: OnlineMatch) -> void:
	var s := o.session
	print("ONLINE_RESULT side=%d winner=%d sets=%s desync=%s frames=%d stats=%s checksums=%d" % [
		o.local_side, o.sim.winner, o.sim.sets_won, s.desynced, s.frame, s.stats, s._local_checksums.size()])
	if quit_after_match:
		Online.close()
		m.get_tree().quit(1 if s.desynced else 0)


# --- Drawing ---------------------------------------------------------------------

func draw_menu() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.4)
	UI.text(ci, Vector2(960, 130), "ONLINE", 110, UI.YELLOW, UI.display, 9, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(ci, Vector2(960, 190), "PLAYING AS  %s   -   %s" % [Settings.player_name, Online.service.service_name().to_upper()],
		28, UI.CYAN, UI.ui, 4)
	for i in MENU.size():
		var label: String = MENU[i]
		var enabled := true
		if label == "NAME":
			label = "NAME:  " + (typing.value + ("_" if (m.frame / 20) % 2 == 0 else " ")
				if typing.get("field", "") == "name" else Settings.player_name)
		elif label == "PLAYBOUND":
			label = "PLAYBOUND SIGN-IN  (SOON)"
			enabled = Online.playbound.is_available()
		UI.button(ci, Rect2(Vector2(560, 260 + i * 100), Vector2(800, 80)), label, i == menu_index, m.frame, 36, enabled)
	if typing.get("field", "") == "name":
		m._hint("TYPE YOUR NAME, ENTER TO SAVE, ESC TO CANCEL")
	else:
		m._hint("%s SELECT     %s BACK     FRIENDS AND INVITES ARRIVE WITH PLAYBOUND ACCOUNTS" % [m._a(), m._b()])


func draw_join() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	UI.text(ci, Vector2(960, 240), "JOIN GAME", 100, UI.YELLOW, UI.display, 8, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(ci, Vector2(960, 360), "TYPE THE HOST'S ADDRESS", 36, Color.WHITE, UI.ui, 4)
	var field := Rect2(Vector2(460, 420), Vector2(1000, 110))
	UI.slant_panel(ci, field, Color("120826"), UI.CYAN, 24, 5)
	var value: String = typing.get("value", "")
	UI.text(ci, Vector2(960, 495), value + ("_" if (m.frame / 20) % 2 == 0 else " "), 56, UI.YELLOW, UI.ui, 5)
	UI.text(ci, Vector2(960, 620), "FOR EXAMPLE  192.168.1.20   OR   203.0.113.5:7777", 28, UI.DIM, UI.ui, 3)
	UI.text(ci, Vector2(960, 670), "CTRL+V PASTES", 26, UI.DIM, UI.ui, 3)
	m._hint("ENTER TO CONNECT     ESC TO GO BACK")


func draw_wait() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	var o := om()
	var hosting: bool = o != null and o.is_host
	var dots := ".".repeat(1 + (m.frame / 20) % 3)
	UI.text(ci, Vector2(960, 300), ("WAITING FOR A PLAYER" if hosting else "CONNECTING") + dots, 80, UI.YELLOW,
		UI.display, 7, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	if hosting:
		var addrs := UdpTransport.local_addresses()
		UI.text(ci, Vector2(960, 420), "TELL YOUR FRIEND TO JOIN:", 34, Color.WHITE, UI.ui, 4)
		var y := 490
		for a in addrs.slice(0, 3):
			UI.text(ci, Vector2(960, y), "%s:%d" % [a, Settings.host_port], 52, UI.CYAN, UI.ui, 5)
			y += 64
		UI.text(ci, Vector2(960, y + 40),
			"SAME NETWORK: USE THE ADDRESS ABOVE.  OVER THE INTERNET: FORWARD UDP PORT %d" % Settings.host_port,
			24, UI.DIM, UI.ui, 3)
		UI.text(ci, Vector2(960, y + 76), "ON YOUR ROUTER AND SHARE YOUR PUBLIC IP (PLAYBOUND WILL DO THIS FOR YOU LATER)",
			24, UI.DIM, UI.ui, 3)
	elif o != null:
		UI.text(ci, Vector2(960, 440), o.transport.describe(), 44, UI.CYAN, UI.ui, 4)
	m._hint("%s CANCEL" % m._b())


func draw_lobby() -> void:
	var ci = m
	var o := om()
	if o == null:
		return
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	UI.slant_panel(ci, Rect2(560, 26, 800, 90), UI.YELLOW, UI.INK, 30, 5)
	UI.text(ci, Vector2(960, 98), "ONLINE LOBBY", 64, UI.INK, UI.display, 2)
	var chars: Array = m.balance.characters
	var cell := Vector2(210, 210)
	var grid_origin := Vector2(960 - cell.x * 1.5 - 10, 230)
	var picks := {o.local_side: o.local_pick, 1 - o.local_side: o.remote_pick}
	for i in chars.size():
		var pos := grid_origin + Vector2((i % 3) * (cell.x + 10), (i / 3) * (cell.y + 10))
		var r := Rect2(pos, cell)
		ci.draw_rect(r.grow(4), UI.INK)
		ci.draw_rect(r, Color("2a1250"))
		ci.draw_texture_rect_region(m.portraits[i], r, Rect2(100, 40, 440, 440))
		for side in [0, 1]:
			if picks[side] != i:
				continue
			var c := UI.P1 if side == 0 else UI.P2
			ci.draw_rect(r.grow(4 + side * 6), c, false, 7)
		UI.text(ci, pos + Vector2(cell.x / 2, cell.y - 12), str(chars[i].name).to_upper(), 22, Color.WHITE, UI.ui, 4)
	for side in [0, 1]:
		var who: int = picks[side]
		if who < 0:
			continue
		var saved: int = m.pick[side]
		m.pick[side] = who
		m._draw_fighter_card(side, chars[who])
		m.pick[side] = saved
		var name: String = o.local_name if side == o.local_side else o.remote_name
		var locked: bool = o.local_locked if side == o.local_side else o.remote_locked
		var x := 240.0 if side == 0 else 1680.0
		UI.text(ci, Vector2(x, 200), name, 44, UI.P1 if side == 0 else UI.P2, UI.display, 5)
		if locked:
			UI.text(ci, Vector2(x, 790), "READY!", 56, UI.YELLOW, UI.display, 6)
	var court_name: String = m.balance.courts[o.court].name
	var r := Rect2(Vector2(660, 700), Vector2(600, 84))
	var court_label := ("<  COURT: %s  >" % court_name) if o.is_host else "COURT: %s" % court_name
	UI.button(ci, r, court_label, o.is_host and lobby_row == 1, m.frame, 34)
	var hint := ""
	if o.is_host:
		if lobby_row == 0:
			hint = "PICK YOUR PLAYER, %s TO LOCK IN" % m._a()
		else:
			hint = ("%s START MATCH" % m._a()) if o.can_start() else "WAITING FOR %s TO LOCK IN" % o.remote_name
		hint += "     %s BACK" % m._b()
	else:
		hint = "PICK YOUR PLAYER, %s TO LOCK IN     THE HOST PICKS THE COURT AND STARTS     %s BACK" % [m._a(), m._b()]
	m._hint(hint)


func draw_leave_menu() -> void:
	var ci = m
	ci.draw_rect(Rect2(Vector2(560, 330), Vector2(800, 380)), Color(0.03, 0.0, 0.1, 0.85))
	UI.text(ci, Vector2(960, 420), "ONLINE MATCH", 64, UI.YELLOW, UI.display, 6)
	UI.text(ci, Vector2(960, 470), "THE GAME KEEPS RUNNING", 26, UI.DIM, UI.ui, 3)
	var items := ["RESUME", "LEAVE MATCH"]
	for i in 2:
		UI.button(ci, Rect2(Vector2(710, 510 + i * 90), Vector2(500, 72)), items[i], i == leave_index, m.frame, 32)


func draw_results_menu() -> void:
	var ci = m
	if m.screen_ticks <= 40:
		return
	for i in ONLINE_RESULTS.size():
		UI.button(ci, Rect2(Vector2(760, 660 + i * 84), Vector2(400, 68)), ONLINE_RESULTS[i],
			i == m.result_index, m.frame, 28)
