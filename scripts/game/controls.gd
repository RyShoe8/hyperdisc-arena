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

const PLAYERS := 2
## Stick travel ignored around the centre, to stop drift on worn sticks.
const DEADZONE := 0.35
## Device ids for virtual (phone) controllers; real pads are far below this.
const VIRTUAL_BASE := 1000
## Rebindable actions, in the order the options menu lists them.
const ACTIONS := ["a", "b", "jump", "slap", "start"]
const ACTION_NAMES := {
	"a": "THROW / DASH / BLOCK", "b": "LOB / DROP SHOT", "jump": "JUMP",
	"slap": "SLAP / EX SHOT", "start": "PAUSE",
}
const MOVE_KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT},
]
const DEFAULT_KEYS := [
	{"a": [KEY_J], "b": [KEY_K], "jump": [KEY_L], "slap": [KEY_I], "start": [KEY_ESCAPE, KEY_ENTER]},
	{"a": [KEY_KP_1], "b": [KEY_KP_2], "jump": [KEY_KP_3], "slap": [KEY_KP_5],
		"start": [KEY_BACKSPACE, KEY_KP_ENTER]},
]
const DEFAULT_PAD := {
	"a": [JOY_BUTTON_A], "b": [JOY_BUTTON_B], "jump": [JOY_BUTTON_X],
	"slap": [JOY_BUTTON_Y, JOY_BUTTON_RIGHT_SHOULDER], "start": [JOY_BUTTON_START],
}

## Controller device id per player slot, or -1 when the slot has none.
var pads: Array[int] = [-1, -1]
## True when the player last touched a controller rather than the keyboard,
## so on-screen prompts can show the right buttons.
var using_pad: Array[bool] = [false, false]
## bindings[player] = {"keys": {action: [keycodes]}, "pad": {action: [buttons]}}
var bindings: Array = []

var _now: Array[Dictionary] = [{}, {}]
var _prev: Array[Dictionary] = [{}, {}]
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
		bindings.append({"keys": DEFAULT_KEYS[i].duplicate(true), "pad": DEFAULT_PAD.duplicate(true)})


func get_bindings() -> Dictionary:
	return {"players": bindings.duplicate(true)}


func set_bindings(data: Dictionary) -> void:
	var players = data.get("players", null)
	if not players is Array or players.size() != PLAYERS:
		return
	reset_bindings()
	for i in PLAYERS:
		for kind in ["keys", "pad"]:
			var src = players[i].get(kind, {})
			for action in ACTIONS:
				if src is Dictionary and src.get(action) is Array and not src[action].is_empty():
					bindings[i][kind][action] = src[action].duplicate()


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


## Some platforms (notably browsers) deliver controller input without ever
## announcing the controller. Register any controller the moment it sends
## something, so it still gets a player slot.
func _input(event: InputEvent) -> void:
	if capturing():
		_try_capture(event)
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
	return {"x": s.get("x", 0), "y": s.get("y", 0),
		"a": pressed(player, "a"), "b": pressed(player, "b"),
		"jump": pressed(player, "jump"), "slap": pressed(player, "slap"),
		"a_down": s.get("a", false), "b_down": s.get("b", false)}


## True on the tick a button goes down.
func pressed(player: int, button: String) -> bool:
	return _now[player].get(button, false) and not _prev[player].get(button, false)


## A direction that was just pushed (for menus); zero otherwise.
func nudged(player: int) -> Vector2i:
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
	for i in [0] if only_player_one else range(PLAYERS):
		var n := nudged(i)
		if n != Vector2i.ZERO:
			return n
	for device in _pad_now:
		if only_player_one and device == pads[1]:
			continue
		var n := pad_nudged(device)
		if n != Vector2i.ZERO:
			return n
	return Vector2i.ZERO


func pad_nudged(device: int) -> Vector2i:
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


## Any key or button at all (title screen).
func anything_pressed() -> bool:
	for button in ACTIONS:
		if menu_pressed(button) != -1:
			return true
	return false


## Makes this controller player 1, moving any previous player-1 controller
## to player 2. Called with the controller that starts a match.
func make_player_one(device: int) -> void:
	if device < 0 or pads[0] == device:
		return
	var old := pads[0]
	if pads[1] == device:
		pads[1] = old
	elif pads[1] < 0:
		pads[1] = old
	pads[0] = device
	using_pad[0] = true
	_prev[0] = {}
	_now[0] = {}


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
		JOY_BUTTON_BACK: "BACK", JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3"}
	var ps := {JOY_BUTTON_A: "CROSS", JOY_BUTTON_B: "CIRCLE", JOY_BUTTON_X: "SQUARE",
		JOY_BUTTON_Y: "TRIANGLE", JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
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

func _sample(player: int) -> Dictionary:
	var mk: Dictionary = MOVE_KEYS[player]
	var kb := Vector2(
		int(Input.is_physical_key_pressed(mk.right)) - int(Input.is_physical_key_pressed(mk.left)),
		int(Input.is_physical_key_pressed(mk.down)) - int(Input.is_physical_key_pressed(mk.up)))
	var keys_down := {}
	for action in ACTIONS:
		var down := false
		for code in bindings[player].keys[action]:
			down = down or Input.is_physical_key_pressed(code)
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
	var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device, JOY_AXIS_LEFT_Y))
	if stick.length() < DEADZONE:
		stick = Vector2.ZERO
	var dpad := Vector2(
		int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT))
			- int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT)),
		int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN))
			- int(Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP)))
	if dpad != Vector2.ZERO:
		stick = dpad
	var dir := snap8(stick)
	var buttons := {}
	for b in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK,
			JOY_BUTTON_RIGHT_STICK]:
		buttons[b] = Input.is_joy_button_pressed(device, b)
	# Menus use the default layout on any controller, whatever the bindings:
	# bottom face button confirms, right face button goes back.
	return {"x": dir.x, "y": dir.y, "buttons": buttons,
		"a": buttons[JOY_BUTTON_A], "b": buttons[JOY_BUTTON_B], "jump": buttons[JOY_BUTTON_X],
		"slap": buttons[JOY_BUTTON_Y], "start": buttons[JOY_BUTTON_START]}


func _virtual_state(device: int) -> Dictionary:
	var v: Dictionary = _virtual[device]
	var stick: Vector2 = v.axes
	if stick.length() < DEADZONE:
		stick = Vector2.ZERO
	var b: Dictionary = v.buttons.duplicate()
	for k in v.latched:
		b[k] = true
	v.latched = {}
	var dpad := Vector2(int(b.get(JOY_BUTTON_DPAD_RIGHT, false)) - int(b.get(JOY_BUTTON_DPAD_LEFT, false)),
		int(b.get(JOY_BUTTON_DPAD_DOWN, false)) - int(b.get(JOY_BUTTON_DPAD_UP, false)))
	if dpad != Vector2.ZERO:
		stick = dpad
	var dir := snap8(stick)
	var buttons := {}
	for k in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_LEFT_SHOULDER,
			JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_LEFT_STICK,
			JOY_BUTTON_RIGHT_STICK]:
		buttons[k] = b.get(k, false)
	return {"x": dir.x, "y": dir.y, "buttons": buttons,
		"a": buttons[JOY_BUTTON_A], "b": buttons[JOY_BUTTON_B], "jump": buttons[JOY_BUTTON_X],
		"slap": buttons[JOY_BUTTON_Y], "start": buttons[JOY_BUTTON_START]}


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
