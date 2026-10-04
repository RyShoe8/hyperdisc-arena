"""HD character sprites: MPFB bodies, MakeHuman clothes and hair, Mixamo
motion, cel shading and ink outlines.

Replaces the procedural figures of make_characters.py with real anatomy and
motion-captured movement, retimed into Windjammers 2-style held key poses.

Setup (one time, outside the repo; see docs/ART.md):
    - MPFB2 Blender extension in D:/Blender/extensions
    - MakeHuman CC0 asset packs unpacked into MPFB's user data folder
    - Mixamo animations (FBX, without skin, 30 fps) in ../refs/mixamo

Run from the repo root (PowerShell):
    $env:BLENDER_USER_EXTENSIONS = "D:/Blender/extensions"
    blender -b --factory-startup -P tools/blender/make_characters_hd.py -- [character_id ...] [--preview]

--preview renders a contact sheet of every frame to refs/preview instead of
writing the game assets.

Outputs (same contract as make_characters.py, plus per-frame timing):
    <id>.webp, <id>.json, <id>_portrait.webp, <id>_select.webp
    in assets/art/characters/. Each animation may carry "ticks": how long
    each frame holds, in 60 Hz ticks (the WJ2 look: strong poses that hold,
    snappy changes between them).
"""

import json
import math
import os
import sys

import addon_utils
import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(__file__))
import common as C  # noqa: E402

OUT = os.path.join(C.ROOT, "assets", "art", "characters")
MIXAMO = os.environ.get("MIXAMO_DIR", os.path.join(C.ROOT, "..", "refs", "mixamo"))
PREVIEW = os.path.join(C.ROOT, "..", "refs", "preview")

FRAME = int(os.environ.get("HD_FRAME", 320))  # square frame size in pixels
ORTHO = 2.42         # metres across a frame (a 1.8 m figure fills ~3/4 of it)
CAM_PITCH = 36.0     # degrees below horizontal; WJ2-like but keeps faces readable
YAW = 32.0           # body turned toward the camera (three-quarter view)
COLUMNS = 8
INK_M = 0.016        # outline thickness in metres (~2 px at this scale)
HEIGHT_REF = 1.8
HEAD_LIFT = 25.0     # degrees the head is tilted up from the mocap pose

addon_utils.enable("bl_ext.blender_org.mpfb", default_set=True)
from bl_ext.blender_org.mpfb.services.assetservice import AssetService  # noqa: E402
from bl_ext.blender_org.mpfb.services.humanservice import HumanService  # noqa: E402


from hd_dressing import DESIGNS  # noqa: E402
import hd_dressing as D  # noqa: E402
import hd_model as M  # noqa: E402

# MPFB body used only as the source of a Mixamo-compatible rig for supplied models.
TEMPLATE_MACRO = {"gender": 1.0, "age": 0.5, "muscle": 1.0, "weight": 0.6, "proportions": 0.9,
                  "height": 0.7, "cupsize": 0.5, "firmness": 0.5,
                  "race": {"asian": 0.1, "caucasian": 0.8, "african": 0.1}}

