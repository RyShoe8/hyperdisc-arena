## The online screens: the online menu, PlayBound sign-in, friends and
## invites, hosting / joining rooms (PlayBound Connect) or LAN addresses,
## the lobby where both players pick, and the online match loop. main.gd
## hands control here for these screens.
extends RefCounted

const MatchSim := preload("res://scripts/sim/match_sim.gd")
const CpuPlayer := preload("res://scripts/sim/cpu_player.gd")
const MatchView := preload("res://scripts/game/view/match_view.gd")
const OnlineMatch := preload("res://scripts/net/online_match.gd")
const UdpTransport := preload("res://scripts/net/udp_transport.gd")
const UI := preload("res://scripts/game/ui/theme.gd")

const ONLINE_RESULTS := ["REMATCH", "LEAVE"]

var m  # main.gd
var menu_index := 0
var typing := {}        # {field, value} while a text field is being edited
var lobby_row := 0      # 0 character grid, 1 court (host, once locked)
var leave_menu := false
var leave_index := 0
var vs_ticks := 0
var announced_rematch := false
var friends_index := 0
## True while waiting on PlayBound (creating or joining a room, inviting).
var busy := false

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

## Keyboard text entry for the name, address and room-code fields. Returns
## true if the event was used.
func handle_text(event: InputEvent) -> bool:
	if typing.is_empty() or not (event is InputEventKey) or not event.pressed:
		return false
	var limit: int = {"name": 16, "room": 8}.get(typing.field, 64)
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER:
			_finish_typing(true)
		KEY_ESCAPE:
			_finish_typing(false)
		KEY_BACKSPACE:
			typing.value = typing.value.left(maxi(typing.value.length() - 1, 0))
		_:
			if event.ctrl_pressed and event.keycode == KEY_V:
				typing.value = _clean(typing.field, typing.value + DisplayServer.clipboard_get().strip_edges()).left(limit)
			elif event.unicode >= 32 and event.unicode < 127:
				typing.value = _clean(typing.field, typing.value + char(event.unicode)).left(limit)
	m.get_viewport().set_input_as_handled()
	return true


