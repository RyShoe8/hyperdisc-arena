## Player input (autoload "Controls"). Polls controllers and keyboard once
## per physics tick, before the match runs, and turns them into the sim's
## input Dictionaries. Controllers are read directly by device id rather than
## through InputMap, so slots survive unplugging and replugging.
##
## Slots: player 1 = first controller + its keyboard keys,
##        player 2 = second controller + its keyboard keys.
## Phones used as controllers (PlayBound) arrive as virtual controllers with
## ids from VIRTUAL_BASE up, and take a slot like a plugged-in pad.
## Every action can be rebound per player, for controller and keyboard,
## from the options menu. Movement is always the left stick or D-pad (pad)
## and the player's four direction keys (keyboard).
extends Node

signal changed(message: String)

const PLAYERS := 4
## Stick travel ignored around the centre, to stop drift on worn sticks.
## Movement starts past DEADZONE and only stops below DEADZONE_RELEASE, so a
## stick resting near the edge doesn't flicker between moving and stopping.
const DEADZONE := 0.27
const DEADZONE_RELEASE := 0.2
## Analog running within this many degrees of straight or an exact diagonal
## snaps onto it, so lining up on the disc is easy.
const SNAP_DEGREES := 8.0
## Device ids for virtual (phone) controllers; real pads are far below this.
const VIRTUAL_BASE := 1000
## Rebindable actions, in the order the options menu lists them.
const ACTIONS := ["a", "slap", "power", "b", "dive", "curve_left", "curve_right", "utility", "start"]
const ACTION_NAMES := {
	"a": "THROW / POP UP", "slap": "SLAP", "power": "POWER MOVE", "b": "LOB / DROP SHOT",
	"dive": "DIVE", "curve_left": "CURVE LEFT", "curve_right": "CURVE RIGHT",
	"utility": "MENU ACTION", "start": "PAUSE",
}
## The analog triggers, bindable like buttons (ids past every real button).
const TRIGGER_LEFT := 200
const TRIGGER_RIGHT := 201
## How far a trigger must be pulled to count as pressed.
const TRIGGER_PRESS := 0.5
const MOVE_KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT},
]
const DEFAULT_KEYS := [
	{"a": [KEY_J], "slap": [KEY_I], "power": [KEY_H], "b": [KEY_K], "dive": [KEY_L],
		"curve_left": [KEY_U], "curve_right": [KEY_O], "utility": [KEY_L], "start": [KEY_ESCAPE, KEY_ENTER]},
	{"a": [KEY_KP_1], "slap": [KEY_KP_5], "power": [KEY_KP_0], "b": [KEY_KP_2], "dive": [KEY_KP_3],
		"curve_left": [KEY_KP_4], "curve_right": [KEY_KP_6], "utility": [KEY_KP_3],
		"start": [KEY_BACKSPACE, KEY_KP_ENTER]},
]
## A throws and pops up, B lobs, X is the power move, Y slaps, the shoulders
## curve and the right trigger dives. Menu action shares X (menus only).
const DEFAULT_PAD := {
	"a": [JOY_BUTTON_A], "slap": [JOY_BUTTON_Y], "power": [JOY_BUTTON_X], "b": [JOY_BUTTON_B],
	"dive": [TRIGGER_RIGHT], "curve_left": [JOY_BUTTON_LEFT_SHOULDER],
	"curve_right": [JOY_BUTTON_RIGHT_SHOULDER], "utility": [JOY_BUTTON_X], "start": [JOY_BUTTON_START],
}

## Controller device id per player slot, or -1 when the slot has none.
var pads: Array[int] = [-1, -1, -1, -1]
## True when the player last touched a controller rather than the keyboard,
## so on-screen prompts can show the right buttons.
var using_pad: Array[bool] = [false, false, false, false]
## bindings[player] = {"keys": {action: [keycodes]}, "pad": {action: [buttons]}}
var bindings: Array = []

