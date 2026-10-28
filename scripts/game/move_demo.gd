## Scripted player inputs for recording the tutorial's successful move clips.
## Shared by the capture tool and tests so recordings cannot fake completion.
extends RefCounted

static func input(session, tick: int) -> Dictionary:
	var p = session.sim.players[0]
	match session.lesson:
		0: return {"x": 1 if p.pos.x < session.target.x else 0}
		1: return {"x": 1, "dive": tick == 9}
		2: return {"y": -1 if p.pos.y > 305 else 0}
		3, 4: return {"y": -1, "a": tick == 15}
		5: return {"y": 1 if tick >= 9 and tick < 20 else 0, "x": 1 if tick >= 13 else 0, "a": tick == 20}
		6: return {"b": tick == 15}
		7: return {"a": p.holding and p.knock_ticks == 0}
		8: return {"a": session.timing().now}
		9: return {"slap": session.timing().now}
		10: return {"b": session.timing().now}
		11: return {"a": p.holding and p.charged}
		12: return {"b": p.holding and p.charged}
		13: return {"power": tick == 15}
		14: return {"power": session.timing().now}
		15: return {"b": p.hold_ticks + 1 >= int(session.balance.air.lob_shallow_after_ticks)}
	return {}
