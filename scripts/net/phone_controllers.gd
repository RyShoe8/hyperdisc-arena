## Phones as controllers, through PlayBound's controller system (Couch Mode).
##
## start() opens a couch session; the game shows its join link as a QR code.
## A phone that scans it opens playbound.club/c/CODE (no account or app),
## which sends a WebRTC offer through the session's signal endpoint. The
## game answers it here, the phone's "input" data channel opens, and its
## pad state (protocol v1: buttons bitmask, sticks) becomes a virtual
## controller in Controls, taking a player slot like a plugged-in pad.
## Packets go phone -> game directly; PlayBound only carries the handshake.
##
## Protocol: PlayBound docs/couch-input-protocol.md and couch-mode.md.
extends Node

## Session started or stopped, or a phone connected or left.
signal changed

const HOST_LABEL := "HyperDisc Arena"
const PAD_NAME := "Phone"
const MAX_PHONES := 2
const SIGNAL_FAST_MS := 500
const SIGNAL_IDLE_MS := 2000
const STATUS_MS := 15000
## The phone sends its state at least every 250 ms; silence this long means gone.
const PAD_TIMEOUT_MS := 3000
## Protocol v1 button bits (Xbox layout) -> Godot buttons.
const BUTTON_BITS := {
	0: JOY_BUTTON_A, 1: JOY_BUTTON_B, 2: JOY_BUTTON_X, 3: JOY_BUTTON_Y,
	4: JOY_BUTTON_LEFT_SHOULDER, 5: JOY_BUTTON_RIGHT_SHOULDER, 6: JOY_BUTTON_BACK,
	7: JOY_BUTTON_START, 8: JOY_BUTTON_LEFT_STICK, 9: JOY_BUTTON_RIGHT_STICK,
	10: JOY_BUTTON_DPAD_UP, 11: JOY_BUTTON_DPAD_DOWN, 12: JOY_BUTTON_DPAD_LEFT,
	13: JOY_BUTTON_DPAD_RIGHT,
}

var api  # PlayBoundApi
## {id, code, host_token, join_url, ice}; empty when no session is open.
var session := {}
var starting := false
var error := ""

var _peers := {}    # controller id -> {pc, channel, last_ms, pending_ice}
var _devices := {}  # controller id -> virtual device id (kept across reconnects)
var _pending_ice := {}  # controller id -> candidates that arrived before the offer
var _since := 0
var _seen := {}
var _poll_busy := false
var _next_poll_ms := 0
var _next_status_ms := 0


func active() -> bool:
	return not session.is_empty()


func join_url() -> String:
	return str(session.get("join_url", ""))


func join_code() -> String:
	return str(session.get("code", ""))


## Phones whose input is arriving right now.
func connected_count() -> int:
	var n := 0
	for id in _peers:
		if _peers[id].last_ms > 0:
			n += 1
	return n


func start() -> void:
	if active() or starting:
		return
	starting = true
	error = ""
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, "/api/couch/sessions",
		{"hostLabel": HOST_LABEL, "maxPlayers": MAX_PHONES, "autoApprove": true}, false)
	starting = false
	if not res._ok:
		error = str(res.get("error", "COULDN'T REACH PLAYBOUND")).to_upper()
		changed.emit()
		return
	var snapshot: Dictionary = res.get("snapshot", {}) if res.get("snapshot") is Dictionary else {}
	var endpoints: Dictionary = snapshot.get("hostEndpoints", {}) if snapshot.get("hostEndpoints") is Dictionary else {}
	session = {"id": str(res.sessionId), "code": str(res.joinCode), "host_token": str(res.hostToken),
		"join_url": str(res.get("joinUrl", "https://playbound.club/c/" + str(res.joinCode))),
		"ice": endpoints.get("iceServers", [])}
	_since = 0
	_seen = {}
	_next_poll_ms = 0
	_next_status_ms = Time.get_ticks_msec() + STATUS_MS
	print("PHONE_SESSION %s" % session.join_url)
	changed.emit()


