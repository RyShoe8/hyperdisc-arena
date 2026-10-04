## Account collection and soundtrack. Downloads only the current song to a
## bounded disk cache; audio never participates in the rollback simulation.
extends Node

signal changed
const CACHE := "user://mixtape_cache"
const MAX_CACHE := 300 * 1024 * 1024
var tracks: Array = []
var inventory: Array = []
var deck: Array = []
var menu_tape := ""
var message := ""
var now_playing := {}
var active_match := ""
var match_info := {}
var dub_candidates: Array = []
var music_volume := 0.7
var _player: AudioStreamPlayer
var _playlist: Array = []
var _index := 0
var _mode := "menu"
var _generation := 0
var _account := ""
var _refreshing := false
var _reported := false
var _catalog_elapsed := 0.0
var _failed_tracks := {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(CACHE)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_next)
	var config := ConfigFile.new()
	if config.load("user://mixtape.cfg") == OK:
		music_volume = float(config.get_value("audio", "volume", 0.7))
	Online.playbound.profile_changed.connect(_account_changed)
	refresh()

func _process(delta: float) -> void:
	_player.volume_db = linear_to_db(maxf(0.0001, music_volume))
	_catalog_elapsed += delta
	if _catalog_elapsed >= 120.0:
		_catalog_elapsed = 0.0
		refresh()

func set_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	var config := ConfigFile.new()
	config.set_value("audio", "volume", music_volume)
	config.save("user://mixtape.cfg")

func catalog_ready() -> bool:
	var base := 0
	var pool := 0
	for tape in tracks:
		if tape.get("starter", false):
			base += 1
		else:
			pool += 1
	return base == 5 and pool >= 15

## Decks hold six tapes, or every owned tape while the catalog is smaller
## (PlayBound's testing mode before the launch catalog exists).
func deck_size() -> int:
	var owned := 0
	for t in tracks:
		if inventory.has(str(t.get("id", ""))):
			owned += 1
	return clampi(owned, 1, 6)

func valid_deck() -> bool:
	if deck.size() != deck_size():
		return false
	var seen := {}
	for id in deck:
		if seen.has(id) or not inventory.has(id) or track(str(id)).is_empty():
			return false
		seen[id] = true
	return true

func track(id: String) -> Dictionary:
	for t in tracks:
		if str(t.get("id", "")) == id:
			return t
	return {}

func _account_changed() -> void:
	_account = str(Online.playbound.profile().get("id", "")) if Online.signed_in() else ""
	inventory = []
	deck = []
	dub_candidates = []
	active_match = ""
	match_info = {}
	changed.emit()
	if _refreshing:
		await changed
	refresh()

func refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	var account := str(Online.playbound.profile().get("id", "")) if Online.signed_in() else ""
	if account != _account:
		inventory = []
		deck = []
		_account = account
	var catalog: Dictionary = await Online.api.call_api(HTTPClient.METHOD_GET, "/api/mixtape/catalog", null, false)
	if catalog.get("_ok", false):
		tracks = catalog.get("tracks", [])
		menu_tape = str(catalog.get("menuTapeId", ""))
		message = "NO TAPES YET - THE SOUNDTRACK IS COMING SOON" if tracks.is_empty() else ""
	else:
		message = "COULDN'T LOAD THE TAPE LIBRARY"
	if account != "":
		var result: Dictionary = await Online.api.call_api(HTTPClient.METHOD_GET, "/api/mixtape/player")
		if account == _account and result.get("_ok", false):
			inventory = result.get("inventory", [])
			deck = result.get("deck", [])
		elif account == _account and not tracks.is_empty():
			message = str(result.get("error", "TAPE COLLECTION UNAVAILABLE"))
	_refreshing = false
	if _mode == "menu":
		var wanted: Array = [menu_tape] if not track(menu_tape).is_empty() else []
		if wanted != _playlist or (not wanted.is_empty() and not _player.playing):
			_set_playlist(wanted)
	changed.emit()

func save_deck(ids: Array) -> bool:
	var res: Dictionary = await Online.api.call_api(HTTPClient.METHOD_PUT, "/api/mixtape/player", {"trackIds": ids})
	if res.get("_ok", false):
		deck = res.get("deck", [])
		message = "MATCH DECK SAVED"
	else:
		message = str(res.get("error", "COULDN'T SAVE DECK"))
	changed.emit()
	return bool(res.get("_ok", false))

func menu_music() -> void:
	if _mode == "menu":
		return
	_mode = "menu"
	_set_playlist([menu_tape] if not track(menu_tape).is_empty() else [])

func local_music() -> void:
	_mode = "match"
	_set_playlist(deck.duplicate())

func begin_match(o) -> void:
	_mode = "match"
	_reported = false
	active_match = o.mixtape_match_id
	match_info = {}
	dub_candidates = []
	_set_playlist(deck.duplicate())
	if not Online.signed_in() or active_match == "" or not valid_deck() or not "session_id" in o.transport:
		active_match = ""
		return
	var res: Dictionary = await Online.api.call_api(HTTPClient.METHOD_POST, "/api/mixtape/match", {
		"action": "register", "matchId": active_match, "sessionId": o.transport.session_id,
		"sessionToken": o.transport.session_token, "role": "host" if o.is_host else "client"})
	if not res.get("_ok", false):
		message = str(res.get("error", "MATCH MUSIC UNAVAILABLE"))
		active_match = ""
		return
	for attempt in 10:
		if active_match != o.mixtape_match_id:
			return
		match_info = res
		var players: Dictionary = res.get("players", {})
		if players.get("host", "") != "" and players.get("client", "") != "":
			var decks: Dictionary = res.get("decks", {})
			var left: Array = decks.get(players.host, [])
			var right: Array = decks.get(players.client, [])
			var merged: Array = []
			for i in mini(left.size(), right.size()):
				merged.append(left[i])
				merged.append(right[i])
			if _mode == "match":
				_set_playlist(merged)
			return
		await get_tree().create_timer(1.0).timeout
		res = await Online.api.call_api(HTTPClient.METHOD_GET, "/api/mixtape/match?matchId=" + active_match.uri_encode())

