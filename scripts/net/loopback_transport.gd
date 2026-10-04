## In-memory transport for tests: two linked ends with simulated latency,
## jitter and packet loss, all measured in ticks so tests are reproducible.
extends "res://scripts/net/transport.gd"

var _other: WeakRef  # the linked end; weak so the pair can be freed
var latency := 0
var jitter := 0
var loss := 0.0
var rng := RandomNumberGenerator.new()
var now := 0
var _queue: Array = []  # [deliver_tick, bytes], in this end's inbox


static func pair(latency_ticks := 4, jitter_ticks := 2, loss_chance := 0.05, seed_value := 1) -> Array:
	var script: GDScript = load("res://scripts/net/loopback_transport.gd")
	var a = script.new()
	var b = script.new()
	for end in [a, b]:
		end.latency = latency_ticks
		end.jitter = jitter_ticks
		end.loss = loss_chance
	a.rng.seed = seed_value
	b.rng.seed = seed_value + 1
	a._other = weakref(b)
	b._other = weakref(a)
	return [a, b]


func has_peer() -> bool:
	return _other != null and _other.get_ref() != null


func describe() -> String:
	return "loopback"


func send(data: PackedByteArray) -> void:
	if rng.randf() < loss:
		return
	var other = _other.get_ref() if _other != null else null
	if other == null:
		return
	var delay := latency + rng.randi_range(0, jitter)
	other._queue.append([other.now + delay, data])


## Advances this end's clock one tick; call once per game tick.
func advance() -> void:
	now += 1


func receive() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var keep: Array = []
	for item in _queue:
		if item[0] <= now:
			out.append(item[1])
		else:
			keep.append(item)
	_queue = keep
	return out
