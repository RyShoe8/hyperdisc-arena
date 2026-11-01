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
 for i in 36:
  if i==2: crowd.handle({"type":"point","side":0})
  if i==13: crowd.handle({"type":"point","side":1})
  if i==24:
   crowd.reaction="watch"
   crowd.ticks_left=0
   crowd.excitement=0
   crowd.clock=int(crowd.people[2].idle_period)-int(crowd.people[2].idle_offset)
  for t in 12: crowd.tick()
  stage.queue_redraw()
  await process_frame
  await RenderingServer.frame_post_draw
  var shot := root.get_texture().get_image()
  shot.save_png("res://build/crowd/preview/%02d.png"%i)
  if i == 0: baseline = shot
  else:
   for y in shot.get_height():
    for x in shot.get_width():
     if shot.get_pixel(x,y)==baseline.get_pixel(x,y): continue
     var allowed := false
     for area in crowd.sections:
      if area.grow(2).has_point(Vector2(x,y)): allowed=true
     if not allowed:
      push_error("Scenery changed outside fan patch at %s"%Vector2i(x,y))
      quit(1)
      return
 print("CROWD RENDER ISOLATION PASSED: 36 frames")
 crowd=null
 stage.queue_free()
 await process_frame
 quit()