# Game animation -> (Mixamo clip, [(source frame, hold ticks)], loop, extras).
# Source frames are picked as strong key poses; holds give WJ2's snap.
ANIMATIONS = [
    ("idle", "bouncing_fight_idle", [(1, 8), (8, 8), (15, 8), (22, 8)], True, {}),
    ("run", "fast_run", [(1, 4), (4, 4), (7, 4), (10, 4), (13, 4), (16, 4)], True, {}),
    ("dash", "running_slide", [(18, 3), (26, 10), (34, 4)], False, {}),
    ("hold", "frisbee_throw", [(30, 12), (32, 12)], True, {"disc": True}),
    ("throw", "frisbee_throw", [(34, 3), (40, 2), (44, 2), (50, 6), (60, 8)], False, {"disc_until": 1}),
    ("lob", "throw", [(20, 4), (30, 3), (38, 3), (48, 8)], False, {"disc_until": 1}),
    ("catch", "catch_medium", [(10, 3), (18, 8), (30, 6)], False, {"disc_from": 1}),
    ("block", "body_block_right", [(8, 3), (16, 8), (28, 6)], False, {}),
    ("slap", "throw", [(30, 2), (38, 2), (46, 6)], False, {}),
    ("jump", "unarmed_jump", [(10, 4), (20, 6), (30, 6), (40, 4)], False, {"air": [1, 2]}),
    ("knock", "knocked_down_punch", [(40, 10), (46, 10)], True, {}),
    ("charge", "frisbee_throw", [(28, 6), (30, 6)], True, {"disc": True}),
    ("special", "baseball_pitching", [(20, 4), (40, 4), (55, 3), (62, 3), (75, 10)], False, {"disc_until": 3}),
    ("win", "fist_pump", [(10, 8), (20, 8), (30, 8)], True, {}),
    ("lose", "defeated", [(20, 12), (40, 12)], True, {}),
]


# --- Scene -------------------------------------------------------------------

def clear_scene():
    # Cached Mixamo actions and source armatures die with the scene.
    _actions.clear()
    _sources.clear()
    _offset_cache.clear()
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.cameras,
                 bpy.data.lights, bpy.data.actions, bpy.data.images):
        for block in list(coll):
            if block.users == 0:
                coll.remove(block)
    C._toon_cache.clear()
    C._ink = None


def setup_scene():
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.view_settings.view_transform = "Standard"
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.eevee.taa_render_samples = 16
    if scene.world is None:
        scene.world = bpy.data.worlds.new("world")
    scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Strength"].default_value = 0.0
    return scene


def setup_camera(scene, size=FRAME, ortho=ORTHO, target_z=0.85, pitch=CAM_PITCH):
    scene.render.resolution_x = scene.render.resolution_y = size
    data = bpy.data.cameras.new("char_cam")
    data.type = "ORTHO"
    data.ortho_scale = ortho
    data.clip_start, data.clip_end = 0.1, 100
    cam = bpy.data.objects.new("char_cam", data)
    tilt = math.radians(90 - pitch)
    dist = 20
    cam.rotation_euler = (tilt, 0, 0)
    cam.location = (0, -dist * math.sin(tilt), target_z + dist * math.cos(tilt))
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def to_pixel(scene, cam, point):
    from bpy_extras.object_utils import world_to_camera_view
    co = world_to_camera_view(scene, cam, Vector(point))
    return [round(co.x * scene.render.resolution_x, 1), round((1 - co.y) * scene.render.resolution_y, 1)]


# --- Building a character ------------------------------------------------------

ASSET_TYPES = {"eyes": "Eyes", "eyebrows": "Eyebrows", "hair": "Hair", "clothes": "Clothes"}


def build(design):
    """MPFB body with a Mixamo-compatible rig, clothes, hair and props."""
    macro = dict(design["macro"])
    macro.setdefault("cupsize", 0.5)
    macro.setdefault("firmness", 0.5)
    body = HumanService.create_human(macro_detail_dict=macro, feet_on_ground=True, scale=0.1)
    rig = HumanService.add_builtin_rig(body, "mixamo")
    # Mixamo animates quaternions; MPFB bones default to Euler, which would
    # silently ignore every rotation key.
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    body["hd_key"] = "skin"
    pieces = [body]
    for key, (subdir, filename) in design["assets"].items():
        path = AssetService.find_asset_absolute_path(filename, subdir)
        if not path:
            raise RuntimeError(f"asset not found: {subdir}/{filename}")
        ob = HumanService.add_mhclo_asset(path, body, asset_type=ASSET_TYPES[subdir], subdiv_levels=0,
                                          material_type="MAKESKIN")
        ob["hd_key"] = key
        pieces.append(ob)
    bpy.context.view_layer.update()
    lm = D.landmarks(rig, pieces)
    D.apply_edits(design, pieces, lm)
    apply_materials(design, pieces, lm)
    props = D.add_props(design, rig, lm, INK_M)
    return body, rig, pieces + props


