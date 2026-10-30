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

const ONLINE_RESULTS := ["DUB TAPES", "REMATCH", "LEAVE"]
const LanDiscovery := preload("res://scripts/net/lan_discovery.gd")
## The multiplayer menu: [id, label, what it does].
const MENU := [
	["online", "ONLINE", "PLAY ANYONE OVER THE INTERNET: CREATE OR JOIN A ROOM"],
	["lan", "LAN", "PLAY SOMEONE ON THE SAME NETWORK: CREATE OR JOIN A ROOM"],
	["add_friend", "ADD FRIEND", "ADD PLAYBOUND FRIENDS SO YOU CAN INVITE THEM TO YOUR ROOM"],
]

var m  # main.gd
var menu_index := 0
var typing := {}        # {field, value} while a text field is being edited
var partner_cpu: CpuPlayer
var lobby_row := 0      # cursor in the room setup's editable rows
## Where to go once PlayBound sign-in finishes: "browse" or "add_friend".
var after_sign_in := ""
## LAN: finds rooms while browsing; answers for our room while hosting.
var lan_find := LanDiscovery.new()
var lan_ad := LanDiscovery.new()
var lan_index := 0
var friend_index := 0
var friend_sent := {}  # user id -> true once a request went out
var leave_menu := false
var leave_index := 0
var vs_ticks := 0
var announced_rematch := false
var friends_index := 0
var browser_index := 0
var player_page := 0
var browser_rows: Array = []
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
	var limit: int = {"name": 16, "room": 8, "search": 24}.get(typing.field, 64)
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
	if keep and value.is_empty() and field in ["address", "room"]:
		return
	typing = {}
	if not keep:
		Sfx.play("menu_back")
		if field == "address":
			open_lan()
		elif field == "room":
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
	elif field == "search":
		friend_index = 0
		Online.playbound.search_players(value)


# --- Online menu ---------------------------------------------------------------

## The multiplayer menu rows.
func menu_items() -> Array:
	return MENU


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
	if Online.signed_in() and Controls.menu_pressed("utility") != -1:
		Online.playbound.sign_out()
		m.toast_msg("SIGNED OUT OF PLAYBOUND")
		return
	if m._confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match items[menu_index][0]:
		"online":
			if Online.signed_in():
				open_browser()
			else:
				sign_in("browse")
		"lan":
			open_lan()
		"add_friend":
			if Online.signed_in():
				open_add_friend()
			else:
				sign_in("add_friend")


## The PlayBound room lobby (online play).
func open_browser() -> void:
	browser_index = 0
	Online.playbound.lobby_visible = true
	Online.playbound.refresh_lobby_now()
	m._go(m.Screen.ONLINE_ROOM)


func host() -> void:
	Online.close()
	lan_find.stop()
	Online.host(Settings.host_port, net_lag, net_loss)
	if Online.current != null:
		lan_ad.advertise(Online.display_name(), Settings.host_port, str(OnlineMatch.build_hash()))
	_after_connect_attempt()


## Keeps our LAN room discoverable while it is open (hosting, before play).
func _advertise_tick() -> void:
	var o := om()
	if o == null or not o.is_host or Online.room_code != "":
		lan_ad.stop()
		return
	if lan_ad.active():
		lan_ad.set_players(1 if o.state == OnlineMatch.State.CONNECTING else 2)
		lan_ad.poll()


func _connect(address: String) -> void:
	Online.close()
	Online.join(address, net_lag, net_loss)
	_after_connect_attempt()


## Hosts a PlayBound Connect room: works across the internet, no ports.
func host_room() -> void:
	Online.close()
	busy = true
	m._go(m.Screen.ONLINE_WAIT)
	await Online.host_room()
	busy = false
	if m.screen != m.Screen.ONLINE_WAIT:
		Online.close()
		return
	_after_connect_attempt()


