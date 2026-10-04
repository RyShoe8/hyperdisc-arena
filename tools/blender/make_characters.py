"""Render character sprite sheets and portraits.

Run from the repo root:
    blender -b --factory-startup -P tools/blender/make_characters.py [-- character_id ...]

Each character is built procedurally: a skeleton posed with forward
kinematics, a skin-modifier body, then clothes, hair and face as separate
pieces. Every animation frame is rebuilt from its pose and rendered with
cel shading and ink outlines from a three-quarter camera, facing right (the
game mirrors sprites for the right-hand player).

Outputs under assets/art/characters/:
    <id>.webp        sprite sheet, frames in a grid
    <id>.json        frame size, anchor (the ground point under the hips),
                     hand and head positions per frame, and the animations
    <id>_portrait.webp head-and-shoulders portrait for menus and the HUD
    <id>_select.webp   full-body pose for the character select screen
"""

import json
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402

OUT = os.path.join(C.ROOT, "assets", "art", "characters")
FRAME = 320           # square frame size in pixels
ORTHO = 236.0         # world units across a frame
CAM_PITCH = 35.0      # degrees below horizontal
YAW = -32.0           # turn the body toward the camera (three-quarter view)
COLUMNS = 8
HEAD_SCALE = 1.25     # stylised big heads, scaled about the head centre


# --- Character designs -----------------------------------------------------
# Build: h = overall height scale, sw = shoulder width, hw = hip width,
# chest/belly = torso radii, arm/leg = limb thickness multipliers.

DESIGNS = {
    "mick": {
        "build": {"h": 1.0, "sw": 40, "hw": 22, "chest": 15, "belly": 12, "arm": 1.0, "leg": 1.0},
        "skin": "e8b48a", "top": "f4f1ff", "top_sleeve": False, "top_accent": "ff2e63",
        "bottom": "1f3a8a", "shoe": "f4f1ff", "shoe_accent": "ff2e88", "sock": "f4f1ff",
        "hair": ("mullet", "6b3a16"), "face": "aviators", "extras": ["headband:ff2e63", "dogtags"],
    },
    "tiffany": {
        "build": {"h": 0.95, "sw": 34, "hw": 22, "chest": 12.5, "belly": 10.5, "arm": 0.85, "leg": 0.9},
        "skin": "f1c8a0", "top": "ff2e3f", "top_sleeve": False, "top_accent": "ffffff",
        "bottom": "ff2e3f", "shoe": "f4f1ff", "shoe_accent": "2de2e6", "sock": "f4f1ff",
        "hair": ("ponytail", "ffd96a"), "face": "eyes", "extras": ["visor:f4f1ff", "whistle"],
    },
    "pete": {
        "build": {"h": 1.04, "sw": 46, "hw": 28, "chest": 19, "belly": 19, "arm": 1.25, "leg": 1.2},
        "skin": "c68642", "top": "2de2e6", "top_sleeve": True, "top_accent": "ff2e88",
        "bottom": "f4f1ff", "shoe": "ffd23f", "shoe_accent": "1a0f2e", "sock": "f4f1ff",
        "hair": ("curly", "1a0f2e"), "face": "shades", "extras": ["bucket_hat:ffd23f"],
    },
    "speed_b": {
        "build": {"h": 0.97, "sw": 35, "hw": 21, "chest": 12.5, "belly": 10.5, "arm": 0.85, "leg": 0.88},
        "skin": "f1d0b5", "top": "1a0f2e", "top_sleeve": False, "top_accent": "ff2e88",
        "bottom": "3b6fb6", "shoe": "1a0f2e", "shoe_accent": "ff2e88", "sock": "1a0f2e",
        "hair": ("mohawk", "ff2e88"), "face": "eyes", "extras": ["kneepads:1a0f2e"],
    },
    "balanced_b": {
        "build": {"h": 1.0, "sw": 40, "hw": 23, "chest": 15, "belly": 12.5, "arm": 1.0, "leg": 1.0},
        "skin": "d9a47a", "top": "7b2cbf", "top_sleeve": False, "top_accent": "5b7fbf",
        "bottom": "1a0f2e", "shoe": "f4f1ff", "shoe_accent": "7b2cbf", "sock": "f4f1ff",
        "hair": ("slick", "1a0f2e"), "face": "eyes", "extras": ["vest:5b7fbf"],
    },
    "power_b": {
        "build": {"h": 1.08, "sw": 50, "hw": 30, "chest": 21, "belly": 20, "arm": 1.4, "leg": 1.3},
        "skin": "a86b45", "top": "1a0f2e", "top_sleeve": False, "top_accent": "ff2e63",
        "bottom": "3a3a4e", "shoe": "1a0f2e", "shoe_accent": "ff2e63", "sock": "f4f1ff",
        "hair": ("bald_beard", "3b2412"), "face": "eyes", "extras": ["bandana:ff2e63"],
    },
}


