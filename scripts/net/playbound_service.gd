## PlayBound accounts, friends, presence, invites and Connect rooms.
##
## Sign-in: started from the game (or skipped entirely when the PlayBound
## launcher passes PLAYBOUND_TOKEN). The game shows a code and opens
## playbound.club/link?code=..., the player signs in or creates an account
## there, and the poll here receives a token. It's stored encrypted per
## machine and checked with /api/game-auth/me on start.
##
## Rooms (Connect) work signed in or not; friends and invites need an account.
extends "res://scripts/net/online_service.gd"

const WebRtcTransport := preload("res://scripts/net/webrtc_transport.gd")
const GAME_SLUG := "hyperdisc-arena"
const TOKEN_FILE := "user://playbound.cfg"
const FRIENDS_REFRESH_MS := 15000
const INVITES_REFRESH_MS := 5000

## The sign-in code to show while waiting for the browser: {code, url}.
signal link_started(info: Dictionary)
## Sign-in finished, failed or was cancelled.
signal link_finished(ok: bool)

var api  # PlayBoundApi node, set by the Online autoload
var build_id := ""
var _profile := {}
var _friends: Array[Dictionary] = []
var _link := {}         # {code, url, poll_token, interval_ms, expires_ms, next_ms}
var _link_busy := false
var _next_friends_ms := 0
var _next_invites_ms := 0
var _presence_session := ""
var _next_heartbeat_ms := 0
var _presence_status := "online"
var _next_presence_start_ms := 0
var _seen_invites := {}
var _busy := {}


func service_name() -> String:
	return "PlayBound"


func is_available() -> bool:
	return api != null


func is_signed_in() -> bool:
	return not _profile.is_empty()


func profile() -> Dictionary:
	if _profile.is_empty():
		return {"id": "", "display_name": "PLAYER"}
	return {"id": _profile.id, "display_name": str(_profile.username).to_upper()}


func signing_in() -> bool:
	return not _link.is_empty()


func link_info() -> Dictionary:
	return _link


func supports_friends() -> bool:
	return is_signed_in()


func friends() -> Array[Dictionary]:
	return _friends


# --- Start-up ------------------------------------------------------------------

## Restores the session: the launcher's token if it passed one, else the
## saved one. Verifies it with the server before trusting it.
func start() -> void:
	var launcher_token := OS.get_environment("PLAYBOUND_TOKEN")
	var token := launcher_token if launcher_token != "" else _load_token()
	if token == "":
		return
	api.token = token
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/api/game-auth/me")
	if res._ok and res.get("user") is Dictionary:
		_signed_in(res.user, token)
	elif res._status == 401:
		api.token = ""
		_save_token("")


func _signed_in(user: Dictionary, token: String) -> void:
	_profile = {"id": str(user.get("id", "")), "username": str(user.get("username", "Player"))}
	api.token = token
	_save_token(token)
	_next_friends_ms = 0
	_next_invites_ms = 0
	profile_changed.emit()
	_start_presence()


# --- Sign in / out ---------------------------------------------------------------

func sign_in() -> void:
	if signing_in() or _link_busy:
		return
	_link_busy = true
	var device := OS.get_environment("COMPUTERNAME")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/game-auth/link",
		{"gameSlug": GAME_SLUG, "deviceName": device}, false)
	_link_busy = false
	if not res._ok:
		error.emit(str(res.get("error", "COULDN'T START SIGN-IN")).to_upper())
		link_finished.emit(false)
		return
	var now := Time.get_ticks_msec()
	_link = {"code": str(res.code), "url": str(res.verifyUrl), "poll_token": str(res.pollToken),
		"interval_ms": int(res.get("intervalMs", 3000)), "expires_ms": now + int(res.get("expiresInMs", 600000)),
		"next_ms": now + int(res.get("intervalMs", 3000))}
	OS.shell_open(_link.url)
	link_started.emit(_link)


## Creating an account happens on the same page (it has a sign-up link).
func create_account() -> void:
	sign_in()


func cancel_sign_in() -> void:
	_link = {}
	link_finished.emit(false)