var _now: Array[Dictionary] = [{}, {}, {}, {}]
var _prev: Array[Dictionary] = [{}, {}, {}, {}]
## Every connected controller's state, slotted or not, by device id.
## Menus read these so any controller can drive them.
var _pad_now := {}
var _pad_prev := {}
## Controllers seen sending input, even if the platform never announced them.
var _seen := {}
## Virtual controllers by device id: {"name", "axes": Vector2, "buttons": {JOY_BUTTON_*: bool}}.
var _virtual := {}
## Last raw controller event, shown on the menu for troubleshooting.
var last_raw := "none yet"
## While rebinding, the next key or button press is captured instead of used.
var _capture := {}
## Presses seen as events since the last tick. Buttons are polled once per
## tick, so a tap that goes down and up in between would otherwise be lost.
var _key_latch := {}  # physical keycode -> true
var _pad_latch := {}  # device -> {button: true}
## Whether each controller's stick is currently past the deadzone.
var _stick_on := {}
## Fixed menu keys, whatever the bindings: Enter / Space select, Escape /
## Backspace go back, Tab is the menus' extra action.
const MENU_KEYS := {"confirm": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], "back": [KEY_ESCAPE, KEY_BACKSPACE],
	"extra": [KEY_TAB]}
var _menu_keys_now := {}
var _menu_keys_prev := {}
## Set when a text field used the keys this tick, so they don't also act
## on the menu underneath.
var _swallow_menu_keys := false
## Menu auto-repeat: holding a direction repeats it after REPEAT_DELAY
## ticks, then every REPEAT_RATE ticks.
const REPEAT_DELAY := 22
const REPEAT_RATE := 6
const MENU_STICK_THRESHOLD := 0.55
const MENU_REPEAT_DELAY := 28
const MENU_REPEAT_RATE := 11
var _held := [[Vector2i.ZERO, 0], [Vector2i.ZERO, 0], [Vector2i.ZERO, 0], [Vector2i.ZERO, 0]]  # per player: [direction, ticks]
var _pad_held := {}  # device -> [direction, ticks]
var _menu_key_held := [[Vector2i.ZERO, 0], [Vector2i.ZERO, 0]]
var _menu_pad_held := {}
var _menu_wait_release := false


func _init() -> void:
	reset_bindings()


func _ready() -> void:
	process_physics_priority = -100  # poll before anything reads input
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_assign(device, false)


func reset_bindings() -> void:
	bindings = []
	for i in PLAYERS:
		# Players 3 and 4 have no keyboard keys by default, only controllers.
		var keys: Dictionary = DEFAULT_KEYS[i].duplicate(true) if i < 2 else {}
		if i >= 2:
			for action in ACTIONS:
				keys[action] = []
		bindings.append({"keys": keys, "pad": DEFAULT_PAD.duplicate(true)})


func get_bindings() -> Dictionary:
	return {"players": bindings.duplicate(true)}


func set_bindings(data: Dictionary) -> void:
	var players = data.get("players", null)
	if not players is Array or players.size() not in [2, PLAYERS]:
		return
	reset_bindings()
	for i in players.size():
		for kind in ["keys", "pad"]:
			var src = players[i].get(kind, {})
			for action in ACTIONS:
				if src is Dictionary and src.get(action) is Array and not src[action].is_empty():
					bindings[i][kind][action] = src[action].duplicate()
			if not src is Dictionary:
				continue
			# Curve high / low became Curve Left / Right on the same buttons.
			for pair in [["curve_high", "curve_left"], ["curve_low", "curve_right"]]:
				if not src.has(pair[1]) and src.get(pair[0]) is Array and not src[pair[0]].is_empty():
					bindings[i][kind][pair[1]] = src[pair[0]].duplicate()
			# Saves from before the curve buttons had RB on slap: it's a curve
			# button now, so take it off slap unless that would leave it empty.
			if kind == "pad" and not src.has("curve_low") and not src.has("curve_right"):
				var slap: Array = bindings[i].pad.slap
				if slap.size() > 1:
					slap.erase(JOY_BUTTON_RIGHT_SHOULDER)


