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


func _ready() -> void:
	process_physics_priority = -100  # poll before anything reads input
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	for device in Input.get_connected_joypads():
		_assign(device, false)


func _physics_process(_delta: float) -> void:
	for i in PLAYERS:
		_prev[i] = _now[i]
		_now[i] = _sample(i)


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


func has_pad(player: int) -> bool:
	return pads[player] >= 0


func pad_name(player: int) -> String:
	return Input.get_joy_name(pads[player]) if has_pad(player) else "Keyboard"


## Short rumble on this player's controller. Strengths are 0..1.
func rumble(player: int, weak: float, strong: float, seconds: float) -> void:
	if has_pad(player):
		Input.start_joy_vibration(pads[player], clampf(weak, 0, 1), clampf(strong, 0, 1), seconds)


## Button labels for prompts, following the device the player last used.
func label(player: int, button: String) -> String:
	if using_pad[player]:
		return {"a": "A", "b": "B", "start": "Start", "move": "Stick"}[button]
	if player == 0:
		return {"a": "J", "b": "K", "start": "Esc", "move": "WASD"}[button]
	return {"a": "Num1", "b": "Num2", "start": "Backspace", "move": "Arrows"}[button]


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

	var stick := Vector2.ZERO
	var pad_a := false
	var pad_b := false
	var pad_start := false
	var device := pads[player]
	if device >= 0:
		stick = Vector2(Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
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
		for b in PAD_A:
			pad_a = pad_a or Input.is_joy_button_pressed(device, b)
		for b in PAD_B:
			pad_b = pad_b or Input.is_joy_button_pressed(device, b)
		pad_start = Input.is_joy_button_pressed(device, JOY_BUTTON_START)

	if stick != Vector2.ZERO or pad_a or pad_b or pad_start:
		using_pad[player] = true
	elif kb != Vector2.ZERO or kb_a or kb_b or kb_start:
		using_pad[player] = false

	var dir := snap8(stick if stick != Vector2.ZERO else kb)
	return {"x": dir.x, "y": dir.y, "a": pad_a or kb_a, "b": pad_b or kb_b,
		"start": pad_start or kb_start}


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