func join_room(code: String) -> void:
	Online.close()
	busy = true
	m._go(m.Screen.ONLINE_WAIT)
	await Online.join_room(code)
	busy = false
	if m.screen != m.Screen.ONLINE_WAIT:
		Online.close()
		return
	_after_connect_attempt()


func _after_connect_attempt() -> void:
	if Online.current == null:
		m.toast_msg(Online.last_error if Online.last_error != "" else "COULDN'T START ONLINE PLAY")
		m._go(m.Screen.ONLINE)
		return
	lobby_row = 0
	m._go(m.Screen.ONLINE_WAIT)


func join_input() -> void:
	if m._back_pressed():
		typing = {}
		open_lan()


func browser_input() -> void:
	if m._back_pressed():
		Online.playbound.lobby_visible = false
		m._go(m.Screen.ONLINE)
		return
	if busy:
		return
	var rooms: Array = browser_rows
	var n := Controls.menu_nudged()
	browser_index = clampi(browser_index + n.y, 0, rooms.size() + 1)
	player_page = clampi(player_page + n.x, 0, maxi(0, (Online.playbound.lobby_players.size()-1)/10))
	if m._confirm_device() == -1:
		return
	if browser_index == 0:
		host_room()
	elif browser_index == 1:
		Online.playbound.refresh_lobby_now()
	else:
		var room: Dictionary = rooms[browser_index-2]
		if str(room.version) != Online.playbound.build_id:
			m.toast_msg("DIFFERENT GAME VERSION - BOTH PLAYERS NEED THE SAME BUILD")
			return
		join_room(str(room.code))


func draw_browser() -> void:
	UI.outrun_background(m, m.SCREEN, m.frame / 60.0, 0.55)
	UI.text(m, Vector2(960, 135), "HYPERDISC LOBBY", 80, UI.YELLOW, UI.display, 6)
	var pb = Online.playbound
	var selected_id := ""
	if browser_index >= 2 and browser_index-2 < browser_rows.size():
		selected_id = str(browser_rows[browser_index-2].id)
	browser_rows = pb.lobby_rooms.duplicate(true)
	if selected_id != "":
		browser_index = 1
		for i in browser_rows.size():
			if str(browser_rows[i].id) == selected_id: browser_index = i+2
	UI.text(m, Vector2(580, 225), "PUBLIC ROOMS", 36, UI.CYAN, UI.ui, 3)
	UI.text(m, Vector2(1450, 225), "PLAYERS ONLINE (%d)" % pb.lobby_players.size(), 32, UI.CYAN, UI.ui, 3)
	UI.button(m, Rect2(150,270,860,64), "CREATING ROOM..." if busy else "CREATE ROOM", browser_index==0,m.frame)
	UI.button(m, Rect2(150,348,860,64), "REFRESH", browser_index==1,m.frame)
	var first := maxi(0, browser_index-7)
	for i in range(first, mini(first+6,pb.lobby_rooms.size())):
		var room: Dictionary = pb.lobby_rooms[i]
		var label := "%s'S ROOM  %d/%d" % [str(room.name).left(24).to_upper(),room.players,room.capacity]
		if str(room.version) != pb.build_id: label += "  [UPDATE NEEDED]"
		UI.button(m, Rect2(150,440+(i-first)*70,860,60),label,browser_index==i+2,m.frame)
	if pb.lobby_rooms.is_empty():
		UI.text(m, Vector2(580,515), "NO OPEN ROOMS - CREATE ONE", 28, UI.DIM, UI.ui, 3)
	player_page=clampi(player_page,0,maxi(0,(pb.lobby_players.size()-1)/10))
	for i in range(player_page*10,mini(player_page*10+10,pb.lobby_players.size())):
		var player: Dictionary=pb.lobby_players[i]
		UI.text(m, Vector2(1450,300+(i%10)*52),str(player.name).left(24).to_upper()+"  -  "+str(player.status).to_upper(),25,Color.WHITE,UI.ui,2)
	UI.text(m,Vector2(960,925),pb.lobby_error if pb.lobby_error!="" else "YOUR PLAYBOUND NAME IS VISIBLE TO PLAYERS IN THIS GAME",24,UI.DIM,UI.ui,2)
	m._hint("%s SELECT     %s BACK     LEFT / RIGHT: PLAYER PAGES" % [m._a(),m._b()])


