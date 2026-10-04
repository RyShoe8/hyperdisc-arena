## Packs a sim input Dictionary into a small integer (16 bits) for the wire
## and back. Rollback compares inputs by these integers.
##
## Bits 0-3: 8-way direction (x, y) used for aiming. Bits 4-9: buttons.
## Bits 10-15: "ma", the analog stick's movement angle: 0 = none (move by
## x/y), 1..MOVE_ANGLES = that angle step, so running follows the stick
## freely while throws keep their 8-way aim.
extends RefCounted

const BUTTONS := ["a", "b", "jump", "slap", "a_down", "b_down"]
const IDLE := 5  # x = 0, y = 0, no buttons
const MOVE_ANGLES := 48  # 7.5 degree steps: includes straight and exact diagonals


static func encode(input: Dictionary) -> int:
	var v := (clampi(int(input.get("x", 0)), -1, 1) + 1) | ((clampi(int(input.get("y", 0)), -1, 1) + 1) << 2)
	for i in BUTTONS.size():
		if input.get(BUTTONS[i], false):
			v |= 1 << (4 + i)
	v |= clampi(int(input.get("ma", 0)), 0, MOVE_ANGLES) << 10
	return v


static func decode(v: int) -> Dictionary:
	var out := {"x": (v & 3) - 1, "y": ((v >> 2) & 3) - 1}
	for i in BUTTONS.size():
		out[BUTTONS[i]] = (v >> (4 + i)) & 1 == 1
	out["ma"] = (v >> 10) & 63
	return out


## The movement angle step for a stick vector (1..MOVE_ANGLES), 0 if centred.
static func angle_step(v: Vector2) -> int:
	if v == Vector2.ZERO:
		return 0
	var step := TAU / MOVE_ANGLES
	return posmod(int(round(v.angle() / step)), MOVE_ANGLES) + 1


## Unit vector for a movement angle step.
static func angle_vector(ma: int) -> Vector2:
	var a := float(ma - 1) * TAU / MOVE_ANGLES
	return Vector2(cos(a), sin(a))
