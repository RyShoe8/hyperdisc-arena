## Direct UDP between two players: one hosts on a port, the other joins by
## address. Used for LAN play and testing until PlayBound brokers
## connections. Optional simulated lag and loss for testing on one machine.
extends "res://scripts/net/transport.gd"

const DEFAULT_PORT := 7777

var udp := PacketPeerUDP.new()
var hosting := false
var peer_ip := ""
var peer_port := 0
var port := 0
## Simulated network conditions (milliseconds, 0..1 chance).
var lag_ms := 0
var loss := 0.0
var _rng := RandomNumberGenerator.new()
var _outbox: Array = []  # [release_msec, bytes]
var _inbox: Array = []


## Listen for a player to join. Returns OK or an error code.
func host(listen_port := DEFAULT_PORT) -> int:
	hosting = true
	port = listen_port
	return udp.bind(listen_port, "*")


## Start talking to a host at address:port.
func join(address: String, host_port := DEFAULT_PORT) -> int:
	hosting = false
	var err := udp.bind(0, "*")
	if err != OK:
		return err
	peer_ip = IP.resolve_hostname(address, IP.TYPE_IPV4) if not address.is_valid_ip_address() else address
	peer_port = host_port
	if peer_ip == "":
		return ERR_CANT_RESOLVE
	udp.set_dest_address(peer_ip, peer_port)
	return OK


func has_peer() -> bool:
	return peer_ip != ""


func describe() -> String:
	if hosting:
		return "port %d" % port
	return "%s:%d" % [peer_ip, peer_port]


func send(data: PackedByteArray) -> void:
	if not has_peer():
		return
	if lag_ms > 0:
		_outbox.append([Time.get_ticks_msec() + lag_ms / 2, data])
	else:
		_send_now(data)


func _send_now(data: PackedByteArray) -> void:
	if loss > 0.0 and _rng.randf() < loss:
		return
	udp.put_packet(data)


func receive() -> Array[PackedByteArray]:
	var now := Time.get_ticks_msec()
	while not _outbox.is_empty() and _outbox[0][0] <= now:
		_send_now(_outbox.pop_front()[1])
	while udp.get_available_packet_count() > 0:
		var data := udp.get_packet()
		var ip := udp.get_packet_ip()
		var from_port := udp.get_packet_port()
		if hosting and peer_ip == "":
			# The first player to say hello becomes our peer.
			peer_ip = ip
			peer_port = from_port
			udp.set_dest_address(peer_ip, peer_port)
		if ip != peer_ip or from_port != peer_port:
			continue
		_inbox.append([now + lag_ms / 2, data])
	var out: Array[PackedByteArray] = []
	while not _inbox.is_empty() and _inbox[0][0] <= now:
		out.append(_inbox.pop_front()[1])
	return out


func close() -> void:
	udp.close()


## This machine's LAN addresses, to show the host what to tell a friend.
static func local_addresses() -> Array[String]:
	var out: Array[String] = []
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out
