"""Character designs and dressing for make_characters_hd.py: MakeHuman assets,
garment edits, painted swimwear, patterns, and small props parented to bones.

Everything is placed from landmarks measured on the rest pose, so props sit
right on any body shape. MPFB bodies face -Y at rest; +Z is up.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C

FORWARD = Vector((0, -1, 0))

# --- Designs -------------------------------------------------------------------
# macro: MPFB body sliders (0..1).
# assets: key -> (MakeHuman subdir, file name). The key picks the colour.
# colors: toon colour per key ("skin" for the body).
# patterns: key -> pattern recipe (see pattern_material).
# edits: garment edits ("sleeveless:top"), paint: body regions painted as clothes.
# props: accessory names built by PROPS below.

DESIGNS = {
    "mick": {
        # Guile-type soldier with Outrun colours.
        "macro": {"gender": 1.0, "age": 0.55, "muscle": 1.0, "weight": 0.62, "proportions": 0.9,
                  "height": 0.62, "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05}},
        "assets": {
            "eyes": ("eyes", "high-poly.mhclo"),
            "eyebrows": ("eyebrows", "eyebrow007.mhclo"),
            "hair": ("hair", "short02.mhclo"),
            "top": ("clothes", "elvs_crude_t-shirt_male.mhclo"),
            "bottom": ("clothes", "cortu_cargo_pants.mhclo"),
            "shoes": ("clothes", "culturalibre_male_boots.mhclo"),
        },
        "colors": {"skin": "e8a97c", "hair": "f6d55c", "eyebrows": "c98f2c", "top": "2de2e6",
                   "bottom": "5b2a86", "shoes": "2b1d3d", "flattop": "f6d55c", "lens": "ff2e88",
                   "frame": "1a0f2e", "tags": "d8dde8", "band": "ff2e63"},
        "patterns": {"bottom": ("camo", ["5b2a86", "3d1a6e", "8a3fb8", "2de2e6"], 7.0)},
        "edits": ["sleeveless:top"],
        "props": ["flattop", "aviators", "dogtags", "wristbands"],
    },
    "tiffany": {
        # 80s teen-show lifeguard: feathered brunette hair, red one-piece, whistle.
        "macro": {"gender": 0.0, "age": 0.45, "muscle": 0.55, "weight": 0.45, "proportions": 0.95,
                  "height": 0.55, "cupsize": 0.55, "firmness": 0.6,
                  "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05}},
        "assets": {
            "eyes": ("eyes", "high-poly.mhclo"),
            "eyebrows": ("eyebrows", "eyebrow002.mhclo"),
            "hair": ("hair", "faydaen_hair_1.mhclo"),
        },
        "colors": {"skin": "f1c09a", "hair": "6b3a1f", "eyebrows": "4a2814", "suit": "ff2e3f",
                   "whistle": "ffd23f", "cord": "f4f1ff"},
        "paint": ["swimsuit:suit"],
        "props": ["whistle"],
    },
    "pete": {
        # Goose from Top Gun, beach edition: moustache, aviators, Hawaiian shirt.
        "macro": {"gender": 1.0, "age": 0.5, "muscle": 0.6, "weight": 0.78, "proportions": 0.75,
                  "height": 0.58, "race": {"asian": 0.05, "caucasian": 0.9, "african": 0.05}},
        "assets": {
            "eyes": ("eyes", "high-poly.mhclo"),
            "eyebrows": ("eyebrows", "eyebrow010.mhclo"),
            "hair": ("hair", "short03.mhclo"),
            "top": ("clothes", "namuhekam_male_polo_shirt.mhclo"),
            "bottom": ("clothes", "cortu_jeans_shorts.mhclo"),
            "shoes": ("clothes", "shoes05.mhclo"),
        },
        "colors": {"skin": "e0a57a", "hair": "5a3417", "eyebrows": "4a2a12", "top": "2de2e6",
                   "bottom": "d9c49a", "shoes": "f4f1ff", "moustache": "5a3417", "lens": "ffd23f",
                   "frame": "1a0f2e"},
        "patterns": {"top": ("floral", ["ffd23f", "ff2e88", "c4166a", "2de2e6"], 9.0)},
        "props": ["aviators", "moustache"],
    },
}


# --- Rest-pose landmarks ---------------------------------------------------------

def landmarks(rig, pieces):
    """World positions measured on the rest pose."""
    def bone(name, tail=False):
        b = rig.data.bones[name]
        return rig.matrix_world @ (b.tail_local if tail else b.head_local)
    lm = {
        "head": bone("mixamorig:Head"),
        "head_top": bone("mixamorig:HeadTop_End") if "mixamorig:HeadTop_End" in rig.data.bones
        else bone("mixamorig:Head", tail=True),
        "neck": bone("mixamorig:Neck"),
        "chest": bone("mixamorig:Spine2"),
        "hips": bone("mixamorig:Hips"),
        "shoulder_l": bone("mixamorig:LeftArm"),
        "shoulder_r": bone("mixamorig:RightArm"),
        "wrist_l": bone("mixamorig:LeftHand"),
        "wrist_r": bone("mixamorig:RightHand"),
        "elbow_l": bone("mixamorig:LeftForeArm"),
        "elbow_r": bone("mixamorig:RightForeArm"),
    }
    eyes = next((p for p in pieces if p.get("hd_key") == "eyes"), None)
    if eyes:
        pts = [eyes.matrix_world @ v.co for v in eyes.data.vertices]
        left = [p for p in pts if p.x > lm["head"].x]
        right = [p for p in pts if p.x <= lm["head"].x]
        lm["eye_l"] = sum(left, Vector()) / len(left)
        lm["eye_r"] = sum(right, Vector()) / len(right)
        lm["eye_front"] = min(p.y for p in pts)
    body = next(p for p in pieces if p.get("hd_key") == "skin")
    lm["body"] = body
    # Chest surface: frontmost body vertex near the chest height and centre line.
    zc = lm["chest"].z + 0.06
    front = [body.matrix_world @ v.co for v in body.data.vertices
             if abs(v.co.x) < 0.05 and abs((body.matrix_world @ v.co).z - zc) < 0.04]
    lm["chest_front"] = min(front, key=lambda p: p.y) if front else lm["chest"] + FORWARD * 0.12
    return lm


# --- Garment edits -----------------------------------------------------------------

def apply_edits(design, pieces, lm):
    for edit in design.get("edits", []):
        kind, key = edit.split(":")
        ob = next((p for p in pieces if p.get("hd_key") == key), None)
        if ob is None:
            continue
        if kind == "sleeveless":
            _cut_sleeves(ob, lm)


def _cut_sleeves(ob, lm):
    """Removes sleeves: faces outside the shoulder joints become a tank top."""
    limit = abs(lm["shoulder_l"].x - lm["neck"].x) * 0.92
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    mw = ob.matrix_world
    doomed = [f for f in bm.faces if abs((mw @ f.calc_center_median()).x - lm["neck"].x) > limit]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bm.to_mesh(ob.data)
    bm.free()


# --- Painted clothes ----------------------------------------------------------------

def apply_paint(design, body, lm, material_for):
    """Paints body faces as clothing (a one-piece swimsuit) with a second material."""
    for entry in design.get("paint", []):
        kind, key = entry.split(":")
        mat = material_for(key)
        body.data.materials.append(mat)
        idx = len(body.data.materials) - 1
        mw = body.matrix_world
        hips, chest = lm["hips"], lm["chest"]
        cx = lm["neck"].x
        hip_w = abs(lm["shoulder_l"].x - cx) * 0.95
        for poly in body.data.polygons:
            c = mw @ poly.center
            dx = abs(c.x - cx)
            if dx > hip_w * 1.25:
                continue  # arms
            # High-cut legs: the leg line rises toward the hips' sides.
            leg_line = hips.z - 0.07 + 0.16 * min(dx / hip_w, 1.0)
            top_line = chest.z + 0.12 - 0.05 * min(dx / hip_w, 1.0)
            if leg_line < c.z < top_line:
                poly.material_index = idx


# --- Materials -----------------------------------------------------------------------

def pattern_material(name, recipe, shade=0.66):
    """Flat cel pattern from UVs: 'camo' blotches or 'floral' (Hawaiian) cells."""
    kind, colors, scale = recipe

    def builder(nt):
        uv = nt.nodes.new("ShaderNodeTexCoord")
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        if kind == "camo":
            tex = nt.nodes.new("ShaderNodeTexNoise")
            tex.inputs["Scale"].default_value = scale
            tex.inputs["Detail"].default_value = 1.0
            tex.inputs["Roughness"].default_value = 0.4
            nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
            src = tex.outputs["Fac"]
            stops = [0.0, 0.45, 0.55, 0.64]
        else:  # floral: voronoi cells with petal-like blobs
            tex = nt.nodes.new("ShaderNodeTexVoronoi")
            tex.feature = "F1"
            tex.inputs["Scale"].default_value = scale
            nt.links.new(uv.outputs["UV"], tex.inputs["Vector"])
            src = tex.outputs["Distance"]
            stops = [0.0, 0.18, 0.3, 0.42]
        while len(ramp.color_ramp.elements) < len(colors):
            ramp.color_ramp.elements.new(0.5)
        # Floral: flower centre, petals, outline ring, background (reversed order).
        order = colors if kind == "camo" else colors
        for el, pos, col in zip(ramp.color_ramp.elements, stops, order):
            el.position = pos
            el.color = C.rgb(col)
        nt.links.new(src, ramp.inputs["Fac"])
        return ramp.outputs["Color"]

    return C.toon_textured(name, builder, shade=shade)


# --- Props ------------------------------------------------------------------------------

def _parent_to_bone(ob, rig, bone):
    world = ob.matrix_world.copy()
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    ob.matrix_world = world


def _mesh_from_bmesh(name, bm, mat, ink):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(ob)
    C.assign(ob, mat)
    C.smooth(ob)
    if ink:
        C.outline(ob, ink)
    return ob


def prop_flattop(design, rig, lm, ink):
    """Guile-style flat-top: a squared block of hair over the crown."""
    top = lm["head_top"]
    head = lm["head"]
    height = (top - head).length
    width = height * 0.72
    depth = height * 0.8
    block = height * 0.3
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= width
        v.co.y *= depth
        v.co.z = (v.co.z + 0.5) * block  # 0..block height
        # Narrower at the base so the sides blend into the short hair.
        if v.co.z < 0.01:
            v.co.x *= 0.9
            v.co.y *= 0.9
    bmesh.ops.bevel(bm, geom=[e for e in bm.edges], offset=height * 0.05, segments=2, affect="EDGES")
    ob = _mesh_from_bmesh("flattop", bm, C.toon(design["colors"]["flattop"], 0.66), ink)
    # Sits on the crown, set back from the brow.
    ob.location = Vector((head.x, head.y + height * 0.12, top.z - block * 0.55))
    bpy.context.view_layer.update()
    _parent_to_bone(ob, rig, "mixamorig:Head")
    return [ob]


def prop_aviators(design, rig, lm, ink):
    if "eye_l" not in lm:
        return []
    out = []
    lens_mat = C.toon(design["colors"]["lens"], 0.55, emission=0.25)
    frame_mat = C.toon(design["colors"]["frame"], 0.8)
    spread = (lm["eye_l"] - lm["eye_r"]).length
    r = spread * 0.36
    y = lm["eye_front"] - 0.008
    for side in ("eye_l", "eye_r"):
        c = lm[side]
        lens = C.sphere(f"lens_{side}", r, (c.x, y, c.z - r * 0.15), lens_mat, scale=(1.0, 0.25, 0.82),
                        segs=20, ink=ink * 0.6)
        out.append(lens)
    mid = (lm["eye_l"] + lm["eye_r"]) / 2
    bridge = C.box("bridge", (spread * 0.35, r * 0.15, r * 0.12), (mid.x, y, mid.z + r * 0.35), frame_mat, ink=0)
    out.append(bridge)
    bpy.context.view_layer.update()
    for ob in out:
        _parent_to_bone(ob, rig, "mixamorig:Head")
    return out


def prop_dogtags(design, rig, lm, ink):
    p = lm["chest_front"] + Vector((0.0, -0.012, 0.0))
    mat = C.toon(design["colors"]["tags"], 0.7)
    a = C.box("tag_a", (0.028, 0.004, 0.045), (p.x - 0.008, p.y, p.z), mat, rot=(0, 0.2, 0), bevel=0.004,
              ink=ink * 0.5)
    b = C.box("tag_b", (0.028, 0.004, 0.045), (p.x + 0.012, p.y - 0.003, p.z - 0.01), mat, rot=(0, -0.25, 0),
              bevel=0.004, ink=ink * 0.5)
    bpy.context.view_layer.update()
    for ob in (a, b):
        _parent_to_bone(ob, rig, "mixamorig:Spine2")
    return [a, b]


def prop_wristbands(design, rig, lm, ink):
    out = []
    mat = C.toon(design["colors"]["band"], 0.66)
    for side in ("l", "r"):
        wrist, elbow = lm[f"wrist_{side}"], lm[f"elbow_{side}"]
        axis = (wrist - elbow).normalized()
        c = wrist - axis * 0.035
        rot = axis.to_track_quat("Z", "Y").to_euler()
        ob = C.cylinder(f"band_{side}", 0.04, 0.06, tuple(c), mat, rot=tuple(rot), verts=20, ink=ink * 0.7)
        out.append(ob)
        bpy.context.view_layer.update()
        _parent_to_bone(ob, rig, "mixamorig:LeftForeArm" if side == "l" else "mixamorig:RightForeArm")
    return out


def prop_whistle(design, rig, lm, ink):
    p = lm["chest_front"] + Vector((0.03, -0.015, 0.05))
    whistle = C.cylinder("whistle", 0.012, 0.045, tuple(p), C.toon(design["colors"]["whistle"], 0.66),
                         rot=(0, math.radians(90), 0), verts=16, ink=ink * 0.5)
    bpy.context.view_layer.update()
    _parent_to_bone(whistle, rig, "mixamorig:Spine2")
    return [whistle]


def prop_moustache(design, rig, lm, ink):
    if "eye_l" not in lm:
        return []
    spread = (lm["eye_l"] - lm["eye_r"]).length
    mid = (lm["eye_l"] + lm["eye_r"]) / 2
    p = Vector((mid.x, lm["eye_front"] - 0.004, mid.z - spread * 0.95))
    ob = C.sphere("moustache", spread * 0.62, tuple(p), C.toon(design["colors"]["moustache"], 0.7),
                  scale=(1.0, 0.28, 0.32), segs=20, ink=ink * 0.6)
    bpy.context.view_layer.update()
    _parent_to_bone(ob, rig, "mixamorig:Head")
    return [ob]


PROPS = {
    "whistle": prop_whistle,
    "moustache": prop_moustache,
    "flattop": prop_flattop,
    "aviators": prop_aviators,
    "dogtags": prop_dogtags,
    "wristbands": prop_wristbands,
}


def add_props(design, rig, lm, ink):
    out = []
    for name in design.get("props", []):
        out += PROPS[name](design, rig, lm, ink)
    return out
