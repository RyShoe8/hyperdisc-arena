"""Render the HyperDisc Arena logo.

Run from the repo root:
    blender -b --factory-startup -P tools/blender/make_logo.py

Writes assets/logo/logo.png (transparent) and assets/logo/logo_preview.png
(on the game's background colour). Everything is built in code, so edit this
file rather than a .blend.
"""

import math
import os

import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FONT = os.path.join(ROOT, "assets", "fonts", "kenney_future.ttf")
OUT_DIR = os.path.join(ROOT, "assets", "logo")

# Palette from scripts/game/main.gd
BG = "16213e"
OUTLINE = "0d1326"
GOLD = "ffd166"
ORANGE = "e8603c"
PINK = "ef476f"
BLUE = "3c9ee8"
WHITE = "f1f2f6"


def rgb(hex_str, a=1.0):
    c = [int(hex_str[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    # sRGB -> linear
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (*c, a)


def flat_material(name, color, emit=0.35, rough=0.35):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = rgb(color)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Emission Color"].default_value = rgb(color)
    bsdf.inputs["Emission Strength"].default_value = emit
    return m


def gradient_material(name, top, bottom, half_height, emit=0.35):
    """Vertical gradient over object-space Y in [-half_height, half_height]."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    span = nt.nodes.new("ShaderNodeMapRange")
    span.inputs["From Min"].default_value = -half_height
    span.inputs["From Max"].default_value = half_height
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.2
    ramp.color_ramp.elements[0].color = rgb(bottom)
    ramp.color_ramp.elements[1].position = 0.8
    ramp.color_ramp.elements[1].color = rgb(top)
    nt.links.new(coord.outputs["Object"], sep.inputs[0])
    nt.links.new(sep.outputs["Y"], span.inputs["Value"])
    nt.links.new(span.outputs["Result"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = emit
    bsdf.inputs["Roughness"].default_value = 0.3
    return m


def _drop_notches(curve, max_turn_deg=120):
    """Rebuild splines without hairpin vertices.

    Kenney Future's R has a sharp inward notch on its right side; bevel mitres
    it into a long spike that runs through the following letters.
    """
    for sp in list(curve.splines):
        pts = list(sp.bezier_points)
        keep = []
        for i, p in enumerate(pts):
            a, b = pts[i - 1].co, pts[(i + 1) % len(pts)].co
            d1, d2 = (p.co - a).xy, (b - p.co).xy
            if d1.length and d2.length and math.degrees(d1.angle(d2)) > max_turn_deg:
                continue
            keep.append((p.co.copy(), p.handle_left.copy(), p.handle_right.copy(),
                         p.handle_left_type, p.handle_right_type))
        if len(keep) == len(pts):
            continue
        new = curve.splines.new("BEZIER")
        new.bezier_points.add(len(keep) - 1)
        for bp, (co, hl, hr, tl, tr) in zip(new.bezier_points, keep):
            bp.co, bp.handle_left, bp.handle_right = co, hl, hr
            bp.handle_left_type, bp.handle_right_type = tl, tr
        new.use_cyclic_u = sp.use_cyclic_u
        curve.splines.remove(sp)


def text(body, size, mat, z=0.0, extrude=0.06, bevel=0.015, spacing=1.0):
    font = bpy.data.fonts.load(FONT, check_existing=True)
    cu = bpy.data.curves.new(body + "_curve", "FONT")
    cu.body = body
    cu.font = font
    cu.size = size
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.space_character = spacing
    ob = bpy.data.objects.new(body, cu)
    bpy.context.collection.objects.link(ob)

    # Convert to a plain curve so glyph outlines can be cleaned before bevel.
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.convert(target="CURVE")
    ob = bpy.context.active_object
    _drop_notches(ob.data)

    ob.data.extrude = extrude
    ob.data.bevel_depth = bevel
    ob.data.bevel_resolution = 3 if extrude > 0 else 0
    ob.location.z = z
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def outlined_text(body, size, fill, outline_mat, shadow_mat, y, spacing=1.0, stroke=0.07):
    """Fill + thick dark stroke + offset drop shadow, all parented to one empty."""
    root = bpy.data.objects.new(body + "_root", None)
    bpy.context.collection.objects.link(root)
    parts = [
        text(body, size, fill, z=0.0, spacing=spacing),
        text(body, size, outline_mat, z=-0.2, extrude=0.0, bevel=stroke, spacing=spacing),
        text(body, size, shadow_mat, z=-0.4, extrude=0.0, bevel=stroke, spacing=spacing),
    ]
    parts[2].location.x = 0.09 * size
    parts[2].location.y = -0.09 * size
    for p in parts:
        p.parent = root
    root.location.y = y
    return root


def rounded_box(name, w, h, depth, radius, mat, loc):
    bpy.ops.mesh.primitive_cube_add(location=loc)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (w / 2, h / 2, depth / 2)
    bpy.ops.object.transform_apply(scale=True)
    bev = ob.modifiers.new("bevel", "BEVEL")
    bev.width = radius
    bev.segments = 6
    bev.limit_method = "NONE"
    ob.data.materials.append(mat)
    return ob


def disc(loc, radius, tilt_deg, spin_deg):
    """A flying disc: domed body, raised rim and a stripe, tilted toward camera."""
    root = bpy.data.objects.new("disc_root", None)
    bpy.context.collection.objects.link(root)

    body_mat = gradient_material("disc_body", "7cc4ff", BLUE, half_height=0.9, emit=0.4)
    rim_mat = flat_material("disc_rim", WHITE, emit=0.5)
    stripe_mat = flat_material("disc_stripe", GOLD, emit=0.5)
    edge_mat = flat_material("disc_edge", OUTLINE, emit=0.0)

    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=64, ring_count=32)
    body = bpy.context.active_object
    body.scale.z = 0.18
    body.data.materials.append(body_mat)
    bpy.ops.object.shade_smooth()

    bpy.ops.mesh.primitive_torus_add(major_radius=radius, minor_radius=radius * 0.09,
                                     major_segments=96, minor_segments=16)
    rim = bpy.context.active_object
    rim.data.materials.append(rim_mat)
    bpy.ops.object.shade_smooth()

    bpy.ops.mesh.primitive_torus_add(major_radius=radius * 0.62, minor_radius=radius * 0.05,
                                     major_segments=96, minor_segments=12)
    stripe = bpy.context.active_object
    stripe.location.z = radius * 0.14
    stripe.scale.z = 0.5
    stripe.data.materials.append(stripe_mat)
    bpy.ops.object.shade_smooth()

    # Dark silhouette slightly larger and behind, so the disc gets the same
    # chunky outline as the lettering.
    bpy.ops.mesh.primitive_cylinder_add(radius=radius * 1.14, depth=radius * 0.1, vertices=96)
    edge = bpy.context.active_object
    edge.location.z = -radius * 0.25
    edge.data.materials.append(edge_mat)
    bpy.ops.object.shade_smooth()

    for p in (body, rim, stripe, edge):
        p.parent = root
    root.location = loc
    root.rotation_euler = (math.radians(tilt_deg), 0, math.radians(spin_deg))
    return root


def speed_lines(origin, count, mat):
    """Tapered streaks trailing to the left of the disc."""
    specs = [(-0.55, 3.6, 0.10), (-0.15, 4.4, 0.13), (0.25, 3.9, 0.11), (0.62, 2.9, 0.08)]
    for i, (dy, length, thick) in enumerate(specs[:count]):
        bpy.ops.mesh.primitive_cone_add(vertices=24, radius1=thick, radius2=0.0, depth=length)
        ob = bpy.context.active_object
        ob.name = f"streak_{i}"
        ob.rotation_euler = (0, math.radians(-90), 0)
        ob.scale.y = 0.6
        ob.location = (origin[0] - length / 2 - 0.4, origin[1] + dy, origin[2] - 0.3)
        ob.data.materials.append(mat)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene

    outline_mat = flat_material("outline", OUTLINE, emit=0.0, rough=0.6)
    shadow_mat = flat_material("shadow", "000000", emit=0.0, rough=1.0)
    hyper_mat = gradient_material("hyper", GOLD, ORANGE, half_height=0.45, emit=0.45)
    disc_text_mat = gradient_material("disc_text", "8fd0ff", BLUE, half_height=0.45, emit=0.45)
    arena_mat = flat_material("arena_text", WHITE, emit=0.5)
    banner_mat = gradient_material("banner", "ff6b8f", PINK, half_height=0.5, emit=0.35)
    streak_mat = flat_material("streak", WHITE, emit=1.2)

    logo = bpy.data.objects.new("logo", None)
    bpy.context.collection.objects.link(logo)

    # HYPER and DISC are separate so DISC can carry the disc's blue: the
    # all-caps logo still reads as "HyperDisc".
    size = 1.55
    hyper = outlined_text("HYPER", size, hyper_mat, outline_mat, shadow_mat, y=0.45,
                          spacing=1.02, stroke=0.075)
    disc_word = outlined_text("DISC", size, disc_text_mat, outline_mat, shadow_mat, y=0.45,
                              spacing=1.02, stroke=0.075)
    bpy.context.view_layer.update()
    w_hyper = hyper.children[0].dimensions.x
    w_disc = disc_word.children[0].dimensions.x
    gap = 0.12 * size
    total = w_hyper + gap + w_disc
    hyper.location.x = -total / 2 + w_hyper / 2
    disc_word.location.x = total / 2 - w_disc / 2
    title = bpy.data.objects.new("title", None)
    bpy.context.collection.objects.link(title)
    hyper.parent = title
    disc_word.parent = title

    banner_root = bpy.data.objects.new("banner_root", None)
    bpy.context.collection.objects.link(banner_root)
    banner = rounded_box("banner", 5.4, 1.05, 0.12, 0.3, banner_mat, (0, 0, -0.35))
    banner_edge = rounded_box("banner_edge", 5.7, 1.35, 0.06, 0.42, outline_mat, (0, 0, -0.5))
    banner_shadow = rounded_box("banner_shadow", 5.7, 1.35, 0.06, 0.42, shadow_mat, (0.12, -0.12, -0.6))
    arena = outlined_text("ARENA", 0.72, arena_mat, outline_mat, shadow_mat, y=0.0,
                          spacing=1.35, stroke=0.05)
    for p in (banner, banner_edge, banner_shadow, arena):
        p.parent = banner_root
    banner_root.location = (0.0, -1.2, -0.8)

    disc_root = disc(loc=(5.15, 1.3, 0.6), radius=0.85, tilt_deg=62, spin_deg=-18)
    speed_lines((4.35, 1.4, -0.6), 4, streak_mat)

    for ob in (title, banner_root, disc_root):
        ob.parent = logo
    for ob in bpy.data.objects:
        if ob.name.startswith("streak_"):
            ob.parent = logo
    # Slight upward slant reads as motion.
    logo.rotation_euler.z = math.radians(5)

    # Camera: orthographic, straight on.
    cam_data = bpy.data.cameras.new("cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 13.0
    cam = bpy.data.objects.new("cam", cam_data)
    cam.location = (0.35, 0.05, 20)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam

    # Lights: warm key from upper left, cool rim from the right.
    for name, energy, rot, color in [
        ("key", 4.0, (math.radians(35), math.radians(-30), 0), (1.0, 0.96, 0.9)),
        ("rim", 2.0, (math.radians(-40), math.radians(45), 0), (0.75, 0.85, 1.0)),
    ]:
        ld = bpy.data.lights.new(name, "SUN")
        ld.energy = energy
        ld.color = color
        ld.use_shadow = False  # flat arcade look; cast shadows smear across the banner
        lo = bpy.data.objects.new(name, ld)
        lo.rotation_euler = rot
        bpy.context.collection.objects.link(lo)

    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = rgb(BG)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    scene.world = world

    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = engine
            break
        except TypeError:
            continue
    scene.view_settings.view_transform = "Standard"
    scene.render.resolution_x = 2400
    scene.render.resolution_y = 1100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    return scene


def render(scene, path, transparent):
    scene.render.film_transparent = transparent
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    os.makedirs(OUT_DIR, exist_ok=True)
    s = build()
    render(s, os.path.join(OUT_DIR, "logo.png"), transparent=True)
    render(s, os.path.join(OUT_DIR, "logo_preview.png"), transparent=False)
