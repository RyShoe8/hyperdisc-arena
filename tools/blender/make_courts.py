"""Render the six court backgrounds.

Run from the repo root:
    blender -b --factory-startup -P tools/blender/make_courts.py [-- court_id ...]

For each court in data/balance.json this writes, under assets/art/courts/:
    <id>.webp          the court and its surroundings, no crowd
    <id>_crowd_a.webp  the crowd, sitting (transparent, already occluded by walls)
    <id>_crowd_b.webp  the crowd, on its feet cheering
The game draws the background, then a crowd layer, then players and the disc.
Goal-zone lights, the net shadow and barriers are drawn by the game on top,
because they change during play.
"""

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402

OUT = os.path.join(C.ROOT, "assets", "art", "courts")
P = C.PROJECTION
WALL_H = P["wall_height"]
PANEL = P["goal_panel_depth"]
PALETTE_CROWD = ["ff2e88", "2de2e6", "ffd23f", "ff8c42", "7b2cbf", "06d6a0", "f15bb5",
                 "fee440", "00bbf9", "ffffff", "ef476f", "118ab2"]
SKIN = ["f1c27d", "e0ac69", "c68642", "8d5524", "ffdbac", "a86b45"]


# --- Floors ------------------------------------------------------------------

def _coords(nt, scale):
    tex = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (scale, scale, scale)
    nt.links.new(tex.outputs["Object"], mapping.inputs["Vector"])
    return mapping.outputs["Vector"]


def _mix(nt, fac, a, b):
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(fac, mix.inputs["Factor"])
    if isinstance(a, tuple):
        mix.inputs[6].default_value = a
    else:
        nt.links.new(a, mix.inputs[6])
    if isinstance(b, tuple):
        mix.inputs[7].default_value = b
    else:
        nt.links.new(b, mix.inputs[7])
    return mix.outputs[2]


def _ramp(nt, fac, stops):
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    els = ramp.color_ramp.elements
    while len(els) < len(stops):
        els.new(0.5)
    for el, (pos, col) in zip(els, stops):
        el.position = pos
        el.color = C.rgb(col)
    nt.links.new(fac, ramp.inputs[0])
    return ramp.outputs[0]