## Starts capturing the next key ("keys") or controller button ("pad") for
## a player's action. Escape / the pad's Start cancels.
func capture(player: int, kind: String, action: String) -> void:
	_capture = {"player": player, "kind": kind, "action": action, "done": false}


func capturing() -> bool:
	return not _capture.is_empty() and not _capture.done


func capture_finished() -> bool:
	return not _capture.is_empty() and _capture.done


func end_capture() -> void:
	_capture = {}


func _physics_process(_delta: float) -> void:
	_pad_prev = _pad_now
	_pad_now = {}
	var devices := Input.get_connected_joypads()
	for device in _seen:
		if device not in devices:
			devices.append(device)
	for device in devices:
		_pad_now[device] = _pad_state(device)
	for device in _virtual:
		_pad_now[device] = _virtual_state(device)
	for i in PLAYERS:
		_prev[i] = _now[i]
		_now[i] = _sample(i)
		_held[i] = _hold(_held[i], Vector2i(_now[i].get("x", 0), _now[i].get("y", 0)))
	for device in _pad_now:
		_pad_held[device] = _hold(_pad_held.get(device, [Vector2i.ZERO, 0]),
			Vector2i(_pad_now[device].get("x", 0), _pad_now[device].get("y", 0)))
		_menu_pad_held[device] = _hold(_menu_pad_held.get(device, [Vector2i.ZERO, 0]),
			_menu_pad_direction(_pad_now[device]))
	for i in 2:
		var mk: Dictionary = MOVE_KEYS[i]
		var keys := Vector2i(int(_key(mk.right)) - int(_key(mk.left)),
			int(_key(mk.down)) - int(_key(mk.up)))
		_menu_key_held[i] = _hold(_menu_key_held[i], keys)
	_menu_keys_prev = _menu_keys_now
	_menu_keys_now = {}
	for kind in MENU_KEYS:
		for code in MENU_KEYS[kind]:
			if _key(code):
				_menu_keys_now[code] = true
	if _swallow_menu_keys:
		_swallow_menu_keys = false
		_menu_keys_prev = _menu_keys_now.duplicate()
	_key_latch.clear()
	_pad_latch.clear()


static func _hold(held: Array, dir: Vector2i) -> Array:
	return [dir, held[1] + 1 if dir == held[0] and dir != Vector2i.ZERO else 0]


static func _repeats(held: Array) -> bool:
	var t: int = held[1]
	return t >= REPEAT_DELAY and (t - REPEAT_DELAY) % REPEAT_RATE == 0


func reset_menu_navigation() -> void:
	# A held stick must return to neutral before it can move a newly opened menu.
	_menu_wait_release = true


static func _menu_nudge(held: Array) -> Vector2i:
	var direction: Vector2i = held[0]
	var ticks: int = held[1]
	if direction != Vector2i.ZERO and (ticks == 0 or
		(ticks >= MENU_REPEAT_DELAY and (ticks - MENU_REPEAT_DELAY) % MENU_REPEAT_RATE == 0)):
		return direction
	return Vector2i.ZERO


static func _menu_pad_direction(pad: Dictionary) -> Vector2i:
	var buttons: Dictionary = pad.get("buttons", {})
	var dpad := Vector2i(
		int(buttons.get(JOY_BUTTON_DPAD_RIGHT, false)) - int(buttons.get(JOY_BUTTON_DPAD_LEFT, false)),
		int(buttons.get(JOY_BUTTON_DPAD_DOWN, false)) - int(buttons.get(JOY_BUTTON_DPAD_UP, false)))
	if dpad != Vector2i.ZERO:
		return dpad
	var stick: Vector2 = pad.get("analog", Vector2.ZERO)
	return snap8(stick) if stick.length() >= MENU_STICK_THRESHOLD else Vector2i.ZERO


