## Opt-in live integration check: anonymous temporary room, no user accounts.
extends SceneTree
const Api = preload("res://scripts/net/playbound_api.gd")
const Transport = preload("res://scripts/net/webrtc_transport.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var api := Api.new()
	root.add_child(api)
	var info: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/multiplayer/hyperdisc-arena/sessions", {"gameVersion": "connect-test", "maxPlayers": 2}, false)
	if not info._ok:
		printerr("Create failed: ", info.get("error", info._status))
		quit(1)
		return
	var host := Transport.new()
	host.start(api, info, "host")
	# Keep host alive past the server's 60-second room deadline.
	var until := Time.get_ticks_msec() + 65000
	while Time.get_ticks_msec() < until and host.failure == "":
		host.receive()
		await create_timer(0.02).timeout
	var joined: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/multiplayer/hyperdisc-arena/sessions/%s/join" % info.joinCode, {"gameVersion": "connect-test"}, false)
	if not joined._ok:
		printerr("Join after 65 seconds failed: ", joined.get("error", joined._status))
		host.close()
		quit(1)
		return
	var guest := Transport.new()
	guest.start(api, joined, "client")
	until = Time.get_ticks_msec() + 40000
	while Time.get_ticks_msec() < until and host.failure == "" and guest.failure == "":
		host.receive()
		guest.receive()
		if host.has_peer() and guest.has_peer():
			host.send(PackedByteArray([42, 17]))
			await create_timer(0.1).timeout
			for packet in guest.receive():
				if packet == PackedByteArray([42, 17]):
					print("LIVE CONNECT PASSED: room survived 65s, WebRTC connected, packet delivered")
					guest.close()
					host.close()
					await create_timer(1.0).timeout
					quit(0)
					return
		await create_timer(0.02).timeout
	printerr("Connect failed: host=", host.failure, " guest=", guest.failure)
	guest.close()
	host.close()
	quit(1)