func finish_match(o) -> void:
	if _reported or active_match == "" or not o.match_settled():
		return
	_reported = true
	var reporting_match := active_match
	var players: Dictionary = match_info.get("players", {})
	var winner_id := str(players.get("host" if o.sim.winner == 0 else "client", ""))
	if winner_id == "":
		return
	var checksum := str(JSON.stringify([o.sim.winner, o.sim.sets_won, o.court]).hash())
	var res: Dictionary = await Online.api.call_api(HTTPClient.METHOD_POST, "/api/mixtape/match", {"action": "report", "matchId": active_match, "winner": winner_id, "checksum": checksum})
	for attempt in 15:
		if reporting_match != active_match:
			return
		if res.get("winner", "") != "":
			match_info = res
			if str(res.winner) == _account:
				var loser := str(players.get("client" if o.sim.winner == 0 else "host", ""))
				dub_candidates = res.get("decks", {}).get(loser, [])
			changed.emit()
			return
		await get_tree().create_timer(1.0).timeout
		res = await Online.api.call_api(HTTPClient.METHOD_GET, "/api/mixtape/match?matchId=" + active_match.uri_encode())
	message = "WAITING FOR BOTH MATCH RESULTS - REOPEN DUB TAPES TO RETRY"
	_reported = false

func dub(id: String) -> bool:
	var res: Dictionary = await Online.api.call_api(HTTPClient.METHOD_POST, "/api/mixtape/match", {"action": "dub", "matchId": active_match, "trackId": id})
	if res.get("_ok", false):
		inventory = res.get("inventory", inventory)
		match_info["dubTrack"] = id
		message = "TAPE DUBBED - THE ORIGINAL STAYS WITH YOUR OPPONENT"
	else:
		message = str(res.get("error", "COULDN'T DUB TAPE"))
	changed.emit()
	return bool(res.get("_ok", false))

func next_round() -> void:
	if _mode == "match":
		_next()

func _set_playlist(ids: Array) -> void:
	_generation += 1
	_player.stop()
	now_playing = {}
	_playlist = ids
	_index = 0
	if not ids.is_empty():
		_play(str(ids[0]), _generation)

func _next() -> void:
	if _playlist.is_empty():
		return
	_index = (_index + 1) % _playlist.size()
	_generation += 1
	_play(str(_playlist[_index]), _generation)

func _play(id: String, generation: int) -> void:
	var info := track(id)
	if info.is_empty() or int(_failed_tracks.get(id, 0)) > Time.get_ticks_msec():
		_skip_unavailable(id, generation)
		return
	var path := await cache_asset(str(info.get("audioUrl", "")), "audio")
	if generation != _generation:
		return
	if path == "":
		_skip_unavailable(id, generation)
		return
	var stream: AudioStream
	match path.get_extension():
		"ogg": stream = AudioStreamOggVorbis.load_from_file(path)
		"mp3": stream = AudioStreamMP3.load_from_file(path)
		"wav": stream = AudioStreamWAV.load_from_file(path)
	if stream == null:
		message = "THIS TAPE COULDN'T BE PLAYED"
		DirAccess.remove_absolute(path)
		_skip_unavailable(id, generation)
		return
	_player.stream = stream
	_player.play()
	now_playing = info
	changed.emit()

func _skip_unavailable(id: String, generation: int) -> void:
	_failed_tracks[id] = Time.get_ticks_msec() + 60000
	var available := false
	for tape in _playlist:
		if int(_failed_tracks.get(str(tape), 0)) <= Time.get_ticks_msec():
			available = true
	if available:
		await get_tree().create_timer(0.5).timeout
		if generation == _generation:
			_next()

func cache_asset(url: String, kind: String) -> String:
	if not url.begins_with("https://"):
		return ""
	var ext := url.split("?")[0].get_extension().to_lower()
	if (kind == "audio" and ext not in ["ogg", "mp3", "wav"]) or (kind == "cover" and ext not in ["png", "jpg", "jpeg"]):
		return ""
	var path := CACHE + "/" + url.sha256_text() + "." + ext
	if FileAccess.file_exists(path):
		return path
	_trim_cache()
	var req := HTTPRequest.new()
	req.timeout = 45.0
	req.body_size_limit = 50 * 1024 * 1024
	# Unique temporary file prevents a preview and soundtrack request racing.
	var temporary := path + "." + str(req.get_instance_id()) + ".part"
	req.download_file = temporary
	add_child(req)
	if req.request(url) != OK:
		req.queue_free()
		return ""
	var res: Array = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		DirAccess.remove_absolute(temporary)
		return ""
	DirAccess.rename_absolute(temporary, path)
	return path

func _trim_cache() -> void:
	var entries: Array = []
	var total := 0
	for file in DirAccess.get_files_at(CACHE):
		var path := CACHE + "/" + file
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var size := f.get_length()
			total += size
			entries.append({"path": path, "size": size, "time": FileAccess.get_modified_time(path)})
	entries.sort_custom(func(a, b): return a.time < b.time)
	for entry in entries:
		if total <= MAX_CACHE - 50 * 1024 * 1024:
			break
		DirAccess.remove_absolute(entry.path)
		total -= entry.size
