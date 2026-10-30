## Finds HyperDisc rooms on the local network, so LAN play works like the
## online lobby: hosts answer, browsers list them.
##
## A browser broadcasts a small query to DISCOVERY_PORT every second; a host
## that is advertising answers with its name, game port and build. Only hosts
## bind the discovery port, so any number of browsers can run, even on the
## same machine as the host.
extends RefCounted

const DISCOVERY_PORT := 7778
const QUERY := "HYPERDISC_LAN_QUERY_1"
const QUERY_EVERY_MS := 1000
## A room not heard from for this long has gone.
const STALE_MS := 3500

var _udp := PacketPeerUDP.new()
var _hosting := false
var _browsing := false
var _info := {}           # what a host advertises
var _rooms := {}          # "ip:port" -> {name, address, port, build, players, seen}
var _last_query := -100000


## Starts answering queries. Returns false if the discovery port is taken
## (another host on this machine); the room still works by address.
func advertise(name: String, game_port: int, build: String) -> bool:
	stop()
	_info = {"name": name, "port": game_port, "build": build, "players": 1}
	_hosting = _udp.bind(DISCOVERY_PORT) == OK
	return _hosting


func set_players(count: int) -> void:
	_info["players"] = count


## Starts listening for rooms.
func browse() -> void:
	stop()
	_rooms.clear()
	_browsing = _udp.bind(0) == OK
	_udp.set_broadcast_enabled(true)
	_last_query = -100000


func stop() -> void:
	_udp.close()
	_hosting = false
	_browsing = false


func active() -> bool:
	return _hosting or _browsing


## Call every tick while hosting or browsing.
func poll() -> void:
	if _browsing and Time.get_ticks_msec() - _last_query >= QUERY_EVERY_MS:
		_last_query = Time.get_ticks_msec()
		for target in ["255.255.255.255", "127.0.0.1"]:
			_udp.set_dest_address(target, DISCOVERY_PORT)
			_udp.put_packet(QUERY.to_utf8_buffer())
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet()
		var ip := _udp.get_packet_ip()
		var port := _udp.get_packet_port()
		if _hosting and data.get_string_from_utf8() == QUERY:
			_udp.set_dest_address(ip, port)
			_udp.put_packet(JSON.stringify(_info).to_utf8_buffer())
		elif _browsing:
			var reply = JSON.parse_string(data.get_string_from_utf8())
			if reply is Dictionary and reply.has("port"):
				var address := "127.0.0.1" if ip.begins_with("127.") else ip
				# A host on this machine answers both the broadcast and the
				# loopback query: list it once, by its network address.
				var key := "%s:%d" % [str(reply.get("name", "")), int(reply.port)]
				if address == "127.0.0.1" and _rooms.has(key) and _rooms[key].address != "127.0.0.1":
					address = _rooms[key].address
				_rooms[key] = {"name": str(reply.get("name", "PLAYER")).left(16), "address": address,
					"port": int(reply.port), "build": str(reply.get("build", "")),
					"players": int(reply.get("players", 1)), "seen": Time.get_ticks_msec()}
	for key in _rooms.keys():
		if Time.get_ticks_msec() - int(_rooms[key].seen) > STALE_MS:
			_rooms.erase(key)


## Rooms heard recently, by name.
func rooms() -> Array:
	var list := _rooms.values()
	list.sort_custom(func(a, b): return a.name < b.name)
	return list
