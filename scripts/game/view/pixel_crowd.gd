## Spectators are independently seated actors drawn over an empty, registered venue.
extends RefCounted

const SCALE := Vector2(1920.0/512.0,1080.0/288.0)
const CELL := Vector2(152,172)
const LIVE := "res://assets/art/crowds/live/"
static var canvases: Array[RID] = []
static var clips: Dictionary
static var sheets: Dictionary

class Fan:
	var seat: Vector2
	var height: float
	var visible_fraction: float
	var view: String
	var flipped: bool
	var variant: int
	var color: Color
	var team: int
	var energy: float
	var pace: float
	var phase: float
	var attention := 0.0
	var rng := RandomNumberGenerator.new()
	var neighbors := PackedInt32Array()
	var action := ""
	var start := 0
	var next_idle := 0
	var priority := 0
	var social_event := -1
	var partner := -1
	var contact_sent := false

# Batch adjacent actors sharing a sheet, retaining the seat depth order.
class BenchBatch:
	var view: String
	var actors: Array[Fan] = []
	var points := PackedVector2Array()
	var uv := PackedVector2Array()
	var colors := PackedColorArray()
	var triangles := PackedInt32Array()

	func add(fan: Fan) -> void:
		var base := actors.size()*6
		actors.append(fan)
		points.resize(base+6)
		uv.resize(base+6)
		for i in 6: colors.append(fan.color)
		for vertex in [0,1,3,0,3,2,2,3,5,2,5,4]: triangles.append(base+int(vertex))

var batches: Array[BenchBatch] = []
var people: Array[Fan] = []
var sections: Array[Rect2] = []
var order := PackedInt32Array()
var audience_visible := true
var canvas := RID()
var background_canvas := RID()
var background: Texture2D
var ambience: ShaderMaterial
var ambience_regions: Array[Rect2] = []
var ambient_enabled := true
var clock := 0
var rally_x := 0.5
var rally_y := 0.5
var excitement := 0.0
var event_serial := 0
var celebration := 0.0
var last_play := -1000

func _init(court: String = "stadium") -> void:
	background = load(LIVE+court+".webp")
	_load_ambience(court)
	if clips.is_empty():
		clips = JSON.parse_string(FileAccess.get_file_as_string("res://data/crowd_motion.json"))
		for view in ["front","profile","rear"]:
			sheets[view] = load(LIVE+view+".webp")
	var layouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/crowd_seating.json"))
	var layout: Dictionary = layouts[court]
	var tickets := RandomNumberGenerator.new()
	tickets.seed = hash(court)
	for row in layout.rows:
		var first := people.size()
		var variants := range(12)
		var count := int(row[5])
		for i in count:
			var fan := Fan.new()
			fan.rng.seed = tickets.randi()
			var t := float(i)/maxi(1,count-1)
			fan.seat = Vector2(row[1],row[2]).lerp(Vector2(row[3],row[4]),t)
			fan.height = float(row[6])*fan.rng.randf_range(0.94,1.04)
			fan.visible_fraction = float(row[7])
			fan.view = "profile" if row[0] in ["left","right"] else row[0]
			fan.flipped = row[0] == "right"
			# Draw tickets without replacement so a bench has different people.
			var k := i%12
			var next := tickets.randi_range(k,11)
			var chosen: int = variants[next]
			variants[next] = variants[k]
			variants[k] = chosen
			fan.variant = chosen
			fan.color = Color(layout.light).darkened(fan.rng.randf_range(0.0,0.10))
			fan.team = fan.rng.randi_range(0,1)
			fan.energy = fan.rng.randf_range(0.2,1.0)
			fan.pace = fan.rng.randf_range(0.81,1.18)
			fan.phase = fan.rng.randf_range(0,TAU)
			fan.next_idle = fan.rng.randi_range(50,600)
			if i>0: fan.neighbors.append(first+i-1)
			if i<count-1: fan.neighbors.append(first+i+1)
			people.append(fan)
			var size := Vector2(fan.height,fan.height*(fan.visible_fraction+0.15))
			var pos := fan.seat-Vector2(size.x*0.5,size.y)
			sections.append(Rect2(pos*SCALE,size*SCALE))
	var sorted := range(people.size())
	sorted.sort_custom(func(a,b): return people[a].seat.y < people[b].seat.y)
	order = PackedInt32Array(sorted)
	for index in order:
		var fan := people[index]
		if batches.is_empty() or batches.back().view != fan.view:
			var batch := BenchBatch.new()
			batch.view = fan.view
			batches.append(batch)
		batches.back().add(fan)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and canvas.is_valid():
		canvases.erase(canvas)
		RenderingServer.free_rid(background_canvas)
		RenderingServer.free_rid(canvas)

