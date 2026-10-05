## Tutorial exercises run the unchanged match simulation. Only the starting
## situation is staged; completion always comes from a real simulation event.
extends RefCounted

const Sim := preload("res://scripts/sim/match_sim.gd")
const LESSONS := [
	["MOVE", "Move into the cyan ring.", "move"],
	["DASH", "Hold a direction, then tap {a} while empty-handed.", "a"],
	["CATCH", "Move your floor circle onto the disc's path.\nCatching is automatic: no button needed.", "move"],
	["AIMED THROW", "With the disc, hold UP and tap {a}.\nYour stick aims the shot; you cannot move while holding.", "a"],
	["WALL SHOT", "Hold UP and tap {a}.\nWatch your shot bounce off the side wall.", "a"],
	["CURVE THROW", "Roll DOWN > DOWN-RIGHT > RIGHT, then tap {a}.\nFinish the quarter-circle in {curve_ms} ms.", "a"],
	["LOB", "With the disc, tap {b} to lob over your opponent.\nEarly = deep lob. Waiting {lob_ms} ms = short lob.", "b"],
	["JUMP", "Empty-handed, tap {jump}.\nJump first; holding the button does not extend it.", "jump"],
	["AIR CATCH", "Stay under the landing ring. Tap {jump} on JUMP NOW.\nCatch the descending disc before you land.", "jump"],
	["AIR SMASH", "Jump on JUMP NOW, catch in midair, then tap {a}.\nThrow before your feet touch the floor.", "a"],
	["QUICK RETURN", "Let the incoming disc reach your floor circle.\nAfter the catch, tap {a} within {quick_ms} ms.", "a"],
	["BLOCK", "Release the stick. Tap {a} on PRESS NOW.\nA block pops the disc up for a follow-up catch.", "a"],
	["SLAP", "Tap {slap} on PRESS NOW to return the disc instantly.\nAim with the stick; no catch needed.", "slap"],
	["DROP SHOT", "Tap {b} on PRESS NOW, BEFORE the catch.\nThe disc drops just behind the net; a miss scores 2.", "b"],
	["CHARGED SPECIAL", "Stand under the landing ring for {charge_ms} ms.\nAfter the charged catch, tap {a}. No full meter needed.", "a"],
	["SUPER LOB", "Stand under the landing ring until the charged catch.\nThen tap {b}: the lob becomes a spinning ground shot.", "b"],
	["POWER THROW", "The power meter is filled for this drill.\nWith the disc, tap {slap}. This spends the full meter.", "slap"],
	["POWER TOSS", "The power meter is filled for this drill.\nPress {a} + {b} together on PRESS NOW to spend it.", "a"],
	["SHORT LOB", "With the disc, WAIT until SHORT LOB READY.\nThen tap {b}. Holding longer brings the landing closer to the net.", "b"],
	["AIR LOB", "Jump on JUMP NOW, then catch the disc in midair.\nTap {b} before landing to lob from the air.", "b"],
]

var sim: Sim
var balance: Dictionary
var lesson := 0
var passed := false
var failed := false
var feedback := ""
var elapsed := 0
var stage := 0
var target := Vector2(350, 300)
var jump_window := Vector2i(-1, -1)
var last_input := {}

func _init(config: Dictionary) -> void:
	balance = config
	reset()

func reset() -> void:
	sim = Sim.new(balance, balance.characters[0], balance.characters[1], 0)
	sim.phase = Sim.Phase.PLAY
	sim.phase_ticks = 0
	sim.set_ticks_left = -1
	sim.players[0].pos = Vector2(220, 300)
	sim.players[1].pos = Vector2(1000, 550)
	for p in sim.players:
		p.holding = false
		p.serving = false
	sim.disc.state = Sim.Disc.HELD
	sim.disc.owner = 1
	sim.players[1].holding = true
	# The stationary feeder keeps its disc only in movement exercises.
	sim.players[1].serving = true
	passed = false
	failed = false
	feedback = ""
	elapsed = 0
	stage = 0
	last_input = {}
	jump_window = Vector2i(-1, -1)
	if lesson in [3, 4, 5, 6, 16, 18]:
		_hold()
		if lesson == 4:
			sim.players[0].pos.y = 120
			sim.disc.pos = sim.players[0].pos + Vector2(float(balance.player.radius), 0)
		if lesson == 16:
			sim.players[0].ex = int(balance.ex.max)
	elif lesson in [2, 10, 11, 12, 13, 17]:
		_flying()
		if lesson == 2:
			sim.players[0].pos.y = 400
		if lesson == 17:
			sim.players[0].ex = int(balance.ex.max)
	elif lesson in [8, 9, 14, 15, 19]:
		sim.players[1].holding = false
		sim._air(Sim.Air.LOB, Vector2(660, 300), Vector2(220, 300), 30, 1,
			int(balance.air.lob_flight_ticks), float(balance.air.lob_peak))
		if lesson in [8, 9, 19]:
			jump_window = _find_jump_window()
	sim.events.clear()

