# Pixel arena pass

Six original environment edits generated with the built-in image tool, saved as assets/art/courts/{beach,lawn,tiled,concrete,clay,stadium}_pixel.png. The original Blender backgrounds remain available as fallback assets.

Prompt set: preserve each source arena orthographic composition, rectangular court, service lines, central divider and goal locations; render premium 1990s arcade pixel clusters and stepped shading with 1980s Outrun accents. Detail belongs outside the playing surface; no players, discs, new obstacles or HUD. Themes: boardwalk beach, lawn country club, Miami pool resort, neon urban rooftop, Mediterranean terracotta club, indoor neon stadium. Clay received a targeted top-boundary alignment correction against the original source.

Runtime scales the generated scenes to the existing 1920x1080 projection. Court selection uses the same artwork as matches. New spectators are baked into these first-pass backgrounds; the incompatible old 3D animated crowd overlay is skipped. Goal-zone lights, barriers, disc effects and rules continue to come from the game renderer and simulation. Dedicated pixel crowd animation, referee art and barrier art remain future polish.

Checked live match captures across all six courts. Windows test export: build/pixel-test/windows/HyperDiscArena.exe.

## Reactive pixel spectators
Built-in image generation produced tools/art/spectator-source.png: three original spectators, four poses each (watch, clap, raised arms, surprise), transparent pixel-art sheet. Prompt matches arcade neon palette, full-body same-person pose continuity, no scenery/text. build_pixel_crowd.gd packs component-isolated sprites into assets/art/courts/pixel_spectators.png. PixelCrowd adds animated front rows to all six arenas while static deeper spectators remain in background art. Match events drive applause, surprise, goals, set wins and 8-second match victories; priority prevents weak events interrupting celebrations. Staggered phases, foot-aligned sprites. Reaction transitions and atlas load tested; two in-game celebration captures checked. Dedicated full-background crowd animation remains further polish.


## Pixel referee and disc
Built-in image generation created the original six-pose referee source (watch, service toss, point award), with transparent background and navy/ivory arcade officiating clothes. build_pixel_referee.gd packs foot-aligned sprites into referee.webp with idle/lob/win mappings. The disc prompt specifies a face-on stepped ivory rim, magenta ring and teal hub, transparent background, readable at gameplay scale. assets/art/disc/hyperdisc.png replaces the procedural disc surface while retaining height squash, spin and power tint. Full Godot tests and Windows export passed; match captures verified the referee integration.


## Crowd composed with the arenas (supersedes separate spectator overlays)
The generic standing-character overlay was rejected for incorrect seating scale, overlap and repetition. Built-in image generation rebuilt all six *_pixel.png backgrounds with varied seated audience members composed directly into benches, terraces and chairs. Prompt preserves the court and architecture, keeps aisles clear, uses inward-facing side spectators and rear views in near stands, and varies age, hair, hats, body shape and clothes.

Three identity-preserving edits per arena create applause, celebration and surprise frames in assets/art/crowds/{court}_{clap,cheer,surprise}.png. Prompt changes only audience arms/faces and preserves individual identities, seat positions, clothes and scenery. PixelCrowd draws these authored reaction regions over the base arena, with separate section timing and priority for goals/set/match wins. The playing surface always comes from the base artwork. Crowds are animation frames of the arena composition, not randomly placed standalone dolls. Individual autonomous agents are not used. Rejected standalone sprite experiments are archived in D:/Hyperdisc Arena/refs/crowd-experiments.

## Continuous arena activity
living_arena.gdshader uses seated crowd cells with independent seeded idle/clap beats, delayed reactions, slight anchored head/shoulder movement and cosmetic rally tracking. No rigid character is translated to a new seat. Pool/ocean highlights, outer foliage, beach bunting and rooftop/stadium neon receive small perimeter-only animation. Canvas backdrop renders behind the match/HUD and hides when leaving the match; RIDs are freed with the view. Cosmetic effects do not change rollback state. Full Godot tests passed; native shader/crowd captures checked on all six courts.
Gesture frames switch coherently by seating block to avoid slicing arms/faces between authored poses. Independent cell motion remains subtle and anchored; reaction timing varies across blocks. Native stadium match and return-to-menu captures verified correct backdrop layering and cleanup.
