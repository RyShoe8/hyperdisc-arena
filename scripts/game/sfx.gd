## Sound effects (autoload "Sfx").
##
## Gameplay sounds come from the Sonniss GDC bundles (royalty free, no
## attribution), cut and levelled by tools/audio/process_sfx.py; menu sounds
## are Kenney Interface Sounds (CC0). A cue layers several sounds, each picked
## at random from its takes with a little pitch and volume variation so
## repeats don't sound mechanical, and is panned to where it happens on court.
##
## Throws, power throws and specials are per character: each character has
## their own takes in assets/sfx/characters/<id>/ (see process_sfx.py), used
## when play() is given the character's id.
extends Node

const DIR := "res://assets/sfx/"
const CHARACTER_DIR := "res://assets/sfx/characters/"
## Sounds that each character has their own takes of.
const CHARACTER_SOUNDS := ["throw_whoosh", "power_whoosh", "special_launch"]

## Sound name -> takes (one is picked at random each time).
const SOUNDS := {
	"menu_move": ["menu_move.ogg"],
	"menu_confirm": ["menu_confirm.ogg"],
	"menu_back": ["menu_back.ogg"],
	"countdown": ["countdown.ogg"],
	"pause": ["pause.ogg"],
	"connect": ["connect.ogg"],
	"disconnect": ["disconnect.ogg"],
	"throw_whoosh": ["throw_whoosh_1.wav", "throw_whoosh_2.wav", "throw_whoosh_3.wav", "throw_whoosh_4.wav",
		"throw_whoosh_5.wav"],
	"power_whoosh": ["power_whoosh_1.wav", "power_whoosh_2.wav", "power_whoosh_3.wav"],
	"special_launch": ["special_launch_1.wav"],
	"catch_hit": ["catch_1.wav", "catch_2.wav", "catch_3.wav", "catch_4.wav", "catch_5.wav"],
	"catch_body": ["catch_body_1.wav", "catch_body_2.wav"],
	"block_hit": ["block_1.wav", "block_2.wav"],
	"wall": ["wall_1.wav", "wall_2.wav"],
	"net": ["net_1.wav"],
	"ground": ["ground.wav"],
	"crowd_goal": ["crowd_goal_1.wav", "crowd_goal_2.wav"],
	"crowd_cheer": ["crowd_cheer.wav"],
	"crowd_miss": ["crowd_miss.wav"],
	"whistle": ["whistle.wav"],
	"buzzer": ["buzzer.wav"],
}

## Cue -> layers of [sound, volume dB, pitch jitter]. Cue names are what the
## game plays; a plain sound name works too.
const CUES := {
	"throw": [["throw_whoosh", -2.0, 0.07]],
	"supersonic": [["power_whoosh", 0.0, 0.05]],
	"special": [["special_launch", 0.0, 0.0], ["power_whoosh", -5.0, 0.05]],
	"slap": [["throw_whoosh", -3.0, 0.08], ["catch_hit", -10.0, 0.06]],
	"lob": [["throw_whoosh", -9.0, 0.05]],
	"catch": [["catch_hit", 0.0, 0.06], ["catch_body", -7.0, 0.06]],
	"block": [["block_hit", -1.0, 0.05], ["catch_body", -9.0, 0.05]],
	"bounce": [["wall", -3.0, 0.08]],
	"net": [["net", -4.0, 0.06]],
	"land": [["ground", -10.0, 0.1]],
	"goal": [["crowd_goal", -3.0, 0.03]],
	"miss": [["crowd_miss", -4.0, 0.03], ["ground", -6.0, 0.05]],
	"set_end": [["whistle", -3.0, 0.0], ["crowd_cheer", -5.0, 0.03]],
	"match_win": [["crowd_cheer", 0.0, 0.0]],
}

const POOL_SIZE := 16
const BED_DB := -20.0
const EFFECTS_GAIN_DB := 4.0