func _hold() -> void:
	sim.players[1].holding = false
	sim.players[0].holding = true
	sim.disc.owner = 0
	sim.disc.pos = sim.players[0].pos + Vector2(26, 0)

func _flying() -> void:
	sim.players[1].holding = false
	sim.disc.state = Sim.Disc.FLYING
	sim.disc.thrower = 1
	sim.disc.pos = Vector2(540, 300)
	sim.disc.vel = Vector2(-9, 0)
	sim.disc.speed = 9

## Derive the jump cue from real collision and height rules, not a guessed
## animation frame. The stationary landing drill has a repeatable window.
func _find_jump_window() -> Vector2i:
	var saved := sim.save_state()
	var window := Vector2i(-1, -1)
	var probe := Sim.new(balance, balance.characters[0], balance.characters[1], 0)
	for at in range(1, int(balance.air.lob_flight_ticks)):
		probe.load_state(saved)
		for t in range(1, int(balance.air.lob_flight_ticks) + 1):
			probe.step([{"jump": t == at}, {}])
			if probe.players[0].holding:
				if probe.players[0].z > 0:
					if window.x < 0:
						window.x = at
					window.y = at
				break
	return window

func advance() -> bool:
	if not passed or lesson == LESSONS.size() - 1:
		return false
	lesson += 1
	reset()
	return true

func step(input: Dictionary) -> void:
	if passed or failed:
		return
	last_input = input.duplicate()
	var early_defence := false
	if lesson in [11, 12, 13, 17]:
		var action := "slap" if lesson == 12 else "b" if lesson == 13 else "a"
		early_defence = input.get(action, false) and not timing().now
	var was_airborne := sim.players[0].z > 0
	var held_ticks := sim.players[0].hold_ticks
	elapsed += 1
	# Prevent the stationary feeder's automatic throw in movement drills.
	sim.players[1].hold_ticks = 0
	sim.step([input, {}])
	if lesson == 0 and sim.players[0].pos.distance_to(target) <= 35:
		_success()
	for e in sim.events:
		if lesson == 4 and stage == 1 and e.type == "bounce" and sim.disc.thrower == 0:
			_success()
		if e.get("side", -1) != 0:
			continue
		match lesson:
			1:
				if e.type == "dash": _success()
			2:
				if e.type == "catch" and not e.air: _success()
			3:
				if e.type == "throw" and input.get("a", false) and Sim.aim_y(input) < -0.5: _success()
			4:
				if e.type == "throw" and input.get("a", false) and Sim.aim_y(input) < -0.5: stage = 1
			5:
				if e.type == "throw" and input.get("a", false) and e.curve: _success()
			6:
				if e.type == "lob": _success()
			7:
				if e.type == "jump": stage = 1
				if e.type == "land" and stage == 1: _success()
			8, 9, 19:
				if e.type == "catch" and e.air and sim.players[0].z > 0:
					stage = 1
					if lesson == 8: _success()
				if lesson == 9 and stage == 1 and e.type == "throw" and e.smash: _success()
				if lesson == 19 and stage == 1 and e.type == "lob" and was_airborne: _success()
			10:
				if e.type == "catch" and not e.air: stage = 1
				if stage == 1 and e.type == "throw" and e.supersonic and not e.smash and input.get("a", false): _success()
			11:
				if e.type == "block": _success()
			12:
				if e.type == "slap": _success()
			13:
				if e.type == "drop": _success()
			14, 15:
				if e.type == "catch" and e.charged: stage = 1
				if stage == 1 and lesson == 14 and e.type == "special" and not e.ex: _success()
				if stage == 1 and lesson == 15 and e.type == "lob" and e.super: _success()
			16:
				if e.type == "special" and e.ex and sim.players[0].ex == 0: _success()
			17:
				if e.type == "power_toss" and sim.players[0].ex == 0: _success()
			18:
				if e.type == "lob" and held_ticks + 1 >= int(balance.air.lob_shallow_after_ticks): _success()
	if passed:
		return
	# Wrong actions are retried from the same situation, without counting them.
	if early_defence:
		_fail("Too early. Wait for PRESS NOW and the yellow ring.")
	elif sim.phase != Sim.Phase.PLAY:
		_fail("Disc missed. Watch the floor marker and try again.")
	elif lesson == 10 and sim.players[0].holding and sim.players[0].hold_ticks >= int(balance.throw.supersonic_window_ticks):
		_fail("Too late. Tap throw immediately AFTER the catch.")
	elif lesson in [11, 12, 13, 17] and sim.players[0].holding:
		_fail("You caught it. Use the move BEFORE it reaches your circle.")
	elif lesson in [8, 9, 19] and sim.players[0].holding and sim.players[0].z <= 0:
		_fail("Feet on the floor. Jump during the highlighted window.")
	elif lesson in [14, 15] and sim.players[0].holding and not sim.players[0].charged:
		_fail("Not charged. Stay inside the landing ring until the catch.")
	elif lesson in [3, 4, 5, 6, 9, 10, 14, 15, 16, 18, 19] and not sim.players[0].holding and sim.disc.thrower == 0 and not (lesson == 4 and stage == 1):
		_fail("Different move. Follow the sequence and try again.")
	elif elapsed > 600:
		_fail("Let's reset the drill. You can try as often as you like.")

