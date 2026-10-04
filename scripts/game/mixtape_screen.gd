extends RefCounted
const UI := preload("res://scripts/game/ui/theme.gd")
var m
var index := 0
var slot := 0
var draft: Array = []
var dubbing := false
var jcard := false
var busy := false
var cover: Texture2D
var cover_id := ""
var recording_until := 0

func _init(main) -> void:
	m = main

func open(as_dub := false) -> void:
	dubbing = as_dub
	index = 0
	slot = 0
	jcard = false
	draft = Mixtape.deck.duplicate()
	while draft.size() < Mixtape.deck_size():
		draft.append("")
	draft.resize(Mixtape.deck_size())
	Mixtape.refresh()
	if dubbing and Online.current != null:
		Mixtape.finish_match(Online.current)
	m._go(m.Screen.MIXTAPE)

func ids() -> Array:
	return Mixtape.dub_candidates if dubbing else Mixtape.inventory

func input() -> void:
	if dubbing and Online.current != null:
		Online.current.poll({})
	if busy:
		return
	if m._back_pressed():
		if jcard:
			jcard = false
		else:
			m._go(m.Screen.RESULTS if dubbing else m.Screen.MAIN)
		return
	var list := ids()
	if list.is_empty():
		if not dubbing and not Online.signed_in() and m._confirm_device() != -1:
			m.net.sign_in()
		return
	index = clampi(index, 0, list.size() - 1)
	var n := Controls.menu_nudged()
	if n.y != 0:
		index = posmod(index + n.y, list.size())
		Sfx.play("menu_move")
		if jcard:
			_load_cover(str(list[index]))
	if n.x != 0:
		slot = posmod(slot + n.x, draft.size())
	if Controls.menu_pressed("slap") != -1:
		jcard = not jcard
		if jcard:
			_load_cover(str(list[index]))
	if jcard:
		var tape := Mixtape.track(str(list[index]))
		if Controls.menu_pressed("jump") != -1:
			var website := str(tape.get("website", ""))
			if website.begins_with("https://"):
				OS.shell_open(website)
		if Controls.menu_pressed("start") != -1:
			var spotify := str(tape.get("spotify", ""))
			if spotify.begins_with("https://"):
				OS.shell_open(spotify)
		if Controls.menu_pressed("a") != -1:
			var url := str(tape.get("bandcamp", tape.get("website", "")))
			if url == "":
				url = str(tape.get("website", ""))
			if url.begins_with("https://"):
				OS.shell_open(url)
		return
	if Controls.menu_pressed("start") != -1 and not dubbing:
		busy = true
		await Mixtape.save_deck(draft)
		busy = false
		return
	if Controls.menu_pressed("a") != -1:
		var id := str(list[index])
		if dubbing:
			if Mixtape.inventory.has(id):
				m.toast_msg("IN COLLECTION")
			elif str(Mixtape.match_info.get("dubTrack", "")) != "":
				m.toast_msg("ONE TAPE PER VICTORY")
			else:
				busy = true
				if await Mixtape.dub(id):
					recording_until = m.frame + 150
					Sfx.play("match_win")
				busy = false
		else:
			# Swapping an equipped tape keeps the six slots unique.
			var previous := draft.find(id)
			if previous >= 0:
				draft[previous] = draft[slot]
			draft[slot] = id
			Sfx.play("menu_confirm")

func _load_cover(id: String) -> void:
	cover_id = id
	cover = null
	var path: String = await Mixtape.cache_asset(str(Mixtape.track(id).get("coverUrl", "")), "cover")
	if path == "" or cover_id != id:
		return
	var image := Image.new()
	if image.load(path) == OK:
		cover = ImageTexture.create_from_image(image)

