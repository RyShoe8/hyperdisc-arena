"""Shared helpers for the Blender art scripts: scene reset, the game camera,
cel-shaded materials, ink outlines and rendering.

Blender world axes vs. game axes:
    Blender X = game x - court_width / 2   (right)
    Blender Y = court_height / 2 - game y  (away from the camera)
    Blender Z = game z                     (up)
so the court floor is centred on the origin.

The camera and scale come from data/projection.json, which the game reads
too, so rendered art lines up exactly with what the game draws on top.
"""

import json
import math
import os
import random

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECTION = json.load(open(os.path.join(ROOT, "data", "projection.json")))
BALANCE = json.load(open(os.path.join(ROOT, "data", "balance.json")))

# 80s Outrun palette, shared with the game UI.
INK = "1a0f2e"
NEON_PINK = "ff2e88"
NEON_CYAN = "2de2e6"
SUNSET_ORANGE = "ff8c42"
SUNSET_YELLOW = "ffd23f"
DEEP_PURPLE = "3d1a6e"
ZONE_3 = "ffd23f"
ZONE_5 = "ff2e63"


def rgb(hex_str, a=1.0):
    c = [int(hex_str[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*c, a)


def reset():
    global _ink
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # The reset deletes every material, so cached ones are now dangling.
    _toon_cache.clear()
    _ink = None
    scene = bpy.context.scene
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    try:
        scene.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.6, 0.6, 0.65, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    return scene


def court_camera(scene, width=None, height=None):
    """Orthographic camera matching the game's court projection."""
    p = PROJECTION
    w = width or p["screen_width"]
    h = height or p["screen_height"]
    scene.render.resolution_x = w
    scene.render.resolution_y = h
    pitch = math.radians(p["pitch_degrees"])
    cam_data = bpy.data.cameras.new("court_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = p["screen_width"] / p["scale"]
    cam_data.clip_start = 1
    cam_data.clip_end = 20000
    # The floor centre sits at floor_centre_screen_y rather than mid-screen.
    cam_data.shift_y = (p["floor_centre_screen_y"] - p["screen_height"] / 2) / p["screen_width"]
    cam = bpy.data.objects.new("court_cam", cam_data)
    tilt = math.pi / 2 - pitch  # from straight down
    cam.rotation_euler = (tilt, 0, 0)
    dist = 5000
    cam.location = (0, -dist * math.sin(tilt), dist * math.cos(tilt))
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    return cam


def sun(name="sun", energy=3.0, angle=(50, -25, 20), color=(1, 0.97, 0.92), shadows=True):
    ld = bpy.data.lights.new(name, "SUN")
    ld.energy = energy
    ld.color = color
    ld.use_shadow = shadows
    try:
        ld.angle = math.radians(1.5)
    except AttributeError:
        pass
    lo = bpy.data.objects.new(name, ld)
    lo.rotation_euler = tuple(math.radians(a) for a in angle)
    bpy.context.collection.objects.link(lo)
    return lo


# --- Materials -------------------------------------------------------------

_toon_cache = {}


def shadow_tint(shade):
    """Shadow multiplier, pushed toward violet for the Outrun look."""
    return (min(shade * 0.9, 1.0), min(shade * 0.8, 1.0), min(shade * 1.2, 1.0), 1)


def toon(color, shade=0.62, name=None, emission=0.0, rim=0.0):
    """Flat two-tone cel shading: lit colour, and a darker band in shadow.

    The light term goes through Shader to RGB and a constant colour ramp,
    so shadows (including cast shadows) snap to one hard step like ink-and-
    paint animation.
    """
    key = (color, shade, emission, rim)
    if name is None and key in _toon_cache:
        return _toon_cache[key]
    m = bpy.data.materials.new(name or f"toon_{color}_{shade}")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    diffuse = nt.nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = shadow_tint(shade)
    ramp.color_ramp.elements[1].position = 0.32
    ramp.color_ramp.elements[1].color = (1, 1, 1, 1)
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    mul.inputs[6].default_value = rgb(color)
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(diffuse.outputs[0], to_rgb.inputs[0])
    nt.links.new(to_rgb.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], mul.inputs[7])
    nt.links.new(mul.outputs[2], emit.inputs[0])
    emit.inputs[1].default_value = 1.0
    if emission > 0:
        glow = nt.nodes.new("ShaderNodeEmission")
        glow.inputs[0].default_value = rgb(color)
        glow.inputs[1].default_value = emission
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(emit.outputs[0], add.inputs[0])
        nt.links.new(glow.outputs[0], add.inputs[1])
        nt.links.new(add.outputs[0], out.inputs[0])
    else:
        nt.links.new(emit.outputs[0], out.inputs[0])
    if name is None:
        _toon_cache[key] = m
    return m


def toon_textured(name, color_node_builder, shade=0.62):
    """Toon material whose base colour comes from a node graph.

    color_node_builder(nt) must return a node output socket giving colour.
    """
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    diffuse = nt.nodes.new("ShaderNodeBsdfDiffuse")
    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].color = shadow_tint(shade)
    ramp.color_ramp.elements[1].position = 0.32
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    emit = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(diffuse.outputs[0], to_rgb.inputs[0])
    nt.links.new(to_rgb.outputs[0], ramp.inputs[0])
    nt.links.new(color_node_builder(nt), mul.inputs[6])
    nt.links.new(ramp.outputs[0], mul.inputs[7])
    nt.links.new(mul.outputs[2], emit.inputs[0])
    nt.links.new(emit.outputs[0], out.inputs[0])
    return m


def flat(color, strength=1.0, name=None):
    """Unlit colour (signs, neon tubes, ink)."""
    m = bpy.data.materials.new(name or f"flat_{color}")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs[0].default_value = rgb(color)
    emit.inputs[1].default_value = strength
    nt.links.new(emit.outputs[0], out.inputs[0])
    return m


_ink = None


def ink_material():
    global _ink
    if _ink is None:
        _ink = flat(INK, name="ink")
        _ink.use_backface_culling = True
        try:
            _ink.surface_render_method = "DITHERED"
        except AttributeError:
            pass
    return _ink


def outline(obj, thickness=2.5):
    """Inverted-hull ink outline: a slightly fattened copy of the mesh with
    flipped normals and backface culling, so only its rim shows."""
    if obj.type != "MESH":
        return
    mat = ink_material()
    if mat.name not in obj.data.materials:
        obj.data.materials.append(mat)
    idx = list(obj.data.materials).index(mat)
    mod = obj.modifiers.new("ink", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.material_offset = idx
    mod.use_quality_normals = True


def assign(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)
    return obj


def smooth(obj):
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


# --- Primitives (created without bpy.ops where practical for speed) --------

def box(name, size, loc, mat, rot=(0, 0, 0), bevel=0.0, ink=3.5):
    bpy.ops.mesh.primitive_cube_add(location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    bpy.ops.object.transform_apply(scale=True)
    if bevel > 0:
        m = ob.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = 2
    assign(ob, mat)
    if ink:
        outline(ob, ink)
    return ob


def cylinder(name, radius, depth, loc, mat, rot=(0, 0, 0), verts=24, ink=3.5):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=loc, rotation=rot, vertices=verts)
    ob = bpy.context.active_object
    ob.name = name
    assign(ob, mat)
    smooth(ob)
    if ink:
        outline(ob, ink)
    return ob


def sphere(name, radius, loc, mat, scale=(1, 1, 1), segs=24, ink=3.5):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=segs, ring_count=segs // 2)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = scale
    bpy.ops.object.transform_apply(scale=True)
    assign(ob, mat)
    smooth(ob)
    if ink:
        outline(ob, ink)
    return ob


def plane(name, size, loc, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(location=loc, rotation=rot)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size[0] / 2, size[1] / 2, 1)
    bpy.ops.object.transform_apply(scale=True)
    assign(ob, mat)
    return ob


def text(body, size, loc, mat, rot=(0, 0, 0), font=None, extrude=0.0, align="CENTER"):
    cu = bpy.data.curves.new(body, "FONT")
    cu.body = body
    cu.size = size
    cu.align_x = align
    cu.align_y = "CENTER"
    cu.extrude = extrude
    if font:
        cu.font = bpy.data.fonts.load(os.path.join(ROOT, "assets", "fonts", font), check_existing=True)
    ob = bpy.data.objects.new(body, cu)
    ob.location = loc
    ob.rotation_euler = rot
    ob.data.materials.append(mat)
    bpy.context.collection.objects.link(ob)
    return ob


def render(path, transparent=True, quality=None):
    """Renders the scene. A .webp path saves lossy WebP (the shipped art);
    anything else saves PNG (intermediate frames)."""
    scene = bpy.context.scene
    scene.render.film_transparent = transparent
    fmt = scene.render.image_settings
    if path.endswith(".webp"):
        fmt.file_format = "WEBP"
        fmt.quality = quality or 88
    else:
        fmt.file_format = "PNG"
    fmt.color_mode = "RGBA" if transparent else "RGB"
    scene.render.filepath = path
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def seeded(seed):
    return random.Random(seed)