# The referee who stands at the net: only needs a few animations.
REFEREE = {
    "build": {"h": 0.98, "sw": 40, "hw": 24, "chest": 16, "belly": 16, "arm": 1.05, "leg": 1.05},
    "skin": "d9a47a", "top": "f4f1ff", "top_sleeve": True, "top_accent": "1a0f2e",
    "bottom": "1a0f2e", "shoe": "1a0f2e", "shoe_accent": "f4f1ff", "sock": "f4f1ff",
    "hair": ("slick", "8a8a9a"), "face": "shades", "extras": ["whistle", "stripes"],
}
REFEREE_ANIMS = ("idle", "lob", "win")


# --- Poses -----------------------------------------------------------------
# A pose is a dict of angles in degrees. Arms/legs are (swing, raise, bend):
# swing is forward(+)/back(-), raise is out to the side, bend is the elbow
# (forearm forward) or knee (shin back). lean tilts the chest forward, twist
# turns the chest (+ toward the net), dz lifts the hips. "air" poses keep
# their height instead of being planted on the ground.

def pose(**kw):
    p = {"lean": 10, "lean_hips": 0, "twist": 0, "head": 0, "head_turn": 0, "dz": 0,
         "arm_l": (25, 20, 50), "arm_r": (25, 20, 50),
         "leg_l": (12, 8, 24), "leg_r": (-6, 8, 24), "air": False, "disc": False}
    p.update(kw)
    return p


def anim_idle():
    frames = []
    for i in range(4):
        b = math.sin(i / 4 * math.tau)
        frames.append(pose(lean=12 + b * 1.5, arm_l=(30 + b * 4, 24, 55), arm_r=(30 - b * 4, 24, 55),
                           leg_l=(12, 9, 26 + b * 4), leg_r=(-6, 9, 26 + b * 4)))
    return frames


def anim_run():
    frames = []
    for i in range(8):
        ph = i / 8 * math.tau
        s = math.sin(ph)
        c = math.cos(ph)
        frames.append(pose(lean=18, twist=-s * 8,
                           leg_l=(38 * s, 6, 22 + 58 * max(0.0, -c)),
                           leg_r=(-38 * s, 6, 22 + 58 * max(0.0, c)),
                           arm_l=(-34 * s, 14, 85), arm_r=(34 * s, 14, 85)))
    return frames


def anim_dash():
    return [
        pose(lean=45, arm_l=(110, 20, 20), arm_r=(120, 20, 15), leg_l=(30, 8, 60), leg_r=(-40, 8, 30)),
        pose(lean=78, dz=40, air=True, arm_l=(165, 18, 5), arm_r=(170, 18, 5),
             leg_l=(-25, 8, 15), leg_r=(-40, 8, 20), head=-30),
        pose(lean=82, dz=26, air=True, arm_l=(170, 22, 10), arm_r=(160, 22, 10),
             leg_l=(-30, 10, 30), leg_r=(-45, 10, 25), head=-35),
    ]


def anim_hold():
    return [
        pose(lean=6, twist=-24, arm_r=(-35, 34, 95), arm_l=(45, 26, 40), leg_l=(18, 10, 22),
             leg_r=(-14, 10, 26), disc=True),
        pose(lean=7, twist=-27, arm_r=(-38, 36, 98), arm_l=(48, 26, 42), leg_l=(18, 10, 26),
             leg_r=(-14, 10, 30), disc=True),
    ]


def anim_throw():
    return [
        pose(lean=4, twist=-48, arm_r=(-60, 62, 85), arm_l=(55, 30, 30), leg_l=(22, 10, 18),
             leg_r=(-18, 10, 30), disc=True),
        pose(lean=16, twist=22, arm_r=(75, 75, 10), arm_l=(-10, 30, 40), leg_l=(26, 10, 30),
             leg_r=(-22, 10, 18)),
        pose(lean=22, twist=44, arm_r=(55, 25, 35), arm_l=(-25, 28, 50), leg_l=(26, 10, 34),
             leg_r=(-16, 10, 22)),
        pose(lean=14, twist=18, arm_r=(35, 22, 50), arm_l=(15, 24, 50)),
    ]


def anim_lob():
    return [
        pose(lean=20, twist=-10, arm_r=(-35, 12, 10), arm_l=(30, 20, 40), leg_l=(18, 10, 45),
             leg_r=(-10, 10, 45), disc=True),
        pose(lean=8, twist=5, arm_r=(70, 10, 10), arm_l=(10, 22, 40), leg_l=(14, 10, 24), leg_r=(-8, 10, 20)),
        pose(lean=-2, twist=10, arm_r=(150, 12, 10), arm_l=(0, 22, 40), leg_l=(10, 10, 12), leg_r=(-6, 10, 12)),
        pose(lean=6, arm_r=(110, 16, 25), arm_l=(15, 22, 45)),
    ]


