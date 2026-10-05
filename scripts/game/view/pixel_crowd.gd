## Crowd frames are authored within each arena's seating composition.
## Only audience regions are animated; court and simulation stay unchanged.
extends RefCounted

const POSES := ["watch","clap","cheer","surprise"]
static var canvases: Array[RID] = []
var frames: Dictionary = {}
var reaction := "watch"
var ticks_left := 0
var clock := 0
var priority := 0
var reaction_age := 0
var sections: Array[Rect2] = []
var material: ShaderMaterial
var canvas := RID()
var rally_x := 0.5

func _init(court: String = "stadium") -> void:
	frames.watch = load("res://assets/art/courts/%s_pixel.png" % court)
	for pose in ["clap","cheer","surprise"]:
		frames[pose] = load("res://assets/art/crowds/%s_%s.png" % [court,pose])
	_build_sections(court)
	material = ShaderMaterial.new()
	material.shader = load("res://scripts/game/view/shaders/living_arena.gdshader")
	material.set_shader_parameter("applause",frames.clap)
	material.set_shader_parameter("celebration",frames.cheer)
	material.set_shader_parameter("surprise",frames.surprise)
	material.set_shader_parameter("court_style",["beach","lawn","tiled","concrete","clay","stadium"].find(court))
	var boxes := PackedVector4Array()
	var grids := PackedVector2Array()
	for area in sections:
		boxes.append(Vector4(area.position.x,area.position.y,area.size.x,area.size.y))
		var cell := Vector2(45,55)
		if court == "stadium": cell = Vector2(35,38)
		if area.size.x < 300: cell = Vector2(60,90)
		grids.append(Vector2(maxi(1,roundi(area.size.x/cell.x)),maxi(1,roundi(area.size.y/cell.y))))
	while boxes.size() < 8:
		boxes.append(Vector4.ZERO)
		grids.append(Vector2.ONE)
	material.set_shader_parameter("audience",boxes)
	material.set_shader_parameter("grids",grids)
	material.set_shader_parameter("audience_count",sections.size())

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
	reaction_age += 1
	ticks_left = maxi(0,ticks_left-1)
	if ticks_left == 0:
		reaction = "watch"
		priority = 0

func handle(event: Dictionary) -> void:
	match event.type:
		"point": _react("cheer",150,3)
		"set_end": _react("cheer",240,4)
		"match_over": _react("victory",480,5)
		"special","block","power_toss": _react("surprise",85,2)
		"catch": _react("clap",80,1)
		"throw","slap": _react("clap",60,1)

func _react(kind: String, duration: int, importance: int) -> void:
	if importance < priority and ticks_left > 0: return
	reaction = kind
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
	var kind := 0
	if reaction == "clap": kind = 1
	if reaction in ["cheer","victory"]: kind = 2
	if reaction == "surprise": kind = 3
	material.set_shader_parameter("reaction",kind)

