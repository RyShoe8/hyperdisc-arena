## Compare unaccepted candidate art without changing game atlases.
extends SceneTree
const UI=preload("res://scripts/game/ui/theme.gd")
var node: Node2D
var art
var sprites: Array[Texture2D]=[]
var tick:=0
var id:="mick"
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--character="): id=arg.get_slice("=",1)
	_setup.call_deferred()
func _setup() -> void:
	UI.load_fonts()
	root.size=Vector2i(1440,700)
	root.content_scale_size=Vector2i(1440,700)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	art=load("res://scripts/game/view/character_art.gd").new(id)
	var jobs: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tools/art/characters/directional-release.json"))
	var folder:="res://tools/art/characters/%s/jobs/%s/" % [id,jobs[id]]
	var sheet:=Image.load_from_file(folder+"candidate.png")
	var parts: Array=JSON.parse_string(FileAccess.get_file_as_string(folder+"preview-components.json"))
	var tallest:=0
	for part in parts: tallest=maxi(tallest,part.bounds[3]-part.bounds[1]+1)
	var height:=275.0 if id=="keno" else (260.0 if id=="steve" else 250.0)
	for index in parts.size():
		if index % 8 == 0:
			tallest=0
			for j in range(index,index+8): tallest=maxi(tallest,parts[j].bounds[3]-parts[j].bounds[1]+1)
		var part: Dictionary=parts[index]
		var b: Array=part.bounds
		var crop:=Image.create(b[2]-b[0]+1,b[3]-b[1]+1,false,Image.FORMAT_RGBA8)
		for run in part.runs:
			crop.blit_rect(sheet,Rect2i(run[1],run[0],run[2],1),Vector2i(run[1]-b[0],run[0]-b[1]))
		crop.resize(roundi(crop.get_width()*height/tallest),roundi(crop.get_height()*height/tallest),Image.INTERPOLATE_NEAREST)
		sprites.append(ImageTexture.create_from_image(crop))
	node=Node2D.new()
	root.add_child(node)
	node.draw.connect(_draw)
	DirAccess.make_dir_recursive_absolute("res://build/identity-preview")
	process_frame.connect(_tick)
func _tick() -> void:
	tick+=1
	node.queue_redraw()
	if tick in [20,40]:
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://build/identity-preview/%s-%d.png" % [id,tick])
	if tick==120: quit()
func _draw() -> void:
	node.draw_rect(Rect2(0,0,1440,700),Color("171828"))
	UI.text(node,Vector2(720,60),id.to_upper()+" — IDENTITY COMPARISON",34,Color.WHITE,UI.display,2)
	for column in 3:
		var ground:=Vector2(240+column*480,550)
		UI.text(node,Vector2(ground.x,135),["APPROVED RUN","UP / BACK","DOWN / FRONT"][column],26,UI.CYAN,UI.ui,2)
		if column==0:
			art.draw(node,art.frame_for("run",tick*2),ground,true,1.4)
		else:
			var texture:=sprites[(column-1)*8+(tick/2)%8]
			var size:=texture.get_size()*1.4
			node.draw_texture_rect(texture,Rect2(ground-Vector2(size.x/2,size.y),size),false)
		UI.text(node,Vector2(ground.x,615),"DRAFT — NOT PUBLISHED" if column>0 else "CANONICAL",22,UI.DIM,UI.ui,2)
