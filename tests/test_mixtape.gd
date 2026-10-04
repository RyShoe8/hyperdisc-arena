extends SceneTree
var failures := 0
func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

func _run() -> void:
	var tapes = root.get_node("Mixtape")
	# Only synthetic silence; the catalog and production accounts are untouched.
	tapes.tracks = []
	tapes.inventory = []
	for i in 20:
		var id := "test_%d" % i
		tapes.tracks.append({"id": id, "starter": i < 5})
		tapes.inventory.append(id)
	tapes.deck = tapes.inventory.slice(0, 6)
	check(tapes.catalog_ready(), "starter catalog readiness")
	check(tapes.valid_deck(), "six owned tapes")
	tapes.deck[5] = tapes.deck[0]
	check(not tapes.valid_deck(), "duplicate tape rejected")
	tapes.deck[5] = "not_owned"
	check(not tapes.valid_deck(), "unowned tape rejected")
	tapes.deck = tapes.inventory.slice(0, 6)
	var url := "https://example.invalid/mixtape-silence-test.wav"
	var path: String = tapes.CACHE + "/" + url.sha256_text() + ".wav"
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(44100 * 2)
	stream.data = samples
	check(stream.save_to_wav(path) == OK, "test cache written")
	check(await tapes.cache_asset(url, "audio") == path, "cache hit avoids downloading")
	tapes.tracks[0]["audioUrl"] = url
	tapes._set_playlist(["test_0"])
	check(tapes._player.stream != null, "cached WAV decoded")
	check(tapes.now_playing.get("id") == "test_0", "now playing metadata")
	tapes._set_playlist([])
	check(tapes.now_playing.is_empty(), "empty catalog leaves no stale song metadata")
	DirAccess.remove_absolute(path)
	print("MIXTAPE TESTS PASSED" if failures == 0 else "MIXTAPE TESTS FAILED")
	quit(0 if failures == 0 else 1)
