extends SceneTree
## Build registered patches without writing to approved arena artwork.
func _initialize() -> void:
 var lock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/venues/approved.json"))
 for entry in lock.courts.values():
  if FileAccess.get_sha256("res://"+entry.path) != entry.sha256:
   fail("Arena changed; review and version the baseline before rebuilding: "+entry.path)
   return
 if FileAccess.get_sha256("res://tools/art/venues/calibration.json") != lock.calibration_sha256:
  fail("Calibration changed; review boundary previews before updating baseline")
  return
 var source := "res://tools/art/venues/crowd/"
 var output := "res://build/crowd/"
 DirAccess.make_dir_recursive_absolute(output)
 for filename in DirAccess.get_files_at(source):
  if not filename.ends_with(".json"): continue
  var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source+filename))
  if data.base_sha256 != lock.courts[data.court].sha256:
   fail("Fan registration references a different court revision")
   return
  var base := Image.load_from_file("res://"+lock.courts[data.court].path)
  if base.get_size() != Vector2i(data.source_size[0],data.source_size[1]):
   fail("Source dimensions changed")
   return
  var poses: Array[Image] = [base]
  for pose in data.poses.slice(1):
   var img := Image.load_from_file(source+data.court+"-"+pose+".png")
   if img == null or img.get_size() != base.get_size():
    fail("Pose must retain exact source dimensions: "+pose)
    return
   poses.append(img)
  for img in poses: img.convert(Image.FORMAT_RGBA8)
  data.cell = [96,96]
  var atlas := Image.create(data.fans.size()*96,data.poses.size()*96,false,Image.FORMAT_RGBA8)
  atlas.fill(Color.TRANSPARENT)
  var occupied: Array[Rect2i] = []
  for i in data.fans.size():
   var r: Array = data.fans[i].rect
   var area := Rect2i(r[0],r[1],r[2],r[3])
   if area.size.x>96 or area.size.y>96 or not Rect2i(Vector2i.ZERO,base.get_size()).encloses(area):
    fail("Fan patch outside atlas or source: "+data.fans[i].id)
    return
   for previous in occupied:
    if area.intersects(previous):
     fail("Fan patches overlap")
     return
   occupied.append(area)
   for pose in poses.size():
    var pose_image: Image=poses[pose]
    var override_path: String=data.fans[i].get("sources",{}).get(data.poses[pose],"")
    if override_path!="":
     pose_image=Image.load_from_file(source+override_path)
     if pose_image==null or pose_image.get_size()!=base.get_size():
      fail("Invalid per-fan source: "+override_path)
      return
     pose_image.convert(Image.FORMAT_RGBA8)
    atlas.blit_rect(pose_image,area,Vector2i(i*96,pose*96))
  # Texture fingerprint survives Godot import/export remapping.
  var image_for_hash := base.duplicate() as Image
  image_for_hash.convert(Image.FORMAT_RGBA8)
  var hash := HashingContext.new()
  hash.start(HashingContext.HASH_SHA256)
  hash.update(image_for_hash.get_data())
  data.texture_sha256 = hash.finish().hex_encode()
  atlas.save_png(output+data.court+".png")
  FileAccess.open(output+data.court+".json",FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
  if "--promote" in OS.get_cmdline_user_args():
   DirAccess.copy_absolute(output+data.court+".png","res://assets/art/crowds/composed/"+data.court+".png")
   DirAccess.copy_absolute(output+data.court+".json","res://assets/art/crowds/composed/"+data.court+".json")
  print("Validated ",data.court,": ",data.fans.size()," registered fans; court artwork untouched")
 quit()
func fail(message: String) -> void:
 push_error(message)
 quit(1)
