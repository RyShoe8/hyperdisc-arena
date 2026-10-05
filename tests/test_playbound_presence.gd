extends SceneTree
const Service = preload("res://scripts/net/playbound_service.gd")

class FakeApi extends RefCounted:
	var token := "test"
	var results: Array[Dictionary] = []
	var calls: Array[String] = []
	func call_api(_method, path, _body = null, _auth = true, _bearer = "") -> Dictionary:
		calls.append(path)
		return results.pop_front()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := FakeApi.new()
	var service := Service.new()
	service.api = api
	service._profile = {"id": "test", "username": "test"}
	api.results.assign([
		{"_ok": false, "_status": 503},
		{"_ok": true, "_status": 200, "sessionId": "restored", "heartbeatIntervalMs": 60000},
		{"_ok": false, "_status": 503},
		{"_ok": true, "_status": 200},
	])
	await service._start_presence()
	assert(not service.has_presence() and not service._busy.has("presence"))
	# Poll should retry registration, instead of remaining invisible forever.
	service._next_presence_start_ms = 0
	service._next_friends_ms = Time.get_ticks_msec() + 100000
	service._next_invites_ms = Time.get_ticks_msec() + 100000
	service.poll()
	assert(service.has_presence())
	await service._heartbeat_presence()
	assert(service._next_heartbeat_ms < Time.get_ticks_msec() + 6000)
	await service._heartbeat_presence()
	assert(service._next_heartbeat_ms >= Time.get_ticks_msec() + 59000)
	assert(api.calls.size() == 4)
	print("PLAYBOUND PRESENCE TESTS PASSED")
	quit(0)
