## Sound effects (autoload "Sfx"). Kenney Interface Sounds (CC0), loaded
## once and played through a small pool so overlapping sounds don't cut
## each other off.
extends Node

const SOUNDS := {
	"menu_move": "res://assets/sfx/menu_move.ogg",
	"menu_confirm": "res://assets/sfx/menu_confirm.ogg",
	"menu_back": "res://assets/sfx/menu_back.ogg",
	"throw": "res://assets/sfx/throw.ogg",
	"supersonic": "res://assets/sfx/supersonic.ogg",
	"lob": "res://assets/sfx/lob.ogg",
	"catch": "res://assets/sfx/catch.ogg",
	"bounce": "res://assets/sfx/bounce.ogg",
	"goal": "res://assets/sfx/goal.ogg",
	"miss": "res://assets/sfx/miss.ogg",
	"set_end": "res://assets/sfx/set_end.ogg",
	"match_win": "res://assets/sfx/match_win.ogg",
	"countdown": "res://assets/sfx/countdown.ogg",
	"pause": "res://assets/sfx/pause.ogg",
	"connect": "res://assets/sfx/connect.ogg",
	"disconnect": "res://assets/sfx/disconnect.ogg",
}
const POOL_SIZE := 8

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for key in SOUNDS:
		_streams[key] = load(SOUNDS[key])
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


## Plays a sound by name. pitch lets repeated sounds (bounces, catches)
## vary so they don't sound mechanical; volume is in decibels.
func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if not _streams.has(sound):
		push_warning("Unknown sound: " + sound)
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
	p.play()
