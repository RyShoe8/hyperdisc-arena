extends SceneTree
var crowd
var stage: Node2D
func _initialize(): run.call_deferred()
func run():
 root.size=Vector2i(1672,941)
 stage=Node2D.new()
 root.add_child(stage)
 crowd=load("res://scripts/game/view/pixel_crowd.gd").new("concrete")
 crowd.ambient_enabled=false
 stage.draw.connect(func(): crowd.draw(stage))
 DirAccess.make_dir_recursive_absolute("res://build/crowd/preview")
 DirAccess.copy_absolute("res://tools/art/venues/crowd-review.html","res://build/crowd/review.html")
 var baseline: Image
 var allowed := Image.new()
 for i in 36:
  if i==2: crowd.handle({"type":"point","side":0})
  if i==13: crowd.handle({"type":"point","side":1})
  if i==24: crowd.handle({"type":"catch","speed":30,"side":1})
  for t in 12: crowd.tick()
  stage.queue_redraw()
  await process_frame
  await RenderingServer.frame_post_draw
  var shot := root.get_texture().get_image()
  shot.save_png("res://build/crowd/preview/%02d.png"%i)
  if i == 0:
   baseline = shot
   allowed = Image.create_empty(shot.get_width(),shot.get_height(),false,Image.FORMAT_L8)
   var scale_to_shot := Vector2(shot.get_size())/Vector2(1920,1080)
   for area in crowd.sections:
    var pixels := Rect2i(area.position*scale_to_shot,area.size*scale_to_shot)
    allowed.fill_rect(pixels.grow(4),Color.WHITE)
  else:
   for y in shot.get_height():
    for x in shot.get_width():
     if shot.get_pixel(x,y)==baseline.get_pixel(x,y) or allowed.get_pixel(x,y).r>0.5: continue
     push_error("Scenery changed outside fan patch at %s"%Vector2i(x,y))
     quit(1)
     return
 print("CROWD RENDER ISOLATION PASSED: 36 frames")
 crowd=null
 stage.queue_free()
 await process_frame
 quit()
