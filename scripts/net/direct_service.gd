## Online without an account: a local display name, and matches set up by
## hosting on a port or joining an address. Used for LAN play and testing
## until the PlayBound service is available.
extends "res://scripts/net/online_service.gd"

const UdpTransport := preload("res://scripts/net/udp_transport.gd")

var display_name := "PLAYER"


func service_name() -> String:
	return "Direct connect"


func is_signed_in() -> bool:
	return true


func profile() -> Dictionary:
	return {"id": "", "display_name": display_name}


## Starts listening; match_ready fires straight away with a transport that
## waits for a player to join.
func host(port := UdpTransport.DEFAULT_PORT, lag_ms := 0, loss := 0.0) -> void:
	var t := UdpTransport.new()
	t.lag_ms = lag_ms
	t.loss = loss
	var err := t.host(port)
	if err != OK:
		error.emit("COULDN'T OPEN PORT %d (ERROR %d)" % [port, err])
		return
	match_ready.emit({"role": "host", "transport": t, "opponent": {}})


## address is "host" or "host:port".
func join(address: String, lag_ms := 0, loss := 0.0) -> void:
	var parts := address.strip_edges().rsplit(":", true, 1)
	var hostname := parts[0]
	var port := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else UdpTransport.DEFAULT_PORT
	var t := UdpTransport.new()
	t.lag_ms = lag_ms
	t.loss = loss
	var err := t.join(hostname, port)
	if err != OK:
		error.emit("COULDN'T REACH %s (ERROR %d)" % [address, err])
		return
	match_ready.emit({"role": "join", "transport": t, "opponent": {}})
