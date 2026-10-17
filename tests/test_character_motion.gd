extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var rules: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var sim=load("res://scripts/sim/match_sim.gd").new(rules,rules.characters[0],rules.characters[1],0)
	var names: Array[String]=["LEFT","RIGHT"]
	var view=load("res://scripts/game/view/match_view.gd").new(sim,["mick","tiffany"],names)
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
	for id in ["mick","pete","tiffany","keno","steve","vanessa"]:
		var art=load("res://scripts/game/view/character_art.gd").new(id)
		assert(art.animations.run.count==12 and art.animations.dash.count==6)
		assert(art.frame_for("run",-1)==art.frame_for("run",31))
		assert(art.frame_for("dash",8)<art.frame_for("dash",9))
		assert(art.frame_for("dash",15)==art.frame_for("dash",100))
	print("CHARACTER MOTION TESTS PASSED")
	quit()
