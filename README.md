# HyperDisc Arena

Arcade disc duel in the style of Windjammers 2, with an 80s Outrun look.
Built in Godot 4.7 (Compatibility renderer); every piece of art is rendered
from scripts in Blender.

## Test builds

Every push to `main` builds the game and publishes it:

- **Play in the browser:** https://ryshoe8.github.io/hyperdisc-arena/
- **Downloads (Windows, macOS, Linux):** the `latest-build` release on GitHub

Pull requests build too; their zips are attached to the workflow run under Actions.

## Play locally

Open the folder in Godot 4.7 and press F5.

## Controls

Controllers are the primary input. Player 1 is the first controller plus the
keyboard; player 2 is the second controller. Controllers can be plugged in or
out at any time, and unplugging one mid-match pauses the game. Every action
can be rebound per player, for controller and keyboard, under
**Options > Controls**.

| Action | Controller (Xbox / PlayStation) | Keyboard P1 | Keyboard P2 |
| --- | --- | --- | --- |
| Move / aim | Left stick or D-pad | WASD | Arrows |
| Throw (holding), dash (moving), block (standing still) | A / Cross | J | Numpad 1 |
| Lob (holding), drop shot (as it arrives) | B / Circle | K | Numpad 2 |
| Jump (catch lobs in the air) | X / Square | L | Numpad 3 |
| Slap shot (as it arrives), EX shot (holding, gauge full) | Y / Triangle or RB / R1 | I | Numpad 5 |
| Pause | Start / Options | Esc or Enter | Backspace |

Moves that combine buttons:

- **Curve:** quarter-circle (down, down-forward, forward) then throw.
- **Supersonic:** throw the instant you catch.
- **Smash:** throw while in the air.
- **Special:** stand on the landing marker of an airborne disc until it
  charges, catch it, then throw. Lob instead for a super lob that lands and
  spins on like a buzzsaw.
- **Power toss:** EX gauge full, press throw and lob together as the disc
  comes in to flip it up over yourself.

The pause menu has the full move list, using your current buttons.

## Rules

Windjammers 2 rules: sets last 90 seconds or until someone reaches 15
points; best of three sets; a drawn set counts for both; still level after
three sets goes to sudden death. Goals score 3 or 5 depending on where they
hit the back wall; an airborne disc landing on your side gives the opponent
2. The player who conceded serves. Each set opens with the referee tossing
the disc in.

Six courts, with their own sizes and rules: Beach (small), Lawn, Tiled
(small; 5-point zones at the edges), Concrete (reversed zones, barriers),
Clay (mid-court barriers) and Stadium (the 5-point zone grows with each
straight point).

Six characters on a speed-versus-power line, each with a special throw:
Mick Magnum (balanced; Danger Zone loop), Tiffany Seasons (speed; Riptide
snake shot), Pete Pelican (power; Pelican Dive ricochet), plus three
placeholders for the disc gang (wall burner, zigzag, cannon).

## Art and sound

All art is made by Blender scripts in `tools/blender/` and saved as WebP:

```
blender -b --factory-startup -P tools/blender/make_courts.py      [-- court_id ...]
blender -b --factory-startup -P tools/blender/make_characters.py  [-- character_id ...]
blender -b --factory-startup -P tools/blender/make_logo.py
```

Courts and characters are cel-shaded with ink outlines. `data/projection.json`
defines the camera used by both Blender and the game, so sprites land exactly
on the rendered courts. Character sheets come with a JSON file giving each
animation's frames and the hand and head position in every frame.

Fonts: Bangers and Russo One (SIL Open Font License, see `assets/fonts/OFL-*`),
Kenney Future (CC0). Sound: Kenney Interface Sounds (CC0, see
`assets/LICENSE-kenney.txt`).

## Layout

| Path | What it is |
| --- | --- |
| `data/balance.json` | Every gameplay number: courts, scoring, throws, defence, specials, EX gauge, characters, CPU |
| `data/projection.json` | The shared camera: scale, pitch and screen placement of the court |
| `scripts/sim/match_sim.gd` | The rules. Fixed 60 Hz ticks, no nodes or rendering, so matches can be re-simulated for rollback netcode later |
| `scripts/sim/cpu_player.gd` | CPU opponent; produces the same inputs a controller would |
| `scripts/game/main.gd` | Every screen: title, menus, select screens, match loop, pause, options, results |
| `scripts/game/view/` | Match drawing (court, players, disc, effects, HUD), projection, character sprite sheets |
| `scripts/game/ui/theme.gd` | Palette, fonts, panels and the animated Outrun background |
| `scripts/game/controls.gd` | Controller and keyboard input: player slots, hot-plugging, rebinding, 8-way stick, rumble |
| `scripts/game/settings.gd` | Graphics, audio and control settings, saved to `user://settings.cfg` |
| `tools/blender/` | Scripts that render the courts, characters and logo |
| `export_presets.cfg`, `.github/workflows/build.yml` | Web, Windows, macOS and Linux exports, built on every push |
| `site/index.html` | Test-build landing page |
| `tests/run_tests.gd` | Headless rules tests |

## Tests

```
godot --headless --import
godot --headless --script res://tests/run_tests.gd
```

## Developer shortcuts

Pass these after `--` when launching the game, e.g.
`godot -- --demo --court=3 --p1=0 --p2=2`:

- `--demo` CPU plays CPU straight away (also an attract mode)
- `--court=N --p1=N --p2=N --difficulty=N` pick the court, characters and CPU level
- `--screen=title|main|select|court|vs|options` open a screen directly
- `--shots=60,240 --out=DIR` save screenshots at those ticks, then quit