static func hide_all() -> void:
	for item in canvases: RenderingServer.canvas_item_set_visible(item,false)

func set_visible(enabled: bool) -> void:
	if canvas.is_valid(): RenderingServer.canvas_item_set_visible(canvas,enabled)

func _cue(fan: Fan, action: String, delay: int, importance: int, partner := -1) -> bool:
	if fan.action != "" and importance <= fan.priority: return false
	fan.action = action
	fan.start = clock+delay
	fan.priority = importance
	fan.partner = partner
	fan.contact_sent = false
	return true

func tick() -> void:
	clock += 1
	excitement = move_toward(excitement,0,0.0025)
	celebration = move_toward(celebration,0,0.004)
	for i in people.size():
		var fan := people[i]
		var target := clampf((rally_x-fan.seat.x/512.0)*1.5,-1,1)
		if fan.partner >= 0 and fan.start <= clock:
			target = signf(people[fan.partner].seat.x-fan.seat.x)
		fan.attention = lerpf(fan.attention,target,0.028+fan.energy*0.025)
		if fan.action != "":
			var tick_number := floori((clock-fan.start)*fan.pace)
			if tick_number >= clips[fan.action].size():
				fan.action = ""
				fan.partner = -1
				fan.priority = 0
			elif fan.action == "clap" and tick_number >= 23 and not fan.contact_sent:
				fan.contact_sent = true
				for j in fan.neighbors:
					var other := people[j]
					if other.social_event == fan.social_event or other.rng.randf() > other.energy*0.69: continue
					if _cue(other,"clap",other.rng.randi_range(8,26),1,i):
						other.social_event = fan.social_event
		elif clock >= fan.next_idle:
			fan.next_idle = clock+fan.rng.randi_range(250,780)
			if excitement>0.42 or clock-last_play<35: continue
			if fan.neighbors.size()>0 and fan.rng.randf()<0.55:
				var j := fan.neighbors[fan.rng.randi_range(0,fan.neighbors.size()-1)]
				if _cue(people[j],"listen",12,0,i):
					_cue(fan,"talk",0,0,j)
			else:
				_cue(fan,"lean",0,0)

func handle(event: Dictionary) -> void:
	var kind: String = event.type
	var score := kind in ["point","set_end","match_over"]
	var big := kind in ["special","block","power_toss","buzzsaw"]
	var skill: bool = kind=="slap" or (kind=="catch" and (event.get("special",false) or event.get("air",false) or float(event.get("speed",0))>20))
	if kind in ["throw","catch","lob","bounce"]:
		last_play = clock
		excitement = minf(1.0,excitement+0.035)
	if not (score or big or skill or kind=="bounce"): return
	event_serial += 1
	var side := int(event.get("winner",event.get("side",-1)))
	if kind=="set_end" and event.has("sets_won") and event.has("scores"):
		side = 0 if event.scores[0]>event.scores[1] else 1
	excitement = minf(1.0,excitement+(0.35 if score or big else 0.06))
	if score: celebration = 1.0
	for fan in people:
		var delay := fan.rng.randi_range(5,27)+roundi(12*(1-fan.energy))
		if score:
			var importance := 5 if kind=="match_over" else (4 if kind=="set_end" else 3)
			var supporter := side<0 or fan.team==side
			var act := "cheer" if fan.rng.randf()<fan.energy+0.20 else "clap"
			if not supporter: act = "slump" if fan.rng.randf()<0.74 else "lean"
			if _cue(fan,act,delay,importance): fan.social_event = event_serial
		else:
			var distance := Vector2(rally_x,rally_y).distance_to(fan.seat/Vector2(512,288))
			if kind=="bounce" and distance>0.38: continue
			var interest := fan.energy*0.40+maxf(0,0.65-distance)*0.6
			if fan.team==side: interest += 0.13
			if fan.rng.randf() > interest: continue
			var act := "flinch" if big or kind=="bounce" else "clap"
			if _cue(fan,act,delay/2,2 if big else 1): fan.social_event = event_serial

