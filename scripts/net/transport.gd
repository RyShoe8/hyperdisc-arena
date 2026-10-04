## A way to exchange small unreliable packets with one other player.
## The rollback session and lobby only talk to this interface, so the
## connection can come from direct UDP today and PlayBound (NAT traversal,
## relay) later without touching the netcode.
extends RefCounted

## Set when the connection can't be made or has dropped, with a message for
## the player. The lobby gives up when it sees this.
var failure := ""


## Queue a packet for the peer. Packets may be lost, duplicated or reordered.
func send(_data: PackedByteArray) -> void:
	pass


## Every packet that has arrived since the last call.
func receive() -> Array[PackedByteArray]:
	return []


## True once there is a peer to talk to (a host waits for the first packet).
func has_peer() -> bool:
	return false


## Human-readable endpoint, for the lobby screen.
func describe() -> String:
	return ""


func close() -> void:
	pass
