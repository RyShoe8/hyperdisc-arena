## Player settings (autoload "Settings"): graphics, audio and control
## bindings, saved to user://settings.cfg and applied immediately.
extends Node

signal changed

const PATH := "user://settings.cfg"
const WINDOW_MODES := ["WINDOWED", "FULLSCREEN", "BORDERLESS"]
const SHAKE_LEVELS := ["OFF", "LOW", "FULL"]
const EFFECT_LEVELS := ["LOW", "HIGH"]
const LABEL_STYLES := ["AUTO", "XBOX", "PLAYSTATION"]

var window_mode := 0
var vsync := true
var shake := 2
var effects := 1
var scanlines := false
var show_fps := false
var show_catch_zones := false
## Button names in prompts: 0 follows the controller, 1 Xbox, 2 PlayStation.
var button_labels := 0
var master_volume := 0.9
## Online display name (until PlayBound accounts provide one).
var player_name := "PLAYER"
## Last address typed into Join, and the port used to host.
var last_address := ""
var host_port := 7777
var sfx_volume := 0.9


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply()


func shake_scale() -> float:
	return [0.0, 0.45, 1.0][shake]


func high_effects() -> bool:
	return effects == 1


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	window_mode = int(cfg.get_value("graphics", "window_mode", window_mode))
	vsync = bool(cfg.get_value("graphics", "vsync", vsync))
	shake = int(cfg.get_value("graphics", "shake", shake))
	effects = int(cfg.get_value("graphics", "effects", effects))
	scanlines = bool(cfg.get_value("graphics", "scanlines", scanlines))
	show_fps = bool(cfg.get_value("graphics", "show_fps", show_fps))
	show_catch_zones = bool(cfg.get_value("graphics", "show_catch_zones", show_catch_zones))
	button_labels = int(cfg.get_value("controls", "button_labels", button_labels))
	master_volume = float(cfg.get_value("audio", "master", master_volume))
	player_name = str(cfg.get_value("online", "name", player_name)).left(16)
	last_address = str(cfg.get_value("online", "last_address", last_address))
	host_port = int(cfg.get_value("online", "host_port", host_port))
	sfx_volume = float(cfg.get_value("audio", "sfx", sfx_volume))
	var bindings = cfg.get_value("controls", "bindings", null)
	if bindings is Dictionary:
		Controls.set_bindings(bindings)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "window_mode", window_mode)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "shake", shake)
	cfg.set_value("graphics", "effects", effects)
	cfg.set_value("graphics", "scanlines", scanlines)
	cfg.set_value("graphics", "show_fps", show_fps)
	cfg.set_value("graphics", "show_catch_zones", show_catch_zones)
	cfg.set_value("controls", "button_labels", button_labels)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("online", "name", player_name)
	cfg.set_value("online", "last_address", last_address)
	cfg.set_value("online", "host_port", host_port)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("controls", "bindings", Controls.get_bindings())
	cfg.save(PATH)


func apply() -> void:
	# Window modes only mean something on desktop; the browser owns the window.
	if not OS.has_feature("web"):
		match window_mode:
			0:
				DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			1:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			2:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(master_volume, 0.0001)))
	AudioServer.set_bus_mute(bus, master_volume <= 0.001)
	changed.emit()
