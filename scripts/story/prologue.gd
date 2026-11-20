## Story opening driven by the native Rigby scene's evaluated timeline.
extends Node2D
signal finished(skipped: bool)
const Actor := preload("res://scripts/story/story_actor.gd")
const Beach := preload("res://scripts/story/beach_stage.gd")
const Props := preload("res://scripts/story/story_props.gd")
const Truck := preload("res://scripts/story/rescue_truck.gd")
const Balloon := preload("res://scripts/story/speech_balloon.gd")
const TowerFront := preload("res://scripts/story/tower_foreground.gd")
const Whistle := preload("res://scripts/story/story_whistle.gd")
const UI := preload("res://scripts/game/ui/theme.gd")
var timeline: Dictionary
var actors: Array = []
var world: Node2D
var beach: Node2D
var props: Node2D
var dialogue: Node2D
var truck: Node2D
var tower_front: Node2D
var whistle: Node2D
var sunlight: ShaderMaterial
var ambience: AudioStreamPlayer
var score: AudioStreamPlayer
var time := 0.0
var beat_index := 0
var playing := true
var skip_question := false
var completed := false
var standalone := false

func _ready() -> void:
	UI.load_fonts()
	Mixtape.cinematic_active = true
	timeline = JSON.parse_string(FileAccess.get_file_as_string("res://data/story_rigby.json"))
	world = Node2D.new()
	# Actor depth must remain below the letterbox and subtitle layer.
	world.z_index = -2000
	add_child(world)
	beach = Beach.new()
	world.add_child(beach)
	tower_front = TowerFront.new()
	tower_front.z_index = 820
	world.add_child(tower_front)
	for id in timeline.ids:
		var actor := Actor.new()
		actor.setup(id, timeline.cast[id])
		world.add_child(actor)
		actors.append(actor)
		if id=="tiffany":
			sunlight = ShaderMaterial.new()
			sunlight.shader = preload("res://scripts/story/sunlight.gdshader")
			actor.material = sunlight
	props = Props.new()
	props.beats = timeline.beats
	for i in actors.size():
		props.cast[timeline.ids[i]] = actors[i]
	props.z_index = 1000
	world.add_child(props)
	whistle = Whistle.new()
	whistle.props = props
	world.add_child(whistle)
	truck = Truck.new()
	truck.z_index = 950
	world.add_child(truck)
	dialogue = Balloon.new()
	add_child(dialogue)
	ambience = AudioStreamPlayer.new()
	var stream: AudioStreamWAV = load("res://assets/sfx/venues/beach.wav").duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	ambience.stream = stream
	add_child(ambience)
	ambience.play()
	score = AudioStreamPlayer.new()
	score.stream = load("res://assets/audio/story/prologue.ogg")
	score.volume_db = linear_to_db(maxf(0.001, Mixtape.music_volume))
	add_child(score)
	score.play()
	standalone = get_parent() == get_tree().root
	seek(0)

func _physics_process(delta: float) -> void:
	if completed:
		return
	if Controls.menu_key("back") or Controls.menu_pressed("b") != -1:
		skip_question = not skip_question
	if Controls.menu_key("confirm") or Controls.menu_pressed("a") != -1:
		if skip_question:
			finish(true)
			return
		if beat_index >= timeline.beats.size() - 1:
			finish(false)
			return
		seek(float(timeline.beats[beat_index + 1].start))
	if playing and not skip_question:
		seek(minf(time + delta, float(timeline.duration)))
		if time >= float(timeline.duration):
			if standalone:
				playing = false
			else:
				finish(false)
	ambience.stream_paused = not playing or skip_question
	score.stream_paused = not playing or skip_question
	dialogue.visible = not skip_question and not str(timeline.beats[beat_index].speaker).is_empty()
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			playing = not playing
		elif event.keycode == KEY_R and standalone:
			completed = false
			playing = true
			seek(0)
			score.play()
			ambience.play()

func _exit_tree() -> void:
	Mixtape.cinematic_active = false