## Ends the session: phones disconnect and their slots free up.
func stop() -> void:
	if not active():
		return
	var ending := session
	for id in _peers.keys():
		_drop(id)
	_devices = {}
	_pending_ice = {}
	session = {}
	changed.emit()
	await api.call_api(HTTPClient.METHOD_DELETE, "/api/couch/sessions/%s?hostToken=%s" % [
		ending.id, str(ending.host_token).uri_encode()], null, false)


func _process(_delta: float) -> void:
	if not active():
		return
	var now := Time.get_ticks_msec()
	for id in _peers.keys():
		_poll_peer(id, now)
	if now >= _next_poll_ms and not _poll_busy:
		var handshaking := false
		for id in _peers:
			handshaking = handshaking or _peers[id].last_ms == 0
		var fast := handshaking or connected_count() == 0
		_next_poll_ms = now + (SIGNAL_FAST_MS if fast else SIGNAL_IDLE_MS)
		_poll_signals()
	if now >= _next_status_ms:
		_next_status_ms = now + STATUS_MS
		_heartbeat()


# --- Signaling -----------------------------------------------------------------

func _poll_signals() -> void:
	_poll_busy = true
	var s := session
	# Signals can be stored slightly out of order: replay a window, skip seen ids.
	var path := "/api/couch/sessions/%s/signal?forRole=host&hostToken=%s&since=%d" % [
		s.id, str(s.host_token).uri_encode(), maxi(0, _since - 10000)]
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, path, null, false)
	_poll_busy = false
	if session != s or not res._ok:
		return
	for m in res.get("messages", []):
		var id := str(m.get("id", ""))
		if _seen.has(id):
			continue
		_seen[id] = true
		_since = maxi(_since, int(m.get("timestamp", 0)))
		var payload = JSON.parse_string(str(m.get("payload", "")))
		if not payload is Dictionary:
			continue
		var from := str(payload.get("from", ""))
		if from == "":
			continue
		match str(payload.get("kind", "")):
			"offer":
				if payload.get("sdp") is Dictionary:
					_answer(from, str(payload.sdp.get("sdp", "")))
			"ice":
				if payload.get("candidate") is Dictionary:
					_remote_candidate(from, payload.candidate)


func _post(msg: Dictionary) -> void:
	if not active():
		return
	await api.call_api(HTTPClient.METHOD_POST, "/api/couch/sessions/%s/signal" % session.id, {
		"senderRole": "host", "recipientRole": "controller", "senderPeerId": "host",
		"hostToken": session.host_token, "payload": JSON.stringify(msg)}, false)


func _heartbeat() -> void:
	var s := session
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, "/api/couch/sessions/%s?hostToken=%s" % [
		s.id, str(s.host_token).uri_encode()], null, false)
	if session == s and res._status == 404:
		error = "PHONE SESSION ENDED"
		stop()


# --- Peers -----------------------------------------------------------------------

## The phone always offers (it adds a receive-only video track for PlayBound's
## game view, which we leave unanswered); we answer with the data channel.
func _answer(controller_id: String, sdp: String) -> void:
	if _peers.has(controller_id):
		_close_peer(controller_id)
	var pc := WebRTCPeerConnection.new()
	if pc.initialize({"iceServers": _ice_servers()}) != OK:
		error = "WEBRTC UNAVAILABLE"
		changed.emit()
		return
	var peer := {"pc": pc, "channel": null, "last_ms": 0}
	_peers[controller_id] = peer
	pc.data_channel_received.connect(func(ch: WebRTCDataChannel):
		ch.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
		peer.channel = ch)
	pc.session_description_created.connect(func(type: String, desc: String):
		pc.set_local_description(type, desc)
		_post({"kind": type, "sdp": {"type": type, "sdp": desc}, "to": controller_id}))
	pc.ice_candidate_created.connect(func(media: String, index: int, name: String):
		_post({"kind": "ice", "candidate": {"candidate": name, "sdpMid": media, "sdpMLineIndex": index},
			"to": controller_id}))
	# Setting a remote offer makes the peer create the answer.
	if pc.set_remote_description("offer", sdp) != OK:
		_close_peer(controller_id)
		return
	for c in _pending_ice.get(controller_id, []):
		_add_candidate(pc, c)
	_pending_ice.erase(controller_id)