def build_model(cid):
    """A character from a supplied 3D model: its own look, rigged here."""
    spec = M.MODELS[cid]
    pieces, lm = M.load_model(spec, 0, style="model")
    props = M.add_aviators(spec, lm, 0, style="model") if "aviators" in spec.get("props", []) else []
    rig, joints = M.rig_model(pieces, lm, lambda: HumanService.create_human(macro_detail_dict=TEMPLATE_MACRO, scale=0.1),
                              lambda h: HumanService.add_builtin_rig(h, "mixamo"))
    pieces = pieces + M.add_garments(spec, pieces, rig, joints)
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    rig["retarget"] = True
    for ob in props:
        D._parent_to_bone(ob, rig, "mixamorig:Head")
    body = next(o for o in pieces if o.get("hd_key") == "skin")
    return body, rig, pieces + props


def model_lighting(scene):
    """Studio lighting for the straight 3D look: warm key, cool rim, soft fill."""
    C.sun("key", 4.0, (50, 0, 35), color=(1.0, 0.95, 0.88))
    C.sun("rim", 3.0, (60, 0, 200), color=(0.75, 0.85, 1.0), shadows=False)
    C.sun("fill", 1.0, (75, 0, -60), color=(1.0, 0.85, 0.95), shadows=False)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.6
    scene.view_settings.view_transform = "AgX"
    scene.eevee.taa_render_samples = 32


def _image_of(ob):
    for mat in ob.data.materials:
        if mat and mat.use_nodes:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    return node.image
    return None


def textured_toon(name, image, tint=None, alpha=False, shade=0.66):
    """Toon material coloured by an image (eyes) or a flat tint cut out by the
    image's alpha (eyebrows, hair cards)."""
    def builder(nt):
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        if tint is None:
            return tex.outputs["Color"]
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = C.rgb(tint)
        return rgb.outputs[0]
    m = C.toon_textured(name, builder, shade=shade)
    if alpha:
        nt = m.node_tree
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        shader = out.inputs[0].links[0].from_node
        mix = nt.nodes.new("ShaderNodeMixShader")
        clear = nt.nodes.new("ShaderNodeBsdfTransparent")
        nt.links.new(tex.outputs["Alpha"], mix.inputs[0])
        nt.links.new(clear.outputs[0], mix.inputs[1])
        nt.links.new(shader.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        m.surface_render_method = "DITHERED"
    return m


def apply_materials(design, pieces, lm):
    colors = design["colors"]
    patterns = design.get("patterns", {})
    for ob in pieces:
        key = ob.get("hd_key", "skin")
        image = _image_of(ob)
        ink = INK_M
        if key == "eyes" and image:
            mat = textured_toon("eyes", image, shade=0.85)
            ink = 0
        elif key in ("eyebrows", "hair") and image and key == "eyebrows":
            mat = textured_toon(key, image, tint=colors[key], alpha=True)
            ink = 0
        elif key in patterns:
            mat = D.pattern_material(key, patterns[key])
        else:
            mat = C.toon(colors.get(key, colors["skin"]), shade=0.66)
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        for poly in ob.data.polygons:
            poly.use_smooth = True
            poly.material_index = 0
        if key == "skin":
            D.apply_paint(design, ob, lm, lambda k: C.toon(colors[k], shade=0.66))
        if ink:
            C.outline(ob, thickness=ink)


# --- Animation -------------------------------------------------------------------

_actions = {}
_sources = {}


def load_action(clip, rig):
    """Imports a Mixamo FBX once. Returns its action (hips rescaled to our
    rig for the direct path) and keeps the source armature for retargeting."""
    if clip in _actions:
        return _actions[clip]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(MIXAMO, clip + ".fbx"), automatic_bone_orientation=False)
    imported = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in imported if o.type == "ARMATURE")
    action = src.animation_data.action
    action.use_fake_user = True
    for o in imported:
        if o is not src:
            bpy.data.objects.remove(o, do_unlink=True)
    src.hide_render = True
    src["clip"] = clip
    _sources[clip] = src
    if not rig.get("retarget"):
        ratio = rig.data.bones["mixamorig:Hips"].head_local.length / src.data.bones["mixamorig:Hips"].head_local.length
        action = action.copy()
        for fc in _fcurves(action):
            if fc.data_path == 'pose.bones["mixamorig:Hips"].location':
                for kp in fc.keyframe_points:
                    kp.co.y *= ratio
                    kp.handle_left.y *= ratio
                    kp.handle_right.y *= ratio
    action["clip"] = clip
    _actions[clip] = action
    return action