def anim_catch():
    return [
        pose(lean=4, arm_l=(75, 12, 70), arm_r=(80, 12, 70), leg_l=(16, 10, 34), leg_r=(-10, 10, 34)),
        pose(lean=-6, arm_l=(65, 16, 95), arm_r=(68, 16, 95), leg_l=(20, 10, 40), leg_r=(-14, 10, 30),
             disc=True),
        pose(lean=2, twist=-15, arm_r=(-20, 30, 90), arm_l=(40, 24, 45), disc=True),
    ]


def anim_block():
    return [
        pose(lean=0, arm_l=(105, 22, 120), arm_r=(110, 22, 120), leg_l=(14, 12, 30), leg_r=(-10, 12, 30)),
        pose(lean=-8, arm_l=(120, 26, 110), arm_r=(125, 26, 110), leg_l=(18, 12, 36), leg_r=(-14, 12, 32), head=10),
        pose(lean=4, arm_l=(70, 22, 70), arm_r=(75, 22, 70)),
    ]


def anim_slap():
    return [
        pose(lean=8, twist=40, arm_r=(40, 85, 70), arm_l=(30, 24, 50), leg_l=(20, 10, 30), leg_r=(-12, 10, 26)),
        pose(lean=14, twist=-34, arm_r=(70, 80, 10), arm_l=(10, 28, 50), leg_l=(24, 10, 32), leg_r=(-14, 10, 24)),
        pose(lean=12, twist=-20, arm_r=(40, 40, 40), arm_l=(20, 24, 50)),
    ]


def anim_jump():
    return [
        pose(lean=20, arm_l=(-30, 18, 30), arm_r=(-30, 18, 30), leg_l=(22, 10, 70), leg_r=(10, 10, 70)),
        pose(lean=6, air=True, dz=20, arm_l=(150, 20, 30), arm_r=(155, 20, 30), leg_l=(40, 10, 80),
             leg_r=(20, 10, 85)),
        pose(lean=-4, air=True, dz=24, arm_l=(170, 14, 10), arm_r=(172, 14, 10), leg_l=(15, 8, 40),
             leg_r=(-5, 8, 45), head=-25),
    ]


def anim_knock():
    return [
        pose(lean=-24, arm_l=(60, 40, 40), arm_r=(70, 40, 30), leg_l=(28, 12, 36), leg_r=(-6, 12, 20), head=15),
        pose(lean=-14, arm_l=(40, 50, 60), arm_r=(50, 50, 50), leg_l=(22, 12, 40), leg_r=(-10, 12, 30), head=8),
    ]


def anim_charge():
    frames = []
    for i in range(4):
        b = math.sin(i / 4 * math.tau)
        frames.append(pose(lean=4, head=-38, arm_l=(145 + b * 6, 34, 35), arm_r=(150 - b * 6, 34, 35),
                           leg_l=(14, 14, 36 + b * 4), leg_r=(-10, 14, 36 + b * 4)))
    return frames


def anim_special():
    return [
        pose(lean=10, twist=-85, arm_r=(-80, 80, 20), arm_l=(70, 40, 20), leg_l=(26, 12, 44),
             leg_r=(-20, 12, 30), disc=True, head_turn=40),
        pose(lean=4, twist=-40, arm_r=(-20, 95, 10), arm_l=(40, 50, 20), leg_l=(28, 12, 40),
             leg_r=(-22, 12, 26), disc=True, head_turn=20),
        pose(lean=24, twist=55, arm_r=(95, 85, 5), arm_l=(-30, 40, 30), leg_l=(32, 12, 36), leg_r=(-26, 12, 18)),
        pose(lean=26, twist=60, arm_r=(70, 40, 20), arm_l=(-35, 30, 45), leg_l=(32, 12, 40), leg_r=(-22, 12, 20)),
    ]


def anim_win():
    return [
        pose(lean=-4, twist=10, arm_r=(170, 15, 40), arm_l=(20, 26, 80), leg_l=(10, 10, 14), leg_r=(-4, 10, 12),
             head=-15),
        pose(lean=-6, twist=12, arm_r=(175, 10, 15), arm_l=(15, 26, 90), leg_l=(10, 10, 10), leg_r=(-4, 10, 8),
             head=-20),
        pose(lean=-4, twist=10, arm_r=(170, 15, 40), arm_l=(20, 26, 80), leg_l=(10, 10, 14), leg_r=(-4, 10, 12),
             head=-15),
        pose(lean=0, twist=6, arm_r=(150, 20, 70), arm_l=(20, 26, 80), head=-10),
    ]


def anim_lose():
    return [
        pose(lean=38, head=35, arm_l=(8, 6, 10), arm_r=(6, 6, 10), leg_l=(6, 8, 14), leg_r=(-4, 8, 14)),
        pose(lean=42, head=40, arm_l=(10, 6, 14), arm_r=(8, 6, 14), leg_l=(6, 8, 18), leg_r=(-4, 8, 18)),
    ]


