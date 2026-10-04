## Packs a sim input Dictionary into a small integer (10 bits) for the wire
## and back. Rollback compares inputs by these integers.
extends RefCounted

const BUTTONS := ["a", "b", "jump", "slap", "a_down", "b_down"]
const IDLE := 5  # x = 0, y = 0, no buttons


static func encode(input: Dictionary) -> int:
	var v := (clampi(int(input.get("x", 0)), -1, 1) + 1) | ((clampi(int(input.get("y", 0)), -1, 1) + 1) << 2)
	for i in BUTTONS.size():
		if input.get(BUTTONS[i], false):
			v |= 1 << (4 + i)
	return v


static func decode(v: int) -> Dictionary:
	var out := {"x": (v & 3) - 1, "y": ((v >> 2) & 3) - 1}
	for i in BUTTONS.size():
		out[BUTTONS[i]] = (v >> (4 + i)) & 1 == 1
	return out
