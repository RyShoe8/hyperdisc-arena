extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/characters/catalog.json"))
	for character in catalog.characters:
		assert(FileAccess.get_sha256("res://"+character.base)==character.hashes["base.png"])
		assert(FileAccess.get_sha256("res://"+character.reference)==character.hashes["reference.png"])
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	for character in rules.characters:
		var art = load("res://scripts/game/view/character_art.gd").new(character.id)
		var previous: int = art.frame_for("idle",0)
		for tick in 360:
			var current: int = art.frame_for("idle",tick)
			assert(absi(current-previous)<=1, "idle must not jump from final pose to first")
			previous = current
	var sim=load("res://scripts/sim/match_sim.gd").new(rules,rules.characters[0],rules.characters[1],0)
	var names: Array[String]=["LEFT","RIGHT"]
	var view=load("res://scripts/game/view/match_view.gd").new(sim,["mick","tiffany"],names)
	# Referee delivery must never select the power-up pose, even with stale charge.
	var serve_sim = load("res://scripts/sim/match_sim.gd").new(rules,rules.characters[0],rules.characters[6],3)
	var serve_view = load("res://scripts/game/view/match_view.gd").new(serve_sim,["mick","alex"],names)
	var saw_toss := false
	var saw_catch := false
	for tick in 260:
		serve_sim.step([{},{}])
		serve_view.tick()
		if serve_sim.disc.state == serve_sim.Disc.AIR and serve_sim.disc.air_kind == serve_sim.Air.REF:
			saw_toss = true
			for receiver in serve_sim.players:
				assert(receiver.charge == 0)
				assert(serve_view._anim_for(receiver)[0] != "charge")
		if serve_sim.players[serve_sim.server].serving:
			saw_catch = true
			break
	assert(saw_toss and saw_catch, "exercise the full referee delivery and catch")
	sim.phase=sim.Phase.PLAY
	var p=sim.players[0]
	# A prior jump must not suppress a subsequent dive or its recovery.
	p.action=sim.Act.JUMP
	p.action_ticks=100
	p.dash_ticks=9
	p.dash_dir=Vector2.LEFT
	assert(view._anim_for(p)==["dash",0])
	p.dash_ticks=0
	p.recovery_ticks=7
	view.dive_age[0]=9
	assert(view._anim_for(p)==["dash",9])
	p.recovery_ticks=0
	view.moving[0]=true
	view.run_phase[0]=-1
	assert(view._anim_for(p)==["run",-1])
	# Sustained vertical movement turns; a single diagonal wobble does not.
	for i in 8:
		p.pos.y -= 3
		view.tick()
	assert(view.run_direction[0]=="run_up")
	assert(view._anim_for(p)[0]==("run_up" if view.arts[0].animations.has("run_up") else "run"))
	p.pos += Vector2(3,0.1)
	view.tick()
	assert(view.run_direction[0]=="run_up")
	for i in 10:
		p.pos.y += 3
		view.tick()
	assert(view.run_direction[0]=="run_down")
	view.tick()
	assert(view._anim_for(p)[0]=="idle")
	sim.server=sim.LEFT
	view.handle({"type":"ref_toss"})
	assert(not view.ref_facing_right)
	sim.server=sim.RIGHT
	view.handle({"type":"ref_toss"})
	assert(view.ref_facing_right)
	view.ref_anim="idle"
	sim.disc.pos.x=0
	for i in 30: view.tick()
	assert(not view.ref_facing_right)
	sim.disc.pos.x=sim.court_width()
	for i in 30: view.tick()
	assert(view.ref_facing_right)
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		var art=load("res://scripts/game/view/character_art.gd").new(id)
		assert(art.animations.run.count==12 and art.animations.dash.count==6)
		assert(art.animations.win.count==8 and not art.animations.win.loop)
		assert(art.frame_for("win",0)==art.animations.win.start)
		assert(art.frame_for("win",1000)==art.animations.win.start+7)
		assert(art.animations.has("run_up") and art.animations.has("run_down"))
		if art.animations.has("run_up"):
			assert(art.animations.run_up.count==8 and art.animations.run_down.count==8)
			assert(art.frame_for("run_up",32)==art.frame_for("run_up",0))
			assert(art.frame_for("run_up",0)!=art.frame_for("run_down",0))
		assert(art.frame_for("run",-1)==art.frame_for("run",31))
		assert(art.frame_for("dash",8)<art.frame_for("dash",9))
		assert(art.frame_for("dash",15)==art.frame_for("dash",100))
	sim.phase=sim.Phase.MATCH_OVER
	sim.winner=0
	view.frame=999
	view.handle({"type":"match_over","winner":0})
	assert(view._anim_for(p)==["win",0])
	view.tick()
	assert(view._anim_for(p)==["win",1])
	var crowd=view.pixel_spectators
	crowd.ticks_left=0
	assert(crowd.frames.watch != null)
	crowd.handle({"type":"point","side":0})
	var serial: int=crowd.event_serial
	crowd.handle({"type":"catch","side":1,"speed":30})
	assert(crowd.reaction=="cheer" and crowd.reaction_side==0 and crowd.event_serial==serial)
	for i in 151: crowd.tick()
	assert(crowd.reaction=="watch")
	print("CHARACTER MOTION TESTS PASSED")
	quit()