ANIMATIONS = [
    ("idle", anim_idle, 6, True), ("run", anim_run, 14, True), ("dash", anim_dash, 14, False),
    ("hold", anim_hold, 4, True), ("throw", anim_throw, 18, False), ("lob", anim_lob, 14, False),
    ("catch", anim_catch, 14, False), ("block", anim_block, 14, False), ("slap", anim_slap, 18, False),
    ("jump", anim_jump, 10, False), ("knock", anim_knock, 8, True), ("charge", anim_charge, 10, True),
    ("special", anim_special, 10, False), ("win", anim_win, 8, True), ("lose", anim_lose, 3, True),
]


# --- Skeleton --------------------------------------------------------------

def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, "X")


def rot_y(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 3, "Z")


DOWN = Vector((0, 0, -1))


def skeleton(design, p):
    """Joint positions (Vectors) for a pose, feet planted unless p['air']."""
    b = design["build"]
    h = b["h"]
    L = {"thigh": 46 * h, "shin": 44 * h, "torso": 50 * h, "neck": 9 * h, "upper": 31 * h,
         "fore": 29 * h, "foot": 15 * h}
    hip_h = L["thigh"] + L["shin"] + 6
    r_hips = rot_z(YAW) @ rot_y(p["lean_hips"])
    r_chest = r_hips @ rot_z(p["twist"]) @ rot_y(p["lean"])
    r_head = r_chest @ rot_y(p["head"]) @ rot_z(p["head_turn"])
    j = {}
    j["pelvis"] = Vector((0, 0, hip_h + p["dz"]))
    j["chest"] = j["pelvis"] + r_chest @ Vector((0, 0, L["torso"]))
    j["neck"] = j["chest"] + r_chest @ Vector((0, 0, L["neck"]))
    j["head"] = j["neck"] + r_head @ Vector((0, 0, 13 * h * HEAD_SCALE))
    j["r_head"] = r_head
    j["r_chest"] = r_chest
    for side, sign in (("l", 1), ("r", -1)):
        swing, raise_, bend = p["arm_" + side]
        sh = j["chest"] + r_chest @ Vector((0, sign * b["sw"] / 2, -4 * h))
        base = r_chest @ rot_x(sign * raise_) @ rot_y(-swing)
        el = sh + base @ DOWN * L["upper"]
        ha = el + (base @ rot_y(-bend)) @ DOWN * L["fore"]
        j["shoulder_" + side], j["elbow_" + side], j["hand_" + side] = sh, el, ha
        swing, raise_, bend = p["leg_" + side]
        hp = j["pelvis"] + r_hips @ Vector((0, sign * b["hw"] / 2, -5 * h))
        base = r_hips @ rot_x(sign * raise_) @ rot_y(-swing)
        kn = hp + base @ DOWN * L["thigh"]
        an = kn + (base @ rot_y(bend)) @ DOWN * L["shin"]
        toe = an + r_hips @ rot_z(sign * 8) @ Vector((L["foot"], 0, -1.5))
        j["hip_" + side], j["knee_" + side], j["ankle_" + side], j["toe_" + side] = hp, kn, an, toe
    if not p["air"]:
        lowest = min(j[k].z for k in ("ankle_l", "ankle_r", "toe_l", "toe_r"))
        shift = Vector((0, 0, 5.5 - lowest))
        for k in list(j):
            if isinstance(j[k], Vector):
                j[k] = j[k] + shift
    return j


# --- Body mesh -------------------------------------------------------------

def skin_mesh(name, points, edges, radii, mat, ink=2.6, levels=2, flatten=()):
    """A smooth tube mesh through `points` (Vectors) along `edges` (index
    pairs), with a radius per point, baked to a plain mesh and inked."""
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(p) for p in points], edges, [])
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    skin = ob.modifiers.new("skin", "SKIN")
    skin.use_smooth_shade = True
    for i, r in enumerate(radii):
        mesh.skin_vertices[0].data[i].radius = (r, r * (0.8 if i in flatten else 1.0))
    mesh.skin_vertices[0].data[0].use_root = True
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.levels = levels
    sub.render_levels = levels
    deps = bpy.context.evaluated_depsgraph_get()
    baked = bpy.data.meshes.new_from_object(ob.evaluated_get(deps))
    bpy.data.objects.remove(ob)
    out = bpy.data.objects.new(name, baked)
    bpy.context.collection.objects.link(out)
    baked.materials.append(mat)
    for poly in baked.polygons:
        poly.use_smooth = True
    if ink:
        C.outline(out, ink)
    return out