## Some platforms (notably browsers) deliver controller input without ever
## announcing the controller. Register any controller the moment it sends
## something, so it still gets a player slot.
func _input(event: InputEvent) -> void:
	if capturing():
		_try_capture(event)
	if event is InputEventKey and event.pressed and not event.echo:
		_key_latch[event.physical_keycode] = true
	elif event is InputEventJoypadButton and event.pressed:
		if not _pad_latch.has(event.device):
			_pad_latch[event.device] = {}
		_pad_latch[event.device][event.button_index] = true
	elif event is InputEventJoypadMotion and event.axis_value >= TRIGGER_PRESS \
			and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		if not _pad_latch.has(event.device):
			_pad_latch[event.device] = {}
		_pad_latch[event.device][TRIGGER_LEFT if event.axis == JOY_AXIS_TRIGGER_LEFT else TRIGGER_RIGHT] = true
	if event is InputEventJoypadButton:
		last_raw = "device %d button %d %s" % [event.device, event.button_index,
			"down" if event.pressed else "up"]
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		last_raw = "device %d axis %d %.2f" % [event.device, event.axis, event.axis_value]
	else:
		return
	if not _seen.has(event.device):
		_seen[event.device] = true
		_assign(event.device, true)


func _try_capture(event: InputEvent) -> void:
	var c := _capture
	if c.kind == "keys" and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode != KEY_ESCAPE or c.action == "start":
			bindings[c.player].keys[c.action] = [event.physical_keycode]
		c.done = true
		get_viewport().set_input_as_handled()
	elif c.kind == "pad" and event is InputEventJoypadButton and event.pressed:
		if event.button_index != JOY_BUTTON_START or c.action == "start":
			bindings[c.player].pad[c.action] = [event.button_index]
		c.done = true
		get_viewport().set_input_as_handled()
	elif c.kind == "pad" and event is InputEventJoypadMotion and event.axis_value >= TRIGGER_PRESS \
			and event.axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		bindings[c.player].pad[c.action] = [TRIGGER_LEFT if event.axis == JOY_AXIS_TRIGGER_LEFT else TRIGGER_RIGHT]
		c.done = true
		get_viewport().set_input_as_handled()


## One line describing detected controllers, for the menu.
func diagnostics() -> String:
	var names := []
	for device in _pad_now:
		var slot := pads.find(device)
		names.append("%s [%s]" % [joy_name(device),
			"P%d" % (slot + 1) if slot >= 0 else "no slot"])
	if names.is_empty():
		names.append("no controllers detected")
	return "Controllers: %s   |   last input: %s" % [", ".join(names), last_raw]


# --- Queries ---------------------------------------------------------------

## The sim input for this tick.
func input(player: int) -> Dictionary:
	var s := _now[player]
	return {"x": s.get("x", 0), "y": s.get("y", 0), "ma": s.get("ma", 0),
		"a": pressed(player, "a"), "b": pressed(player, "b"), "slap": pressed(player, "slap"),
		"power": pressed(player, "power"), "dive": pressed(player, "dive"),
		"curve_left": pressed(player, "curve_left") or (pressed(player, "a") and s.get("curve_left", false)),
		"curve_right": pressed(player, "curve_right") or (pressed(player, "a") and s.get("curve_right", false))}


## True on the tick a button goes down.
func pressed(player: int, button: String) -> bool:
	return _now[player].get(button, false) and not _prev[player].get(button, false)


## A direction that was just pushed, or is held long enough to repeat (for
## menus); zero otherwise.
func nudged(player: int) -> Vector2i:
	if _repeats(_held[player]):
		return _held[player][0]
	var x: int = _now[player].get("x", 0)
	var y: int = _now[player].get("y", 0)
	var px: int = _prev[player].get("x", 0)
	var py: int = _prev[player].get("y", 0)
	return Vector2i(x if x != px else 0, y if y != py else 0)


func any_pressed(button: String) -> bool:
	for i in PLAYERS:
		if pressed(i, button):
			return true
	return false


