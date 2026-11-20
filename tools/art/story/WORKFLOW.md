# Beach prologue

The tone is **sincere 1980s action melodrama applied to an absurd situation**.
Nobody knows they are in a comedy. Mick believes his ridiculous résumé deserves
respect; Pete considers the impossible fuel-transfer anecdote sacred history.
Use committed poses and dry reaction holds. Avoid rubbery movement, constant
bobbing, comic ragdolls, winking, or gag sound effects. Tango's injury is sincere
and non-graphic. Mick's final vow gets excessive, completely earnest gravity.

## Source and editing

- `data/story_prologue.json` contains the supplied story and dialogue.
- The existing `assets/art/characters/*.webp` atlases remain unchanged.
- `assets/art/story` contains the painted set, rescue props and additional
  interaction poses based on the existing cast. `art-prompts.json` records the
  built-in image-generation prompts. These are scene assets, not story slides.
- `prepare_cast.py` extracts those pixels and creates tight skin grids.
- `acting.mjs` authors native Rigby bones, skin weights and performances.
- `blocking.mjs` directs action, reactions, entrances and exits.
- `build.mjs` writes editable `projects/*.rigby` files and evaluates the
  timeline with Rigby's own `Skeleton`/`Pose` implementation.
- Godot consumes `data/story_rigby.json`; it doesn't invent additional bone
  animation. Runtime props attach to the evaluated wrists.

Standing performances keep the lower body rigid. Do not reintroduce crouching
by compressing the standing mesh: that caused reversed knees and rubbery hips.
Mick's kneel uses the existing drawn frame 9 with restrained upper-body acting.
Use the drawn stride frames for travel. Rigby blends compatible acting clips;
different silhouettes change at deliberate cuts.

Stair descent uses a continuous native Rigby mesh with two-bone leg constraints,
forward-bending knees, and separate sole contacts. `stairs.mjs` records the eight
painted treads and the final sand landing. One foot stays planted while the other
clears the next tread; the palm follows the diagonal rail. The six source poses
remain available as art references, rather than jumping between whole sprites.
The near rail is a separate foreground depth layer sampled from the painting.
Tiffany and her neck whistle pass behind its wood, in front of the far rail.
Ponytail wind is a Rigby bone track; restrained skin highlights use a sunlight
shader that preserves vertex tint/alpha (including the contact shadow).
Vanessa's rail mesh locks the supported
palm and feet while the head and torso perform. Do not allow the gang's older
laugh/listen clips to override that contact. Tango has a look-back pose before
his protective jump. The wider throwing lane must remain clear: Tiffany moves
behind Mick and the gang steps behind Keno. The disc's unobstructed trajectory
intersects Mick's evaluated head position; Tango crosses it first.

Run clip playback is derived from distance, duration and stride span rather
than a single global speed. Props use evaluated atlas markers or mesh anchors;
the kneeling mesh has its own anchors. The initial ball catch, rail contact,
throw direction, recognition beat and balloon text preservation have assertions.
The stair checks also verify every tread landing, forward knee bends, reachable
ankles, and nonzero scale when an actor changes facing. The descent has a closer
tracking shot; foreground arrivals wait until Tiffany has cleared the stairs.

## Rebuild and review

Run from the repository root, with Rigby 0.5.1 at `build/rigby-tool`:

```
python tools/art/story/prepare_cast.py
node tools/art/story/build.mjs
python tools/art/story/score.py
node tools/art/story/build.mjs
```

The second build bundles the regenerated score into the editable stage project.
Import updated resources with Godot before running previews.

```
godot --path . --script tools/preview_story_acting.gd
godot --path . --script tools/preview_prologue.gd
godot --headless --path . --script tests/test_story_prologue.gd
python tools/art/story/check_motion.py
python tools/art/story/render.py --tower
python tools/art/story/render.py --reel
python tools/art/story/render.py
```

`render.py --godot <path>` accepts a different Godot executable. Video encoding
requires Python `imageio_ffmpeg`; score generation also requires NumPy. Movies
stream to the local encoder and don't leave huge intermediate AVI files.
Captures default to 1920x1080; use `--height 720` for quicker iteration.
The exported video includes the original score and beach ambience.

Review the actual motion, not just still screenshots. Check wrists, shoulders,
feet, silhouette changes, prop handoffs, camera cuts and the rescue lift. Check
the acting once with captions hidden: actions should still make sense. The
current soundtrack is original synthesized music; dialogue is subtitled, not
voice acted. Comic balloons split longer lines into readable pages without
discarding words. The painted beach has a time-driven surf shader: rolling
crests, breaking foam, uprush, wet sand and retreat. Dry structures are masked
out. The truck renders at its physical foreground depth; carriers load at its
tailgate. The runtime Godot compositor owns environmental effects and props;
the native Rigby project owns character poses, motion and camera direction.

Native Rigby validation passes. Its optional Spine JSON round trip reports
differences, and its binary `.skel` exporter does not support this grid topology.
Those optional exports are not used by this game; don't silently mark them as
passing.

No 3D character assets are used. The old prototypes were moved to the external
`Archived assets/retired-3d-characters-2026-11-19` folder, not permanently erased.
