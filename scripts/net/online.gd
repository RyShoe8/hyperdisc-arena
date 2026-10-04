## Online play (autoload "Online"): the active online service (PlayBound
## when available, direct connect until then) and the current OnlineMatch.
extends Node

const DirectService := preload("res://scripts/net/direct_service.gd")
const PlayBoundService := preload("res://scripts/net/playbound_service.gd")
const OnlineMatch := preload("res://scripts/net/online_match.gd")

var service  # an OnlineService
var direct: DirectService
var playbound: PlayBoundService
var current: OnlineMatch
var last_error := ""

var _balance: Dictionary


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	direct = DirectService.new()
	playbound = PlayBoundService.new()
	service = playbound if playbound.is_available() else direct
	for s in [direct, playbound]:
		s.match_ready.connect(_on_match_ready)
		s.error.connect(func(msg): last_error = msg)


func _physics_process(_delta: float) -> void:
	service.poll()


func display_name() -> String:
	return str(service.profile().display_name)


func host(port: int, lag_ms := 0, loss := 0.0) -> void:
	last_error = ""
	direct.display_name = display_name_setting()
	direct.host(port, lag_ms, loss)


func join(address: String, lag_ms := 0, loss := 0.0) -> void:
	last_error = ""
	direct.display_name = display_name_setting()
	direct.join(address, lag_ms, loss)


func display_name_setting() -> String:
	var settings := get_node_or_null("/root/Settings")
	return settings.player_name if settings != null else "PLAYER"


func close() -> void:
	if current != null and current.state != OnlineMatch.State.FAILED:
		current.leave()
	current = null


func _on_match_ready(info: Dictionary) -> void:
	current = OnlineMatch.new(info.transport, _balance, info.role == "host", display_name_setting())
