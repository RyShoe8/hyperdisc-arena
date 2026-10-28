## Tutorial exercises run the unchanged match simulation. Only the starting
## situation is staged; completion always comes from a real simulation event.
extends RefCounted

const Sim := preload("res://scripts/sim/match_sim.gd")
## Original clip IDs keep bundled demonstrations aligned after removing aerial drills.
const CLIP_IDS := [0, 1, 2, 3, 4, 5, 6, 10, 11, 12, 13, 14, 15, 16, 17, 18]
const LESSONS := [
	["MOVE", "Move into the cyan ring.", "move"],
	["DIVE", "Hold a direction, then tap {dive} while empty-handed.\nReach for the disc, then recover to your feet.", "dive"],
	["CATCH", "Line up your torso with the incoming disc.\nCatching is automatic: no button needed.", "move"],
	["AIMED THROW", "With the disc, hold UP and tap {a}.\nYour stick aims the shot; you cannot move while holding.", "a"],
	["WALL SHOT", "Hold UP and tap {a}.\nWatch your shot bounce off the side wall.", "a"],
	["CURVE THROW", "Tap {curve_left} or {curve_right} to bend the disc to your left or right.\nEach throws a curve instantly.", "curve_right"],
	["LOB", "With the disc, tap {b} to lob over your opponent.\nEarly = deep lob. Waiting {lob_ms} ms = short lob.", "b"],
	["QUICK RETURN", "Line up with the incoming disc.\nAfter the catch, tap {a} within {quick_ms} ms.", "a"],
	["POP UP", "Tap {a} on PRESS NOW, before the catch.\nPopping the disc up sets up a follow-up catch.", "a"],
	["SLAP", "Tap {slap} on PRESS NOW to return the disc instantly.\nAim with the stick; no catch needed.", "slap"],
	["DROP SHOT", "Tap {b} on PRESS NOW, BEFORE the catch.\nThe disc drops just behind the net; a miss scores 2.", "b"],
	["CHARGED SPECIAL", "Stand under the landing ring for {charge_ms} ms.\nAfter the charged catch, tap {a}. No full meter needed.", "a"],
	["SUPER LOB", "Stand under the landing ring until the charged catch.\nThen tap {b}: the lob becomes a spinning ground shot.", "b"],
	["POWER THROW", "The power meter is filled for this drill.\nWith the disc, tap {power}. This spends the full meter.", "power"],
	["POWER TOSS", "The power meter is filled for this drill.\nTap {power} on PRESS NOW, before the catch, to spend it.", "power"],
	["SHORT LOB", "With the disc, WAIT until SHORT LOB READY.\nThen tap {b}. Holding longer brings the landing closer to the net.", "b"],
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
	if lesson in [3, 4, 5, 6, 13, 15]:
		_hold()
		if lesson == 4:
			sim.players[0].pos.y = 120
			sim.disc.pos = sim.players[0].pos + Vector2(float(balance.player.radius), 0)
		if lesson == 13:
			sim.players[0].ex = int(balance.ex.max)
	elif lesson in [2, 7, 8, 9, 10, 14]:
		_flying()
		if lesson == 2:
			sim.players[0].pos.y = 400
		if lesson == 14:
			sim.players[0].ex = int(balance.ex.max)
	elif lesson in [11, 12]:
		sim.players[1].holding = false
		sim._air(Sim.Air.LOB, Vector2(660, 300), Vector2(220, 300), 30, 1,
			int(balance.air.lob_flight_ticks), float(balance.air.lob_peak))
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
	if lesson in [8, 9, 10, 14]:
		var action := "slap" if lesson == 9 else "b" if lesson == 10 else "power" if lesson == 14 else "a"
		early_defence = input.get(action, false) and not timing().now
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
				if e.type == "throw" and e.curve: _success()
			6:
				if e.type == "lob": _success()
			7:
				if e.type == "catch" and not e.air: stage = 1
				if stage == 1 and e.type == "throw" and e.supersonic and not e.smash and input.get("a", false): _success()
			8:
				if e.type == "block": _success()
			9:
				if e.type == "slap": _success()
			10:
				if e.type == "drop": _success()
			11, 12:
				if e.type == "catch" and e.charged: stage = 1
				if stage == 1 and lesson == 11 and e.type == "special" and not e.ex: _success()
				if stage == 1 and lesson == 12 and e.type == "lob" and e.super: _success()
			13:
				if e.type == "special" and e.ex and sim.players[0].ex == 0: _success()
			14:
				if e.type == "power_toss" and sim.players[0].ex == 0: _success()
			15:
				if e.type == "lob" and held_ticks + 1 >= int(balance.air.lob_shallow_after_ticks): _success()
	if passed:
		return
	# Wrong actions are retried from the same situation, without counting them.
	if early_defence:
		_fail("Too early. Wait for PRESS NOW and the yellow ring.")
	elif sim.phase != Sim.Phase.PLAY:
		_fail("Disc missed. Watch the floor marker and try again.")
	elif lesson == 7 and sim.players[0].holding and sim.players[0].hold_ticks >= int(balance.throw.supersonic_window_ticks):
		_fail("Too late. Tap throw immediately AFTER the catch.")
	elif lesson in [8, 9, 10, 14] and sim.players[0].holding:
		_fail("You caught it. Use the move BEFORE it reaches your circle.")
	elif lesson in [11, 12] and sim.players[0].holding and not sim.players[0].charged:
		_fail("Not charged. Stay inside the landing ring until the catch.")
	elif lesson in [3, 4, 5, 6, 7, 11, 12, 13, 15] and not sim.players[0].holding and sim.disc.thrower == 0 and not (lesson == 4 and stage == 1):
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
	if lesson == 8: return float(balance.defence.block_radius)
	if lesson == 14: return float(balance.defence.power_toss_radius)
	return float(balance.defence.slap_radius)

func timing() -> Dictionary:
	var p := sim.players[0]
	var d := sim.disc
	if lesson in [8, 9, 10, 14] and d.state == Sim.Disc.FLYING:
		var distance := p.pos.distance_to(d.pos)
		var radius := defence_radius()
		var now := distance <= radius and sim.side_of(d.pos.x) == 0
		var ticks := maxi(0, ceili((distance - radius) / maxf(d.vel.length(), 1)))
		return {"now": now, "text": "PRESS NOW" if now else "WAIT  %d ms" % (ticks * 1000 / 60),
			"value": clampf(1.0 - (distance - radius) / 320.0, 0, 1)}
	if lesson == 7 and p.holding:
		# A throw pressed during the hit-stop or the slide is buffered and goes
		# the moment it can, so it's always "now" once the disc is caught.
		if p.knock_ticks > 0 or sim.freeze_ticks > 0:
			return {"now": true, "text": "CATCH! THROW NOW", "value": 1.0}
		var remaining := maxi(0, int(balance.throw.supersonic_window_ticks) - p.hold_ticks)
		return {"now": true, "text": "THROW NOW  %d ms LEFT" % (remaining * 1000 / 60), "value": remaining / float(balance.throw.supersonic_window_ticks)}
	if lesson in [11, 12] and not p.holding:
		return {"now": false, "text": "CHARGE READY - STAY" if p.charge >= int(balance.charge.ticks_needed) else "STAY IN THE LANDING RING", "value": clampf(p.charge / float(balance.charge.ticks_needed), 0, 1)}
	if lesson == 15:
		var remaining := maxi(0, int(balance.air.lob_shallow_after_ticks) - p.hold_ticks - 1)
		return {"now": remaining == 0, "text": "SHORT LOB READY" if remaining == 0 else "WAIT  %d ms" % (remaining * 1000 / 60), "value": 1.0 - remaining / float(balance.air.lob_shallow_after_ticks)}
	return {"now": true, "text": "YOUR TURN" if lesson != 7 else "WAIT FOR THE CATCH", "value": 1.0}
