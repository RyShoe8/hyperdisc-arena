extends SceneTree
class FakeApi extends RefCounted:
	var response := {"_ok":true,"rooms":[],"players":[]}
	func call_api(_method,_path,_body=null,_auth=true,_bearer="") -> Dictionary:
		return response
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.net.typing={"field":"address","value":""}
	game.net._finish_typing(true)
	assert(not game.net.typing.is_empty())
	game.net._finish_typing(false)
	assert(game.net.typing.is_empty() and game.screen==game.Screen.ONLINE)
	var service=load("res://scripts/net/playbound_service.gd").new()
	var api=FakeApi.new()
	service.api=api
	api.response={"_ok":true,"rooms":[{"id":"one"}],"players":[{"name":"Player"}]}
	await service._refresh_lobby()
	assert(service.lobby_rooms.size()==1 and service.lobby_error=="")
	api.response={"_ok":false,"error":"unavailable"}
	await service._refresh_lobby()
	assert(service.lobby_rooms.is_empty() and service.lobby_players.is_empty())
	service.lobby_room={"sessionId":"expired"}
	api.response={"_ok":false,"_status":409}
	await service._lobby_pulse()
	assert(service.lobby_room.is_empty())
	print("LOBBY TESTS PASSED")
	quit()