def _rot(m):
    return m.to_3x3().normalized().to_quaternion()


def retarget_pose(scene, rig, src, frame):
    """Poses `rig` like the Mixamo source armature at `frame`.

    For each bone, the source's rotation away from its own rest orientation
    is applied to the target's rest orientation after that has been aimed
    along the source's rest direction. Limbs therefore point where the mocap
    says even though the model was sculpted in an A-pose and Mixamo's rest
    is a T-pose, and each bone keeps its own twist convention."""
    scene.frame_set(frame)
    bpy.context.view_layer.update()
    src_mw = src.matrix_world
    offsets = src.get("_offsets_for")
    if offsets != rig.name:
        cache = {}
        for bone in rig.data.bones:
            sb = src.data.bones.get(bone.name)
            if sb is None:
                continue
            s_rest = _rot(src_mw @ sb.matrix_local)
            t_rest = _rot(bone.matrix_local)
            s_dir = s_rest @ Vector((0, 1, 0))
            t_dir = t_rest @ Vector((0, 1, 0))
            aligned = t_dir.rotation_difference(s_dir) @ t_rest
            cache[bone.name] = s_rest.inverted() @ aligned
        _offset_cache[src.name] = cache
        src["_offsets_for"] = rig.name
    cache = _offset_cache[src.name]
    src_hips_rest = (src_mw @ src.data.bones["mixamorig:Hips"].head_local).z
    ratio = rig.data.bones["mixamorig:Hips"].head_local.z / max(src_hips_rest, 1e-6)
    posed = {}

    def visit(bone):
        name = bone.name
        spb = src.pose.bones.get(name)
        if bone.parent is not None:
            pm = posed[bone.parent.name]
            rest_rel = bone.parent.matrix_local.inverted() @ bone.matrix_local
            follow = pm @ rest_rel
        else:
            follow = bone.matrix_local.copy()
        if spb is None or name not in cache:
            m = follow
        else:
            rot = (_rot(src_mw @ spb.matrix) @ cache[name]).to_matrix().to_4x4()
            head = (src_mw @ spb.head) * ratio if bone.parent is None else follow.to_translation()
            m = Matrix.Translation(head) @ rot
        posed[name] = m
        # Set the local transform directly: the pose-matrix setter would use
        # the parent's stale (not yet re-evaluated) pose.
        rig.pose.bones[name].matrix_basis = follow.inverted() @ m
        for child in bone.children:
            visit(child)

    for bone in rig.data.bones:
        if bone.parent is None:
            visit(bone)
    bpy.context.view_layer.update()


_offset_cache = {}


def _fcurves(action):
    if hasattr(action, "layers") and action.layers:
        out = []
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    out += list(bag.fcurves)
        return out
    return list(action.fcurves)