func seek(seconds: float) -> void:
	if score != null and absf(seconds - time) > 0.2:
		score.seek(seconds)
	time = clampf(seconds, 0, float(timeline.duration))
	var frame: Array = timeline.frames[clampi(roundi(time * 30), 0, timeline.frames.size() - 1)]
	world.scale = Vector2.ONE * float(frame[2])
	# Reserve sky above faces for comic balloons instead of covering the cast.
	world.position = Vector2(960, 575) - Vector2(frame[0], frame[1]) * float(frame[2])
	for i in actors.size():
		var pose: Array = frame[3][i]
		actors[i].position = Vector2(pose[0], pose[1])
		actors[i].scale = Vector2(pose[2], pose[3])
		actors[i].visible = float(pose[1]) < 1800
		actors[i].z_index = int(pose[1])
		actors[i].sample(pose[4], float(pose[5]))
		actors[i].shadow_offset = 0.0
		if timeline.ids[i]=="tango" and ((time>=2.65 and time<3.85) or (time>=float(timeline.beats[35].start)+1.95 and time<float(timeline.beats[36].start))):
			actors[i].shadow_offset = maxf(0, (855-float(pose[1]))/float(pose[3]))
	beach.set_time(time)
	beach.broken_sign = clampf((time - float(timeline.beats[36].start)) * 2, 0, 1)
	tower_front.broken_sign = beach.broken_sign
	tower_front.queue_redraw()
	sunlight.set_shader_parameter("cinematic_time",time)
	var arrive := float(timeline.beats[42].start)
	var leave := float(timeline.beats[45].start)
	truck.visible = time >= arrive and time < leave+7
	var approach := smoothstep(0,2.5,time-arrive)
	var departure := maxf(0,time-leave)
	truck.position = Vector2(lerpf(3700,2500,approach)+departure*departure*65,930)
	truck.driving = (time<arrive+2.5 or time>leave) and truck.visible
	truck.time = time
	truck.queue_redraw()
	beach.queue_redraw()
	props.time = time
	props.queue_redraw()
	whistle.refresh()
	beat_index = 0
	for i in timeline.beats.size():
		if time >= float(timeline.beats[i].start):
			beat_index = i
	var beat: Dictionary = timeline.beats[beat_index]
	# Action directions are performed on stage, never displayed as narration.
	var who := str(beat.speaker)
	var actor_id := who if who != "gang" else "steve"
	var head := Vector2(960,500)
	if props.cast.has(actor_id):
		head = world.to_global(props.cast[actor_id].attachment_point("head"))
	dialogue.set_line(str(beat.text) if not who.is_empty() else "",who,(time-float(beat.start))/float(beat.duration),head)
	var quiet := time >= float(timeline.beats[36].start)
	ambience.volume_db = (-36.0 if quiet else -14.0) + linear_to_db(maxf(0.001, Settings.sfx_volume))
	queue_redraw()

func finish(skipped: bool) -> void:
	if completed:
		return
	completed = true
	ambience.stop()
	score.stop()
	finished.emit(skipped)
	if standalone:
		playing = false
		completed = false
		seek(float(timeline.beats[-1].start))

func _draw() -> void:
	if timeline.is_empty():
		return
	draw_rect(Rect2(0, 0, 1920, 66), Color("100e1c"))
	draw_rect(Rect2(0, 1014, 1920, 66), Color("100e1c"))
	UI.text(self, Vector2(64, 40), "HYPERDISC ARENA  /  STORY", 20, Color("c9c0cc"), UI.ui, 2, HORIZONTAL_ALIGNMENT_LEFT)
	UI.text(self, Vector2(1850, 40), "P  PAUSE    ENTER / A  NEXT    ESC / B  SKIP", 17, Color("ada5bd"), UI.ui, 2, HORIZONTAL_ALIGNMENT_RIGHT)
	var beat: Dictionary = timeline.beats[beat_index]
	if beat_index == 0:
		var a := clampf(time / 1.8, 0, 1) * clampf((float(beat.duration) - time) / 1.2, 0, 1)
		UI.text(self, Vector2(960, 330), "SOUTHERN CALIFORNIA", 100, Color(1, .94, .81, a), UI.display, 5, HORIZONTAL_ALIGNMENT_CENTER, -1, true)
		UI.text(self, Vector2(960, 385), "A PERFECTLY ORDINARY DAY OFF.", 26, Color(1, .94, .81, a), UI.ui, 2)
	if beat_index >= 52:
		draw_rect(Rect2(0, 66, 1920, 948), Color(.04,.03,.09,.78))
		UI.text(self, Vector2(960, 420), "SIX NAMES. ONE WAY UP." if beat_index == 52 else "THE LEAKY TIKI", 108, UI.YELLOW, UI.display, 6)
		UI.text(self, Vector2(960, 500), "THE ROAD TO KENO STARTS HERE." if beat_index == 52 else "FIRST CHALLENGE  /  ALEX ALOHA", 28, Color("fff0d7"), UI.ui, 2)
		if standalone and not playing:
			UI.text(self, Vector2(960, 650), "R  REPLAY OPENING", 23, UI.CYAN, UI.ui, 2)
	var impact := time - float(timeline.beats[36].start)
	if impact >= 0 and impact < .18:
		draw_rect(Rect2(0, 66, 1920, 948), Color(1, 1, .95, (1 - impact / .18) * .85))
	if time < 1.2:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0,0,0,1-time/1.2))
	if skip_question:
		draw_rect(Rect2(0,0,1920,1080),Color(0.04,0.03,0.09,.85))
		UI.text(self, Vector2(960,450),"SKIP THE OPENING?",80,UI.WHITE,UI.display,4)
		UI.text(self, Vector2(960,540),"ENTER / A  CONTINUE TO THE FIRST MATCH",28,UI.CYAN,UI.ui,2)
		UI.text(self, Vector2(960,600),"ESC / B  KEEP WATCHING",24,UI.WHITE,UI.ui,2)