# --- PlayBound sign-in -----------------------------------------------------------

func sign_in(then := "") -> void:
	after_sign_in = then
	Online.last_error = ""
	Online.playbound.sign_in()
	m._go(m.Screen.ONLINE_SIGNIN)


func signin_input() -> void:
	var pb = Online.playbound
	if pb.is_signed_in():
		Sfx.play("connect")
		m.toast_msg("SIGNED IN AS %s" % pb.profile().display_name)
		match after_sign_in:
			"browse":
				open_browser()
			"add_friend":
				open_add_friend()
			_:
				m._go(m.Screen.ONLINE)
		after_sign_in = ""
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
	_advertise_tick()
	if m._back_pressed():
		Online.close()
		m._go(m.Screen.ONLINE)
		return
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
	_advertise_tick()
	o.poll({})
	if o.state == OnlineMatch.State.FAILED:
		_fail(o.failure)
		return
	if o.state == OnlineMatch.State.PLAYING:
		lan_ad.stop()
		_start_online_match()
		return
	if bot:
		_bot_lobby(o)
		return
	var rows := lobby_rows(o)
	var editable := []
	for i in rows.size():
		if rows[i].edit:
			editable.append(i)
	lobby_row = clampi(lobby_row, 0, editable.size() - 1)
	var row: Dictionary = rows[editable[lobby_row]]
	var n := Controls.menu_nudged()
	if n.y != 0:
		lobby_row = posmod(lobby_row + n.y, editable.size())
		Sfx.play("menu_move")
	# A second local player joins as partner with START, like the VS setup.
	if o.doubles and Controls.pressed(1, "start"):
		o.configure_team(o.doubles, o.local_partner_pick, not o.local_partner_human)
	if n.x != 0:
		var count: int = m.balance.characters.size()
		match row.id:
			"format":
				o.configure_team(not o.doubles, o.local_partner_pick, o.local_partner_human)
			"pick":
				o.set_pick(posmod(o.local_pick + n.x, count), false)
			"partner":
				o.configure_team(o.doubles, posmod(o.local_partner_pick + n.x, count), o.local_partner_human)
			"difficulty":
				o.set_difficulty(posmod(o.difficulty + n.x, m.DIFFICULTIES.size()))
			"court":
				o.set_court(posmod(o.court + n.x, m.balance.courts.size()))
		Sfx.play("menu_move")
	if row.id == "partner" and Controls.menu_pressed("utility") != -1:
		o.configure_team(o.doubles, o.local_partner_pick, not o.local_partner_human)
		Sfx.play("menu_move")
	if m._confirm_device() != -1 and row.id == "go":
		if o.is_host:
			o.set_pick(o.local_pick, true)
			if o.can_start():
				Sfx.play("menu_confirm")
				o.start()
			else:
				m.toast_msg("WAITING FOR %s TO BE READY" % o.remote_name)
		else:
			o.set_pick(o.local_pick, not o.local_locked)
			Sfx.play("menu_confirm" if o.local_locked else "menu_back")
	elif m._back_pressed():
		if o.local_locked and not o.is_host:
			o.set_pick(o.local_pick, false)
			Sfx.play("menu_back")
		else:
			Sfx.play("menu_back")
			lan_ad.stop()
			Online.close()
			m._go(m.Screen.ONLINE)