func _clean(field: String, value: String) -> String:
	if field == "name":
		return value.to_upper()
	if field == "room":
		var out := ""
		for ch in value.to_upper():
			if (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
				out += ch
		return out
	return value


func _finish_typing(keep: bool) -> void:
	var field: String = typing.field
	var value: String = typing.value.strip_edges()
	typing = {}
	if not keep:
		Sfx.play("menu_back")
		if field == "address" or field == "room":
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
	elif field == "room" and value != "":
		join_room(value)


# --- Online menu ---------------------------------------------------------------

## The menu rows for the current state: [id, label, enabled].
func menu_items() -> Array:
	var items := []
	if Online.signed_in():
		var online_count := 0
		for f in Online.playbound.friends():
			if f.online:
				online_count += 1
		items.append(["friends", "FRIENDS  (%d ONLINE)" % online_count, true])
	else:
		items.append(["sign_in", "SIGN IN WITH PLAYBOUND", true])
	items.append(["host_room", "HOST ROOM", true])
	items.append(["join_room", "JOIN ROOM", true])
	items.append(["host_lan", "HOST ON LAN", true])
	items.append(["join_ip", "JOIN BY ADDRESS", true])
	if Online.signed_in():
		items.append(["sign_out", "SIGN OUT", true])
	else:
		items.append(["name", "NAME:  " + Settings.player_name, true])
	items.append(["back", "BACK", true])
	return items


func menu_input() -> void:
	if not typing.is_empty() or busy:
		return
	var items := menu_items()
	menu_index = clampi(menu_index, 0, items.size() - 1)
	var n := Controls.menu_nudged()
	if n.y != 0:
		menu_index = posmod(menu_index + n.y, items.size())
		Sfx.play("menu_move")
	if m._back_pressed():
		Sfx.play("menu_back")
		m._go(m.Screen.MAIN)
		return
	if m._confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match items[menu_index][0]:
		"sign_in":
			sign_in()
		"friends":
			friends_index = 0
			Online.playbound.refresh_friends_now()
			m._go(m.Screen.ONLINE_FRIENDS)
		"host_room":
			host_room()
		"join_room":
			typing = {"field": "room", "value": ""}
			m._go(m.Screen.ONLINE_ROOM)
		"host_lan":
			host()
		"join_ip":
			typing = {"field": "address", "value": Settings.last_address}
			m._go(m.Screen.ONLINE_JOIN)
		"sign_out":
			Online.playbound.sign_out()
			m.toast_msg("SIGNED OUT OF PLAYBOUND")
			menu_index = 0
		"name":
			typing = {"field": "name", "value": Settings.player_name}
		"back":
			m._go(m.Screen.MAIN)


func host() -> void:
	Online.close()
	Online.host(Settings.host_port, net_lag, net_loss)
	_after_connect_attempt()


func _connect(address: String) -> void:
	Online.close()
	Online.join(address, net_lag, net_loss)
	_after_connect_attempt()


## Hosts a PlayBound Connect room: works across the internet, no ports.
func host_room() -> void:
	Online.close()
	busy = true
	await Online.host_room()
	busy = false
	_after_connect_attempt()


func join_room(code: String) -> void:
	Online.close()
	busy = true
	m._go(m.Screen.ONLINE_WAIT)
	await Online.join_room(code)
	busy = false
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


# --- PlayBound sign-in -----------------------------------------------------------

func sign_in() -> void:
	Online.last_error = ""
	Online.playbound.sign_in()
	m._go(m.Screen.ONLINE_SIGNIN)


func signin_input() -> void:
	var pb = Online.playbound
	if pb.is_signed_in():
		Sfx.play("connect")
		m.toast_msg("SIGNED IN AS %s" % pb.profile().display_name)
		menu_index = 0
		m._go(m.Screen.ONLINE)
		return
	if not pb.signing_in() and m.screen_ticks > 30:
		# Failed, expired or turned down; the reason is in last_error.
		m.toast_msg(Online.last_error if Online.last_error != "" else "SIGN-IN CANCELLED")
		m._go(m.Screen.ONLINE)
		return
	if m._back_pressed():
		Sfx.play("menu_back")
		pb.cancel_sign_in()
		m._go(m.Screen.ONLINE)
	elif m._confirm_device() != -1 and pb.signing_in():
		OS.shell_open(str(pb.link_info().get("url", "")))  # reopen the page


# --- Friends and invites -----------------------------------------------------------

func friends_input() -> void:
	if busy:
		return
	var list: Array[Dictionary] = Online.playbound.friends()
	var n := Controls.menu_nudged()
	if n.y != 0 and not list.is_empty():
		friends_index = posmod(friends_index + n.y, list.size())
		Sfx.play("menu_move")
	if m._back_pressed():
		Sfx.play("menu_back")
		# Back from inviting while hosting returns to the room.
		m._go(m.Screen.ONLINE_WAIT if Online.current != null else m.Screen.ONLINE)
		return
	if m._confirm_device() != -1 and not list.is_empty():
		var friend: Dictionary = list[clampi(friends_index, 0, list.size() - 1)]
		Sfx.play("menu_confirm")
		invite(friend)


## Invites a friend into our room, opening one first if we aren't hosting.
func invite(friend: Dictionary) -> void:
	if Online.current == null or Online.room_code == "" or not Online.current.is_host:
		busy = true
		Online.close()
		await Online.host_room()
		busy = false
		if Online.current == null:
			m.toast_msg(Online.last_error if Online.last_error != "" else "COULDN'T CREATE A ROOM")
			return
	Online.last_error = ""
	busy = true
	await Online.playbound.send_invite(str(friend.id), Online.room_code)
	busy = false
	if Online.last_error != "":
		m.toast_msg(Online.last_error)
	else:
		m.toast_msg("INVITED %s - WAITING FOR THEM TO JOIN" % friend.display_name)
	lobby_row = 0
	m._go(m.Screen.ONLINE_WAIT)


## An invite pop-up shows over any menu (never mid-match).
func invite_modal_active() -> bool:
	if Online.pending_invite.is_empty() or bot:
		return false
	return m.screen not in [m.Screen.MATCH, m.Screen.VS, m.Screen.PAUSED, m.Screen.ONLINE_LOBBY] \
		and not (m.screen == m.Screen.RESULTS and m.online)


func invite_input() -> void:
	var inv: Dictionary = Online.pending_invite
	if m._confirm_device() != -1:
		Online.pending_invite = {}
		Sfx.play("menu_confirm")
		Online.playbound.respond_to_invite(str(inv.id), true)
		m.online = false
		join_room(str(inv.connect_code))
	elif m._back_pressed():
		Online.pending_invite = {}
		Sfx.play("menu_back")
		Online.playbound.respond_to_invite(str(inv.id), false)


# --- Waiting for a connection ------------------------------------------------

func wait_input() -> void:
	var o := om()
	if o == null:
		if not busy:
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
	elif o.is_host and Online.room_code != "" and Online.signed_in() and Controls.menu_pressed("slap") != -1:
		friends_index = 0
		Online.playbound.refresh_friends_now()
		m._go(m.Screen.ONLINE_FRIENDS)


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
	Online.playbound.set_presence("in_match")
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
	if o.match_settled() and (o.sim.phase_ticks > 150 or o.opponent_left):
		if bot:
			_bot_report(o)
		m.result_index = 0
		Sfx.play("menu_confirm")
		Online.playbound.set_presence("online")
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
	if ONLINE_RESULTS[m.result_index] == "REMATCH" and o != null and o.opponent_left:
		m.toast_msg("%s HAS LEFT" % o.remote_name)
		Online.close()
		m.online = false
		m._go(m.Screen.ONLINE)
	elif ONLINE_RESULTS[m.result_index] == "REMATCH" and o != null:
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
	UI.text(ci, Vector2(960, 120), "ONLINE", 110, UI.YELLOW, UI.display, 9, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	var who := ("SIGNED IN TO PLAYBOUND AS  %s" % Online.display_name()) if Online.signed_in() \
		else "PLAYING AS  %s   -   NOT SIGNED IN" % Settings.player_name
	UI.text(ci, Vector2(960, 180), who, 28, UI.CYAN, UI.ui, 4)
	var items := menu_items()
	for i in items.size():
		var label: String = items[i][1]
		if items[i][0] == "name" and typing.get("field", "") == "name":
			label = "NAME:  " + typing.value + ("_" if (m.frame / 20) % 2 == 0 else " ")
		UI.button(ci, Rect2(Vector2(560, 230 + i * 96), Vector2(800, 78)), label, i == menu_index, m.frame, 34, items[i][2])
	if busy:
		UI.text(ci, Vector2(960, 1000), "TALKING TO PLAYBOUND" + ".".repeat(1 + (m.frame / 20) % 3), 30, UI.YELLOW, UI.ui, 4)
	if typing.get("field", "") == "name":
		m._hint("TYPE YOUR NAME, ENTER TO SAVE, ESC TO CANCEL")
	else:
		var id: String = items[clampi(menu_index, 0, items.size() - 1)][0]
		var about: String = {
			"sign_in": "USE YOUR PLAYBOUND ACCOUNT (OR MAKE ONE) FOR FRIENDS AND INVITES",
			"friends": "SEE WHO'S ONLINE AND INVITE THEM TO PLAY",
			"host_room": "GET A ROOM CODE TO SHARE - WORKS OVER THE INTERNET, NO SETUP",
			"join_room": "TYPE A FRIEND'S ROOM CODE",
			"host_lan": "PLAY SOMEONE ON THE SAME NETWORK",
			"join_ip": "CONNECT STRAIGHT TO AN ADDRESS",
		}.get(id, "")
		m._hint("%s SELECT     %s BACK%s" % [m._a(), m._b(), ("     " + about) if about != "" else ""])


func draw_join() -> void:
	var ci = m
	var room: bool = typing.get("field", "") == "room" or m.screen == m.Screen.ONLINE_ROOM
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	UI.text(ci, Vector2(960, 240), "JOIN ROOM" if room else "JOIN BY ADDRESS", 100, UI.YELLOW, UI.display, 8,
		HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	UI.text(ci, Vector2(960, 360), "TYPE THE ROOM CODE" if room else "TYPE THE HOST'S ADDRESS", 36, Color.WHITE, UI.ui, 4)
	var field := Rect2(Vector2(460, 420), Vector2(1000, 110))
	UI.slant_panel(ci, field, Color("120826"), UI.CYAN, 24, 5)
	var value: String = typing.get("value", "")
	var caret := "_" if (m.frame / 20) % 2 == 0 and not typing.is_empty() else " "
	UI.text(ci, Vector2(960, 495), value + caret, 64 if room else 56, UI.YELLOW, UI.ui, 5)
	if room:
		UI.text(ci, Vector2(960, 620), "THE HOST SEES IT ON THEIR SCREEN.  CTRL+V PASTES", 28, UI.DIM, UI.ui, 3)
	else:
		UI.text(ci, Vector2(960, 620), "FOR EXAMPLE  192.168.1.20   OR   203.0.113.5:7777", 28, UI.DIM, UI.ui, 3)
		UI.text(ci, Vector2(960, 670), "CTRL+V PASTES", 26, UI.DIM, UI.ui, 3)
	m._hint("ENTER TO CONNECT     ESC TO GO BACK")


func draw_wait() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	var o := om()
	var hosting: bool = o != null and o.is_host
	var dots := ".".repeat(1 + (m.frame / 20) % 3)
	UI.text(ci, Vector2(960, 260), ("WAITING FOR A PLAYER" if hosting else "CONNECTING") + dots, 80, UI.YELLOW,
		UI.display, 7, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	if hosting and Online.room_code != "":
		UI.text(ci, Vector2(960, 390), "YOUR ROOM CODE", 34, Color.WHITE, UI.ui, 4)
		var box := Rect2(Vector2(610, 420), Vector2(700, 150))
		UI.slant_panel(ci, box, Color("120826"), UI.CYAN, 28, 6)
		UI.text(ci, Vector2(960, 528), Online.room_code, 104, UI.YELLOW, UI.display, 8)
		UI.text(ci, Vector2(960, 640), "YOUR FRIEND PICKS ONLINE > JOIN ROOM AND TYPES THIS CODE", 28, UI.DIM, UI.ui, 3)
		if Online.signed_in():
			UI.text(ci, Vector2(960, 700), "OR PRESS %s TO INVITE A PLAYBOUND FRIEND" % Controls.label(0, "slap"),
				32, UI.CYAN, UI.ui, 4)
	elif hosting:
		var addrs := UdpTransport.local_addresses()
		UI.text(ci, Vector2(960, 420), "TELL YOUR FRIEND TO JOIN:", 34, Color.WHITE, UI.ui, 4)
		var y := 490
		for a in addrs.slice(0, 3):
			UI.text(ci, Vector2(960, y), "%s:%d" % [a, Settings.host_port], 52, UI.CYAN, UI.ui, 5)
			y += 64
		UI.text(ci, Vector2(960, y + 40),
			"SAME NETWORK: USE THE ADDRESS ABOVE.  OVER THE INTERNET, HOST A ROOM INSTEAD - NO ROUTER SETUP",
			24, UI.DIM, UI.ui, 3)
	elif o != null:
		UI.text(ci, Vector2(960, 440), o.transport.describe(), 44, UI.CYAN, UI.ui, 4)
	elif busy:
		UI.text(ci, Vector2(960, 440), "FINDING THE ROOM", 44, UI.CYAN, UI.ui, 4)
	m._hint("%s CANCEL" % m._b())


func draw_signin() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.55)
	UI.text(ci, Vector2(960, 200), "SIGN IN WITH PLAYBOUND", 84, UI.YELLOW, UI.display, 7,
		HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	var info: Dictionary = Online.playbound.link_info()
	if info.is_empty():
		UI.text(ci, Vector2(960, 480), "GETTING A CODE" + ".".repeat(1 + (m.frame / 20) % 3), 44, UI.CYAN, UI.ui, 4)
		m._hint("%s CANCEL" % m._b())
		return
	var url: String = str(info.url).get_slice("?", 0).trim_prefix("https://")
	UI.text(ci, Vector2(960, 320), "YOUR BROWSER HAS OPENED  %s" % url.to_upper(), 34, Color.WHITE, UI.ui, 4)
	UI.text(ci, Vector2(960, 370), "SIGN IN OR CREATE AN ACCOUNT THERE, THEN CHECK THIS CODE MATCHES:", 30, UI.DIM, UI.ui, 3)
	var box := Rect2(Vector2(560, 410), Vector2(800, 170))
	UI.slant_panel(ci, box, Color("120826"), UI.CYAN, 30, 6)
	UI.text(ci, Vector2(960, 530), str(info.code), 110, UI.YELLOW, UI.display, 8)
	var left := maxi(0, int(info.expires_ms) - Time.get_ticks_msec()) / 1000
	UI.text(ci, Vector2(960, 660), "WAITING FOR YOU TO APPROVE" + ".".repeat(1 + (m.frame / 20) % 3), 36, UI.CYAN, UI.ui, 4)
	UI.text(ci, Vector2(960, 715), "CODE EXPIRES IN %d:%02d" % [left / 60, left % 60], 26, UI.DIM, UI.ui, 3)
	m._hint("%s REOPEN THE PAGE     %s CANCEL" % [m._a(), m._b()])


func draw_friends() -> void:
	var ci = m
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.5)
	UI.text(ci, Vector2(960, 130), "FRIENDS", 100, UI.YELLOW, UI.display, 8, HORIZONTAL_ALIGNMENT_CENTER, -1.0, true)
	var list: Array[Dictionary] = Online.playbound.friends()
	if list.is_empty():
		UI.text(ci, Vector2(960, 440), "NO FRIENDS YET", 48, Color.WHITE, UI.display, 5)
		UI.text(ci, Vector2(960, 510), "ADD FRIENDS ON PLAYBOUND.CLUB AND THEY'LL SHOW UP HERE", 30, UI.DIM, UI.ui, 3)
		m._hint("%s BACK" % m._b())
		return
	const ROWS := 7
	var first := clampi(friends_index - ROWS / 2, 0, maxi(0, list.size() - ROWS))
	for row in mini(ROWS, list.size() - first):
		var i := first + row
		var f: Dictionary = list[i]
		var r := Rect2(Vector2(460, 210 + row * 104), Vector2(1000, 86))
		UI.button(ci, r, "", i == friends_index, m.frame, 34)
		var dot := UI.YELLOW if f.in_game else (Color("39ff88") if f.online else UI.DIM)
		ci.draw_circle(r.position + Vector2(56, 43), 13, dot)
		UI.text(ci, r.position + Vector2(100, 58), f.display_name, 38, Color.WHITE, UI.display, 4, HORIZONTAL_ALIGNMENT_LEFT)
		var status := "IN HYPERDISC" if f.in_game else ("ONLINE" if f.online else "OFFLINE")
		UI.text(ci, r.position + Vector2(960, 56), status, 26, dot, UI.ui, 3, HORIZONTAL_ALIGNMENT_RIGHT)
	if list.size() > ROWS:
		UI.text(ci, Vector2(960, 950), "%d / %d" % [friends_index + 1, list.size()], 24, UI.DIM, UI.ui, 3)
	if busy:
		UI.text(ci, Vector2(960, 1000), "SENDING INVITE" + ".".repeat(1 + (m.frame / 20) % 3), 30, UI.YELLOW, UI.ui, 4)
	m._hint("%s INVITE TO PLAY     %s BACK" % [m._a(), m._b()])


func draw_invite() -> void:
	var ci = m
	var inv: Dictionary = Online.pending_invite
	ci.draw_rect(Rect2(Vector2.ZERO, m.SCREEN), Color(0.03, 0.0, 0.1, 0.75))
	var panel := Rect2(Vector2(460, 350), Vector2(1000, 340))
	UI.slant_panel(ci, panel, Color("1a0b38"), UI.YELLOW, 34, 6)
	UI.text(ci, Vector2(960, 440), "MATCH INVITE", 72, UI.YELLOW, UI.display, 7)
	UI.text(ci, Vector2(960, 530), "%s WANTS TO PLAY" % inv.get("from_name", "A FRIEND"), 44, Color.WHITE, UI.display, 5)
	UI.text(ci, Vector2(960, 620), "%s JOIN     %s NOT NOW" % [m._a(), m._b()], 36, UI.CYAN, UI.ui, 4)


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
