## Crowd frames are authored within each arena's seating composition.
## Only audience regions are animated; court and simulation stay unchanged.
extends RefCounted

const POSES := ["watch","clap","cheer","surprise"]
static var canvases: Array[RID] = []
var frames: Dictionary = {}
var people: Array[Dictionary] = []
var atlas: Texture2D = preload("res://assets/art/crowds/fans.png")
var fan_regions: Array[Rect2] = []
var fan_rng := RandomNumberGenerator.new()

var reaction := "watch"
var ticks_left := 0
var clock := 0
var priority := 0
var reaction_age := 0
var sections: Array[Rect2] = []
var material: ShaderMaterial
var canvas := RID()
var rally_x := 0.5
var reaction_side := -1
var excitement := 0.0
var event_serial := 0

func _init(court: String = "stadium") -> void:
	frames.watch = load("res://assets/art/courts/%s_pixel.png" % court)
	_build_sections(court)
	var groups_path := "res://assets/art/crowds/%s_groups.json" % court
	if FileAccess.file_exists(groups_path):
		sections.clear()
		for box in JSON.parse_string(FileAccess.get_file_as_string(groups_path)):
			sections.append(Rect2(box[0],box[1],box[2],box[3]))
	material = ShaderMaterial.new()
	material.shader = load("res://scripts/game/view/shaders/living_arena.gdshader")
	material.set_shader_parameter("court_style",["beach","lawn","tiled","concrete","clay","stadium"].find(court))
	var boxes := PackedVector4Array()
	var grids := PackedVector2Array()
	var seat_map := Image.create(1920,1080,false,Image.FORMAT_R8)
	seat_map.fill(Color.BLACK)
	for area in sections:
		boxes.append(Vector4(area.position.x,area.position.y,area.size.x,area.size.y))
		seat_map.fill_rect(Rect2i(area),Color(float(boxes.size())/255.0,0,0))
		var cell := Vector2(45,55)
		if court == "stadium": cell = Vector2(35,38)
		if area.size.x < 300: cell = Vector2(60,90)
		grids.append(Vector2(maxi(1,roundi(area.size.x/cell.x)),maxi(1,roundi(area.size.y/cell.y))))
	# Crowd bands may straddle a railing. Never swap pixels on the playing surface.
	var layouts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/court_layouts.json"))
	var bounds: Array = layouts[court].bounds
	for y in range(ceili(float(bounds[1])*3.75),floori(float(bounds[4])*3.75)+1):
		var t := inverse_lerp(float(bounds[1])*3.75,float(bounds[4])*3.75,float(y))
		var left := floori(lerpf(float(bounds[0]),float(bounds[3]),t)*3.75)
		var right := ceili(lerpf(float(bounds[2]),float(bounds[5]),t)*3.75)
		seat_map.fill_rect(Rect2i(left,y,right-left+1,1),Color.BLACK)
	while boxes.size() < 64:
		boxes.append(Vector4.ZERO)
		grids.append(Vector2.ONE)
	material.set_shader_parameter("audience",boxes)
	material.set_shader_parameter("grids",grids)
	material.set_shader_parameter("audience_count",sections.size())
	material.set_shader_parameter("seat_map",ImageTexture.create_from_image(seat_map))

	# Register each authored pose on its opaque feet rather than the cell boundary.
	var source_image := atlas.get_image()
	var row_cuts := [0.0,0.281,0.561,0.86]
	for row in 3:
		for column in 8:
			var cell := Rect2i(column*source_image.get_width()/8+3, int(source_image.get_height()*row_cuts[row])+4,
				source_image.get_width()/8-6, int(source_image.get_height()*(row_cuts[row+1]-row_cuts[row]))-8)
			var used := source_image.get_region(cell).get_used_rect()
			fan_regions.append(Rect2(Vector2(cell.position+used.position),Vector2(used.size)))
	fan_rng.seed = court.hash()
	# A terrace is a space to stand or wander, with enough room for raised arms.
	for band in layouts[court].audience:
		var near_row := float(band[1]) > float(bounds[4])-4.0
		var side_row := float(band[3])-float(band[1]) > float(band[2])-float(band[0])
		var left := float(band[0])*3.75
		var right := float(band[2])*3.75
		var top := float(band[1])*3.75
		var bottom := float(band[3])*3.75
		var size := 112.0 if near_row else 92.0
		var count := maxi(1,int((bottom-top if side_row else right-left)/(size*0.94)))
		for j in count:
			var u := (j+0.5)/count
			var anchor := Vector2((left+right)/2 if side_row else lerpf(left,right,u), lerpf(top,bottom,u) if side_row else bottom)
			anchor.y += fan_rng.randf_range(-11,5)
			var identity := fan_rng.randi_range(0,3)+(4 if near_row else 0)
			people.append({"home":anchor,"x":anchor.x,"goal":anchor.x,"id":identity,"size":size*fan_rng.randf_range(0.91,1.06),
				"tempo":fan_rng.randi_range(7,13),"next":fan_rng.randi_range(20,330),"team":fan_rng.randi_range(0,1),
				"delay":fan_rng.randi_range(2,35),"phase":fan_rng.randi_range(0,200),"energy":fan_rng.randf(),"step":0.0})

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and canvas.is_valid():
		canvases.erase(canvas)
		RenderingServer.free_rid(canvas)