## The room setup, laid out like the VS match setup: format, both teams,
## CPU difficulty, court, then start. Each row: {id, label, edit}; the
## host sets the shared rows and each player sets their own team.
func lobby_rows(o: OnlineMatch) -> Array:
	var chars: Array = m.balance.characters
	var host_side: bool = o.is_host
	var rows := []
	rows.append({"id": "format", "edit": o.is_host,
		"label": "FORMAT:  < %s >" % ("DOUBLES 2v2" if o.doubles else "SINGLES 1v1")})
	for team in [0, 1]:
		var mine: bool = (team == 0) == host_side
		var name: String = o.local_name if mine else o.remote_name
		var pick: int = o.local_pick if mine else o.remote_pick
		var locked: bool = o.local_locked if mine else o.remote_locked
		var label := "TEAM %s   %s   < %s >" % ["A" if team == 0 else "B", name.left(14),
			chars[pick].name if pick >= 0 else "PICKING..."]
		if locked:
			label += "   READY"
		rows.append({"id": "pick" if mine else "", "edit": mine, "label": label})
		if o.doubles:
			var partner: int = o.local_partner_pick if mine else o.remote_partner_pick
			var human: bool = o.local_partner_human if mine else o.remote_partner_human
			rows.append({"id": "partner" if mine else "", "edit": mine,
				"label": "TEAM %s   %s   < %s >" % ["A" if team == 0 else "B",
					("%s P2" % name.left(10)) if human else "CPU", chars[partner].name]})
	rows.append({"id": "difficulty", "edit": o.is_host,
		"label": "CPU DIFFICULTY:  < %s >" % m.DIFFICULTIES[o.difficulty].to_upper()})
	rows.append({"id": "court", "edit": o.is_host, "label": "COURT:  < %s >" % m.balance.courts[o.court].name})
	var go := ""
	if o.is_host:
		go = "START MATCH" if o.remote_locked else "WAITING FOR %s..." % o.remote_name.left(14)
	else:
		go = "READY!  WAITING FOR THE HOST" if o.local_locked else "READY"
	rows.append({"id": "go", "edit": true, "label": go})
	return rows


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
	if o.doubles:
		ids.append(o.sim.players[2].character.id)
		ids.append(o.sim.players[3].character.id)
		names.append(((o.local_name if o.is_host else o.remote_name) + " / 2") if (o.local_partner_human if o.is_host else o.remote_partner_human) else "CPU A")
		names.append(((o.remote_name if o.is_host else o.local_name) + " / 2") if (o.remote_partner_human if o.is_host else o.local_partner_human) else "CPU B")
	partner_cpu = CpuPlayer.new(o.local_side + 2, m.balance.cpu[m.DIFFICULTIES[o.difficulty]], int(Time.get_ticks_usec())) if o.doubles and not o.local_partner_human else null
	m.story = false
	m.doubles = o.doubles
	m.view = MatchView.new(o.sim, ids, names)
	m.stats.assign([{}, {}])
	m.last_second = -1
	m.online = true
	m.pick.assign([_index_of(o.sim.players[0].character), _index_of(o.sim.players[1].character)])
	leave_menu = false
	vs_ticks = 0
	bot_cpu = CpuPlayer.new(o.local_side, m.balance.cpu.hard, int(Time.get_ticks_usec())) if bot else null
	Online.playbound.set_presence("in_match")
	Mixtape.begin_match(o)
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
	elif Controls.pressed(0, "start") or (o.doubles and o.local_partner_human and Controls.pressed(1, "start")):
		leave_menu = true
		leave_index = 0
		Sfx.play("pause")
	_step(leave_menu)
	if o.state == OnlineMatch.State.FAILED:
		_fail(o.failure)
		return
	if o.session != null and o.session.desynced and m.toast_ticks <= 0:
		m.toast_msg("DESYNC DETECTED AT FRAME %d" % o.session.desync_frame)
	if o.match_settled() and (o.sim.phase_ticks > MatchView.CELEBRATION_TICKS or o.opponent_left):
		Mixtape.finish_match(o)
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
	if o.doubles and o.sim != null:
		input = input.duplicate()
		input["partner"] = {} if idle else (Controls.input(1) if o.local_partner_human else partner_cpu.think(o.sim))
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
	if ONLINE_RESULTS[m.result_index] == "DUB TAPES":
		m.tapes.open(true)
	elif ONLINE_RESULTS[m.result_index] == "REMATCH" and o != null and o.opponent_left:
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
	UI.text(ci, Vector2(960, 200), "MULTIPLAYER", 100, UI.YELLOW, UI.display, 5)
	var who := ("SIGNED IN TO PLAYBOUND AS  %s" % Online.display_name()) if Online.signed_in() \
		else "PLAYING AS  %s   -   NOT SIGNED IN" % Online.display_name()
	UI.text(ci, Vector2(960, 300), who, 28, UI.CYAN, UI.ui, 4)
	var items := menu_items()
	for i in items.size():
		UI.button(ci, Rect2(460, 420 + i * 110, 1000, 80), items[i][1], i == menu_index, m.frame, 36)
	UI.text(ci, Vector2(960, 800), items[clampi(menu_index, 0, items.size() - 1)][2], 28, UI.CYAN, UI.ui, 3)
	if busy:
		UI.text(ci, Vector2(960, 1000), "TALKING TO PLAYBOUND" + ".".repeat(1 + (m.frame / 20) % 3), 30, UI.YELLOW, UI.ui, 4)
	var sign_out := ("     %s SIGN OUT" % Controls.label(0, "utility")) if Online.signed_in() else ""
	m._hint("%s SELECT     %s BACK%s" % [m._a(), m._b(), sign_out])


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
		UI.text(ci, Vector2(960, 390), "PUBLIC ROOM", 34, Color.WHITE, UI.ui, 4)
		var box := Rect2(Vector2(610, 420), Vector2(700, 150))
		UI.slant_panel(ci, box, Color("120826"), UI.CYAN, 28, 6)
		UI.text(ci, Vector2(960, 528), Online.display_name() + "'S ROOM", 64, UI.YELLOW, UI.display, 8)
		UI.text(ci, Vector2(960, 640), "PLAYERS CAN FIND YOU IN ONLINE > LOBBY", 28, UI.DIM, UI.ui, 3)
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
	UI.outrun_background(ci, m.SCREEN, m.frame / 60.0, 0.25)
	var where := "LAN" if Online.room_code == "" else "ONLINE"
	UI.text(ci, Vector2(960, 130), "%s %s MATCH SETUP" % [where, "DOUBLES" if o.doubles else "SINGLES"], 72,
		UI.YELLOW, UI.display, 5)
	var rows := lobby_rows(o)
	var editable := []
	for i in rows.size():
		if rows[i].edit:
			editable.append(i)
	var selected: int = editable[clampi(lobby_row, 0, editable.size() - 1)]
	for i in rows.size():
		UI.button(ci, Rect2(360, 220 + i * 82, 1200, 68), rows[i].label, i == selected, m.frame, 30, rows[i].edit)
	var help := "UP/DOWN: ROW   LEFT/RIGHT: CHANGE"
	if o.doubles:
		help += "   %s: CPU / PLAYER 2 PARTNER   P2 START: JOIN" % Controls.label(0, "utility")
	UI.text(ci, Vector2(960, 940), help, 25, UI.CYAN, UI.ui, 2)
	var shared := "" if o.is_host else "     THE HOST SETS FORMAT, DIFFICULTY AND COURT"
	m._hint("%s %s     %s LEAVE%s" % [m._a(), "START MATCH" if o.is_host else "READY", m._b(), shared])


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


