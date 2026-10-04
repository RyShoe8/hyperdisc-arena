"""Characters built from a supplied 3D model (rather than MPFB parts).

load_model() imports a GLB, scales it to real height (metres, feet on the
floor, facing -Y), recolours each part as toon-shaded ink-and-paint, and adds
props measured from the model itself (e.g. aviators from the eye meshes).
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector

import common as C

MODELS = {
    "mick": {
        "file": r"C:\Users\rysho\Downloads\MascularMale.glb",
        "height": 1.85,
        # Part name in the model -> colour key.
        "parts": {"Body": "skin", "EyeBraws": "eyebrows", "Eyes": "eyes", "Hair": "hair", "Trunks": "trunks"},
        "colors": {"skin": "e3a072", "eyebrows": "b98a2e", "eyes": "f4f1ff", "hair": "f6d55c",
                   "trunks": "5b2a86", "lens_top": "ff2e88", "lens_bottom": "ffb347", "frame": "e8e2d0"},
        "props": ["aviators"],
        # Straight 3D look: tint the model's own colours (painted skin keeps
        # its variation); plain parts are set outright.
        "model_tints": {"skin": "d9a67e", "hair": "f5d066", "eyebrows": "a8782e"},
    },
}


def load_model(spec, ink, style="toon"):
    """Imports and prepares the model. Returns (pieces, landmarks).

    style "toon" repaints it as ink-and-paint; "model" keeps its own
    materials (a straight 3D render)."""
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=spec["file"])
    pieces = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    # Normalise: real height, feet at z=0, centred on x/y.
    pts = [o.matrix_world @ Vector(c) for o in pieces for c in o.bound_box]
    zmin, zmax = min(p.z for p in pts), max(p.z for p in pts)
    cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
    cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
    s = spec["height"] / (zmax - zmin)
    fix = Matrix.Scale(s, 4) @ Matrix.Translation((-cx, -cy, -zmin))
    for o in pieces:
        o.matrix_world = fix @ o.matrix_world
    bpy.context.view_layer.update()
    for o in pieces:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in pieces:
        o.select_set(False)

    colors = spec["colors"]
    for o in pieces:
        key = next((k for name, k in spec["parts"].items() if o.name.startswith(name)), "skin")
        o["hd_key"] = key
        if style == "model":
            C.smooth(o)
            tint = spec.get("model_tints", {}).get(key)
            if tint:
                _tint_material(o, tint)
            continue
        # Light shadows like WJ2's paint: one soft step, never near-black.
        C.assign(o, C.toon(colors[key], shade=0.8 if key != "eyes" else 0.9))
        C.smooth(o)
        if key not in ("eyes", "eyebrows"):
            C.outline(o, ink)
    lm = _landmarks(pieces)
    return pieces, lm


def _tint_material(ob, hex_color):
    """Multiplies a painted base colour by a tint, or sets a plain one."""
    mat = ob.data.materials[0].copy()  # parts can share materials
    ob.data.materials[0] = mat
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    base = bsdf.inputs["Base Color"]
    if base.is_linked:
        src = base.links[0].from_socket
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        nt.links.new(src, mix.inputs[6])
        mix.inputs[7].default_value = C.rgb(hex_color)
        nt.links.new(mix.outputs[2], base)
    else:
        base.default_value = C.rgb(hex_color)
    # Matte skin and hair read better than the model's glossy default.
    bsdf.inputs["Roughness"].default_value = max(bsdf.inputs["Roughness"].default_value, 0.58)


def _landmarks(pieces):
    lm = {}
    eyes = next((o for o in pieces if o["hd_key"] == "eyes"), None)
    if eyes:
        pts = [v.co for v in eyes.data.vertices]
        left = [p for p in pts if p.x > 0]
        right = [p for p in pts if p.x <= 0]
        lm["eye_l"] = sum(left, Vector()) / len(left)
        lm["eye_r"] = sum(right, Vector()) / len(right)
        lm["eye_front"] = min(p.y for p in pts)
        lm["eye_radius"] = (max(p.z for p in left) - min(p.z for p in left)) / 2
    body = next(o for o in pieces if o["hd_key"] == "skin")
    if "eye_l" in lm:
        z = lm["eye_l"].z
        band = [v.co for v in body.data.vertices if abs(v.co.z - z) < 0.01]
        lm["head_half_width"] = max(abs(p.x) for p in band if p.y < lm["eye_front"] + 0.12)
        lm["ear_y"] = lm["eye_front"] + 0.09
    return lm


# --- Aviators ----------------------------------------------------------------------

def _teardrop(n=48):
    """Aviator lens outline (x: inner -1 .. outer +1, z up), unit size.

    A nearly straight top bar, a full outer side that drops into the
    classic teardrop point low on the outside, and a shallow inner edge.
    Sampled from a closed Catmull-Rom spline through hand-placed points.
    """
    ctrl = [(-0.95, 0.50), (-0.2, 0.62), (0.55, 0.62), (0.98, 0.42), (1.02, -0.05),
            (0.82, -0.62), (0.40, -0.98), (-0.15, -0.88), (-0.70, -0.45), (-1.0, 0.05)]
    out = []
    m = len(ctrl)
    per = max(1, n // m)
    for i in range(m):
        p0, p1, p2, p3 = (ctrl[(i + k) % m] for k in (-1, 0, 1, 2))
        for j in range(per):
            t = j / per
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * ((2 * p1[c]) + (-p0[c] + p2[c]) * t + (2 * p0[c] - 5 * p1[c] + 4 * p2[c] - p3[c]) * t2
                                    + (-p0[c] + 3 * p1[c] - 3 * p2[c] + p3[c]) * t3) for c in (0, 1)))
    return out


def _curve_tube(name, points, radius, mat, cyclic=False):
    cu = bpy.data.curves.new(name, "CURVE")
    cu.dimensions = "3D"
    cu.bevel_depth = radius
    cu.bevel_resolution = 3
    sp = cu.splines.new("POLY")
    sp.points.add(len(points) - 1)
    for p, co in zip(sp.points, points):
        p.co = (co[0], co[1], co[2], 1)
    sp.use_cyclic_u = cyclic
    ob = bpy.data.objects.new(name, cu)
    bpy.context.collection.objects.link(ob)
    ob.data.materials.append(mat)
    return ob


def _lens_material(top, bottom):
    """Sunset-gradient lens: a constant-step gradient down the lens, glossy."""
    def builder(nt):
        coord = nt.nodes.new("ShaderNodeTexCoord")
        sep = nt.nodes.new("ShaderNodeSeparateXYZ")
        nt.links.new(coord.outputs["Generated"], sep.inputs[0])
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.interpolation = "CONSTANT"
        ramp.color_ramp.elements[0].position = 0.0
        ramp.color_ramp.elements[0].color = C.rgb(bottom)
        ramp.color_ramp.elements[1].position = 0.55
        ramp.color_ramp.elements[1].color = C.rgb(top)
        nt.links.new(sep.outputs["Z"], ramp.inputs[0])
        return ramp.outputs["Color"]
    return C.toon_textured("lens", builder, shade=0.75)


def _pbr_lens(top, bottom):
    """Glossy gradient lens for the straight 3D look."""
    m = bpy.data.materials.new("lens_pbr")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    coord = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = C.rgb(bottom)
    ramp.color_ramp.elements[1].position = 0.85
    ramp.color_ramp.elements[1].color = C.rgb(top)
    nt.links.new(coord.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs[0])
    nt.links.new(ramp.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.05
    bsdf.inputs["Metallic"].default_value = 0.35
    return m


def _pbr_metal(color):
    m = bpy.data.materials.new("frame_pbr")
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = C.rgb(color)
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.22
    return m


def add_aviators(spec, lm, ink, style="toon"):
    colors = spec["colors"]
    if style == "model":
        lens_mat = _pbr_lens(colors["lens_top"], colors["lens_bottom"])
        frame_mat = _pbr_metal("e0b25a")
    else:
        lens_mat = _lens_material(colors["lens_top"], colors["lens_bottom"])
        frame_mat = C.toon(colors["frame"], 0.6)
    spread = (lm["eye_l"] - lm["eye_r"]).length
    w = spread * 0.56       # lens half-width (a touch oversized so they read in game)
    h = spread * 0.46       # lens half-height
    y = lm["eye_front"] - 0.012
    out = []
    for side, sign in (("l", 1), ("r", -1)):
        c = lm["eye_" + side]
        outline = []
        for x, z in _teardrop():
            # Mirror so the droop is on the outer side; wrap the lens slightly.
            lx = x * sign
            px = c.x + lx * w
            py = y + 0.010 * (lx * sign) ** 2 + 0.004 * abs(z)
            pz = c.z - h * 0.05 + z * h
            outline.append((px, py, pz))
        # Lens: a fan of triangles over the outline.
        bm = bmesh.new()
        centre = bm.verts.new((c.x, y + 0.002, c.z - h * 0.2))
        ring = [bm.verts.new(p) for p in outline]
        for i in range(len(ring)):
            bm.faces.new((centre, ring[i], ring[(i + 1) % len(ring)]))
        me = bpy.data.meshes.new("lens_" + side)
        bm.to_mesh(me)
        bm.free()
        lens = bpy.data.objects.new("lens_" + side, me)
        bpy.context.collection.objects.link(lens)
        lens.data.materials.append(lens_mat)
        solid = lens.modifiers.new("thick", "SOLIDIFY")
        solid.thickness = 0.003
        out.append(lens)
        out.append(_curve_tube("rim_" + side, outline, 0.0022, frame_mat, cyclic=True))
        # Temple arm: from the outer top corner back to the ear.
        outer = max(outline, key=lambda p: (p[0] * sign) + p[2] * 0.3)
        ear = (sign * lm["head_half_width"] * 0.98, lm["ear_y"], outer[2] - 0.004)
        out.append(_curve_tube("temple_" + side, [outer, (ear[0] * 0.98, (outer[1] + ear[1]) / 2, outer[2]), ear],
                               0.0018, frame_mat))
    # Double bridge across the nose.
    l_in = (lm["eye_l"].x - w * 0.95, y + 0.001, lm["eye_l"].z + h * 0.35)
    r_in = (lm["eye_r"].x + w * 0.95, y + 0.001, lm["eye_r"].z + h * 0.35)
    mid_y = y - 0.004
    out.append(_curve_tube("bridge_top", [r_in, (0, mid_y, r_in[2] + 0.002), l_in], 0.0018, frame_mat))
    out.append(_curve_tube("bridge_low", [(r_in[0] * 0.7, y, r_in[2] - h * 0.35), (0, mid_y, r_in[2] - h * 0.28),
                                          (l_in[0] * 0.7, y, l_in[2] - h * 0.35)], 0.0016, frame_mat))
    return out
