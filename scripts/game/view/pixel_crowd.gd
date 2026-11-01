## Immutable arena artwork plus registered, individually timed spectator patches.
extends RefCounted
static var canvases: Array[RID] = []
var frames: Dictionary = {}
var people: Array = []
var sections: Array[Rect2] = []
var atlas: Texture2D
var canvas := RID()
var background_canvas := RID()
var ambience: ShaderMaterial
var ambience_regions: Array[Rect2] = []
var ambient_enabled := true
var texture_hash := ""
var clock := 0
var reaction := "watch"
var reaction_age := 0
var reaction_side := -1
var ticks_left := 0
var priority := 0
var excitement := 0.0
var event_serial := 0
var rally_x := 0.5
var source_size := Vector2(1672,941)
var cell := Vector2(80,96)

func _init(court: String = "stadium") -> void:
 frames.watch = load("res://assets/art/courts/%s_pixel.png" % court)
 var base_image: Image = frames.watch.get_image()
 base_image.convert(Image.FORMAT_RGBA8)
 var hash := HashingContext.new()
 hash.start(HashingContext.HASH_SHA256)
 hash.update(base_image.get_data())
 texture_hash = hash.finish().hex_encode()
 _load_ambience(court)
 var path := "res://assets/art/crowds/composed/%s.json" % court
 if not FileAccess.file_exists(path): return
 var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
 # A background revision invalidates its registered patches until repacked.
 if texture_hash != data.texture_sha256:
  push_warning("Crowd patches disabled: arena revision differs for "+court)
  return
 source_size = Vector2(data.source_size[0],data.source_size[1])
 cell = Vector2(data.cell[0],data.cell[1])
 atlas = load("res://assets/art/crowds/composed/%s.png" % court)
 people = data.fans
 for fan in people:
  var r: Array = fan.rect
  sections.append(Rect2(r[0],r[1],r[2],r[3]))

func _notification(what: int) -> void:
 if what == NOTIFICATION_PREDELETE and canvas.is_valid():
  canvases.erase(canvas)
  if background_canvas.is_valid(): RenderingServer.free_rid(background_canvas)
  RenderingServer.free_rid(canvas)

static func hide_all() -> void:
 for item in canvases: RenderingServer.canvas_item_set_visible(item,false)

func set_visible(enabled: bool) -> void:
 if canvas.is_valid(): RenderingServer.canvas_item_set_visible(canvas,enabled)

func tick() -> void:
 clock += 1
 reaction_age += 1
 excitement = maxf(0.0,excitement-0.003)
 ticks_left = maxi(0,ticks_left-1)
 if ticks_left == 0:
  reaction = "watch"
  priority = 0

func handle(event: Dictionary) -> void:
 if event.type in ["throw","catch","slap","special","point"]:
  excitement = minf(1.0,excitement+(0.35 if event.type in ["special","point"] else 0.07))
 var side := int(event.get("side",event.get("winner",-1)))
 match event.type:
  "point": _react("cheer",150,3,side)
  "set_end": _react("cheer",240,4,side)
  "match_over": _react("victory",480,5,side)
  "special","block","power_toss": _react("surprise",85,2,side)
  "catch":
   if event.get("special",false) or float(event.get("speed",0))>20:
    _react("clap",80,1,side)
  "slap": _react("clap",60,1,side)

func _react(kind: String, duration: int, importance: int, side := -1) -> void:
 if importance < priority and ticks_left > 0: return
 if kind == reaction and importance == priority and ticks_left > duration/2: return
 reaction = kind
 reaction_side = side
 event_serial += 1
 ticks_left = duration
 priority = importance
 reaction_age = 0

func pose_for(index: int) -> int:
 if index < 0 or index >= people.size(): return 0
 var fan: Dictionary = people[index]
 if reaction == "watch":
  if excitement>0.3: return 0
  var idle_time := posmod(clock+int(fan.get("idle_offset",0)),int(fan.get("idle_period",1500)))
  return int(fan.get("idle_pose",0)) if idle_time<42 else 0
 var age := reaction_age-int(fan.delay)
 if age < 0: return 0
 var supporting := reaction_side < 0 or int(fan.team) == reaction_side
 # Opposing fans watch the point; they don't celebrate a loss.
 if reaction in ["cheer","victory"] and not supporting: return 0
 var duration := int(65+float(fan.energy)*120)
 if reaction == "victory": duration *= 3
 if age >= duration: return 0
 var step := (age/int(fan.tempo))%8
 if reaction in ["cheer","victory"]:
  return [0,1,2,2,1,0,0,0][step]
 return [0,1,1,0,0,1,0,0][step]

func draw(ci: CanvasItem, offset: Vector2 = Vector2.ZERO) -> void:
 if not canvas.is_valid():
  canvas = RenderingServer.canvas_item_create()
  canvases.append(canvas)
  RenderingServer.canvas_item_set_parent(canvas,ci.get_canvas_item())
  RenderingServer.canvas_item_set_draw_behind_parent(canvas,true)
  background_canvas = RenderingServer.canvas_item_create()
  RenderingServer.canvas_item_set_parent(background_canvas,canvas)
  RenderingServer.canvas_item_set_draw_behind_parent(background_canvas,true)
  if ambience != null: RenderingServer.canvas_item_set_material(background_canvas,ambience.get_rid())
  RenderingServer.canvas_item_add_texture_rect(background_canvas,Rect2(0,0,1920,1080),frames.watch.get_rid())
 RenderingServer.canvas_item_clear(canvas)
 RenderingServer.canvas_item_set_visible(canvas,true)
 RenderingServer.canvas_item_set_transform(canvas,Transform2D(0.0,offset))
 if ambience != null:
  ambience.set_shader_parameter("clock_seconds",float(clock)/60.0)
  ambience.set_shader_parameter("energy",excitement)
  ambience.set_shader_parameter("celebration",float(ticks_left)/480.0 if reaction in ["cheer","victory"] else 0.0)
  ambience.set_shader_parameter("activity",1.0 if ambient_enabled else 0.0)
 if atlas == null: return
 var scale_to_screen := Vector2(1920,1080)/source_size
 for i in people.size():
  var pose := pose_for(i)
  if pose == 0: continue
  var area: Rect2 = sections[i]
  var dest := Rect2(area.position*scale_to_screen,area.size*scale_to_screen)
  var region := Rect2(Vector2(i*cell.x,pose*cell.y),area.size)
  RenderingServer.canvas_item_add_texture_rect_region(canvas,dest,atlas.get_rid(),region)

func _load_ambience(court: String) -> void:
 var config: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/venue_ambience.json"))
 if not config.courts.has(court): return
 var data: Dictionary=config.courts[court]
 if data.texture_sha256 != texture_hash:
  push_warning("Ambience disabled: arena revision differs for "+court)
  return
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