def pose_rig(scene, rig, action, frame, keep_height=False):
    """Poses the rig at a source frame, holding the hips over the origin."""
    if rig.get("retarget"):
        src = _sources[action["clip"]]
        rig.location = (0, 0, 0)
        facing = rig.rotation_euler.copy()
        rig.rotation_euler = (0, 0, 0)
        bpy.context.view_layer.update()
        retarget_pose(scene, rig, src, frame)
        rig.rotation_euler = facing
        _lift_head(rig)
        hips = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
        rig.location = (-hips.x, -hips.y, 0)
        bpy.context.view_layer.update()
        return
    rig.animation_data_create()
    rig.animation_data.action = action
    if hasattr(rig.animation_data, "action_slot") and action.slots:
        rig.animation_data.action_slot = action.slots[0]
    rig.location = (0, 0, 0)
    scene.frame_set(frame)
    # Freeze this pose: with the action detached, scene updates no longer
    # overwrite the tweaks below.
    rig.animation_data.action = None
    _lift_head(rig)
    hips = rig.matrix_world @ rig.pose.bones["mixamorig:Hips"].head
    rig.location = (-hips.x, -hips.y, 0)
    bpy.context.view_layer.update()


def _lift_head(rig):
    """Keeps the face toward the camera: mocap fighters tuck the chin, which
    from above hides the face. Lift head and neck a little on every frame."""
    for bone, deg in (("mixamorig:Neck", -HEAD_LIFT * 0.4), ("mixamorig:Head", -HEAD_LIFT * 0.6)):
        pb = rig.pose.bones[bone]
        pb.rotation_quaternion = pb.rotation_quaternion @ Matrix.Rotation(math.radians(deg), 4, "X").to_quaternion()
    bpy.context.view_layer.update()


def bone_world(rig, name, tail=False):
    pb = rig.pose.bones[name]
    return rig.matrix_world @ (pb.tail if tail else pb.head)


# --- Disc prop --------------------------------------------------------------------

def make_disc():
    ob = C.cylinder("held_disc", 0.13, 0.03, (0, 0, 0), C.toon(C.NEON_PINK, 0.7), verts=24, ink=0)
    C.outline(ob, thickness=INK_M * 0.8)
    return ob


def place_disc(disc, rig, show):
    disc.hide_render = not show
    if not show:
        return
    hand = rig.pose.bones["mixamorig:RightHand"]
    m = rig.matrix_world @ hand.matrix
    disc.matrix_world = m @ Matrix.Translation((0, 0.09, 0.03)) @ Matrix.Rotation(math.radians(90), 4, "Z")


# --- Rendering ---------------------------------------------------------------------

def render(path):
    scene = bpy.context.scene
    scene.render.filepath = path
    scene.render.image_settings.file_format = "WEBP" if path.endswith(".webp") else "PNG"
    if path.endswith(".webp"):
        scene.render.image_settings.quality = 92
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.render.render(write_still=True)


def render_frames(cid, design, tmp):
    clear_scene()
    scene = setup_scene()
    cam = setup_camera(scene)
    if cid in M.MODELS:
        model_lighting(scene)
        body, rig, pieces = build_model(cid)
    else:
        C.sun("key", 3.4, (55, 0, 48))
        body, rig, pieces = build(design)
    # MPFB bodies face -Y; turn to face the net (+X), then toward the camera.
    rig.rotation_euler = (0, 0, math.radians(90 - YAW))
    disc = make_disc()
    frames = []
    anims = {}
    only = [a for a in os.environ.get("HD_ONLY", "").split(",") if a]
    for name, clip, picks, loop, extra in ANIMATIONS:
        if only and name not in only:
            continue
        action = load_action(clip, rig)
        start = len(frames)
        for i, (src_frame, _ticks) in enumerate(picks):
            pose_rig(scene, rig, action, src_frame)
            holding = extra.get("disc") or i < extra.get("disc_until", -1) or i >= extra.get("disc_from", 99)
            place_disc(disc, rig, bool(holding))
            path = os.path.join(tmp, f"{cid}_{len(frames):03d}.png")
            render(path)
            hand = bone_world(rig, "mixamorig:RightHand")
            head = bone_world(rig, "mixamorig:HeadTop_End") if "mixamorig:HeadTop_End" in rig.pose.bones \
                else bone_world(rig, "mixamorig:Head", tail=True)
            frames.append({"path": path, "hand": to_pixel(scene, cam, hand),
                           "head": to_pixel(scene, cam, head + Vector((0, 0, 0.12))),
                           "air": i in extra.get("air", [])})
        anims[name] = {"start": start, "count": len(picks), "fps": 60.0 / max(1, picks[0][1]), "loop": loop,
                       "ticks": [t for _f, t in picks]}
    anchor = to_pixel(scene, cam, (0, 0, 0))
    return frames, anims, anchor