## A direction just pushed on any keyboard or any controller (for menus).
## With only_player_one, player 2's slot is left out (they pick separately).
func menu_nudged(only_player_one := false) -> Vector2i:
	if _menu_wait_release:
		for held in _menu_key_held:
			if held[0] != Vector2i.ZERO:
				return Vector2i.ZERO
		for held in _menu_pad_held.values():
			if held[0] != Vector2i.ZERO:
				return Vector2i.ZERO
		_menu_wait_release = false
		return Vector2i.ZERO
	for i in [0] if only_player_one else range(2):
		var n := _menu_nudge(_menu_key_held[i])
		if n != Vector2i.ZERO:
			return n
	for device in _menu_pad_held:
		if only_player_one and device == pads[1]:
			continue
		var n := _menu_nudge(_menu_pad_held[device])
		if n != Vector2i.ZERO:
			return n
	return Vector2i.ZERO


func pad_nudged(device: int) -> Vector2i:
	if _repeats(_pad_held.get(device, [Vector2i.ZERO, 0])):
		return _pad_held[device][0]
	var now: Dictionary = _pad_now.get(device, {})
	var prev: Dictionary = _pad_prev.get(device, {})
	var x: int = now.get("x", 0) if now.get("x", 0) != prev.get("x", 0) else 0
	var y: int = now.get("y", 0) if now.get("y", 0) != prev.get("y", 0) else 0
	return Vector2i(x, y)


## The controller that just pressed this button, -2 for a keyboard, or -1
## if nothing did. Lets any controller confirm in menus.
func menu_pressed(button: String) -> int:
	if capturing():
		return -1
	for device in _pad_now:
		if _pad_now[device].get(button, false) and not _pad_prev.get(device, {}).get(button, false):
			return device
	for i in PLAYERS:
		if _keys_pressed(i, button):
			return -2
	return -1


## True on the tick a fixed menu key ("confirm", "back" or "extra") goes down.
func menu_key(kind: String) -> bool:
	if capturing():
		return false
	for code in MENU_KEYS[kind]:
		if _menu_keys_now.has(code) and not _menu_keys_prev.has(code):
			return true
	return false


## Like menu_pressed, but controllers only (their Start selects in menus;
## the keyboard's Start keys are Escape and Enter, which have menu roles).
func menu_pad_pressed(button: String) -> int:
	if capturing():
		return -1
	for device in _pad_now:
		if _pad_now[device].get(button, false) and not _pad_prev.get(device, {}).get(button, false):
			return device
	return -1


## A text field just used Enter or Escape: keep them off the menu this tick.
func swallow_menu_keys() -> void:
	_swallow_menu_keys = true
	_menu_keys_prev = _menu_keys_now.duplicate()
	for kind in MENU_KEYS:
		for code in MENU_KEYS[kind]:
			_menu_keys_prev[code] = true


## Any key or button at all (title screen).
func anything_pressed() -> bool:
	for button in ACTIONS:
		if menu_pressed(button) != -1:
			return true
	return false


## Give a solo mode to the controller that selected it, swapping its previous
## slot with player 1. Keep current samples so the menu press is not replayed.
func make_player_one(device: int) -> void:
	if device < 0 or pads[0] == device:
		return
	var previous_slot := pads.find(device)
	var old := pads[0]
	if previous_slot < 0:
		for slot in range(1, PLAYERS):
			if pads[slot] < 0:
				previous_slot = slot
				break
	if previous_slot > 0:
		pads[previous_slot] = old
	pads[0] = device
	for slot in [0, previous_slot]:
		if slot < 0:
			continue
		using_pad[slot] = pads[slot] >= 0
		_now[slot] = _sample(slot)
		_prev[slot] = _now[slot].duplicate()
		_held[slot] = [Vector2i.ZERO, 0]


func has_pad(player: int) -> bool:
	return pads[player] >= 0


func pad_name(player: int) -> String:
	return joy_name(pads[player]) if has_pad(player) else "Keyboard"


func joy_name(device: int) -> String:
	if _virtual.has(device):
		return _virtual[device].name
	return Input.get_joy_name(device)


# --- Virtual controllers (phones) -----------------------------------------

