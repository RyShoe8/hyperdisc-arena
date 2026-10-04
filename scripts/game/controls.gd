## Player input (autoload "Controls"). Polls controllers and keyboard once
## per physics tick, before the match runs, and turns them into the sim's
## input Dictionaries. Controllers are read directly by device id rather than
## through InputMap, so slots survive unplugging and replugging.
##
## Slots: player 1 = first controller + WASD/J/K/Esc or Enter,
##        player 2 = second controller + arrows/Numpad1/Numpad2/Backspace.
## Controller: left stick or D-pad = move/aim, A = throw/dash, B = lob,
##             X = throw/dash, Y = lob (alternates), Start = pause.
extends Node

signal changed(message: String)

const PLAYERS := 2
## Stick travel ignored around the centre, to stop drift on worn sticks.
const DEADZONE := 0.35

const KEYS := [
	{"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D,
		"a": KEY_J, "b": KEY_K, "start": KEY_ESCAPE, "start2": KEY_ENTER},
	{"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"a": KEY_KP_1, "b": KEY_KP_2, "start": KEY_BACKSPACE, "start2": KEY_KP_ENTER},
]
const PAD_A := [JOY_BUTTON_A, JOY_BUTTON_X]
const PAD_B := [JOY_BUTTON_B, JOY_BUTTON_Y]

## Controller device id per player slot, or -1 when the slot has none.
var pads: Array[int] = [-1, -1]
## True when the player last touched a controller rather than the keyboard,
## so on-screen prompts can show the right buttons.
var using_pad: Array[bool] = [false, false]

var _now: Array[Dictionary] = [{}, {}]
var _prev: Array[Dictionary] = [{}, {}]
## Every connected controller's state, slotted or not, by device id.
## Menus read these so any controller can drive them.
var _pad_now := {}
var _pad_prev := {}
## Controllers seen sending input, even if the platform never announced them.
var _seen := {}
## Last raw controller event, shown on the menu for troubleshooting.
var last_raw := "none yet"


func _ready() -> void:
	process_physics_priority = -100  # poll before anything reads input
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_assign(device, false)


func _physics_process(_delta: float) -> void:
	_pad_prev = _pad_now
	_pad_now = {}
	var devices := Input.get_connected_joypads()
	for device in _seen:
		if device not in devices:
			devices.append(device)
	for device in devices:
		_pad_now[device] = _pad_state(device)
	for i in PLAYERS:
		_prev[i] = _now[i]
		_now[i] = _sample(i)


## Some platforms (notably browsers) deliver controller input without ever
## announcing the controller. Register any controller the moment it sends
## something, so it still gets a player slot.
func _input(event: InputEvent) -> void:
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


## One line describing detected controllers, for the menu.
func diagnostics() -> String:
	var names := []
	for device in _pad_now:
		var slot := pads.find(device)
		names.append("%s [%s]" % [Input.get_joy_name(device),
			"P%d" % (slot + 1) if slot >= 0 else "no slot"])
	if names.is_empty():
		names.append("no controllers detected")
	return "Controllers: %s   |   last input: %s" % [", ".join(names), last_raw]


# --- Queries ---------------------------------------------------------------

## The sim input for this tick.
func input(player: int) -> Dictionary:
	var s := _now[player]
	return {"x": s.get("x", 0), "y": s.get("y", 0),
		"a": pressed(player, "a"), "b": pressed(player, "b")}


## True on the tick a button ("a", "b" or "start") goes down.
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
		var now: Dictionary = _pad_now[device]
		var prev: Dictionary = _pad_prev.get(device, {})
		var x: int = now.x if now.x != prev.get("x", 0) else 0
		var y: int = now.y if now.y != prev.get("y", 0) else 0
		if x != 0 or y != 0:
			return Vector2i(x, y)
	return Vector2i.ZERO


## The controller that just pressed this button, -2 for a keyboard, or -1
## if nothing did. Lets any controller confirm in menus.
func menu_pressed(button: String) -> int:
	for device in _pad_now:
		if _pad_now[device].get(button, false) and not _pad_prev.get(device, {}).get(button, false):
			return device
	for i in PLAYERS:
		if _keys_pressed(i, button):
			return -2
	return -1


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
	return Input.get_joy_name(pads[player]) if has_pad(player) else "Keyboard"


## Short rumble on this player's controller. Strengths are 0..1.
func rumble(player: int, weak: float, strong: float, seconds: float) -> void:
	if has_pad(player):
		Input.start_joy_vibration(pads[player], clampf(weak, 0, 1), clampf(strong, 0, 1), seconds)


## Button labels for prompts, following the device the player last used.
## PlayStation controllers get Cross/Circle/Options instead of A/B/Start.
func label(player: int, button: String) -> String:
	if using_pad[player]:
		if is_playstation(player):
			return {"a": "Cross", "b": "Circle", "start": "Options", "move": "Stick"}[button]
		return {"a": "A", "b": "B", "start": "Start", "move": "Stick"}[button]
	if player == 0:
		return {"a": "J", "b": "K", "start": "Esc", "move": "WASD"}[button]
	return {"a": "Num1", "b": "Num2", "start": "Backspace", "move": "Arrows"}[button]


func is_playstation(player: int) -> bool:
	if not has_pad(player):
		return false
	var name := Input.get_joy_name(pads[player]).to_lower()
	for hint in ["playstation", "dualsense", "dualshock", "ps4", "ps5", "sony", "wireless controller"]:
		if hint in name:
			return true
	return false


# --- Sampling --------------------------------------------------------------

func _sample(player: int) -> Dictionary:
	var keys: Dictionary = KEYS[player]
	var kb := Vector2(
		int(Input.is_physical_key_pressed(keys.right)) - int(Input.is_physical_key_pressed(keys.left)),
		int(Input.is_physical_key_pressed(keys.down)) - int(Input.is_physical_key_pressed(keys.up)))
	var kb_a := Input.is_physical_key_pressed(keys.a)
	var kb_b := Input.is_physical_key_pressed(keys.b)
	var kb_start := Input.is_physical_key_pressed(keys.start) \
		or Input.is_physical_key_pressed(keys.start2)

	var pad: Dictionary = _pad_now.get(pads[player], {}) if pads[player] >= 0 else {}
	var stick := Vector2(pad.get("x", 0), pad.get("y", 0))
	var pad_a: bool = pad.get("a", false)
	var pad_b: bool = pad.get("b", false)
	var pad_start: bool = pad.get("start", false)

	if stick != Vector2.ZERO or pad_a or pad_b or pad_start:
		using_pad[player] = true
	elif kb != Vector2.ZERO or kb_a or kb_b or kb_start:
		using_pad[player] = false

	var dir := Vector2i(stick) if stick != Vector2.ZERO else snap8(kb)
	return {"x": dir.x, "y": dir.y, "a": pad_a or kb_a, "b": pad_b or kb_b,
		"start": pad_start or kb_start, "kb_a": kb_a, "kb_b": kb_b, "kb_start": kb_start}


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
	var a := false
	var b := false
	for button in PAD_A:
		a = a or Input.is_joy_button_pressed(device, button)
	for button in PAD_B:
		b = b or Input.is_joy_button_pressed(device, button)
	return {"x": dir.x, "y": dir.y, "a": a, "b": b,
		"start": Input.is_joy_button_pressed(device, JOY_BUTTON_START)}


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
				changed.emit("Player %d: %s connected" % [i + 1, Input.get_joy_name(device)])
			return
