extends SceneTree
func _initialize() -> void:
 _run.call_deferred()
func _run() -> void:
 var game=load("res://scenes/main.tscn").instantiate()
 root.add_child(game)
 game.set_physics_process(false)
 root.size=Vector2i(1920,1080)
 var pb=root.get_node("Online").playbound
 pb.lobby_rooms=[{"id":"sample","name":"MICK","players":1,"capacity":2,"version":pb.build_id,"code":"TEST"}]
 pb.lobby_players=[{"name":"MICK","status":"online"},{"name":"PETE","status":"playing"}]
 game._go(game.Screen.ONLINE_ROOM)
 game.queue_redraw()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://build/lobby-preview.png")
 quit()