## Adds or updates a virtual controller. axes is the left stick (-1..1, down
## positive); buttons maps JOY_BUTTON_* to pressed.
func set_virtual_pad(device: int, name: String, axes: Vector2, buttons: Dictionary) -> void:
	var is_new := not _virtual.has(device)
	# A press and release can both arrive between two ticks (a quick tap);
	# latch presses until a tick has seen them so no tap is lost.
	var latched: Dictionary = {} if is_new else _virtual[device].latched
	for b in buttons:
		if buttons[b]:
			latched[b] = true
	_virtual[device] = {"name": name, "axes": axes, "buttons": buttons, "latched": latched}
	if is_new:
		_assign(device, true)


func remove_virtual_pad(device: int) -> void:
	if _virtual.erase(device):
		_on_joy_connection_changed(device, false)


func virtual_pads() -> Array:
	return _virtual.keys()


func is_virtual(device: int) -> bool:
	return _virtual.has(device)


## Short rumble on this player's controller. Strengths are 0..1.
func rumble(player: int, weak: float, strong: float, seconds: float) -> void:
	if has_pad(player) and not is_virtual(pads[player]):
		Input.start_joy_vibration(pads[player], clampf(weak, 0, 1), clampf(strong, 0, 1), seconds)


## Button label for prompts, following the device the player last used.
func label(player: int, button: String) -> String:
	if button == "move":
		return "STICK" if using_pad[player] else ("WASD" if player == 0 else "ARROWS")
	if using_pad[player]:
		var b: Array = bindings[player].pad[button]
		return button_name(b[0], is_playstation(player)) if not b.is_empty() else "?"
	var k: Array = bindings[player].keys[button]
	return key_name(k[0]) if not k.is_empty() else "?"


static func key_name(code: int) -> String:
	return OS.get_keycode_string(code).to_upper()


static func button_name(button: int, playstation: bool) -> String:
	var xbox := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_START: "START",
		TRIGGER_LEFT: "LT", TRIGGER_RIGHT: "RT",
		JOY_BUTTON_BACK: "BACK", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"}
	var ps := {JOY_BUTTON_A: "CROSS", JOY_BUTTON_B: "CIRCLE", JOY_BUTTON_X: "SQUARE",
		JOY_BUTTON_Y: "TRIANGLE", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
		TRIGGER_LEFT: "L2", TRIGGER_RIGHT: "R2",
		JOY_BUTTON_START: "OPTIONS", JOY_BUTTON_BACK: "CREATE", JOY_BUTTON_LEFT_STICK: "L3",
		JOY_BUTTON_RIGHT_STICK: "R3"}
	var names := ps if playstation else xbox
	return names.get(button, "BUTTON %d" % button)


## True when prompts for this player should use PlayStation names (Cross,
## Circle...). Follows Options > Controls > Button labels, and on Auto looks
## at the controller actually plugged into the player's slot.
func is_playstation(player: int) -> bool:
	# Looked up at runtime: the headless tests load this script without the
	# Settings autoload.
	var settings := get_node_or_null("/root/Settings")
	var style: int = settings.button_labels if settings != null else 0
	if style != 0:
		return style == 2
	return has_pad(player) and _is_playstation_pad(pads[player])


## Controller detection is cached per device; it's cleared on hot-plug.
var _playstation_cache := {}


func _is_playstation_pad(device: int) -> bool:
	if is_virtual(device):
		return false  # the phone pad shows Xbox letters
	if not _playstation_cache.has(device):
		var info := Input.get_joy_info(device)
		var vendor := int(info.get("vendor_id", 0))
		var name := Input.get_joy_name(device) + " " + _browser_pad_id(device)
		_playstation_cache[device] = looks_like_playstation(name, vendor)
	return _playstation_cache[device]


const SONY_VENDOR := 0x054C


static func looks_like_playstation(name: String, vendor_id := 0) -> bool:
	if vendor_id == SONY_VENDOR:
		return true
	var n := name.to_lower()
	for hint in ["playstation", "dualsense", "dualshock", "ps3", "ps4", "ps5", "sony",
			"wireless controller", "054c"]:
		if hint in n:
			return true
	return false