static func hide_all() -> void:
	for item in canvases: RenderingServer.canvas_item_set_visible(item,false)

func set_visible(enabled: bool) -> void:
	if canvas.is_valid(): RenderingServer.canvas_item_set_visible(canvas,enabled)

func _strip(area: Rect2, count: int) -> void:
	for i in count:
		sections.append(Rect2(area.position+Vector2(area.size.x*i/count,0),Vector2(area.size.x/count,area.size.y)))

func _build_sections(court: String) -> void:
	match court:
		"stadium":
			_strip(Rect2(0,0,820,104),1)
			_strip(Rect2(1100,0,820,104),1)
			_strip(Rect2(0,250,135,650),1)
			_strip(Rect2(1785,250,135,650),1)
			_strip(Rect2(0,945,810,135),1)
			_strip(Rect2(1110,945,810,135),1)
		"beach":
			_strip(Rect2(280,0,1360,177),1)
			_strip(Rect2(0,180,280,650),1)
			_strip(Rect2(1640,180,280,650),1)
			_strip(Rect2(0,880,1920,200),1)
		"tiled":
			_strip(Rect2(280,0,1360,170),1)
			_strip(Rect2(0,280,145,555),1)
			_strip(Rect2(1775,280,145,555),1)
			_strip(Rect2(0,880,1920,200),1)
		"concrete":
			_strip(Rect2(0,0,1920,145),1)
			_strip(Rect2(0,200,145,680),1)
			_strip(Rect2(1775,200,145,680),1)
			_strip(Rect2(0,900,1920,180),1)
		"lawn","clay":
			_strip(Rect2(0,0,1920,145),1)
			_strip(Rect2(0,180,145,655),1)
			_strip(Rect2(1775,180,145,655),1)
			_strip(Rect2(0,880,1920,200),1)

func tick() -> void:
	clock += 1
	for fan in people:
		if clock >= fan.next:
			fan.goal = fan.home.x + fan_rng.randf_range(-11,11) + (rally_x-0.5)*5
			fan.next = clock+fan_rng.randi_range(80,420)
		var dx := float(fan.goal)-float(fan.x)
		fan.x = move_toward(float(fan.x),float(fan.goal),0.34)
		fan.step = absf(sin(clock*0.18+fan.phase))*1.8 if absf(dx)>0.5 else 0.0
	excitement = maxf(0.0, excitement - 0.003)
	reaction_age += 1
	ticks_left = maxi(0,ticks_left-1)
	if ticks_left == 0:
		reaction = "watch"
		priority = 0

