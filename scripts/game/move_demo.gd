## Scripted player inputs for recording the tutorial's successful move clips.
## Shared by the capture tool and tests so recordings cannot fake completion.
extends RefCounted

static func input(session, tick: int) -> Dictionary:
	var p = session.sim.players[0]
	match session.lesson:
		0: return {"x": 1 if p.pos.x < session.target.x else 0}
		1: return {"x": 1, "a": tick == 12}
		2: return {"y": -1 if p.pos.y > 305 else 0}
		3, 4: return {"y": -1, "a": tick == 18}
		5: return {"y": 1 if tick >= 12 and tick < 20 else 0, "x": 1 if tick >= 16 else 0, "a": tick == 20}
		6: return {"b": tick == 18}
		7: return {"jump": tick == 18}
		8, 9, 19:
			return {"jump": tick == (session.jump_window.x + session.jump_window.y) / 2,
				"a": session.lesson == 9 and p.holding and p.z > 0,
				"b": session.lesson == 19 and p.holding and p.z > 0}
		10: return {"a": p.holding and p.knock_ticks == 0}
		11: return {"a": session.timing().now}
		12: return {"slap": session.timing().now}
		13: return {"b": session.timing().now}
		14: return {"a": p.holding and p.charged}
		15: return {"b": p.holding and p.charged}
		16: return {"slap": tick == 18}
		17: return {"a": session.timing().now, "b": session.timing().now, "a_down": true, "b_down": true}
		18: return {"b": p.hold_ticks + 1 >= int(session.balance.air.lob_shallow_after_ticks)}
	return {}
