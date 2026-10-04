## Online play (autoload "Online"): PlayBound (account, friends, invites,
## Connect rooms) and direct connect (LAN), plus the current OnlineMatch.
extends Node

const DirectService := preload("res://scripts/net/direct_service.gd")
const PlayBoundService := preload("res://scripts/net/playbound_service.gd")
const PlayBoundApi := preload("res://scripts/net/playbound_api.gd")
const OnlineMatch := preload("res://scripts/net/online_match.gd")

var direct: DirectService
var playbound: PlayBoundService
var api: PlayBoundApi
var current: OnlineMatch
## The Connect room code while hosting a room (shown and sent with invites).
var room_code := ""
var last_error := ""
## An invite that arrived and hasn't been answered: {id, from_name, connect_code}.
var pending_invite := {}

var _balance: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	api = PlayBoundApi.new()
	api.name = "PlayBoundApi"
	var base := OS.get_environment("PLAYBOUND_API_BASE")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--playbound-api="):
			base = arg.trim_prefix("--playbound-api=")
	if base != "":
		api.base = base.trim_suffix("/")
	add_child(api)
	direct = DirectService.new()
	playbound = PlayBoundService.new()
	playbound.api = api
	playbound.build_id = str(OnlineMatch.build_hash())
	for s in [direct, playbound]:
		s.match_ready.connect(_on_match_ready)
		s.error.connect(func(msg): last_error = msg)
	playbound.invite_received.connect(func(inv): pending_invite = inv)
	playbound.start()
	# Closing the window waits (briefly) to tell PlayBound we've gone offline.
	get_tree().set_auto_accept_quit(false)


func _physics_process(_delta: float) -> void:
	playbound.poll()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_game()


## Quits the game, first telling PlayBound we went offline.
func quit_game() -> void:
	if playbound.has_presence():
		get_tree().create_timer(1.5, true, false, true).timeout.connect(get_tree().quit)
		await playbound.shutdown()
	get_tree().quit()


func signed_in() -> bool:
	return playbound.is_signed_in()


## The name other players see: the PlayBound username, else the local name.
func display_name() -> String:
	if playbound.is_signed_in():
		return str(playbound.profile().display_name).left(16)
	return display_name_setting()


func display_name_setting() -> String:
	var settings := get_node_or_null("/root/Settings")
	return settings.player_name if settings != null else "PLAYER"


## LAN / direct IP.
func host(port: int, lag_ms := 0, loss := 0.0) -> void:
	last_error = ""
	room_code = ""
	direct.display_name = display_name()
	direct.host(port, lag_ms, loss)


func join(address: String, lag_ms := 0, loss := 0.0) -> void:
	last_error = ""
	room_code = ""
	direct.display_name = display_name()
	direct.join(address, lag_ms, loss)


## PlayBound Connect rooms (no ports, works across the internet).
func host_room() -> void:
	last_error = ""
	await playbound.host_room()


func join_room(code: String) -> void:
	last_error = ""
	await playbound.join_room(code)


func close() -> void:
	if current != null and current.state != OnlineMatch.State.FAILED:
		current.leave()
	current = null
	room_code = ""


func _on_match_ready(info: Dictionary) -> void:
	room_code = str(info.get("room_code", ""))
	current = OnlineMatch.new(info.transport, _balance, info.role == "host", display_name())