# --- LAN rooms ---------------------------------------------------------------------

func open_lan() -> void:
	lan_index = 0
	lan_find.browse()
	m._go(m.Screen.LAN_BROWSER)


## LAN browser rows: [id, label]; rooms found on the network come last.
func lan_rows() -> Array:
	var rows := [["create", "CREATE ROOM"], ["address", "JOIN BY ADDRESS"]]
	if not Online.signed_in():
		var name := Settings.player_name
		if typing.get("field", "") == "name":
			name = typing.value + ("_" if (m.frame / 20) % 2 == 0 else " ")
		rows.append(["name", "YOUR NAME:  " + name])
	for room in lan_find.rooms():
		var label := "%s'S ROOM  %d/2" % [room.name, room.players]
		if room.build != str(OnlineMatch.build_hash()):
			label += "  [UPDATE NEEDED]"
		rows.append(["room", label, room])
	return rows


func lan_input() -> void:
	lan_find.poll()
	if not typing.is_empty():
		return
	var rows := lan_rows()
	lan_index = clampi(lan_index, 0, rows.size() - 1)
	var n := Controls.menu_nudged()
	if n.y != 0:
		lan_index = posmod(lan_index + n.y, rows.size())
		Sfx.play("menu_move")
	if m._back_pressed():
		Sfx.play("menu_back")
		lan_find.stop()
		m._go(m.Screen.ONLINE)
		return
	if m._confirm_device() == -1:
		return
	Sfx.play("menu_confirm")
	match rows[lan_index][0]:
		"create":
			host()
		"address":
			lan_find.stop()
			typing = {"field": "address", "value": Settings.last_address}
			m._go(m.Screen.ONLINE_JOIN)
		"name":
			typing = {"field": "name", "value": Settings.player_name}
		"room":
			var room: Dictionary = rows[lan_index][2]
			if room.build != str(OnlineMatch.build_hash()):
				m.toast_msg("DIFFERENT GAME VERSION - BOTH PLAYERS NEED THE SAME BUILD")
				return
			lan_find.stop()
			Settings.last_address = "%s:%d" % [room.address, room.port]
			Settings.save()
			_connect(Settings.last_address)


