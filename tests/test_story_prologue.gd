extends SceneTree
var failed := 0
func check(value: bool, message: String) -> void:
	if not value:
		failed += 1
		printerr(message)
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.story_order = game._story_ladder()
	game.story_round = 0
	game._play_story_opening()
	var opening = game.get_node("StoryPrologue")
	opening.set_physics_process(false)
	check(not game.is_physics_processing(), "Menus must not receive cinematic input")
	check(root.get_node("Mixtape").cinematic_active, "Menu music must pause during the cinematic")
	var table: Dictionary = opening.timeline
	check(table.ids.size() == 10, "The opening must use all ten existing characters")
	check(str(table.generator).begins_with("Rigby2D"), "Motion must be evaluated by Rigby")
	for index in table.beats.size():
		opening.seek(float(table.beats[index].start) + 0.1)
		check(opening.beat_index == index, "Seek must resolve every dialogue beat")
		for actor in opening.actors:
			check(not actor.quads.is_empty() or actor.skin != null, "Every actor must have an evaluated pose")
		if not str(table.beats[index].speaker).is_empty():
			var joined: String = " ".join(opening.dialogue.pages)
			check(joined==str(table.beats[index].text).replace("\n"," ").replace("  "," "),"Balloon pages must preserve every spoken word")
	opening.seek(3.249)
	var catch_before: Vector2 = opening.props.ball_position()
	opening.seek(3.25)
	check(catch_before.distance_to(opening.props.mouth())<5,"Ball must meet Tango's mouth at the catch")
	for t in [3.5,4.6,6.8]:
		opening.seek(t)
		check(opening.props.ball_position().distance_to(opening.props.mouth())<.01,"Caught ball must remain in Tango's mouth")
	for offset in [1.2,1.8,2.1,2.7,3.2]:
		opening.seek(float(table.beats[6].start)+offset)
		var palm: Vector2 = opening.props.hand("tiffany")
		var rail_y := 406+(1185-palm.x)*255/366
		check(absf(palm.y-rail_y)<9,"Stair hand must track the painted rail")
	var stair: Dictionary = table.cast.tiffany.stairs
	for step in stair.treads.size():
		opening.seek(float(table.beats[6].start)+float(stair.start)+(step+.95)*float(stair.step))
		var tiff: Node2D = opening.props.cast.tiffany
		var sole: Vector2 = tiff.attachment_point("front_sole" if step%2==0 else "back_sole")
		var tread: Array = stair.treads[step]
		# The stage clock and local pose clock are independently sampled at 30Hz.
		# Allow subpixel bake quantization, never a visible floating foot.
		check(sole.distance_to(Vector2(tread[0],tread[1]))<.35,"Step %d: sole %s must reach tread %s (gap %.3f)" % [step,sole,tread,sole.distance_to(Vector2(tread[0],tread[1]))])
		if step<stair.treads.size()-1:
			check(tiff.z_index<opening.tower_front.z_index,"The near rail must occlude the descending actor")
	check(opening.whistle.z_index==opening.props.cast.tiffany.z_index+1,"The worn whistle must share Tiffany's depth")
	opening.seek(float(table.beats[16].start)+1)
	check(opening.props.hand("vanessa").distance_to(Vector2(1890,626))<6,"Vanessa must contact the tower post")
	opening.seek(float(table.beats[35].start)+.4)
	check(opening.actors[3].last_key.begins_with("look_back"),"Tango must look back at Mick before the jump")
	check(opening.actors[9].position.x-opening.actors[0].position.x>1000,"Keno needs a readable throwing lane")
	opening.seek(float(table.beats[35].start)+1.6)
	var release: Vector2 = opening.props.disc_position()
	var target: Vector2 = opening.props.cast.mick.attachment_point("head")
	opening.seek(float(table.beats[35].start)+2.6)
	var direction: Vector2 = (opening.props.disc_position()-release).normalized()
	check(absf((target-release).cross(direction))<4,"Unintercepted throw must be aimed at Mick's head")
	opening.seek(float(table.beats[35].start) + 3.8)
	check(opening.actors[3].position.y < 750, "Tango must physically leap into the disc path")
	opening.seek(float(table.beats[36].start) + 0.3)
	check(not opening.actors[3].visible, "Impact must remain non-graphic")
	opening.finish(true)
	check(game.screen == game.Screen.STORY_LADDER, "Skipping must advance to the original first-match ladder")
	check(game.is_physics_processing(), "Main-menu input must recover after the scene")
	check(not root.get_node("Mixtape").cinematic_active, "Menu music must resume after the scene")
	game.set_physics_process(false)
	game.queue_free()
	await process_frame
	print("STORY PROLOGUE: %d failures" % failed)
	quit(1 if failed else 0)
