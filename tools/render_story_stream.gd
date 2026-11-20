## Frames go directly to the local encoder: no multi-gigabyte AVI intermediary.
extends SceneTree
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	var args := OS.get_cmdline_user_args()
	var port := int(args[0])
	var reel := args.size() > 1 and args[1] == "reel"
	var tower := args.size() > 1 and args[1] == "tower"
	var width := int(args[2]) if args.size()>2 else 1280
	var height := int(args[3]) if args.size()>3 else 720
	root.size = Vector2i(width,height)
	root.content_scale_size = Vector2i(1920,1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var movie = load("res://scenes/story_prologue.tscn").instantiate()
	root.add_child(movie)
	movie.set_physics_process(false)
	movie.set_process_unhandled_input(false)
	movie.ambience.stop()
	movie.score.stop()
	var spans: Array = [[0.0,float(movie.timeline.duration)]]
	if reel:
		spans = [[1.2,8.0]]
		for entry in [[3,0,6.5],[6,0,8],[15,0,4],[25,0,4],[32,0,4],[35,0,5],[37,0,8],[44,0,7],[49,0,4.5]]:
			var start := float(movie.timeline.beats[entry[0]].start)+float(entry[1])
			spans.append([start,start+float(entry[2])])
	if tower:
		spans = [[float(movie.timeline.beats[5].start),float(movie.timeline.beats[7].start)],[float(movie.timeline.beats[15].start),float(movie.timeline.beats[15].start)+4]]
	var total := 0
	for span in spans:
		total += ceili((float(span[1])-float(span[0]))*30)
	var stream := StreamPeerTCP.new()
	if stream.connect_to_host("127.0.0.1",port) != OK:
		quit(2)
		return
	while stream.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		stream.poll()
		await process_frame
	if stream.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		quit(3)
		return
	stream.put_u32(width)
	stream.put_u32(height)
	stream.put_u32(total)
	var n := 0
	for span in spans:
		for frame in ceili((float(span[1])-float(span[0]))*30):
			movie.seek(float(span[0])+frame/30.0)
			await process_frame
			await RenderingServer.frame_post_draw
			var img := root.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			if stream.put_data(img.get_data()) != OK:
				quit(4)
				return
			n += 1
			if n % 300 == 0:
				print("STORY CAPTURE %d/%d frames" % [n,total])
	stream.disconnect_from_host()
	movie.queue_free()
	await process_frame
	quit()
