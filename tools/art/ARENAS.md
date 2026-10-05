# Pixel arena pass

Six original environment edits generated with the built-in image tool, saved as assets/art/courts/{beach,lawn,tiled,concrete,clay,stadium}_pixel.png. The original Blender backgrounds remain available as fallback assets.

Prompt set: preserve each source arena orthographic composition, rectangular court, service lines, central divider and goal locations; render premium 1990s arcade pixel clusters and stepped shading with 1980s Outrun accents. Detail belongs outside the playing surface; no players, discs, new obstacles or HUD. Themes: boardwalk beach, lawn country club, Miami pool resort, neon urban rooftop, Mediterranean terracotta club, indoor neon stadium. Clay received a targeted top-boundary alignment correction against the original source.

Runtime scales the generated scenes to the existing 1920x1080 projection. Court selection uses the same artwork as matches. New spectators are baked into these first-pass backgrounds; the incompatible old 3D animated crowd overlay is skipped. Goal-zone lights, barriers, disc effects and rules continue to come from the game renderer and simulation. Dedicated pixel crowd animation, referee art and barrier art remain future polish.

Checked live match captures across all six courts. Windows test export: build/pixel-test/windows/HyperDiscArena.exe.

## Reactive pixel spectators
Built-in image generation produced tools/art/spectator-source.png: three original spectators, four poses each (watch, clap, raised arms, surprise), transparent pixel-art sheet. Prompt matches arcade neon palette, full-body same-person pose continuity, no scenery/text. build_pixel_crowd.gd packs component-isolated sprites into assets/art/courts/pixel_spectators.png. PixelCrowd adds animated front rows to all six arenas while static deeper spectators remain in background art. Match events drive applause, surprise, goals, set wins and 8-second match victories; priority prevents weak events interrupting celebrations. Staggered phases, foot-aligned sprites. Reaction transitions and atlas load tested; two in-game celebration captures checked. Dedicated full-background crowd animation remains further polish.


## Pixel referee and disc
Built-in image generation created the original six-pose referee source (watch, service toss, point award), with transparent background and navy/ivory arcade officiating clothes. build_pixel_referee.gd packs foot-aligned sprites into referee.webp with idle/lob/win mappings. The disc prompt specifies a face-on stepped ivory rim, magenta ring and teal hub, transparent background, readable at gameplay scale. assets/art/disc/hyperdisc.png replaces the procedural disc surface while retaining height squash, spin and power tint. Full Godot tests and Windows export passed; match captures verified the referee integration.