func sign_out() -> void:
	if api.token != "":
		_end_presence()
		api.call_api(HTTPClient.METHOD_POST, "/api/game-auth/logout", {})
	api.token = ""
	_profile = {}
	_friends = []
	_save_token("")
	profile_changed.emit()
	friends_changed.emit()


func _poll_link() -> void:
	var now := Time.get_ticks_msec()
	if _link.is_empty() or _busy.has("link") or now < int(_link.next_ms):
		return
	if now > int(_link.expires_ms):
		_link = {}
		error.emit("SIGN-IN CODE EXPIRED - TRY AGAIN")
		link_finished.emit(false)
		return
	_busy["link"] = true
	_link.next_ms = now + int(_link.interval_ms)
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/game-auth/link/poll",
		{"pollToken": _link.get("poll_token", "")}, false)
	_busy.erase("link")
	if _link.is_empty():
		return  # cancelled meanwhile
	match str(res.get("status", "")):
		"approved":
			_link = {}
			_signed_in(res.user, str(res.token))
			link_finished.emit(true)
		"denied":
			_link = {}
			error.emit("SIGN-IN WAS TURNED DOWN")
			link_finished.emit(false)
		"expired", "invalid":
			_link = {}
			error.emit("SIGN-IN CODE EXPIRED - TRY AGAIN")
			link_finished.emit(false)


# --- Friends, presence, invites --------------------------------------------------

func poll() -> void:
	if not _link.is_empty():
		_poll_link()
	if not is_signed_in():
		return
	var now := Time.get_ticks_msec()
	if now >= _next_friends_ms and not _busy.has("friends"):
		_next_friends_ms = now + FRIENDS_REFRESH_MS
		_refresh_friends()
	if now >= _next_invites_ms and not _busy.has("invites"):
		_next_invites_ms = now + INVITES_REFRESH_MS
		_refresh_invites()
	if _presence_session == "" and now >= _next_presence_start_ms and not _busy.has("presence"):
		_start_presence()
	elif _presence_session != "" and now >= _next_heartbeat_ms and not _busy.has("presence"):
		_heartbeat_presence()


func refresh_friends_now() -> void:
	_next_friends_ms = 0


func _refresh_friends() -> void:
	_busy["friends"] = true
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/api/friends")
	_busy.erase("friends")
	if res._status == 401:
		_session_expired()
		return
	if not res._ok:
		error.emit("COULDN'T REFRESH FRIENDS: " + str(res.get("error", "PLAYBOUND UNREACHABLE")).to_upper())
		return
	var list: Array[Dictionary] = []
	for f in res.get("friends", []):
		var presence: Dictionary = f.get("presence", {}) if f.get("presence") is Dictionary else {}
		var status := str(presence.get("status", "offline"))
		list.append({
			"id": str(f.get("id", "")),
			"display_name": str(f.get("username", "Player")).to_upper(),
			"online": status != "offline",
			"in_game": str(presence.get("currentGameId", "")) == GAME_SLUG,
			"status": status,
		})
	# Friends in HyperDisc first, then online, then the rest; by name within.
	list.sort_custom(func(a, b):
		var ka := (0 if a.in_game else (1 if a.online else 2))
		var kb := (0 if b.in_game else (1 if b.online else 2))
		return ka < kb if ka != kb else a.display_name < b.display_name)
	_friends = list
	friends_changed.emit()


func _refresh_invites() -> void:
	_busy["invites"] = true
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/api/play-invites")
	_busy.erase("invites")
	if not res._ok:
		return
	for inv in res.get("invites", []):
		if inv.get("direction", "") != "incoming" or inv.get("status", "") != "pending":
			continue
		if inv.get("gameSlug", "") != GAME_SLUG or str(inv.get("connectCode", "")) == "":
			continue
		var key := "%s:%s" % [inv.id, inv.connectCode]
		if _seen_invites.has(key):
			continue
		_seen_invites[key] = true
		invite_received.emit({"id": str(inv.id), "from_id": str(inv.senderId),
			"from_name": str(inv.get("senderUsername", "A friend")).to_upper(), "connect_code": str(inv.connectCode)})


