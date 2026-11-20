## Rigby evaluates every bone; Godot skins the unmodified character atlas.
extends Node2D
var sheet: Texture2D
var source: Dictionary
var quads: Array = []
var columns := 8
var frame_size := 512
var skin: ArrayMesh
var mesh_uvs: Dictionary = {}
var mesh_indices: Dictionary = {}
var cache: Dictionary = {}
var last_key := ""
var anchors: Dictionary = {}
var frame_markers: Array = []
var textures: Dictionary = {}
var skin_texture: Texture2D
var shadow_offset := 0.0

func setup(id: String, rigby: Dictionary) -> void:
	source = rigby
	sheet = load("res://assets/art/characters/%s.webp" % id)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/characters/%s.json" % id))
	columns = int(meta.columns)
	frame_size = int(meta.frame_size)
	frame_markers = meta.frames
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for image in source.images.values():
		if image.has("texture") and not textures.has(image.texture):
			textures[image.texture] = load(image.texture)
	for mesh_name in source.meshes:
		var mesh: Dictionary = source.meshes[mesh_name]
		var image: Dictionary = source.images[mesh.image]
		var crop: Array = image.crop
		var external := image.has("texture")
		var texture: Texture2D = textures[image.texture] if external else sheet
		var origin := Vector2.ZERO if external else Vector2((int(image.frame) % columns) * frame_size, (int(image.frame) / columns) * frame_size)
		var uvs := PackedVector2Array()
		for i in range(0, mesh.uvs.size(), 2):
			uvs.append((origin + Vector2(crop[0] + mesh.uvs[i] * mesh.width, crop[1] + mesh.uvs[i + 1] * mesh.height)) / texture.get_size())
		mesh_uvs[mesh_name] = uvs
		mesh_indices[mesh_name] = PackedInt32Array(mesh.triangles)

func sample(animation: String, time: float) -> void:
	var clip: Dictionary = source.animations[animation]
	var index := clampi(roundi(time * 30), 0, clip.frames.size() - 1)
	var cache_key := "%s:%d" % [animation, index]
	if cache_key == last_key:
		return
	last_key = cache_key
	var frame = clip.frames[index]
	if frame is Array:
		quads = frame
		anchors.clear()
		for q in quads:
			if source.images[q[0]].has("markers"):
				for name in source.images[q[0]].markers:
					var point: Array = source.images[q[0]].markers[name]
					anchors[name] = Vector2(point[0],point[1])
			var cell := int(source.images[q[0]].frame)
			if cell >= 0 and cell < frame_markers.size():
				var markers: Dictionary = frame_markers[cell]
				for name in ["head","hand"]:
					if markers.has(name):
						var point: Array = markers[name]
						anchors["hand_front" if name=="hand" else name] = Vector2(point[0]-256,point[1]-450)
		skin = null
	else:
		quads = frame.q
		anchors.clear()
		var anchor_map: Dictionary = source.get("meshAnchors",{}).get(frame.m,source.anchors)
		for name in anchor_map:
			var matrix: Array = frame.b[int(anchor_map[name])]
			anchors[name] = Vector2(matrix[4], -matrix[5])
		var skin_image: Dictionary = source.images[source.meshes[frame.m].image]
		skin_texture = textures[skin_image.texture] if skin_image.has("texture") else sheet
		if cache.has(cache_key):
			skin = cache[cache_key]
		else:
			var vertices := PackedVector2Array()
			for weights in source.meshes[frame.m].weights:
				var p := Vector2.ZERO
				for w in weights:
					var m: Array = frame.b[int(w.bone)]
					p += Vector2(m[0] * w.x + m[2] * w.y + m[4], -(m[1] * w.x + m[3] * w.y + m[5])) * float(w.weight)
				vertices.append(p)
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_TEX_UV] = mesh_uvs[frame.m]
			arrays[Mesh.ARRAY_INDEX] = mesh_indices[frame.m]
			skin = ArrayMesh.new()
			skin.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			if cache.size() >= 180:
				cache.erase(cache.keys()[0])
			cache[cache_key] = skin
	queue_redraw()

func _draw() -> void:
	if sheet == null:
		return
	# The stair rig's origin follows its hips, not a sand contact. A ground
	# ellipse there would float below the steps and spoil the planted feet.
	if not anchors.has("front_sole"):
		draw_set_transform(Vector2(0,shadow_offset), 0, Vector2(1, 0.2))
		draw_circle(Vector2.ZERO, 46, Color(0.12, 0.11, 0.25, 0.21))
		draw_set_transform(Vector2.ZERO)
	if skin != null:
		draw_mesh(skin, skin_texture)
	for q in quads:
		var image: Dictionary = source.images[q[0]]
		var crop: Array = image.crop
		var frame := int(image.frame)
		var external := image.has("texture")
		var texture: Texture2D = textures[image.texture] if external else sheet
		var origin := Vector2.ZERO if external else Vector2((frame % columns) * frame_size, (frame / columns) * frame_size)
		var uv0 := (origin + Vector2(crop[0], crop[1])) / texture.get_size()
		var uv1 := (origin + Vector2(crop[2], crop[3])) / texture.get_size()
		var points := PackedVector2Array([Vector2(q[1], q[2]), Vector2(q[3], q[4]), Vector2(q[5], q[6]), Vector2(q[7], q[8])])
		draw_polygon(points, PackedColorArray([Color.WHITE]), PackedVector2Array([uv0, Vector2(uv1.x, uv0.y), uv1, Vector2(uv0.x, uv1.y)]), texture)

func attachment_point(name: String) -> Vector2:
	var local: Vector2 = anchors.get(name, Vector2(65, -130))
	return position + local * scale