def floor_material(kind):
    def sand(nt):
        v = _coords(nt, 0.02)
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.0
        noise.inputs["Detail"].default_value = 6
        nt.links.new(v, noise.inputs["Vector"])
        wave = nt.nodes.new("ShaderNodeTexWave")
        wave.inputs["Scale"].default_value = 1.4
        wave.inputs["Distortion"].default_value = 3
        nt.links.new(v, wave.inputs["Vector"])
        a = _ramp(nt, noise.outputs["Fac"], [(0.0, "f4d396"), (0.5, "f7dba4"), (0.7, "fae3b3")])
        ripple = nt.nodes.new("ShaderNodeMath")
        ripple.operation = "MULTIPLY"
        ripple.inputs[1].default_value = 0.22
        nt.links.new(wave.outputs["Fac"], ripple.inputs[0])
        return _mix(nt, ripple.outputs[0], a, C.rgb("e8c07f"))

    def grass(nt):
        v = _coords(nt, 1.0)
        stripes = nt.nodes.new("ShaderNodeTexWave")
        stripes.wave_type = "BANDS"
        stripes.bands_direction = "X"
        stripes.wave_profile = "SAW"
        stripes.inputs["Scale"].default_value = 0.0062
        nt.links.new(v, stripes.inputs["Vector"])
        a = _ramp(nt, stripes.outputs["Fac"], [(0.0, "4fbf4a"), (0.5, "5fd35a")])
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.08
        nt.links.new(v, noise.inputs["Vector"])
        return _mix(nt, noise.outputs["Fac"], a, C.rgb("57c752"))

    def tiles(nt):
        v = _coords(nt, 1.0)
        brick = nt.nodes.new("ShaderNodeTexBrick")
        brick.inputs["Scale"].default_value = 0.016
        brick.inputs["Mortar Size"].default_value = 0.03
        brick.inputs["Brick Width"].default_value = 1.0
        brick.inputs["Row Height"].default_value = 1.0
        brick.inputs["Bias"].default_value = 0.0
        brick.offset = 0.0
        brick.inputs["Color1"].default_value = C.rgb("ff8fc7")
        brick.inputs["Color2"].default_value = C.rgb("8de8f2")
        brick.inputs["Mortar"].default_value = C.rgb("fdf6ff")
        nt.links.new(v, brick.inputs["Vector"])
        return brick.outputs["Color"]

    def concrete(nt):
        v = _coords(nt, 1.0)
        brick = nt.nodes.new("ShaderNodeTexBrick")
        brick.inputs["Scale"].default_value = 0.0042
        brick.inputs["Mortar Size"].default_value = 0.008
        brick.inputs["Brick Width"].default_value = 1.0
        brick.inputs["Row Height"].default_value = 1.0
        brick.offset = 0.0
        nt.links.new(v, brick.inputs["Vector"])
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.02
        noise.inputs["Detail"].default_value = 8
        nt.links.new(v, noise.inputs["Vector"])
        base = _ramp(nt, noise.outputs["Fac"], [(0.0, "a7a3b5"), (0.45, "b8b4c4"), (0.62, "c9c5d3")])
        return _mix(nt, brick.outputs["Fac"], base, C.rgb("6f6a80"))

    def clay(nt):
        v = _coords(nt, 1.0)
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 0.03
        noise.inputs["Detail"].default_value = 6
        nt.links.new(v, noise.inputs["Vector"])
        drag = nt.nodes.new("ShaderNodeTexWave")
        drag.bands_direction = "Y"
        drag.inputs["Scale"].default_value = 0.012
        drag.inputs["Distortion"].default_value = 1.5
        nt.links.new(v, drag.inputs["Vector"])
        a = _ramp(nt, noise.outputs["Fac"], [(0.0, "d9653b"), (0.5, "e2734a"), (0.66, "ea8558")])
        return _mix(nt, drag.outputs["Fac"], a, C.rgb("d35f36"))

    def wood(nt):
        v = _coords(nt, 1.0)
        planks = nt.nodes.new("ShaderNodeTexBrick")
        planks.inputs["Scale"].default_value = 0.012
        planks.inputs["Brick Width"].default_value = 4.0
        planks.inputs["Row Height"].default_value = 0.4
        planks.inputs["Mortar Size"].default_value = 0.01
        planks.inputs["Color1"].default_value = C.rgb("e3a154")
        planks.inputs["Color2"].default_value = C.rgb("d39043")
        planks.inputs["Mortar"].default_value = C.rgb("9c5d22")
        nt.links.new(v, planks.inputs["Vector"])
        grain = nt.nodes.new("ShaderNodeTexWave")
        grain.bands_direction = "X"
        grain.inputs["Scale"].default_value = 0.05
        grain.inputs["Distortion"].default_value = 4
        nt.links.new(v, grain.inputs["Vector"])
        return _mix(nt, grain.outputs["Fac"], planks.outputs["Color"], C.rgb("c98a40"))

    builders = {"sand": sand, "grass": grass, "tiles": tiles, "concrete": concrete,
                "clay": clay, "wood": wood}
    return C.toon_textured(f"floor_{kind}", builders[kind], shade=0.7)


# --- Shared court furniture --------------------------------------------------

def court_lines(hw, hh, color="ffffff", width=5):
    mat = C.flat(color, 0.95, name=f"line_{color}")
    z = 0.4
    for x in (-hw + 110, hw - 110):
        C.plane("svc", (width, hh * 2 - 20), (x, 0, z), mat)
    C.plane("mid", (hw * 2 - 20, width * 0.8), (0, 0, z), mat)
    for y in (-hh + 6, hh - 6):
        C.plane("edge", (hw * 2 - 12, width), (0, y, z), mat)
    for x in (-hw + 6, hw - 6):
        C.plane("edge", (width, hh * 2 - 12), (x, 0, z), mat)


def net(hh):
    yellow = C.toon(C.SUNSET_YELLOW, 0.75)
    post = C.toon("f4f1ff", 0.7)
    C.cylinder("net", 3.2, hh * 2, (0, 0, 5), yellow, rot=(math.pi / 2, 0, 0), verts=12, ink=1.2)
    for y in (-hh - 8, hh + 8):
        C.cylinder("net_post", 7, 46, (0, y, 23), post, verts=16, ink=2.0)
        C.sphere("net_cap", 8.5, (0, y, 48), C.toon(C.NEON_PINK, 0.7, emission=0.6), ink=2.0)