def render_stills(cid, design, out_dir=OUT):
    """HUD portrait (head and shoulders) and character-select pose."""
    clear_scene()
    scene = setup_scene()
    if cid in M.MODELS:
        model_lighting(scene)
        body, rig, pieces = build_model(cid)
    else:
        C.sun("key", 3.4, (55, 0, 48))
        body, rig, pieces = build(design)
    rig.rotation_euler = (0, 0, math.radians(90 - YAW))
    pose_rig(scene, rig, load_action("bouncing_fight_idle", rig), 1)
    head = bone_world(rig, "mixamorig:Head")
    cam = setup_camera(scene, size=640, ortho=0.62, target_z=head.z + 0.06, pitch=8)
    cam.location.x += head.x
    cam.location.y += head.y
    render(os.path.join(out_dir, f"{cid}_portrait.webp"))
    bpy.data.objects.remove(cam, do_unlink=True)
    disc = make_disc()
    pose_rig(scene, rig, load_action("frisbee_throw", rig), 30)
    place_disc(disc, rig, True)
    setup_camera(scene, size=800, ortho=2.3, target_z=1.0, pitch=12)
    render(os.path.join(out_dir, f"{cid}_select.webp"))


def pack(cid, frames, anims, anchor, out_dir=OUT):
    rows = math.ceil(len(frames) / COLUMNS)
    sheet = np.zeros((rows * FRAME, COLUMNS * FRAME, 4), dtype=np.float32)
    for i, f in enumerate(frames):
        img = bpy.data.images.load(f["path"])
        px = np.empty(FRAME * FRAME * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(FRAME, FRAME, 4)
        r, c = divmod(i, COLUMNS)
        y0 = (rows - 1 - r) * FRAME
        sheet[y0:y0 + FRAME, c * FRAME:(c + 1) * FRAME] = px
        bpy.data.images.remove(img)
    out = bpy.data.images.new(cid, COLUMNS * FRAME, rows * FRAME, alpha=True)
    out.pixels.foreach_set(sheet.ravel())
    os.makedirs(out_dir, exist_ok=True)
    out.filepath_raw = os.path.join(out_dir, f"{cid}.webp")
    out.file_format = "WEBP"
    out.save(quality=92)
    meta = {
        "frame_size": FRAME, "columns": COLUMNS, "anchor": anchor,
        "frames": [{"hand": f["hand"], "head": f["head"], "air": f["air"]} for f in frames],
        "animations": anims,
    }
    with open(os.path.join(out_dir, f"{cid}.json"), "w") as fh:
        json.dump(meta, fh, indent=1)


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    preview = "--preview" in args
    wanted = [a for a in args if not a.startswith("--")]
    tmp = os.path.join(os.environ.get("TEMP", "/tmp"), "hyperdisc_hd_frames")
    os.makedirs(tmp, exist_ok=True)
    for cid, design in DESIGNS.items():
        if wanted and cid not in wanted:
            continue
        frames, anims, anchor = render_frames(cid, design, tmp)
        pack(cid, frames, anims, anchor, PREVIEW if preview else OUT)
        render_stills(cid, design, PREVIEW if preview else OUT)
        print("rendered", cid, len(frames), "frames")
