# Character animation pipeline

## Canonical source

Each of the six approved characters has an immutable `characters/<id>/base-v1/`:

- `base.png`: exact pixels cropped from the approved in-game idle pose.
- `reference.png`: idle, run, throw and catch in a 2x2 sheet, integer-scaled without repainting.
- `origin.json`: source commit, atlas frame indices and crop bounds.

`characters/catalog.json` records SHA-256 hashes and character-specific identity locks.
Mick's magenta glasses, dog tags and cargo pockets, and Pete's glasses are mandatory.
These are **2D sprite masters**, not rigged 3D models. They cannot be rotated to reveal
unseen surfaces automatically. Drawing new angles still requires visual comparison.
Hash validation prevents reference substitution; it cannot prove a drawing matches.

## Repeatable workflow

Run PowerShell commands from the repository root:

```powershell
./tools/art/character_pipeline.ps1 -Action List
./tools/art/character_pipeline.ps1 -Action NewJob -Character mick -Animation run-directions-v2 -Frames 16 -Columns 4 -Rows 4
```

The job records the frozen base version, frame count and grid, and writes `prompt.txt`
with exact reference paths and identity requirements. Supply **both** canonical images
to the built-in image-generation tool. Inspect them first. Create a turnaround before
generating a full cycle. Compare side-by-side at game scale and enlarged pixel scale.
Do not use the rejected turn-v1 sheets as identity references.

```powershell
./tools/art/character_pipeline.ps1 -Action Submit -Character mick -Animation run-directions-v2 -Source 'C:\path\candidate.png'
./tools/art/character_pipeline.ps1 -Action Validate -Character mick -Animation run-directions-v2
```

Submission is non-destructive and stays `needs-review`. Rejected candidates get a new
job version; never replace a canonical reference to match a drifting animation.
Check all frames for face/hair, body proportions, outfit cut, accessories, palette,
pixel density, feet registration, complete limbs, and gait continuity. View against
the original run cycle in the game. Only then record acceptance:

```powershell
./tools/art/character_pipeline.ps1 -Action Accept -Character mick -Animation run-directions-v2 -ReviewNotes 'Describe actual comparisons and checks performed.'
```

Acceptance binds the review to the candidate hash. Altered candidates or bases fail
validation. It is a visual review record, not an automated likeness guarantee.

## Directional integration

`characters/directional-release.json` selects the reviewed job version per character for both `inspect-turns.ps1` and `pack_turns.gd`.
All six must be accepted before the packer writes any runtime atlas. Extraction must
find the declared frame count and layout. Runtime has a sideways-run fallback while
directional art is pending, so rejected artwork cannot appear during movement.
When advancing versions, update that manifest, preview the candidate with `inspect-turns.ps1 -Character <id> -Preview` and `tools/preview_character_identity.gd`, then accept and extract without `-Preview`.

After packing: import, run `tests/test_character_motion.gd` and `tests/run_tests.gd`,
then render `tools/preview_arena_life.gd`. Inspect actual gameplay before publishing.

## Current status

## Celebration jobs

Run `inspect-turns.ps1 -Character <id> -JobName celebration-v1` after review
(Vanessa uses `celebration-v2` for corrected transparency), then run
`pack_celebrations.gd`. Run this after `pack_turns.gd` when rebuilding both sets.
Eight authored victory poses play once and hold the final pose. The view resets
their clock on match_over; the animation never starts at an arbitrary match frame.
`tools/preview_celebrations.gd` renders all six gestures for comparison.
The built-in image generation prompts are saved beside each animation job.

## Directional status

Base-v1 masters are copied from approved build 9422b2b, not from the rejected angles.
Six corrected directional jobs have passed visual comparison and separate-frame
extraction. The selected jobs supply eight up and eight down frames per character.
Existing side runs and actions retain their frame indices. Referee tracking and
independent audience groups accompany this integration.
