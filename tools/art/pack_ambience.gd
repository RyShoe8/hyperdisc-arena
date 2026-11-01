extends SceneTree
func _initialize() -> void:
 var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/venues/approved.json"))
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/venues/ambience.json"))
 if FileAccess.get_sha256("res://tools/art/venues/calibration.json") != baseline.calibration_sha256:
  push_error("Ambience requires reviewed calibration")
  quit(1)
  return
 for id in data.courts:
  var entry: Dictionary=baseline.courts[id]
  if FileAccess.get_sha256("res://"+entry.path) != entry.sha256:
   push_error("Ambience registration requires reviewed court: "+id)
   quit(1)
   return
  var img=Image.load_from_file("res://"+entry.path)
  img.convert(Image.FORMAT_RGBA8)
  var hash=HashingContext.new()
  hash.start(HashingContext.HASH_SHA256)
  hash.update(img.get_data())
  data.courts[id].texture_sha256=hash.finish().hex_encode()
 DirAccess.make_dir_recursive_absolute("res://build/venues")
 FileAccess.open("res://build/venues/ambience.json",FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
 if "--promote" in OS.get_cmdline_user_args():
  DirAccess.copy_absolute("res://build/venues/ambience.json","res://data/venue_ambience.json")
 print("Validated ambience against six court baselines")
 quit()