func draw_lan() -> void:
	UI.outrun_background(m, m.SCREEN, m.frame / 60.0, 0.55)
	UI.text(m, Vector2(960, 135), "LAN LOBBY", 80, UI.YELLOW, UI.display, 6)
	UI.text(m, Vector2(960, 205), "PLAYING AS  %s" % Online.display_name(), 28, UI.CYAN, UI.ui, 3)
	var rows := lan_rows()
	var first := maxi(0, lan_index - 8)
	for i in range(first, mini(first + 9, rows.size())):
		UI.button(m, Rect2(460, 250 + (i - first) * 76, 1000, 64), rows[i][1], i == lan_index, m.frame, 30)
	if lan_find.rooms().is_empty():
		UI.text(m, Vector2(960, 250 + rows.size() * 76 + 40), "LOOKING FOR ROOMS ON YOUR NETWORK" + ".".repeat(1 + (m.frame / 20) % 3),
			28, UI.DIM, UI.ui, 3)
	if typing.get("field", "") == "name":
		m._hint("TYPE YOUR NAME, ENTER TO SAVE, ESC TO CANCEL")
	else:
		m._hint("%s SELECT     %s BACK     ROOMS ON THIS NETWORK APPEAR HERE" % [m._a(), m._b()])


# --- Add friend ----------------------------------------------------------------------

func open_add_friend() -> void:
	friend_index = 0
	friend_sent = {}
	Online.playbound.search_results = []
	Online.playbound.refresh_friend_requests()
	Online.playbound.lobby_visible = true
	Online.playbound.refresh_lobby_now()
	m._go(m.Screen.ONLINE_ADD_FRIEND)


## Everything on the Add Friend screen, in order: [kind, label, data].
## Kinds: search (the name field), header, result, request, player.
func friend_rows() -> Array:
	var pb = Online.playbound
	var rows := []
	var query: String = typing.get("value", "") + ("_" if (m.frame / 20) % 2 == 0 else " ") \
		if typing.get("field", "") == "search" else ""
	rows.append(["search", "SEARCH BY NAME:  " + query])
	for u in pb.search_results:
		rows.append(["result", u.name + "   " + _friend_status(u.id, u.status), u])
	if not pb.friend_requests.is_empty():
		rows.append(["header", "WANT TO BE YOUR FRIEND"])
		for r in pb.friend_requests:
			rows.append(["request", r.name + "   ACCEPT", r])
	var friends := {}
	for f in pb.friends():
		friends[f.id] = true
	var here := []
	for p in pb.lobby_players:
		var id := str(p.get("id", ""))
		if id != "" and id != str(pb.profile().id) and not friends.has(id):
			here.append(p)
	if not here.is_empty():
		rows.append(["header", "IN HYPERDISC NOW"])
		for p in here:
			rows.append(["player", str(p.name).to_upper().left(20) + "   " + _friend_status(str(p.id), "none"), p])
	return rows