func handle(event: Dictionary) -> void:
	if event.type in ["throw", "slap", "catch", "block", "special"]:
		excitement = minf(1.0, excitement + (0.25 if event.type == "special" else 0.07))
	var side := int(event.get("side", event.get("winner", -1)))
	match event.type:
		"point": _react("cheer",150,3,side)
		"set_end": _react("cheer",240,4,reaction_side)
		"match_over": _react("victory",480,5,side)
		"special","block","power_toss": _react("surprise",85,2,side)
		"catch":
			if event.get("special",false) or float(event.get("speed",0)) > 20.0:
				_react("clap",80,1,side)
		"slap": _react("clap",60,1,side)

func _react(kind: String, duration: int, importance: int, side := -1) -> void:
	if importance < priority and ticks_left > 0: return
	# Repeated catches must not restart the wave before distant fans react.
	if kind == reaction and importance == priority and ticks_left > duration / 2: return
	reaction = kind
	reaction_side = side
	event_serial += 1
	ticks_left = duration
	priority = importance
	reaction_age = 0

func pose_for(index: int) -> int:
	var delay := (index*13)%30
	if reaction_age < delay: return 0
	var beat := posmod((clock+index*19)/(15+index%8),4)
	match reaction:
		"clap": return 1 if beat%2==0 else 0
		"cheer","victory": return 2 if beat<3 else 1
		"surprise": return 3 if beat<3 else 0
	return 1 if posmod(clock+index*41,360)<35 else 0

func draw(ci: CanvasItem, offset: Vector2 = Vector2.ZERO) -> void:
	if not canvas.is_valid():
		canvas = RenderingServer.canvas_item_create()
		canvases.append(canvas)
		RenderingServer.canvas_item_set_parent(canvas,ci.get_canvas_item())
		RenderingServer.canvas_item_set_draw_behind_parent(canvas,true)
		RenderingServer.canvas_item_set_material(canvas,material.get_rid())
		RenderingServer.canvas_item_add_texture_rect(canvas,Rect2(0,0,1920,1080),frames.watch.get_rid())
	RenderingServer.canvas_item_set_visible(canvas,true)
	RenderingServer.canvas_item_set_transform(canvas,Transform2D(0.0,offset))
	material.set_shader_parameter("clock_seconds",float(clock)/60.0)
	material.set_shader_parameter("reaction_age",float(reaction_age)/60.0)
	material.set_shader_parameter("rally_x",rally_x)
	material.set_shader_parameter("reaction_side",reaction_side)
	material.set_shader_parameter("excitement",excitement)
	material.set_shader_parameter("event_serial",float(event_serial))
	var kind := 0
	if reaction == "clap": kind = 1
	if reaction in ["cheer","victory"]: kind = 2
	if reaction == "surprise": kind = 3
	material.set_shader_parameter("reaction",kind)

	_draw_fans(ci)

func _draw_fans(ci: CanvasItem) -> void:
	for fan in people:
		var beat := posmod((clock+int(fan.phase))/int(fan.tempo),8)
		var row := 0
		var lift := float(fan.step)
		var engaged := reaction_age >= int(fan.delay) and reaction_age < int(fan.delay)+65+int(fan.energy*155)
		if reaction != "watch" and engaged:
			if reaction in ["cheer","victory"] and (reaction_side == fan.team or fan.energy>0.68):
				row = [0,1,2,2,2,1,1,0][beat]
				lift += 4.0*absf(sin((clock+fan.phase)*0.16)) if row==2 else 0.0
			else:
				row = 1 if beat in [1,2,4,5] else 0
		elif posmod(clock+int(fan.phase)*17,270+int(fan.tempo)*9)<36:
			row = 1
		var source: Rect2 = fan_regions[row*8+int(fan.id)]
		var reference: Rect2 = fan_regions[int(fan.id)]
		var scale_factor := float(fan.size)/reference.size.y
		var size := source.size*scale_factor
		var feet := Vector2(fan.x,fan.home.y-lift)
		ci.draw_texture_rect_region(atlas,Rect2(feet-Vector2(size.x/2,size.y),size),source,Color.WHITE,false,true)