def body(design, j):
    """Bare body in skin colour, then clothes as slightly larger shells over
    it. Shells give clean inked hems where the clothes end."""
    b = design["build"]
    arm, leg = b["arm"], b["leg"]
    names = ["pelvis", "chest", "neck", "shoulder_l", "elbow_l", "hand_l", "shoulder_r", "elbow_r",
             "hand_r", "hip_l", "knee_l", "ankle_l", "toe_l", "hip_r", "knee_r", "ankle_r", "toe_r"]
    radius = {"pelvis": b["belly"], "chest": b["chest"], "neck": 6.0, "shoulder_l": 7.8 * arm,
              "elbow_l": 5.6 * arm, "hand_l": 6.4 * arm, "shoulder_r": 7.8 * arm, "elbow_r": 5.6 * arm,
              "hand_r": 6.4 * arm, "hip_l": 10.0 * leg, "knee_l": 7.2 * leg, "ankle_l": 5.4 * leg,
              "toe_l": 7.0, "hip_r": 10.0 * leg, "knee_r": 7.2 * leg, "ankle_r": 5.4 * leg, "toe_r": 7.0}
    edges = [("pelvis", "chest"), ("chest", "neck"), ("chest", "shoulder_l"), ("shoulder_l", "elbow_l"),
             ("elbow_l", "hand_l"), ("chest", "shoulder_r"), ("shoulder_r", "elbow_r"), ("elbow_r", "hand_r"),
             ("pelvis", "hip_l"), ("hip_l", "knee_l"), ("knee_l", "ankle_l"), ("ankle_l", "toe_l"),
             ("pelvis", "hip_r"), ("hip_r", "knee_r"), ("knee_r", "ankle_r"), ("ankle_r", "toe_r")]
    skin_mesh("body", [j[n] for n in names], [(names.index(a), names.index(c)) for a, c in edges],
              [radius[n] for n in names], C.toon(design["skin"], 0.62), levels=2, flatten=(0, 1))

    def lerp(a, c, t):
        return j[a] + (j[c] - j[a]) * t

    grow = 1.22  # clothes must clear the body and its ink hull everywhere
    top = C.toon(design["top"], 0.62)
    # Shirt: waist to collar, plus sleeves or narrow tank-top straps.
    sleeve_t = 0.55 if design["top_sleeve"] else 0.12
    pts = [lerp("pelvis", "chest", -0.04), j["chest"], lerp("chest", "neck", 0.3),
           j["shoulder_l"], lerp("shoulder_l", "elbow_l", sleeve_t),
           j["shoulder_r"], lerp("shoulder_r", "elbow_r", sleeve_t)]
    rad = [b["belly"] * grow + 3.4, b["chest"] * grow + 2.0, 8.0,
           7.8 * arm * grow + 1.5, 7.0 * arm * grow + 1.5 if design["top_sleeve"] else 5.0,
           7.8 * arm * grow + 1.5, 7.0 * arm * grow + 1.5 if design["top_sleeve"] else 5.0]
    if not design["top_sleeve"]:
        rad[3] = rad[5] = 8.6 * arm
    skin_mesh("shirt", pts, [(0, 1), (1, 2), (1, 3), (3, 4), (1, 5), (5, 6)], rad, top, flatten=(0, 1))
    # Shorts: waistband to mid-thigh.
    bottom = C.toon(design["bottom"], 0.62)
    pts = [lerp("pelvis", "chest", 0.3), j["pelvis"], j["hip_l"], lerp("hip_l", "knee_l", 0.48),
           j["hip_r"], lerp("hip_r", "knee_r", 0.48)]
    rad = [b["belly"] * grow + 2.4, b["belly"] * grow + 2.4, 10.0 * leg * grow + 1.5, 8.4 * leg * grow + 1.5,
           10.0 * leg * grow + 1.5, 8.4 * leg * grow + 1.5]
    skin_mesh("shorts", pts, [(0, 1), (1, 2), (2, 3), (1, 4), (4, 5)], rad, bottom, flatten=(0, 1))
    # Socks and sneakers.
    sock = C.toon(design["sock"], 0.66)
    shoe = C.toon(design["shoe"], 0.62)
    for side in ("l", "r"):
        skin_mesh("sock_" + side, [lerp("knee_" + side, "ankle_" + side, 0.72), j["ankle_" + side]],
                  [(0, 1)], [7.4 * leg, 7.2 * leg], sock, ink=1.8)
        heel = j["ankle_" + side] + (j["ankle_" + side] - j["toe_" + side]) * 0.25
        skin_mesh("shoe_" + side, [heel, j["ankle_" + side], j["toe_" + side]], [(0, 1), (1, 2)],
                  [7.6, 8.4, 8.6], shoe, ink=2.4)