func _friend_status(id: String, status: String) -> String:
	if friend_sent.has(id) or status == "outgoing_request":
		return "REQUEST SENT"
	return {"friends": "FRIENDS", "incoming_request": "WANTS TO BE FRIENDS - SEE BELOW"}.get(status, "ADD")


func add_friend_input() -> void:
	if not typing.is_empty() or busy:
		return
	var rows := friend_rows()
	var picks := []
	for i in rows.size():
		if rows[i][0] != "header":
			picks.append(i)
	friend_index = clampi(friend_index, 0, picks.size() - 1)
	var n := Controls.menu_nudged()
	if n.y != 0:
		friend_index = posmod(friend_index + n.y, picks.size())
		Sfx.play("menu_move")
	if m._back_pressed():
		Sfx.play("menu_back")
		Online.playbound.lobby_visible = false
		m._go(m.Screen.ONLINE)
		return
	if m._confirm_device() == -1:
		return
	var row: Array = rows[picks[friend_index]]
	match row[0]:
		"search":
			Sfx.play("menu_confirm")
			typing = {"field": "search", "value": ""}
		"result", "player":
			var id := str(row[2].id)
			var status := str(row[2].get("status", "none"))
			if friend_sent.has(id) or status != "none":
				return
			Sfx.play("menu_confirm")
			busy = true
			var err: String = await Online.playbound.send_friend_request(id)
			busy = false
			if err == "":
				friend_sent[id] = true
				m.toast_msg("FRIEND REQUEST SENT TO %s" % str(row[2].name).to_upper())
			else:
				m.toast_msg(err)
		"request":
			Sfx.play("menu_confirm")
			busy = true
			var err: String = await Online.playbound.accept_friend_request(str(row[2].id))
			busy = false
			m.toast_msg(err if err != "" else "YOU AND %s ARE NOW FRIENDS" % row[2].name)


func draw_add_friend() -> void:
	UI.outrun_background(m, m.SCREEN, m.frame / 60.0, 0.5)
	UI.text(m, Vector2(960, 130), "ADD FRIEND", 90, UI.YELLOW, UI.display, 6)
	var rows := friend_rows()
	var picks := []
	for i in rows.size():
		if rows[i][0] != "header":
			picks.append(i)
	var selected: int = picks[clampi(friend_index, 0, picks.size() - 1)]
	var first := clampi(selected - 5, 0, maxi(0, rows.size() - 10))
	for i in range(first, mini(first + 10, rows.size())):
		var y := 210 + (i - first) * 72
		if rows[i][0] == "header":
			UI.text(m, Vector2(960, y + 46), rows[i][1], 28, UI.CYAN, UI.ui, 3)
		else:
			UI.button(m, Rect2(460, y, 1000, 60), rows[i][1], i == selected, m.frame, 28)
	if rows.size() == 1:
		UI.text(m, Vector2(960, 420), "NOBODY ELSE IS IN HYPERDISC RIGHT NOW", 30, UI.DIM, UI.ui, 3)
	if busy:
		UI.text(m, Vector2(960, 1000), "TALKING TO PLAYBOUND" + ".".repeat(1 + (m.frame / 20) % 3), 30, UI.YELLOW, UI.ui, 4)
	if typing.get("field", "") == "search":
		m._hint("TYPE A PLAYBOUND NAME (3+ LETTERS), ENTER TO SEARCH, ESC TO CANCEL")
	else:
		m._hint("%s ADD / ACCEPT / SEARCH     %s BACK     SEARCHING NEEDS A KEYBOARD" % [m._a(), m._b()])
