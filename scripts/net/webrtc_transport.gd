## Peer-to-peer packets over WebRTC, set up through PlayBound Connect: the
## room's signal endpoint carries the offer, answer and ICE candidates, and
## Connect's STUN/TURN servers find a direct route through home routers or
## relay when there isn't one. No port forwarding needed.
##
## The data channel is unordered with no retransmits: rollback netcode
## resends inputs itself, so a late packet is worse than a lost one.
extends "res://scripts/net/transport.gd"

const GAME_SLUG := "hyperdisc-arena"
## How long to keep trying before giving up on a connection.
const CONNECT_TIMEOUT_MS := 30000

var api  # PlayBoundApi node
var session_id := ""
var session_token := ""
var room_code := ""
var role := "host"  # "host" or "client"

var peer := WebRTCPeerConnection.new()
var channel: WebRTCDataChannel
var _since := 0
var _seen := {}  # signal ids already handled
var _poll_busy := false
var _next_poll_ms := 0
var _next_join_ms := 0
var _offered := false
var _answered := false
var _started_ms := 0
var _opened := false
var _closed := false
var _next_heartbeat_ms := 0
var _heartbeat_busy := false
var _remote_description_set := false
var _pending_candidates: Array = []


## info is the Connect session response: sessionId, joinCode, hostToken or
## clientToken, stunServers, turnServers.
func start(playbound_api, info: Dictionary, as_role: String) -> int:
	api = playbound_api
	role = as_role
	session_id = str(info.get("sessionId", ""))
	room_code = str(info.get("joinCode", ""))
	session_token = str(info.get("hostToken" if role == "host" else "clientToken", ""))
	var ice := []
	var stun: Array = info.get("stunServers", [])
	if not stun.is_empty():
		ice.append({"urls": stun})
	for t in info.get("turnServers", []):
		ice.append({"urls": [t.urls] if t.urls is String else t.urls, "username": t.username, "credential": t.credential})
	var err := peer.initialize({"iceServers": ice})
	if err != OK:
		failure = "WEBRTC UNAVAILABLE (ERROR %d)" % err
		return err
	channel = peer.create_data_channel("hyperdisc", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
	peer.session_description_created.connect(_on_description)
	peer.ice_candidate_created.connect(_on_candidate)
	_started_ms = Time.get_ticks_msec()
	return OK


func has_peer() -> bool:
	return channel != null and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN


func describe() -> String:
	return "ROOM " + room_code


func send(data: PackedByteArray) -> void:
	if has_peer():
		channel.put_packet(data)


func receive() -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	peer.poll()
	var now := Time.get_ticks_msec()
	if not _closed and role == "host" and now >= _next_heartbeat_ms and not _heartbeat_busy:
		_next_heartbeat_ms = now + 20000
		_heartbeat()
	if has_peer():
		_opened = true
	elif failure == "":
		var state := peer.get_connection_state()
		if state == WebRTCPeerConnection.STATE_FAILED:
			failure = "COULDN'T CONNECT TO THE OTHER PLAYER"
		elif _opened and state != WebRTCPeerConnection.STATE_CONNECTED:
			failure = "CONNECTION LOST"
		elif not _opened and role == "client" and now - _started_ms > CONNECT_TIMEOUT_MS:
			failure = "COULDN'T CONNECT TO THE HOST"
		# The guest announces itself until the host's offer arrives.
		if role == "client" and not _answered and now >= _next_join_ms:
			_next_join_ms = now + 3000
			_signal({"t": "join"})
		if now >= _next_poll_ms and not _poll_busy:
			_next_poll_ms = now + 500
			_poll_signals()
	if channel != null:
		while channel.get_available_packet_count() > 0:
			out.append(channel.get_packet())
	return out


func close() -> void:
	_closed = true
	if channel != null:
		channel.close()
	peer.close()
	if role == "host":
		api.call_api(HTTPClient.METHOD_DELETE, "/api/multiplayer/%s/sessions/%s/heartbeat" % [GAME_SLUG, session_id], null, true, session_token)


func _heartbeat() -> void:
	_heartbeat_busy = true
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST,
		"/api/multiplayer/%s/sessions/%s/heartbeat" % [GAME_SLUG, session_id], {}, true, session_token)
	_heartbeat_busy = false
	if _closed:
		return
	if not res._ok:
		if res._status in [401, 404]:
			failure = "ROOM EXPIRED - CREATE A NEW ROOM"
		else:
			_next_heartbeat_ms = Time.get_ticks_msec() + 3000