## Invites a friend to the room we're hosting.
func send_invite(friend_id: String, connect_code := "") -> void:
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/play-invites",
		{"recipientId": friend_id, "gameSlug": GAME_SLUG, "connectCode": connect_code})
	if not res._ok:
		var msg := str(res.get("error", "COULDN'T SEND THE INVITE"))
		var results = res.get("results", [])
		if results is Array and not results.is_empty() and results[0] is Dictionary and results[0].has("error"):
			msg = str(results[0].error)
		error.emit(msg.to_upper())
		return
	invite_answered.emit("", true)


func respond_to_invite(invite_id: String, accept: bool) -> void:
	await api.call_api(HTTPClient.METHOD_POST, "/api/play-invites/%s" % invite_id,
		{"action": "accept" if accept else "decline"})


func set_presence(status: String) -> void:
	_presence_status = "playing" if status == "in_match" else "online"
	_next_heartbeat_ms = 0


func _start_presence() -> void:
	if _busy.has("presence"):
		return
	_busy["presence"] = true
	_next_presence_start_ms = Time.get_ticks_msec() + 5000
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/presence/start",
		{"status": _presence_status, "gameId": GAME_SLUG})
	_busy.erase("presence")
	if not is_signed_in():
		return
	if res._ok:
		_presence_session = str(res.get("sessionId", ""))
		_next_heartbeat_ms = Time.get_ticks_msec() + int(res.get("heartbeatIntervalMs", 60000))
	elif res._status == 401:
		_session_expired()


func _heartbeat_presence() -> void:
	_busy["presence"] = true
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/presence/heartbeat",
		{"sessionId": _presence_session, "status": _presence_status, "gameId": GAME_SLUG})
	_busy.erase("presence")
	_next_heartbeat_ms = Time.get_ticks_msec() + (60000 if res._ok else 5000)
	if res._status == 401:
		_session_expired()
	elif res._status == 404:
		_presence_session = ""


func _end_presence() -> void:
	var session := _presence_session
	_presence_session = ""
	if session != "":
		await api.call_api(HTTPClient.METHOD_POST, "/api/presence/end", {"sessionId": session})


func has_presence() -> bool:
	return _presence_session != ""


## Called when the game quits, so friends stop seeing us online.
func shutdown() -> void:
	await _end_presence()


func _session_expired() -> void:
	api.token = ""
	_profile = {}
	_friends = []
	_save_token("")
	profile_changed.emit()
	error.emit("SIGNED OUT OF PLAYBOUND - SIGN IN AGAIN")


# --- Connect rooms -----------------------------------------------------------------

## Opens a room; match_ready fires with a WebRTC transport waiting for a guest.
func host_room() -> void:
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/multiplayer/%s/sessions" % GAME_SLUG,
		{"gameVersion": build_id, "maxPlayers": 2}, false)
	if not res._ok:
		error.emit(str(res.get("error", "COULDN'T CREATE A ROOM")).to_upper())
		return
	_ready_transport(res, "host")


func join_room(code: String) -> void:
	var clean := code.strip_edges().to_upper().replace(" ", "")
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST,
		"/api/multiplayer/%s/sessions/%s/join" % [GAME_SLUG, clean.uri_encode()], {"gameVersion": build_id}, false)
	if not res._ok:
		error.emit(str(res.get("error", "COULDN'T JOIN THAT ROOM")).to_upper())
		return
	if res.get("versionMismatch", false):
		error.emit("THAT ROOM IS ON A DIFFERENT GAME VERSION")
		return
	_ready_transport(res, "join")


func _ready_transport(info: Dictionary, as_role: String) -> void:
	var t := WebRtcTransport.new()
	if t.start(api, info, "host" if as_role == "host" else "client") != OK:
		error.emit(t.failure)
		return
	match_ready.emit({"role": as_role, "transport": t, "opponent": {}, "room_code": str(info.get("joinCode", ""))})


# --- Token storage -------------------------------------------------------------------

## Encrypted with a key tied to this machine, so the file is useless elsewhere.
func _key() -> String:
	return (OS.get_unique_id() + ":hyperdisc-playbound").sha256_text()


func _load_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load_encrypted_pass(TOKEN_FILE, _key()) != OK:
		return ""
	return str(cfg.get_value("playbound", "token", ""))


func _save_token(token: String) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("playbound", "token", token)
	cfg.save_encrypted_pass(TOKEN_FILE, _key())