func draw() -> void:
	UI.outrun_background(m, m.SCREEN, m.frame / 60.0, 0.4)
	UI.text(m, Vector2(960, 110), "DUB A TAPE" if dubbing else "YOUR MIXTAPES", 100, UI.YELLOW, UI.display)
	UI.text(m, Vector2(960, 170), "COPY ONE OPPONENT TAPE - THEY KEEP THE ORIGINAL" if dubbing else "SIX TAPES. YOUR MATCH SOUNDTRACK.", 26, UI.CYAN)
	var list := ids()
	if list.is_empty():
		UI.text(m, Vector2(960, 470), "NO TAPES TO DUB" if dubbing else "YOUR CASSETTE SHELF IS EMPTY", 48, UI.WHITE, UI.display)
		UI.text(m, Vector2(960, 540), "SIGN IN WITH PLAYBOUND TO START YOUR COLLECTION" if not Online.signed_in() else Mixtape.message.left(85).to_upper(), 24, UI.DIM)
	else:
		index = clampi(index, 0, list.size() - 1)
		var page := index / 4
		for row in 4:
			var i := page * 4 + row
			if i >= list.size():
				break
			var tape := Mixtape.track(str(list[i]))
			_cassette(Rect2(150, 240 + row * 165, 970, 142), tape, i == index)
			if dubbing and Mixtape.inventory.has(list[i]):
				UI.text(m, Vector2(1080, 360 + row * 165), "IN COLLECTION", 20, UI.DIM, null, 0, HORIZONTAL_ALIGNMENT_RIGHT)
		if not dubbing:
			for i in draft.size():
				var tape := Mixtape.track(str(draft[i]))
				UI.button(m, Rect2(1190, 240 + i * 95, 550, 78), "%d  %s" % [i + 1, str(tape.get("title", "EMPTY SLOT")).left(24)], slot == i, m.frame, 25)
			UI.text(m, Vector2(1465, 865), "START: SAVE MATCH DECK", 24, UI.YELLOW)
	if recording_until > m.frame:
		UI.text(m, Vector2(960, 955), "REC  ●  DUBBING YOUR NEW TAPE", 32, UI.PINK if m.frame % 30 < 15 else UI.YELLOW)
	else:
		UI.text(m, Vector2(960, 955), Mixtape.message.left(100).to_upper(), 22, UI.DIM)
	m._hint("UP/DOWN TAPE   LEFT/RIGHT SLOT   %s %s   %s J-CARD   %s BACK" % [m._a(), "DUB" if dubbing else "EQUIP", Controls.label(0, "slap"), m._b()])
	if list.is_empty():
		m.draw_rect(Rect2(0, 1000, 1920, 80), UI.NIGHT)
		m._hint("%s SIGN IN WITH PLAYBOUND    %s BACK" % [m._a(), m._b()] if not Online.signed_in() and not dubbing else "%s BACK" % m._b())
	if jcard and not list.is_empty():
		_draw_jcard(Mixtape.track(str(list[index])))

func _cassette(rect: Rect2, tape: Dictionary, selected: bool) -> void:
	UI.slant_panel(m, rect, UI.PURPLE if selected else UI.DEEP, UI.CYAN if selected else UI.PURPLE, 14, 4)
	var center := rect.position + Vector2(145, 70)
	for dx in [-42, 42]:
		m.draw_circle(center + Vector2(dx, 0), 27, UI.INK)
		m.draw_arc(center + Vector2(dx, 0), 17, m.frame * 0.02, m.frame * 0.02 + TAU * 0.85, 18, UI.CYAN if selected else UI.DIM, 4)
	UI.text(m, rect.position + Vector2(260, 56), str(tape.get("title", "UNAVAILABLE TAPE")).left(35), 30, UI.WHITE, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(m, rect.position + Vector2(260, 99), str(tape.get("artist", "")).left(42), 23, UI.YELLOW, null, 0, HORIZONTAL_ALIGNMENT_LEFT)

func _draw_jcard(tape: Dictionary) -> void:
	m.draw_rect(Rect2(0, 0, 1920, 1080), Color(0, 0, 0, 0.8))
	UI.slant_panel(m, Rect2(210, 170, 1500, 740), UI.DEEP, UI.CYAN, 30, 6)
	if cover != null:
		m.draw_texture_rect(cover, Rect2(280, 240, 490, 490), false)
	else:
		UI.slant_panel(m, Rect2(280, 240, 490, 490), UI.PURPLE, UI.CYAN, 16, 3)
		for x in [445, 605]:
			m.draw_circle(Vector2(x, 470), 65, UI.INK)
			m.draw_arc(Vector2(x, 470), 43, 0, TAU * 0.9, 24, UI.CYAN, 7)
		UI.text(m, Vector2(525, 655), "NO COVER ART", 26, UI.DIM)
	UI.text(m, Vector2(820, 275), str(tape.get("title", "")).left(30), 48, UI.YELLOW, UI.display, 0, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(m, Vector2(820, 335), str(tape.get("artist", "")).left(35), 30, UI.CYAN, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(m, Vector2(820, 390), "%s  %s" % [str(tape.get("album", "")).left(35), str(tape.get("year", "")) if tape.get("year") != null else ""], 24, UI.WHITE, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	var lines: Array[String] = [""]
	for word in str(tape.get("bio", "")).split(" "):
		var next := lines[-1] + (" " if lines[-1] != "" else "") + word
		if UI.text_width(next, 23) > 720 and lines[-1] != "":
			lines.append(word)
		else:
			lines[-1] = next
	for i in mini(5, lines.size()):
		UI.text(m, Vector2(820, 450 + i * 36), lines[i].left(64), 23, UI.DIM, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	var code := str(tape.get("discountCode", ""))
	UI.text(m, Vector2(820, 690), "%s%% OFF  -  %s" % [tape.get("discountPercent", ""), code] if code != "" else "", 28, UI.PINK, null, 0, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(m, Vector2(960, 825), "%s VISIT ARTIST STORE    %s CLOSE J-CARD" % [m._a(), m._b()], 26, UI.CYAN)
	UI.text(m, Vector2(960, 870), "%s WEBSITE   %s SPOTIFY" % [Controls.label(0, "jump"), Controls.label(0, "start")], 22, UI.DIM)