def head(design, j):
    hd = j["head"]
    r = j["r_head"]
    skin = C.toon(design["skin"], 0.64)
    C.sphere("head", 12.5, tuple(hd), skin, scale=(1.0, 0.92, 1.1), segs=24, ink=2.6)
    fwd = r @ Vector((1, 0, 0))
    side = r @ Vector((0, 1, 0))
    up = r @ Vector((0, 0, 1))
    face = hd + fwd * 11.0
    C.sphere("nose", 2.6, tuple(face + fwd * 1.6 - up * 1.5), skin, segs=10, ink=1.4)
    for s in (-1, 1):
        C.sphere("ear", 3.0, tuple(hd + side * s * 12 + up * 0.5), skin, segs=10, ink=1.4)
    style = design["face"]
    ink_mat = C.flat(C.INK, name="face_ink")
    if style == "aviators":
        lens = C.toon("2b2b44", 0.8)
        for s in (-1, 1):
            C.sphere("lens", 4.2, tuple(face + side * s * 4.4 + up * 2.6), lens, scale=(0.5, 1.1, 0.85), segs=12, ink=1.2)
        C.box("bridge", (1.2, 9, 1.2), tuple(face + up * 3.6), C.toon("d4af37", 0.7), ink=0.6)
    elif style == "shades":
        C.box("shades", (3, 20, 5.5), tuple(face + up * 2.8), C.toon("1a0f2e", 0.8), ink=1.2)
    else:
        for s in (-1, 1):
            C.sphere("eye_white", 2.9, tuple(face + side * s * 4.6 + up * 2.4 - fwd * 0.4), C.flat("ffffff"),
                     scale=(0.45, 0.95, 1.25), segs=10, ink=0)
            C.sphere("eye", 1.9, tuple(face + side * s * 4.2 + up * 2.2 + fwd * 0.6), ink_mat,
                     scale=(0.5, 0.9, 1.3), segs=8, ink=0)
            C.box("brow", (1, 5.5, 1.2), tuple(face + side * s * 4.6 + up * 6.2), ink_mat, ink=0)
    C.box("mouth", (0.8, 4.5, 0.9), tuple(face - up * 5.5 - fwd * 0.9), ink_mat, ink=0)
    hair(design, hd, fwd, side, up)


def hair(design, hd, fwd, side, up):
    style, color = design["hair"]
    m = C.toon(color, 0.6)
    if style == "mullet":
        C.sphere("hair_top", 13.2, tuple(hd + up * 4.2 - fwd * 4.0), m, scale=(1.0, 1.02, 0.7), ink=2.4)
        C.sphere("hair_back", 10.5, tuple(hd - fwd * 8 - up * 6), m, scale=(0.75, 1.05, 1.3), ink=2.4)
        C.sphere("fringe", 5.5, tuple(hd + fwd * 6 + up * 10), m, scale=(0.9, 1.5, 0.55), ink=2.0)
    elif style == "ponytail":
        C.sphere("hair_top", 13.8, tuple(hd + up * 4 - fwd * 4), m, scale=(1.05, 1.08, 0.82), ink=2.4)
        C.sphere("bangs", 6.5, tuple(hd + fwd * 6.5 + up * 9), m, scale=(0.8, 1.9, 0.6), ink=2.0)
        C.sphere("tail", 7, tuple(hd - fwd * 15 + up * 4), m, scale=(1.4, 0.9, 0.9), ink=2.0)
        C.sphere("tail_end", 6, tuple(hd - fwd * 22 - up * 6), m, scale=(0.9, 0.8, 1.6), ink=2.0)
    elif style == "curly":
        for i in range(9):
            a = i / 9 * math.tau
            C.sphere("curl", 5.5, tuple(hd + up * 7 + fwd * math.cos(a) * 8 + side * math.sin(a) * 9), m, ink=1.8)
        C.sphere("curl_top", 9, tuple(hd + up * 10), m, ink=2.0)
    elif style == "mohawk":
        C.sphere("buzz", 13, tuple(hd + up * 1.5 - fwd * 1), C.toon("3b2412", 0.6), scale=(1.0, 1.0, 0.75), ink=2.0)
        for i in range(6):
            t = i / 5
            pos = hd + up * (13 + math.sin(t * math.pi) * 3) + fwd * (9 - t * 20)
            C.sphere("spike", 4.5, tuple(pos), m, scale=(1.0, 0.55, 2.2), ink=1.8)
    elif style == "slick":
        C.sphere("hair_top", 13.4, tuple(hd + up * 4 - fwd * 4), m, scale=(1.05, 1.0, 0.7), ink=2.4)
        C.sphere("quiff", 6, tuple(hd + fwd * 7 + up * 11), m, scale=(1.4, 1.5, 0.8), ink=2.0)
    elif style == "bald_beard":
        C.sphere("beard", 10, tuple(hd + fwd * 5 - up * 7), m, scale=(0.9, 1.1, 0.9), ink=2.2)
    for extra in design["extras"]:
        name, _, col = extra.partition(":")
        if name == "headband":
            C.cylinder("headband", 13.3, 3.4, tuple(hd + up * 5.5), C.toon(col, 0.65),
                       rot=_euler_from(up), verts=20, ink=1.6)
        elif name == "visor":
            C.cylinder("visor_band", 13.4, 3.0, tuple(hd + up * 5.5), C.toon(col, 0.65), rot=_euler_from(up),
                       verts=20, ink=1.4)
            C.sphere("visor_brim", 9, tuple(hd + fwd * 13 + up * 6), C.toon(col, 0.65), scale=(0.9, 1.2, 0.18), ink=1.6)
        elif name == "bucket_hat":
            hat = C.toon(col, 0.65)
            C.cylinder("hat_brim", 19, 2.5, tuple(hd + up * 9), hat, rot=_euler_from(up), verts=24, ink=1.8)
            C.sphere("hat_top", 12.5, tuple(hd + up * 12), hat, scale=(1, 1, 0.65), ink=2.0)
        elif name == "bandana":
            C.sphere("bandana", 13.2, tuple(hd + up * 3.5), C.toon(col, 0.65), scale=(1.0, 1.0, 0.7), ink=2.2)
            C.sphere("knot", 3.5, tuple(hd - fwd * 13 + up * 3), C.toon(col, 0.65), ink=1.4)


