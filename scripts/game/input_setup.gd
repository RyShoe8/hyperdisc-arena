## Registers controller and keyboard bindings at startup (autoload), so the
## bindings live in code review instead of hand-edited project.godot blocks.
##
## Player 1: WASD + J (throw/dash) + K (lob), or controller 1.
## Player 2: arrows + Numpad 1 (throw/dash) + Numpad 2 (lob), or controller 2.
## Controllers: left stick or D-pad to move, A/Cross = throw/dash, B/Circle = lob.
extends Node

const KEYS := {
	"p1": {"up": KEY_W, "down": KEY_S, "left": KEY_A, "right": KEY_D, "a": KEY_J, "b": KEY_K},
	"p2": {"up": KEY_UP, "down": KEY_DOWN, "left": KEY_LEFT, "right": KEY_RIGHT,
		"a": KEY_KP_1, "b": KEY_KP_2},
}

const PAD_BUTTONS := {
	"up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT,
	"a": JOY_BUTTON_A, "b": JOY_BUTTON_B,
}

const PAD_AXES := {
	"up": [JOY_AXIS_LEFT_Y, -1.0], "down": [JOY_AXIS_LEFT_Y, 1.0],
	"left": [JOY_AXIS_LEFT_X, -1.0], "right": [JOY_AXIS_LEFT_X, 1.0],
}


func _ready() -> void:
	for player in KEYS:
		var device := 0 if player == "p1" else 1
		for control in KEYS[player]:
			var action: String = "%s_%s" % [player, control]
			if not InputMap.has_action(action):
				InputMap.add_action(action, 0.5)

			var key := InputEventKey.new()
			key.physical_keycode = KEYS[player][control]
			InputMap.action_add_event(action, key)

			var button := InputEventJoypadButton.new()
			button.device = device
			button.button_index = PAD_BUTTONS[control]
			InputMap.action_add_event(action, button)

			if PAD_AXES.has(control):
				var motion := InputEventJoypadMotion.new()
				motion.device = device
				motion.axis = PAD_AXES[control][0]
				motion.axis_value = PAD_AXES[control][1]
				InputMap.action_add_event(action, motion)

	var start := InputEventJoypadButton.new()
	start.device = -1
	start.button_index = JOY_BUTTON_START
	InputMap.action_add_event("ui_accept", start)


## Reads one player's controls as a sim input Dictionary.
static func read(player: String) -> Dictionary:
	return {
		"x": int(Input.is_action_pressed(player + "_right")) - int(Input.is_action_pressed(player + "_left")),
		"y": int(Input.is_action_pressed(player + "_down")) - int(Input.is_action_pressed(player + "_up")),
		"a": Input.is_action_just_pressed(player + "_a"),
		"b": Input.is_action_just_pressed(player + "_b"),
	}