# --- Signaling through PlayBound Connect --------------------------------------

func _signal(msg: Dictionary) -> void:
	var body := {"senderRole": role, "recipientRole": "client" if role == "host" else "host",
		"senderPeerId": role, "payload": JSON.stringify(msg)}
	_post(body)


func _post(body: Dictionary) -> void:
	# Signals are fire-and-forget; a lost one is covered by ICE retries and
	# the guest's repeated join.
	var path := "/api/multiplayer/%s/sessions/%s/signal" % [GAME_SLUG, session_id]
	for attempt in range(3):
		if _closed:
			return
		var res: Dictionary = await api.call_api(HTTPClient.METHOD_POST, path, body, true, session_token)
		if res._ok:
			return
		if res._status in [400, 401, 404]:
			failure = "PLAYBOUND SIGNALING FAILED: " + str(res.get("error", res._status)).to_upper()
			return
	if not _closed:
		failure = "COULDN'T SEND CONNECTION DETAILS TO PLAYBOUND"


func _poll_signals() -> void:
	_poll_busy = true
	# Ask from a millisecond back: two signals can share a timestamp, and the
	# second may land after a poll that returned the first.
	var path := "/api/multiplayer/%s/sessions/%s/signal?forRole=%s&since=%d" % [GAME_SLUG, session_id, role, maxi(0, _since - 1)]
	var res: Dictionary = await api.call_api(HTTPClient.METHOD_GET, path, null, true, session_token)
	_poll_busy = false
	if _closed:
		return
	if not res._ok:
		if res._status in [401, 404]:
			failure = "ROOM EXPIRED - CREATE A NEW ROOM"
		return
	for m in res.get("messages", []):
		_since = maxi(_since, int(m.get("timestamp", 0)))
		var id := str(m.get("id", ""))
		if id != "":
			if _seen.has(id):
				continue
			_seen[id] = true
		var msg = JSON.parse_string(str(m.get("payload", "")))
		if msg is Dictionary:
			_on_signal(msg)


func _on_signal(msg: Dictionary) -> void:
	match msg.get("t", ""):
		"join":
			# A guest arrived: the host makes the offer (again, if the guest
			# missed the first one).
			if role == "host" and not _offered:
				_offered = true
				peer.create_offer()
		"sdp":
			var kind := str(msg.get("type", ""))
			if role == "client" and kind == "offer" and not _answered:
				_answered = true
				peer.set_remote_description(kind, str(msg.get("sdp", "")))
				_remote_description_set = true
				_flush_candidates()
			elif role == "host" and kind == "answer" and not _remote_description_set:
				peer.set_remote_description(kind, str(msg.get("sdp", "")))
				_remote_description_set = true
				_flush_candidates()
		"ice":
			var c := [str(msg.get("media", "")), int(msg.get("index", 0)), str(msg.get("name", ""))]
			if _remote_ready():
				peer.add_ice_candidate(c[0], c[1], c[2])
			else:
				_pending_candidates.append(c)


func _remote_ready() -> bool:
	return _remote_description_set


func _flush_candidates() -> void:
	for c in _pending_candidates:
		peer.add_ice_candidate(c[0], c[1], c[2])
	_pending_candidates.clear()


func _on_description(kind: String, sdp: String) -> void:
	peer.set_local_description(kind, sdp)
	_signal({"t": "sdp", "type": kind, "sdp": sdp})


func _on_candidate(media: String, index: int, name: String) -> void:
	_signal({"t": "ice", "media": media, "index": index, "name": name})
