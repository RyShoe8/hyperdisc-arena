# Court and crowd workflow

## Current state
Twelve spectators across the bar court have registered watch/applause/cheer poses; two also have quiet drinking gestures. All six venues have registered environmental lighting/water animation. Other spectators remain static until their own poses are authored and reviewed. Do not claim complete crowd coverage. No random replacement sprites or whole-scene deformation is enabled.

## Sources of truth
- `assets/art/courts/*_pixel.png`: current composed court backgrounds.
- `tools/art/venues/*-empty.png`: matching source artwork (legacy filenames; these contain seated crowds).
- `tools/art/venues/calibration.json`: authored wall edges and court registration.
- `tools/art/venues/approved.json`: SHA-256 baseline for all six court backgrounds and calibration.
- `tools/art/venues/crowd/<court>.json`: individual fan IDs, exact source-pixel rectangles, source revision, team, reaction delay, tempo and energy.
- `<court>-clap.png` / `<court>-cheer.png`: candidate pose sources. Never use these full images as gameplay backgrounds.
- `assets/art/crowds/composed/`: generated runtime patches and manifests.

## Incremental authoring
1. Select an existing spectator from the current composed background. Keep their identity, clothes, facing direction and seat anchor. Add a stable fan ID and a non-overlapping patch rectangle with room for all approved poses. Keep rails, neighbors and court outside it.
2. Generate/edit candidate poses from that exact background, changing only the selected people. Save candidates separately. Do not regenerate the arena to animate its crowd.
3. Inspect each pose for anatomy, identity, clipping, and background drift INSIDE its patch. Automated isolation does not detect a wrong arm or a changed bottle inside an allowed rectangle.
4. Build into staging:
   `Godot --headless --path . --script tools/art/pack_crowd.gd`
   The builder rejects changed court/calibration hashes, wrong dimensions, overlapping patches and stale registration. It writes only `build/crowd/` by default.
5. After inspecting staging, explicitly publish the patches locally:
   `Godot --headless --path . --script tools/art/pack_crowd.gd -- --promote`
   This copies only crowd atlas/manifest files, never court backgrounds or geometry. Reimport using Godot editor/headless import.
6. Run `tests/run_tests.gd`, `tests/test_court_projection.gd` and `tools/preview_authored_crowd.gd`. The render preview checks all changed pixels stay within registered fan rectangles (2-pixel filtering allowance). Review `build/crowd/review.html` for motion, and the six court screenshots from `tools/preview_story_venues.gd` for composition.
7. Commit source poses, manifests, generated patches and relevant code together. Keep the previous revision recoverable in Git. Never silently update the baseline just to make validation pass.

## Court revisions
Make proposed art changes as separate candidates first. Review against the existing court, including scoring edges, referee, net, entrances and players. Deliberately update calibration only if geometry changes. Re-register/review affected fans and then update baseline hashes. The old venue packer now stages calibration in `build/venues/`; it cannot silently overwrite runtime geometry.

Runtime checks the decoded background fingerprint before loading patches, including exported builds. A mismatched patch set is disabled rather than drawn in the wrong position. Approved poses are selected without moving/scaling scene rectangles; each fan has independent timing and team allegiance. Higher-priority score reactions survive lower-priority rally events.

Next art passes: add anticipation/disappointment and more idle poses, intermediate animation frames, then additional individually reviewed fans and courts. Walking spectators need an authored clean background and foreground occlusion layer first; do not slide patches containing scenery around the image.

## Environment animation
`ambience.json` stores named regions in 512x288 source coordinates. Water, lanterns, neon and beacons modify illumination only; the shader never offsets texture coordinates. No generic fixtures are placed over the walls. Background and fan patches use separate canvas materials, so fixture effects cannot distort fan sprite sheets.

Build with `tools/art/pack_ambience.gd`; inspect the staged file in `build/venues/`, then use `-- --promote` to update `data/venue_ambience.json`. Baseline checks apply here too. `tools/preview_venue_life.gd` renders all six venues and checks every changing pixel lies within the registered fixture regions. Review `build/venue-life/review.html`. Crowd isolation disables ambient animation so each layer is tested separately.

Per-fan `sources` overrides preserve existing pose sources when expanding a crowd. Do not regenerate already reviewed spectators just because another spectator is being added. Optional `idle_pose`, `idle_period` and `idle_offset` control quiet gestures; high rally excitement suppresses them. Every fan rect must contain the complete pose without covering neighbors. Use a clean background and foreground masks before adding wider movement.