def _euler_from(up):
    return Vector((0, 0, 1)).rotation_difference(up).to_euler()


def extras_body(design, j):
    r = j["r_chest"]
    fwd = r @ Vector((1, 0, 0))
    up = r @ Vector((0, 0, 1))
    side = r @ Vector((0, 1, 0))
    chest = j["chest"]
    b = design["build"]
    accent = C.toon(design["top_accent"], 0.64)
    if "stripes" in design["extras"]:
        # Referee stripes down the shirt.
        for k in (-2, -1, 0, 1, 2):
            C.box("ref_stripe", (2.5, 3.2, 34), tuple(chest + fwd * (b["chest"] * 1.0) + side * (k * 7) - up * 12),
                  accent, rot=r.to_euler(), ink=0)
    elif design["top_sleeve"]:
        # Hawaiian shirt flowers.
        for k in range(5):
            off = side * ((k - 2) * 6) + up * (-6 - (k % 2) * 10)
            C.sphere("flower", 2.6, tuple(chest + fwd * (b["chest"] * 0.9) + off), accent, segs=8, ink=0.8)
    for extra in design["extras"]:
        name, _, col = extra.partition(":")
        if name == "whistle":
            C.sphere("whistle", 2.6, tuple(chest + fwd * (b["chest"] * 0.92) - up * 4), C.toon("ffd23f", 0.7),
                     segs=8, ink=1.0)
        elif name == "vest":
            vest = C.toon(col, 0.62)
            for s in (-1, 1):
                C.box("vest", (b["chest"] * 1.7, 8, 30), tuple(chest + side * s * (b["chest"] * 0.55) - up * 10),
                      vest, rot=r.to_euler(), ink=1.6)
        elif name == "kneepads":
            for s in ("l", "r"):
                C.sphere("pad", 6.8, tuple(j["knee_" + s] + fwd * 2), C.toon(col, 0.6), segs=12, ink=1.6)
    for s in ("l", "r"):
        # Sneaker accent swoosh and wristbands.
        C.sphere("shoe_accent", 3.0, tuple(j["ankle_" + s] + (j["toe_" + s] - j["ankle_" + s]) * 0.5 + Vector((0, 0, 1.5))),
                 C.toon(design["shoe_accent"], 0.65), scale=(1.4, 1.4, 0.6), segs=10, ink=0.8)
    if "headband" in " ".join(design["extras"]):
        for s in ("l", "r"):
            C.cylinder("wristband", 5.0, 4.5, tuple(j["hand_" + s] + (j["elbow_" + s] - j["hand_" + s]) * 0.18),
                       C.toon(design["top_accent"], 0.65),
                       rot=_euler_from((j["hand_" + s] - j["elbow_" + s]).normalized()), verts=12, ink=1.0)


def disc_in_hand(j):
    hand = j["hand_r"]
    C.cylinder("held_disc", 13, 3.2, tuple(hand + Vector((3, -4, 0))), C.toon("f4f1ff", 0.7),
               rot=(math.radians(70), 0, math.radians(YAW)), verts=24, ink=1.8)
    C.cylinder("held_disc_ring", 9, 3.6, tuple(hand + Vector((3, -4, 0))), C.toon(C.NEON_PINK, 0.7),
               rot=(math.radians(70), 0, math.radians(YAW)), verts=20, ink=0)


# --- Rendering -------------------------------------------------------------