var _streams := {}
var _character_streams := {}  # character id -> {sound: takes}
var _players: Array[AudioStreamPlayer2D] = []
var _next := 0
var _bed: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var effects_bus := AudioServer.get_bus_index("Effects")
	if effects_bus == -1:
		AudioServer.add_bus()
		effects_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(effects_bus, "Effects")
		AudioServer.set_bus_send(effects_bus, "Master")
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -1.0
		AudioServer.add_bus_effect(effects_bus, limiter)
	for key in SOUNDS:
		var takes: Array = []
		for file in SOUNDS[key]:
			if ResourceLoader.exists(DIR + file):
				takes.append(load(DIR + file))
		_streams[key] = takes
	for id in _character_ids():
		var sounds := {}
		for sound in CHARACTER_SOUNDS:
			var takes: Array = []
			var i := 1
			while ResourceLoader.exists("%s%s/%s_%d.wav" % [CHARACTER_DIR, id, sound, i]):
				takes.append(load("%s%s/%s_%d.wav" % [CHARACTER_DIR, id, sound, i]))
				i += 1
			if not takes.is_empty():
				sounds[sound] = takes
		_character_streams[id] = sounds
	for i in POOL_SIZE:
		var p := AudioStreamPlayer2D.new()
		p.bus = "Effects"
		# Panning only: no fall-off with distance.
		p.attenuation = 0.0
		p.max_distance = 100000.0
		p.panning_strength = 1.0
		add_child(p)
		_players.append(p)
	_bed = AudioStreamPlayer.new()
	_bed.bus = "Effects"
	add_child(_bed)
	if ResourceLoader.exists(DIR + "crowd_bed.wav"):
		var bed: AudioStreamWAV = load(DIR + "crowd_bed.wav").duplicate()
		bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
		bed.loop_end = int(bed.get_length() * bed.mix_rate)
		_bed.stream = bed


## Character ids from the balance data.
func _character_ids() -> Array:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var ids := []
	if data is Dictionary:
		for c in data.get("characters", []):
			ids.append(str(c.id))
	return ids


## Plays a cue or sound. pitch scales every layer (bounces and catches vary
## it), volume is in decibels, pan runs -1 (left of the court) to 1 (right).
## With a character id, that character's own takes are used where they have
## them.
func play(sound: String, pitch := 1.0, volume_db := 0.0, pan := 0.0, character := "") -> void:
	var layers: Array = CUES.get(sound, [[sound, 0.0, 0.0]])
	var own: Dictionary = _character_streams.get(character, {})
	for layer in layers:
		var takes: Array = own.get(layer[0], _streams.get(layer[0], []))
		if takes.is_empty():
			push_warning("Unknown sound: " + str(layer[0]))
			continue
		var p := _players[_next]
		_next = (_next + 1) % POOL_SIZE
		p.stream = takes[randi() % takes.size()]
		p.pitch_scale = pitch * (1.0 + randf_range(-layer[2], layer[2]))
		p.volume_db = volume_db + float(layer[1]) + randf_range(-1.0, 1.0) * (1.0 if layer[2] > 0.0 else 0.0) \
			+ EFFECTS_GAIN_DB + linear_to_db(maxf(Settings.sfx_volume, 0.0001))
		var size := get_viewport().get_visible_rect().size
		p.position = Vector2(size.x * (0.5 + clampf(pan, -1.0, 1.0) * 0.45), size.y * 0.5)
		p.play()


## The crowd murmur under a match; fades rather than cutting.
func set_crowd(on: bool) -> void:
	if _bed.stream == null:
		return
	var target := BED_DB + linear_to_db(maxf(Settings.sfx_volume, 0.0001)) if on else -60.0
	if on and not _bed.playing:
		_bed.volume_db = -60.0
		_bed.play()
	var tw := create_tween()
	tw.tween_property(_bed, "volume_db", target, 0.8)
	if not on:
		tw.tween_callback(_bed.stop)