def goal_walls(hw, hh, panel_color, frame_color):
    """Outward-leaning goal panels. The game paints the zone lights on them."""
    panel = C.toon(panel_color, 0.7)
    frame = C.toon(frame_color, 0.65)
    neon = C.toon(C.NEON_CYAN, 0.9, emission=1.5)
    for side in (-1, 1):
        x0 = side * hw
        # Panel face: a slab leaning outward at 45 degrees from the goal line.
        length = PANEL * math.sqrt(2)
        cx = x0 + side * PANEL / 2
        C.box("goal_panel", (length, hh * 2 + 20, 6), (cx + side * 3, 0, PANEL / 2 - 2),
              panel, rot=(0, -side * math.pi / 4, 0), ink=2.0)
        # Frame rails along the top edge and posts at the corners.
        C.box("goal_rail", (12, hh * 2 + 40, 12), (x0 + side * (PANEL + 6), 0, PANEL + 4), frame)
        C.box("goal_lip", (8, hh * 2 + 20, 8), (x0 + side * 2, 0, 3), frame, ink=1.5)
        C.cylinder("goal_neon", 2.6, hh * 2 + 30, (x0 + side * (PANEL + 6), 0, PANEL + 13), neon,
                   rot=(math.pi / 2, 0, 0), verts=10, ink=1.0)
        for y in (-hh - 16, hh + 16):
            C.box("goal_post", (22, 22, PANEL + 70), (x0 + side * (PANEL / 2 + 4), y, (PANEL + 70) / 2), frame)
            C.sphere("goal_post_light", 9, (x0 + side * (PANEL / 2 + 4), y, PANEL + 80),
                     C.toon(C.NEON_PINK, 0.8, emission=1.2), ink=2.0)


