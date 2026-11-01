extends SceneTree
var crowd
var stage: Node2D
func _initialize(): run.call_deferred()
func run():
 root.size=Vector2i(1024,576)
 stage=Node2D.new()
 root.add_child(stage)
 stage.draw.connect(func(): crowd.draw(stage))
 DirAccess.make_dir_recursive_absolute("res://build/venue-life")
 DirAccess.copy_absolute("res://tools/art/venues/ambience-review.html","res://build/venue-life/review.html")
 for id in ["beach","concrete","lawn","clay","tiled","stadium"]:
  if crowd!=null: crowd.set_visible(false)
  crowd=load("res://scripts/game/view/pixel_crowd.gd").new(id)
  crowd.people.clear() # Isolate the environmental pass from crowd-pose tests.
  var baseline: Image
  var total_changes := 0
  for sample in 8:
   if sample==4: crowd.handle({"type":"match_over","winner":0})
   for tick in 24: crowd.tick()
   stage.queue_redraw()
   await process_frame
   await RenderingServer.frame_post_draw
   var shot := root.get_texture().get_image()
   shot.save_png("res://build/venue-life/%s-%d.png"%[id,sample])
   if sample==0: baseline=shot
   else:
    for y in shot.get_height():
     for x in shot.get_width():
      if shot.get_pixel(x,y)==baseline.get_pixel(x,y): continue
      total_changes+=1
      var allowed := false
      for r in crowd.ambience_regions:
       var area := Rect2(r.position*2,r.size*2).grow(2)
       if area.has_point(Vector2(x,y)): allowed=true
      if not allowed:
       push_error("Ambient effect changed protected scenery in %s at %s"%[id,Vector2i(x,y)])
       quit(1)
       return
  if total_changes==0:
   push_error("No visible ambient animation for "+id)
   quit(1)
   return
  print(id,": ",total_changes," changed pixels confined to authored fixtures")
 print("VENUE AMBIENCE ISOLATION PASSED")
 crowd=null
 stage.queue_free()
 await process_frame
 quit()