## In a web build Godot reports a generic "Standard Gamepad Mapping" name, so
## ask the browser for the controller's real id (it includes the vendor).
func _browser_pad_id(device: int) -> String:
	if not OS.has_feature("web"):
		return ""
	var id = JavaScriptBridge.eval(
		"(function(){var p=navigator.getGamepads()[%d];return p?p.id:'';})()" % device, true)
	return str(id) if id != null else ""


# --- Sampling --------------------------------------------------------------

## A key held now, or tapped since the last tick.
func _key(code: int) -> bool:
	return Input.is_physical_key_pressed(code) or _key_latch.has(code)


## A controller button (or trigger) held now, or tapped since the last tick.
func _button(device: int, button: int) -> bool:
	if _pad_latch.get(device, {}).has(button):
		return true
	if button == TRIGGER_LEFT:
		return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) >= TRIGGER_PRESS
	if button == TRIGGER_RIGHT:
		return Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) >= TRIGGER_PRESS
	return Input.is_joy_button_pressed(device, button)


## Applies the deadzone (with hysteresis) to a controller's stick.
func _deadzone(device: int, stick: Vector2) -> Vector2:
	var on := stick.length() >= (DEADZONE_RELEASE if _stick_on.get(device, false) else DEADZONE)
	_stick_on[device] = on
	return stick if on else Vector2.ZERO


func _sample(player: int) -> Dictionary:
	var mk: Dictionary = MOVE_KEYS[player] if player < 2 else {"up": 0, "down": 0, "left": 0, "right": 0}
	var kb := Vector2(int(_key(mk.right)) - int(_key(mk.left)), int(_key(mk.down)) - int(_key(mk.up)))
	var keys_down := {}
	for action in ACTIONS:
		var down := false
		for code in bindings[player].keys[action]:
			down = down or _key(code)
		keys_down[action] = down

	var pad: Dictionary = _pad_now.get(pads[player], {}) if pads[player] >= 0 else {}
	var stick := Vector2(pad.get("x", 0), pad.get("y", 0))
	var pad_any := stick != Vector2.ZERO
	var kb_any := kb != Vector2.ZERO
	var out := {}
	for action in ACTIONS:
		var p: bool = _pad_action(pad, player, action)
		pad_any = pad_any or p
		kb_any = kb_any or keys_down[action]
		out[action] = p or keys_down[action]
		out["kb_" + action] = keys_down[action]
	if pad_any:
		using_pad[player] = true
	elif kb_any:
		using_pad[player] = false
	var dir := Vector2i(stick) if stick != Vector2.ZERO else snap8(kb)
	out["x"] = dir.x
	out["y"] = dir.y
	# The analog stick also moves freely (any angle); D-pad and keys stay 8-way.
	var raw: Vector2 = pad.get("analog", Vector2.ZERO)
	out["ma"] = angle_step(snap_angle(raw)) if stick != Vector2.ZERO else 0
	return out


func _pad_action(pad: Dictionary, player: int, action: String) -> bool:
	if pad.is_empty():
		return false
	var buttons: Dictionary = pad.get("buttons", {})
	for b in bindings[player].pad[action]:
		if buttons.get(b, false):
			return true
	return false


func _pad_state(device: int) -> Dictionary:
	var stick := _deadzone(device, Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)))
	var dpad := Vector2(
		int(_button(device, JOY_BUTTON_DPAD_RIGHT)) - int(_button(device, JOY_BUTTON_DPAD_LEFT)),
		int(_button(device, JOY_BUTTON_DPAD_DOWN)) - int(_button(device, JOY_BUTTON_DPAD_UP)))
	if dpad != Vector2.ZERO:
		stick = dpad
	var analog := stick if dpad == Vector2.ZERO else Vector2.ZERO
	var dir := snap8(stick)
	var buttons := {}
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK,
			JOY_BUTTON_RIGHT_STICK, TRIGGER_LEFT, TRIGGER_RIGHT]:
		buttons[b] = _button(device, b)
	# Menus use the default layout on any controller, whatever the bindings:
	# bottom face button confirms, right face button goes back.
	return {"x": dir.x, "y": dir.y, "analog": analog, "buttons": buttons,
		"a": buttons[JOY_BUTTON_A], "b": buttons[JOY_BUTTON_B], "utility": buttons[JOY_BUTTON_X],
		"slap": buttons[JOY_BUTTON_Y], "start": buttons[JOY_BUTTON_START]}