def back_wall(hw, hh, wall_color, trim_color, ads):
    """The far (top) wall with advertising boards and a fence above it."""
    wall = C.toon(wall_color, 0.7)
    trim = C.toon(trim_color, 0.65)
    fence = C.toon("d7d3e3", 0.65)
    y = hh + 14
    C.box("back_wall", (hw * 2 + 40, 16, WALL_H), (0, y, WALL_H / 2), wall)
    C.box("back_trim", (hw * 2 + 44, 20, 8), (0, y, WALL_H + 2), trim)
    # Ad boards on the wall's court-facing side.
    n = len(ads)
    board_w = (hw * 2 - 40) / n
    for i, (label, bg, fg) in enumerate(ads):
        x = -hw + 20 + board_w * (i + 0.5)
        C.box("ad", (board_w - 14, 4, WALL_H - 22), (x, y - 10, WALL_H / 2 + 1), C.toon(bg, 0.85), ink=1.6)
        C.text(label, 34, (x, y - 12.6, WALL_H / 2 - 2), C.flat(fg, 1.0),
               rot=(math.pi / 2, 0, 0), font="Bangers-Regular.ttf")
    # Chain-link fence above the wall.
    posts = int((hw * 2) // 120) + 1
    for i in range(posts + 1):
        x = -hw - 10 + i * (hw * 2 + 20) / posts
        C.cylinder("fence_post", 3.5, 70, (x, y + 4, WALL_H + 35), fence, verts=10, ink=1.4)
    C.cylinder("fence_rail", 3, hw * 2 + 30, (0, y + 4, WALL_H + 68), fence, rot=(0, math.pi / 2, 0), verts=10, ink=1.4)


def front_rail(hw, hh, color):
    rail = C.toon(color, 0.65)
    y = -hh - 12
    C.box("front_rail", (hw * 2 + 40, 10, 16), (0, y, 8), rail, ink=1.8)
    for i in range(0, 13):
        x = -hw - 10 + i * (hw * 2 + 20) / 12
        C.box("front_post", (10, 10, 26), (x, y, 13), rail, ink=1.6)


def floor_logo(hw, hh, color, size=70):
    for x, rot in ((-hw / 2, 0.0), (hw / 2, math.pi)):
        C.text("HYPERDISC", size, (x, hh * 0.62 * (1 if rot == 0 else -1), 0.6),
               C.flat(color, 0.9, name=f"logo_{color}"), rot=(0, 0, rot), font="Bangers-Regular.ttf")


# --- Scenery -------------------------------------------------------------------

def palm(x, y, height, rng, scale=1.0):
    trunk = C.toon("a9743f", 0.62)
    leaf = C.toon("2fbf71", 0.6)
    leaf_dark = C.toon("1f9c5a", 0.6)
    segs = 7
    lean = rng.uniform(-0.25, 0.25)
    top = (x, y, 0)
    for i in range(segs):
        z = (i + 0.5) * height / segs
        px = x + lean * z * 0.35
        C.cylinder("trunk", (9 - i * 0.6) * scale, height / segs + 2, (px, y, z), trunk, verts=10, ink=1.8)
        top = (px, y, height)
    for i in range(8):
        a = i * math.tau / 8 + rng.uniform(-0.2, 0.2)
        length = rng.uniform(70, 95) * scale
        bpy.ops.mesh.primitive_cone_add(radius1=13 * scale, radius2=1, depth=length, vertices=6)
        ob = bpy.context.active_object
        ob.scale = (1, 0.35, 1)
        droop = rng.uniform(0.9, 1.35)
        ob.rotation_euler = (0, math.pi / 2 + droop * 0.6, a)
        ob.location = (top[0] + math.cos(a) * length * 0.42, top[1] + math.sin(a) * length * 0.42,
                       top[2] - length * 0.18)
        C.assign(ob, leaf if i % 2 else leaf_dark)
        C.outline(ob, 1.8)
    C.sphere("coconuts", 9 * scale, (top[0], top[1], top[2] - 6), C.toon("6b4226", 0.6), ink=1.6)


def umbrella(x, y, rng):
    a, b = rng.choice([(C.NEON_PINK, "ffffff"), (C.NEON_CYAN, "ffffff"), (C.SUNSET_YELLOW, C.NEON_PINK),
                       ("7b2cbf", C.NEON_CYAN)])
    C.cylinder("pole", 2.5, 70, (x, y, 35), C.toon("eeeeee", 0.7), verts=8, ink=1.2)
    bpy.ops.mesh.primitive_cone_add(radius1=50, radius2=0, depth=20, vertices=10, location=(x, y, 74))
    ob = bpy.context.active_object
    ob.data.materials.append(C.toon(a, 0.72))
    ob.data.materials.append(C.toon(b, 0.72))
    # Alternate the canopy wedges between the two colours.
    for i, poly in enumerate(ob.data.polygons):
        poly.material_index = i % 2
    C.outline(ob, 2.0)


def towel(x, y, rng):
    a, b = rng.choice([(C.NEON_PINK, "ffffff"), (C.NEON_CYAN, C.SUNSET_YELLOW), ("7b2cbf", C.NEON_CYAN)])
    for i in range(4):
        C.box("towel", (60, 9, 1.5), (x, y - 13 + i * 9, 0.8), C.toon(a if i % 2 else b, 0.75), ink=0.8)


def surfboard(x, y, color, rng):
    C.sphere("board", 14, (x, y, 40), C.toon(color, 0.7), scale=(1, 0.28, 3.0), ink=1.8)


def lifeguard_tower(x, y):
    wood = C.toon("f4f1ff", 0.7)
    red = C.toon("ff2e63", 0.7)
    for dx in (-22, 22):
        for dy in (-18, 18):
            C.cylinder("leg", 3, 80, (x + dx, y + dy, 40), wood, verts=8, ink=1.4)
    C.box("deck", (64, 52, 6), (x, y, 82), wood)
    C.box("hut", (54, 44, 42), (x, y + 2, 106), red)
    C.box("roof", (66, 56, 6), (x, y + 2, 130), wood)
    C.text("LIFEGUARD", 9, (x, y - 21, 108), C.flat("ffffff"), rot=(math.pi / 2, 0, 0), font="Bangers-Regular.ttf")


def hedge(x, y, w, d, h):
    C.box("hedge", (w, d, h), (x, y, h / 2), C.toon("2e9e4f", 0.6), bevel=8)


def tree(x, y, rng, s=1.0):
    C.cylinder("tree_trunk", 7 * s, 60 * s, (x, y, 30 * s), C.toon("8a5a2b", 0.6), verts=10, ink=1.8)
    for i in range(3):
        C.sphere("canopy", rng.uniform(32, 42) * s,
                 (x + rng.uniform(-18, 18) * s, y + rng.uniform(-12, 12) * s, (70 + i * 10) * s),
                 C.toon(rng.choice(["3fbf5a", "35a84f", "4ccf66"]), 0.6), ink=2.0)


def planter(x, y, flower):
    C.cylinder("pot", 16, 26, (x, y, 13), C.toon("c65a2e", 0.65), verts=14, ink=1.8)
    C.sphere("bush", 18, (x, y, 32), C.toon("37a85a", 0.6), ink=1.8)
    for i in range(5):
        a = i * math.tau / 5
        C.sphere("flower", 4.5, (x + math.cos(a) * 11, y + math.sin(a) * 11, 42), C.toon(flower, 0.7), ink=1.0)


def crate(x, y, s, color):
    C.box("crate", (s, s, s), (x, y, s / 2), C.toon(color, 0.62), bevel=1.5)


def barrel(x, y, color):
    C.cylinder("barrel", 18, 46, (x, y, 23), C.toon(color, 0.62), verts=16)
    C.cylinder("barrel_ring", 18.5, 4, (x, y, 36), C.toon("333344", 0.6), verts=16, ink=1.0)


def neon_sign(x, y, z, label, color, size=36, rot=(math.pi / 2, 0, 0)):
    C.box("sign_back", (len(label) * size * 0.62 + 30, 6, size + 22), (x, y + 4, z), C.toon("241a3a", 0.8), ink=2.0)
    C.text(label, size, (x, y, z - size * 0.05), C.flat(color, 2.4), rot=rot, font="Bangers-Regular.ttf")


def deck_chair(x, y, color):
    C.box("chair_seat", (30, 60, 4), (x, y, 14), C.toon(color, 0.7), rot=(0.25, 0, 0), ink=1.4)
    C.box("chair_frame", (34, 64, 3), (x, y, 10), C.toon("f4f1ff", 0.7), rot=(0.25, 0, 0), ink=1.2)


def pool(x, y, w, d):
    edge = C.toon("f4f1ff", 0.75)
    C.box("pool_edge", (w + 24, d + 24, 6), (x, y, 1), edge, ink=1.6)
    water = C.toon_textured("water", lambda nt: _ramp(
        nt, _water_fac(nt), [(0.0, "1ec8e6"), (0.55, "4ddcf2"), (0.8, "b8f6ff")]), shade=0.85)
    C.plane("pool_water", (w, d), (x, y, 4.5), water)


def _water_fac(nt):
    v = _coords(nt, 1.0)
    wave = nt.nodes.new("ShaderNodeTexWave")
    wave.inputs["Scale"].default_value = 0.008
    wave.inputs["Distortion"].default_value = 5
    wave.inputs["Detail"].default_value = 2
    nt.links.new(v, wave.inputs["Vector"])
    return wave.outputs["Fac"]


def ocean(y0, depth, width):
    mat = C.toon_textured("ocean", lambda nt: _ramp(
        nt, _water_fac(nt), [(0.0, "0fb3d1"), (0.6, "1cc4de"), (0.9, "d9f9ff")]), shade=0.85)
    C.plane("wet_sand", (width, 40), (0, y0 - 10, 0.2), C.toon("d9ad6c", 0.8))
    C.plane("ocean", (width, depth), (0, y0 + depth / 2, 0.4), mat)
    C.plane("foam", (width, 7), (0, y0 + 3, 0.6), C.flat("ffffff", 1.0))


STAND_BASE = 34


def bleachers(x0, x1, y0, rows, step_d=44, step_h=30, color="5a3c8c"):
    mat = C.toon(color, 0.65)
    for r in range(rows):
        h = STAND_BASE + step_h * (r + 1)
        C.box("bleacher", (x1 - x0, step_d, h), ((x0 + x1) / 2, y0 + step_d * (r + 0.5), h / 2), mat, ink=2.0)


# --- Crowd ---------------------------------------------------------------------

CROWD_TAG = "crowd"


def spectator(x, y, z, rng, cheering):
    shirt = C.toon(rng.choice(PALETTE_CROWD), 0.62)
    skin = C.toon(rng.choice(SKIN), 0.68)
    hair = C.toon(rng.choice(["2b1b17", "f2d16b", "8b3a1e", "1a0f2e", "ff2e88", "e8e1d9"]), 0.6)
    s = rng.uniform(0.9, 1.1) * 1.4
    parts = []
    body = C.cylinder("body", 9 * s, 26 * s, (x, y, z + 13 * s), shirt, verts=10, ink=1.6)
    head = C.sphere("head", 7.5 * s, (x, y, z + 34 * s), skin, segs=12, ink=1.6)
    hair_ob = C.sphere("hair", 7.8 * s, (x, y + 1.5, z + 37 * s), hair, scale=(1, 1, 0.65), segs=12, ink=1.2)
    parts += [body, head, hair_ob]
    for side in (-1, 1):
        if cheering:
            arm = C.cylinder("arm", 2.6 * s, 20 * s, (x + side * 11 * s, y, z + 36 * s), skin,
                             rot=(0, side * 0.35, 0), verts=8, ink=1.2)
        else:
            arm = C.cylinder("arm", 2.6 * s, 18 * s, (x + side * 10.5 * s, y - 1, z + 14 * s), shirt,
                             rot=(0, -side * 0.2, 0), verts=8, ink=1.2)
        parts.append(arm)
    for p in parts:
        p[CROWD_TAG] = True
    return parts


def crowd_rows(x0, x1, y0, rows, step_d, step_h, seed, cheering, density=0.85):
    rng = C.seeded(seed)
    for r in range(rows):
        x = x0 + 18
        while x < x1 - 18:
            if rng.random() < density:
                jitter = rng.uniform(-3, 3)
                lift = (rng.uniform(5, 11) if cheering else 0)
                spectator(x + jitter, y0 + step_d * (r + 0.5), STAND_BASE + step_h * (r + 1) + lift, rng, cheering)
            x += rng.uniform(32, 42)


def crowd_cluster(x, y, count, seed, cheering, spread=60):
    """A loose group standing on the ground beside the court."""
    rng = C.seeded(seed)
    for i in range(count):
        lift = rng.uniform(5, 11) if cheering else 0
        spectator(x + rng.uniform(-spread, spread), y + rng.uniform(-spread, spread) * 0.6, lift, rng, cheering)


# --- Courts --------------------------------------------------------------------

def build_court(court, cheering):
    """Builds one court. Crowd members are tagged so they can be isolated."""
    C.reset()
    scene = bpy.context.scene
    C.court_camera(scene)
    hw = court["width"] / 2
    hh = court["height"] / 2
    cid = court["id"]
    rng = C.seeded(hash(cid) & 0xffff)
    C.sun("sun", 3.2, (48, -28, -35))

    floor_kind = {"beach": "sand", "lawn": "grass", "tiled": "tiles", "concrete": "concrete",
                  "clay": "clay", "stadium": "wood"}[cid]
    C.plane("floor", (hw * 2, hh * 2), (0, 0, 0), floor_material(floor_kind))
    line_color = {"beach": "ffffff", "lawn": "ffffff", "tiled": "ffffff", "concrete": "ffd23f",
                  "clay": "ffffff", "stadium": "ffffff"}[cid]
    court_lines(hw, hh, line_color)
    net(hh)

    ads_sets = [
        ("RAD COLA", "ff2e88", "ffffff"), ("NEON NIGHTS", "1a0f2e", "2de2e6"),
        ("MAGNUM SPF 80", "ffd23f", "1a0f2e"), ("TUBULAR TOWELS", "2de2e6", "1a0f2e"),
        ("PLAYBOUND", "7b2cbf", "ffffff"), ("SYNTH FM 88.8", "ff8c42", "1a0f2e"),
    ]
    rng_ads = C.seeded(len(cid) * 7 + court["width"])
    rng_ads.shuffle(ads_sets)
    ads = ads_sets[:4] if hw < 600 else ads_sets[:5]

    # Ground beyond the court, by theme.
    ground = {"beach": "f0c987", "lawn": "4aa84a", "tiled": "f4f1ff", "concrete": "8f8a9e",
              "clay": "f3e6d0", "stadium": "2a1f45"}[cid]
    C.plane("ground", (3400, 2400), (0, 0, -0.6), C.toon(ground, 0.75))

    panel_color, frame_color, wall_color, trim_color, rail_color = {
        "beach": ("2a1f6e", "f4f1ff", "ff2e88", "ffd23f", "f4f1ff"),
        "lawn": ("1e4d3a", "f4f1ff", "2a6f4a", "ffd23f", "f4f1ff"),
        "tiled": ("1a2b6e", "ff8fc7", "1ec8e6", "ff2e88", "ff8fc7"),
        "concrete": ("2b2b3a", "ffd23f", "4a4a5e", "ffd23f", "ffd23f"),
        "clay": ("6e2a1a", "f4f1ff", "f4f1ff", "2a6f4a", "f4f1ff"),
        "stadium": ("1a1a5e", "c0c4d6", "1a1a5e", "ff2e88", "c0c4d6"),
    }[cid]
    goal_walls(hw, hh, panel_color, frame_color)
    back_wall(hw, hh, wall_color, trim_color, ads)
    front_rail(hw, hh, rail_color)
    if cid in ("tiled", "stadium", "concrete"):
        floor_logo(hw, hh, {"tiled": "ffffff", "stadium": "ff2e88", "concrete": "ff2e88"}[cid])

    top = hh + 30  # first row of the stands, behind the back wall
    sides = hw + PANEL + 40

    if cid == "beach":
        bleachers(-hw + 40, hw - 40, top, 3)
        crowd_rows(-hw + 40, hw - 40, top, 3, 44, 30, 11, cheering)
        crowd_cluster(-hw - 150, hh + 20, 7, 12, cheering)
        crowd_cluster(hw + 150, hh - 10, 6, 13, cheering)
        ocean(top + 120, 400, 3400)
        for x in (-hw - 120, hw + 120):
            palm(x, top + 40, 190, rng)
        for x, y in ((-hw - 150, -60), (hw + 150, 40), (-hw - 130, -hh - 60), (hw + 160, -hh - 40)):
            palm(x, y, 170, rng, 0.9)
        towel(-hw + 120, -hh - 95, rng)
        towel(hw - 160, -hh - 110, rng)
        umbrella(-hw + 220, -hh - 120, rng)
        umbrella(hw - 300, -hh - 120, rng)
        surfboard(sides + 30, hh - 60, C.NEON_PINK, rng)
        surfboard(sides + 60, hh - 90, C.NEON_CYAN, rng)
        lifeguard_tower(-sides - 40, -hh + 60)
        neon_sign(-sides - 50, -hh * 0.35, 40, "SURF'S UP", C.NEON_CYAN, 28)
    elif cid == "lawn":
        bleachers(-hw + 40, hw - 40, top, 3, color="f4f1ff")
        crowd_rows(-hw + 40, hw - 40, top, 3, 44, 30, 21, cheering)
        crowd_cluster(hw + 150, -hh + 80, 6, 22, cheering)
        hedge(0, top + 150, hw * 2 + 300, 40, 60)
        for x in (-hw - 140, hw + 140, -hw - 150, hw + 150):
            tree(x, rng.uniform(-hh, hh), rng)
        for x in range(-int(hw), int(hw) + 1, 160):
            planter(x, -hh - 90, rng.choice(["ff2e88", "ffd23f", "ffffff"]))
        neon_sign(-hw * 0.5, top + 150, 72, "GARDEN PARTY", C.NEON_PINK)
    elif cid == "tiled":
        bleachers(-hw + 40, hw - 40, top, 2, color="ff8fc7")
        crowd_rows(-hw + 40, hw - 40, top, 2, 44, 30, 31, cheering)
        crowd_cluster(-hw - 150, hh - 40, 6, 32, cheering)
        pool(0, top + 170, hw * 2 + 200, 120)
        for x in (-hw - 140, hw + 140):
            palm(x, top + 20, 180, rng)
            deck_chair(x, -hh + 40, C.NEON_PINK)
            deck_chair(x + 30 * (1 if x > 0 else -1), -hh + 120, C.NEON_CYAN)
        for x in (-hw * 0.6, hw * 0.6):
            deck_chair(x, -hh - 110, C.SUNSET_YELLOW)
        neon_sign(0, top + 260, 70, "POOL CLUB", C.NEON_PINK)
    elif cid == "concrete":
        C.box("rooftop_wall", (hw * 2 + 400, 30, 120), (0, top + 160, 60), C.toon("514a66", 0.6))
        bleachers(-hw + 60, hw - 60, top, 2, color="3a3a4e")
        crowd_rows(-hw + 60, hw - 60, top, 2, 44, 30, 41, cheering, 0.7)
        crowd_cluster(-hw - 150, -hh + 120, 6, 42, cheering)
        for x, y, s in ((-hw - 120, 60, 50), (-hw - 150, 10, 40), (hw + 130, -60, 56), (hw + 110, hh - 40, 44)):
            crate(x, y, s, "b07a3a")
        for x, y in ((-hw - 110, -hh + 40), (hw + 130, -hh + 80), (-hw - 140, hh - 20)):
            barrel(x, y, rng.choice(["ff2e63", "2de2e6", "ffd23f"]))
        neon_sign(-hw * 0.45, top + 140, 80, "NIGHT DISC", C.NEON_PINK)
        neon_sign(hw * 0.45, top + 140, 80, "NO SKATING", C.NEON_CYAN)
    elif cid == "clay":
        C.box("stucco", (hw * 2 + 600, 30, 110), (0, top + 140, 55), C.toon("f4ead8", 0.7))
        for x in range(-int(hw) - 100, int(hw) + 101, 180):
            C.box("arch", (90, 32, 70), (x, top + 130, 35), C.toon("c65a2e", 0.6), ink=1.6)
        bleachers(-hw + 40, hw - 40, top, 2, color="f4f1ff")
        crowd_rows(-hw + 40, hw - 40, top, 2, 44, 30, 51, cheering)
        for x in (-hw - 120, hw + 120):
            tree(x, hh * 0.4, rng, 0.9)
            tree(x, -hh * 0.5, rng, 0.9)
        for x in range(-int(hw), int(hw) + 1, 220):
            planter(x, -hh - 90, rng.choice(["ff2e88", "ffd23f"]))
        neon_sign(0, top + 150, 80, "CLUB DEL SOL", C.SUNSET_ORANGE)
    elif cid == "stadium":
        bleachers(-hw - 200, hw + 200, top, 4, step_d=40, step_h=28, color="3d2a6e")
        crowd_rows(-hw - 200, hw + 200, top, 4, 40, 28, 61, cheering, 0.92)
        for side in (-1, 1):
            C.box("side_stand", (200, hh * 2 + 120, 40), (side * (sides + 110), 0, 20), C.toon("3d2a6e", 0.6))
        for x in (-hw * 0.6, 0, hw * 0.6):
            C.box("screen", (220, 10, 90), (x, top + 210, 150), C.toon("111122", 0.8))
            C.text("WORLD DISC CHAMPIONSHIP" if x == 0 else "HYPERDISC", 18, (x, top + 204, 150),
                   C.flat(C.NEON_CYAN if x == 0 else C.NEON_PINK, 2.2), rot=(math.pi / 2, 0, 0),
                   font="Bangers-Regular.ttf")
        C.plane("arena_glow", (hw * 2 + 300, hh * 2 + 300), (0, 0, -0.4), C.toon("3a2560", 0.8))

    # Referee chair at the bottom of the net (the game draws the referee).
    chair = C.toon("f4f1ff", 0.7)
    for dx in (-14, 14):
        C.cylinder("chair_leg", 2.5, 44, (dx, -hh - 34, 22), chair, verts=8, ink=1.2)
    C.box("chair_seat", (40, 30, 6), (0, -hh - 34, 46), C.toon(C.NEON_PINK, 0.7))
    C.box("disc_rack", (30, 20, 26), (40, -hh - 40, 13), C.toon("2de2e6", 0.65))
    return scene


def set_holdout(exclude_tag):
    """Turns every object except tagged ones into a holdout (cuts alpha but
    still hides what is behind it)."""
    hold = bpy.data.materials.new("holdout")
    hold.use_nodes = True
    nt = hold.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    h = nt.nodes.new("ShaderNodeHoldout")
    nt.links.new(h.outputs[0], out.inputs[0])
    for ob in bpy.data.objects:
        if ob.type not in ("MESH", "FONT") or ob.get(exclude_tag):
            continue
        if ob.type == "FONT":
            ob.data.materials.clear()
            ob.data.materials.append(hold)
            continue
        for i in range(len(ob.data.materials)):
            ob.data.materials[i] = hold


def render_court(court):
    cid = court["id"]
    build_court(court, cheering=False)
    for ob in bpy.data.objects:
        if ob.get(CROWD_TAG):
            ob.hide_render = True
    C.render(os.path.join(OUT, f"{cid}.webp"), transparent=False)
    for ob in bpy.data.objects:
        ob.hide_render = False
    set_holdout(CROWD_TAG)
    C.render(os.path.join(OUT, f"{cid}_crowd_a.webp"))
    build_court(court, cheering=True)
    set_holdout(CROWD_TAG)
    C.render(os.path.join(OUT, f"{cid}_crowd_b.webp"))


if __name__ == "__main__":
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for court in C.BALANCE["courts"]:
        if wanted and court["id"] not in wanted:
            continue
        render_court(court)
        print("rendered", court["id"])