def setup_camera(scene, size=FRAME, ortho=ORTHO, target_z=88.0, pitch=CAM_PITCH):
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    cam_data = bpy.data.cameras.new("char_cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ortho
    cam = bpy.data.objects.new("char_cam", cam_data)
    tilt = math.radians(90 - pitch)
    dist = 800
    cam.rotation_euler = (tilt, 0, 0)
    cam.location = (0, -dist * math.sin(tilt), target_z + dist * math.cos(tilt))
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    return cam


def to_pixel(scene, cam, point):
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(scene, cam, Vector(point))
    return [round(co.x * scene.render.resolution_x, 1), round((1 - co.y) * scene.render.resolution_y, 1)]


def clear_character():
    for ob in list(bpy.data.objects):
        if ob.type in ("MESH", "FONT"):
            bpy.data.objects.remove(ob, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def build(design, p):
    j = skeleton(design, p)
    body(design, j)
    before = set(bpy.data.objects)
    head(design, j)
    centre = j["head"]
    for ob in set(bpy.data.objects) - before:
        ob.location = centre + (ob.location - centre) * HEAD_SCALE
        ob.scale = ob.scale * HEAD_SCALE
    extras_body(design, j)
    if p["disc"]:
        disc_in_hand(j)
    return j


def render_frames(cid, design, tmp, only=None):
    scene = C.reset()
    cam = setup_camera(scene)
    C.sun("key", 3.4, (55, 0, 48))
    frames = []
    anims = {}
    for name, fn, fps, loop in ANIMATIONS:
        if only and name not in only:
            continue
        start = len(frames)
        for p in fn():
            clear_character()
            j = build(design, p)
            path = os.path.join(tmp, f"{cid}_{len(frames):03d}.png")
            C.render(path)
            frames.append({
                "path": path,
                "hand": to_pixel(scene, cam, j["hand_r"] + Vector((3, -4, 0))),
                "head": to_pixel(scene, cam, j["head"] + Vector((0, 0, 18))),
                "air": p["air"],
            })
        anims[name] = {"start": start, "count": len(frames) - start, "fps": fps, "loop": loop}
    anchor = to_pixel(scene, cam, (0, 0, 0))
    return frames, anims, anchor


def pack(cid, frames, anims, anchor):
    rows = math.ceil(len(frames) / COLUMNS)
    sheet = np.zeros((rows * FRAME, COLUMNS * FRAME, 4), dtype=np.float32)
    for i, f in enumerate(frames):
        img = bpy.data.images.load(f["path"])
        px = np.empty(FRAME * FRAME * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(FRAME, FRAME, 4)
        r, c = divmod(i, COLUMNS)
        # Image rows are stored bottom-up; place frame rows top-down.
        y0 = (rows - 1 - r) * FRAME
        sheet[y0:y0 + FRAME, c * FRAME:(c + 1) * FRAME] = px
        bpy.data.images.remove(img)
    out = bpy.data.images.new(cid, COLUMNS * FRAME, rows * FRAME, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = os.path.join(OUT, f"{cid}.webp")
    out.file_format = "WEBP"
    out.save(quality=92)
    meta = {
        "frame_size": FRAME, "columns": COLUMNS, "anchor": anchor,
        "frames": [{"hand": f["hand"], "head": f["head"], "air": f["air"]} for f in frames],
        "animations": anims,
    }
    with open(os.path.join(OUT, f"{cid}.json"), "w") as fh:
        json.dump(meta, fh, indent=1)


def render_portrait(cid, design):
    scene = C.reset()
    p = pose(lean=2, twist=-12, head_turn=-14, arm_l=(10, 12, 20), arm_r=(10, 12, 20))
    head_z = skeleton(design, p)["head"].z
    setup_camera(scene, size=640, ortho=104, target_z=head_z - 14, pitch=8)
    scene.camera.location.x += 6
    C.sun("key", 3.6, (62, 0, 20))
    build(design, p)
    C.render(os.path.join(OUT, f"{cid}_portrait.webp"), quality=92)


def render_select(cid, design):
    scene = C.reset()
    setup_camera(scene, size=800, ortho=236, target_z=104, pitch=12)
    C.sun("key", 3.6, (60, 0, 22))
    p = pose(lean=-2, twist=-20, head=-4, arm_r=(-20, 40, 100), arm_l=(30, 30, 110),
             leg_l=(10, 12, 6), leg_r=(-4, 14, 4), disc=True)
    build(design, p)
    C.render(os.path.join(OUT, f"{cid}_select.webp"), quality=92)


if __name__ == "__main__":
    wanted = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    tmp = os.path.join(os.environ.get("TEMP", "/tmp"), "hyperdisc_frames")
    os.makedirs(tmp, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    for cid, design in DESIGNS.items():
        if wanted and cid not in wanted:
            continue
        frames, anims, anchor = render_frames(cid, design, tmp)
        pack(cid, frames, anims, anchor)
        render_portrait(cid, design)
        render_select(cid, design)
        print("rendered", cid, len(frames), "frames")
    if not wanted or "referee" in wanted:
        frames, anims, anchor = render_frames("referee", REFEREE, tmp, REFEREE_ANIMS)
        pack("referee", frames, anims, anchor)
        print("rendered referee", len(frames), "frames")