func _remote_candidate(controller_id: String, c: Dictionary) -> void:
	if str(c.get("candidate", "")) == "":
		return  # end-of-candidates marker
	if _peers.has(controller_id):
		_add_candidate(_peers[controller_id].pc, c)
	else:
		var list: Array = _pending_ice.get(controller_id, [])
		list.append(c)
		_pending_ice[controller_id] = list


func _add_candidate(pc: WebRTCPeerConnection, c: Dictionary) -> void:
	pc.add_ice_candidate(str(c.get("sdpMid", "0")), int(c.get("sdpMLineIndex", 0)), str(c.candidate))


func _poll_peer(controller_id: String, now: int) -> void:
	var peer: Dictionary = _peers[controller_id]
	var pc: WebRTCPeerConnection = peer.pc
	pc.poll()
	var ch: WebRTCDataChannel = peer.channel
	if ch != null:
		while ch.get_available_packet_count() > 0:
			_on_message(controller_id, ch, ch.get_packet().get_string_from_utf8(), now)
	var state := pc.get_connection_state()
	var gone := state == WebRTCPeerConnection.STATE_FAILED or state == WebRTCPeerConnection.STATE_CLOSED
	if gone or (peer.last_ms > 0 and now - peer.last_ms > PAD_TIMEOUT_MS):
		_drop(controller_id)


func _on_message(controller_id: String, ch: WebRTCDataChannel, text: String, now: int) -> void:
	var msg = JSON.parse_string(text)
	if not msg is Dictionary:
		return
	if int(msg.get("v", 0)) == 1:
		_on_input(controller_id, msg, now)
	elif msg.get("type", "") == "ping":
		ch.put_packet(JSON.stringify({"type": "pong", "t": msg.get("t", 0)}).to_utf8_buffer())


func _on_input(controller_id: String, msg: Dictionary, now: int) -> void:
	var peer: Dictionary = _peers[controller_id]
	var first: bool = peer.last_ms == 0
	peer.last_ms = now
	if not _devices.has(controller_id):
		var used := _devices.values()
		var device := _virtual_base()
		while device in used:
			device += 1
		_devices[controller_id] = device
	var bits := int(msg.get("buttons", 0))
	if OS.get_environment("HYPERDISC_PHONE_DEBUG") != "" and bits != int(peer.get("bits", 0)):
		print("PHONE_BUTTONS %s %d" % [controller_id.left(8), bits])
	peer["bits"] = bits
	var buttons := {}
	for bit in BUTTON_BITS:
		buttons[BUTTON_BITS[bit]] = (bits >> bit) & 1 == 1
	var axes := Vector2(clampf(float(msg.get("lx", 0.0)), -1, 1), clampf(float(msg.get("ly", 0.0)), -1, 1))
	var controls := get_node_or_null("/root/Controls")
	if controls != null:
		controls.set_virtual_pad(_devices[controller_id], PAD_NAME, axes, buttons)
	if first:
		print("PHONE_CONNECTED %s device=%d" % [controller_id, _devices[controller_id]])
		changed.emit()


## Forgets a phone's connection and frees its controller slot.
func _drop(controller_id: String) -> void:
	print("PHONE_DROPPED %s" % controller_id)
	_close_peer(controller_id)
	var controls := get_node_or_null("/root/Controls")
	if controls != null and _devices.has(controller_id):
		controls.remove_virtual_pad(_devices[controller_id])
	changed.emit()


func _close_peer(controller_id: String) -> void:
	var peer: Dictionary = _peers.get(controller_id, {})
	if not peer.is_empty():
		if peer.channel != null:
			peer.channel.close()
		peer.pc.close()
	_peers.erase(controller_id)


func _virtual_base() -> int:
	var controls := get_node_or_null("/root/Controls")
	return controls.VIRTUAL_BASE if controls != null else 1000


## PlayBound's ICE list (STUN + TURN) in the shape WebRTCPeerConnection wants.
func _ice_servers() -> Array:
	var out := []
	for s in session.get("ice", []):
		if not s is Dictionary or not s.has("urls"):
			continue
		var entry := {"urls": [s.urls] if s.urls is String else s.urls}
		if s.has("username"):
			entry["username"] = str(s.username)
			entry["credential"] = str(s.get("credential", ""))
		out.append(entry)
	return out