func _virtual_state(device: int) -> Dictionary:
	var v: Dictionary = _virtual[device]
	var stick := _deadzone(device, v.axes)
	var b: Dictionary = v.buttons.duplicate()
	for k in v.latched:
		b[k] = true
	v.latched = {}
	var dpad := Vector2(int(b.get(JOY_BUTTON_DPAD_RIGHT, false)) - int(b.get(JOY_BUTTON_DPAD_LEFT, false)),
		int(b.get(JOY_BUTTON_DPAD_DOWN, false)) - int(b.get(JOY_BUTTON_DPAD_UP, false)))
	if dpad != Vector2.ZERO:
		stick = dpad
	var analog := stick if dpad == Vector2.ZERO else Vector2.ZERO
	var dir := snap8(stick)
	var buttons := {}
	for k in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK,
			JOY_BUTTON_RIGHT_STICK, TRIGGER_LEFT, TRIGGER_RIGHT]:
		buttons[k] = b.get(k, false)
	return {"x": dir.x, "y": dir.y, "analog": analog, "buttons": buttons,
		"a": buttons[JOY_BUTTON_A], "b": buttons[JOY_BUTTON_B], "utility": buttons[JOY_BUTTON_X],
		"slap": buttons[JOY_BUTTON_Y], "start": buttons[JOY_BUTTON_START]}


## Snaps a stick direction onto straight or an exact diagonal when it's
## within SNAP_DEGREES of one; otherwise leaves it alone.
static func snap_angle(v: Vector2) -> Vector2:
	if v == Vector2.ZERO:
		return v
	var a := v.angle()
	var nearest := roundf(a / (PI / 4.0)) * (PI / 4.0)
	if absf(angle_difference(a, nearest)) <= deg_to_rad(SNAP_DEGREES):
		return Vector2.from_angle(nearest) * v.length()
	return v


## Movement angle step (1..48) for a stick vector, 0 when centred. Matches
## InputCodec.MOVE_ANGLES so it survives the network unchanged.
static func angle_step(v: Vector2) -> int:
	if v == Vector2.ZERO:
		return 0
	return posmod(int(round(v.angle() / (TAU / 48.0))), 48) + 1


func _keys_pressed(player: int, button: String) -> bool:
	var key := "kb_" + button
	return _now[player].get(key, false) and not _prev[player].get(key, false)


## Snaps an analog direction to one of 8 directions by angle, so diagonals
## (needed for quarter-circle curves) register as easily as straight ones.
static func snap8(v: Vector2) -> Vector2i:
	if v == Vector2.ZERO:
		return Vector2i.ZERO
	var octant := int(round(v.angle() / (PI / 4.0)))
	var a := octant * PI / 4.0
	return Vector2i(int(round(cos(a))), int(round(sin(a))))


# --- Hot-plugging ----------------------------------------------------------

func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_playstation_cache.erase(device)
	if connected:
		_assign(device, true)
		return
	for i in PLAYERS:
		if pads[i] == device:
			pads[i] = -1
			using_pad[i] = false
			changed.emit("Player %d controller disconnected" % (i + 1))


func _assign(device: int, announce: bool) -> void:
	if device in pads:
		return
	for i in PLAYERS:
		if pads[i] < 0:
			pads[i] = device
			using_pad[i] = true
			if announce:
				changed.emit("Player %d: %s connected" % [i + 1, joy_name(device)])
			return
