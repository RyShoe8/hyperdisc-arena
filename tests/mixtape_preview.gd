## Test-only fixture: never registered in the catalog or bundled as music.
extends "res://scripts/game/main.gd"

func _ready() -> void:
	super._ready()
	Mixtape.tracks = []
	Mixtape.inventory = []
	for i in 20:
		var id := "test_%d" % i
		Mixtape.tracks.append({"id": id, "title": "TEST CASSETTE %02d" % i, "artist": "PLAYBACK TEST", "album": "TEST FIXTURE", "year": 2026, "bio": "Synthetic test metadata. No artist tracks are included.", "starter": i < 5, "audioUrl": ""})
		Mixtape.inventory.append(id)
	Mixtape.deck = Mixtape.inventory.slice(0, 6)
	tapes.draft = Mixtape.deck.duplicate()
	screen = Screen.MIXTAPE
	for arg in OS.get_cmdline_user_args():
		if arg == "--jcard-test":
			tapes.jcard = true