func _success() -> void:
	passed = true
	feedback = "MOVE COMPLETE"

func _fail(message: String) -> void:
	failed = true
	feedback = message

func defence_radius() -> float:
	if lesson == 11: return float(balance.defence.block_radius)
	if lesson == 17: return float(balance.defence.power_toss_radius)
	return float(balance.defence.slap_radius)

func timing() -> Dictionary:
	var p := sim.players[0]
	var d := sim.disc
	if lesson in [11, 12, 13, 17] and d.state == Sim.Disc.FLYING:
		var distance := p.pos.distance_to(d.pos)
		var radius := defence_radius()
		var now := distance <= radius and sim.side_of(d.pos.x) == 0
		var ticks := maxi(0, ceili((distance - radius) / maxf(d.vel.length(), 1)))
		return {"now": now, "text": "PRESS NOW" if now else "WAIT  %d ms" % (ticks * 1000 / 60),
			"value": clampf(1.0 - (distance - radius) / 320.0, 0, 1)}
	if lesson in [8, 9, 19] and stage == 0:
		if p.z > 0:
			return {"now": false, "text": "AIRBORNE - WAIT FOR CATCH", "value": 1.0}
		var t := d.air_tick + 1
		var now := t >= jump_window.x and t <= jump_window.y
		return {"now": now, "text": "JUMP NOW" if now else ("WAIT  %d ms" % (maxi(0, jump_window.x - t) * 1000 / 60) if t < jump_window.x else "JUMP WINDOW PASSED"),
			"value": clampf(float(t) / maxf(jump_window.x, 1), 0, 1)}
	if lesson == 10 and p.holding:
		if p.knock_ticks > 0 or sim.freeze_ticks > 0:
			return {"now": false, "text": "CATCH! BRACE FOR THE RETURN", "value": 1.0}
		var remaining := maxi(0, int(balance.throw.supersonic_window_ticks) - p.hold_ticks)
		return {"now": p.knock_ticks == 0 and sim.freeze_ticks == 0, "text": "THROW NOW  %d ms LEFT" % (remaining * 1000 / 60), "value": remaining / float(balance.throw.supersonic_window_ticks)}
	if lesson in [14, 15] and not p.holding:
		return {"now": false, "text": "CHARGE READY - STAY" if p.charge >= int(balance.charge.ticks_needed) else "STAY IN THE LANDING RING", "value": clampf(p.charge / float(balance.charge.ticks_needed), 0, 1)}
	if lesson == 9 and p.holding:
		return {"now": true, "text": "SMASH NOW - STILL AIRBORNE", "value": 1.0}
	if lesson == 19 and p.holding:
		return {"now": true, "text": "LOB NOW - STILL AIRBORNE", "value": 1.0}
	if lesson == 18:
		var remaining := maxi(0, int(balance.air.lob_shallow_after_ticks) - p.hold_ticks - 1)
		return {"now": remaining == 0, "text": "SHORT LOB READY" if remaining == 0 else "WAIT  %d ms" % (remaining * 1000 / 60), "value": 1.0 - remaining / float(balance.air.lob_shallow_after_ticks)}
	return {"now": true, "text": "YOUR TURN" if lesson != 10 else "WAIT FOR THE CATCH", "value": 1.0}