func draw(ci: CanvasItem, offset: Vector2 = Vector2.ZERO) -> void:
	if not canvas.is_valid():
		canvas = RenderingServer.canvas_item_create()
		canvases.append(canvas)
		RenderingServer.canvas_item_set_parent(canvas,ci.get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(canvas,true)
		RenderingServer.canvas_item_set_default_texture_filter(canvas,RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
		background_canvas = RenderingServer.canvas_item_create()
		RenderingServer.canvas_item_set_parent(background_canvas,canvas)
		RenderingServer.canvas_item_set_draw_behind_parent(background_canvas,true)
		if ambience != null: RenderingServer.canvas_item_set_material(background_canvas,ambience.get_rid())
		RenderingServer.canvas_item_add_texture_rect(background_canvas,Rect2(0,0,1920,1080),background.get_rid())
	RenderingServer.canvas_item_clear(canvas)
	set_visible(true)
	RenderingServer.canvas_item_set_transform(canvas,Transform2D(0.0,offset))
	if ambience != null:
		ambience.set_shader_parameter("clock_seconds",clock/60.0)
		ambience.set_shader_parameter("energy",excitement)
		ambience.set_shader_parameter("celebration",celebration)
		ambience.set_shader_parameter("activity",float(ambient_enabled))
	if not audience_visible: return
	for batch in batches:
		for i in batch.actors.size():
			_pose_fan(batch.actors[i],batch,i*6)
		RenderingServer.canvas_item_add_triangle_array(canvas,batch.triangles,batch.points,batch.colors,batch.uv,PackedInt32Array(),PackedFloat32Array(),sheets[batch.view].get_rid())

func _pose_fan(fan: Fan, batch: BenchBatch, vertex: int) -> void:
	var cell := 0
	var sway := fan.attention*0.043
	var lift := sin(clock*(0.028+fan.energy*0.01)+fan.phase)*0.009
	if fan.action != "" and clock>=fan.start:
		var clip: Array = clips[fan.action]
		var key: Array = clip[mini(clip.size()-1,floori((clock-fan.start)*fan.pace))]
		cell = int(key[0])
		sway += float(key[1]) * (-1.0 if fan.partner>=0 and fan.attention<0 else 1.0)
		lift += float(key[2])
	var h := fan.height
	var w := h*(CELL.x/CELL.y)
	var left := fan.seat.x-w/2
	var top := fan.seat.y-h*fan.visible_fraction
	var bottom := fan.seat.y
	# The bench lip stays in front. Weight dies out at the hips, keeping
	# feet planted. Only the transparent actor texture is ever transformed.
	for y in [0.0,0.49,fan.visible_fraction]:
		var weight := maxf(0.0,1.0-y/0.59)
		var py := minf(bottom,top+h*(float(y)+lift*weight))
		for u in [0.0,1.0]:
			batch.points[vertex] = Vector2(left+w*u+h*sway*weight,py)*SCALE
			batch.uv[vertex] = Vector2((cell+(1.0-u if fan.flipped else u))/25.0,(fan.variant+y)/12.0)
			vertex += 1

func _load_ambience(court: String) -> void:
	var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/venue_ambience.json"))
	if not config.courts.has(court): return
	var data: Dictionary=config.courts[court]
	var boxes := PackedVector4Array()
	var behavior := PackedVector2Array()
	for region in data.regions:
		var r: Array=region.rect
		boxes.append(Vector4(r[0],r[1],r[2],r[3]))
		behavior.append(Vector2(["water","lantern","neon","beacon"].find(region.kind),region.phase))
		ambience_regions.append(Rect2(r[0],r[1],r[2],r[3]))
	while boxes.size()<32:
		boxes.append(Vector4.ZERO)
		behavior.append(Vector2.ZERO)
	ambience=ShaderMaterial.new()
	ambience.shader=load("res://scripts/game/view/shaders/living_arena.gdshader")
	ambience.set_shader_parameter("regions",boxes)
	ambience.set_shader_parameter("behavior",behavior)
	ambience.set_shader_parameter("region_count",data.regions.size())
