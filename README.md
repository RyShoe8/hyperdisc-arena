# Hyperdisc Arena

Arcade disc duel built in Godot 4.5 (Compatibility renderer). This is the
single-player prototype: coloured boxes, full core rules, one CPU opponent.

## Test builds

Every push to `main` builds the game and publishes it:

- **Play in the browser:** https://ryshoe8.github.io/hyperdisc-arena/
- **Downloads (Windows, macOS, Linux):** the `latest-build` release on GitHub

Pushes to other branches build too; their zips are attached to the workflow run under Actions.

## Play locally

Open the folder in Godot 4.5 and press F5.

## Controls

Controllers are the primary input. Player 1 is the first controller plus the
keyboard; player 2 is the second controller. Controllers can be plugged in or
out at any time, and unplugging one mid-match pauses the game.

| Action | Controller | Keyboard P1 | Keyboard P2 |
| --- | --- | --- | --- |
| Move / aim | Left stick or D-pad | WASD | Arrows |
| Throw (holding) / dash (not holding) | A or X | J | Numpad 1 |
| Lob | B or Y | K | Numpad 2 |
| Curve throw | Quarter-circle (down, down-forward, forward) then A | Same with WASD then J | |
| Pause | Start | Esc | Backspace |

Menu: up/down picks a row, left/right changes it, A or Enter starts. In
"VS PLAYER 2" mode, player 2 picks their own character with their stick.
Catches, goals and supersonic throws rumble the controller.

## Layout

| Path | What it is |
| --- | --- |
| `data/balance.json` | Every gameplay number: court, scoring, throws, lobs, knockback, characters, CPU difficulty |
| `scripts/sim/match_sim.gd` | The rules. Fixed 60 Hz ticks, no nodes or rendering, so matches can be re-simulated for rollback netcode later |
| `scripts/sim/cpu_player.gd` | CPU opponent; produces the same inputs a controller would |
| `scripts/game/main.gd` | Menu, match loop, pause and placeholder drawing |
| `scripts/game/controls.gd` | Controller and keyboard input: player slots, hot-plugging, deadzone, 8-way stick, rumble |
| `export_presets.cfg`, `.github/workflows/build.yml` | Web, Windows, macOS and Linux exports, built on every push |
| `site/index.html` | Test-build landing page with the Play button |
| `tests/run_tests.gd` | Headless rules tests |

## Tests

```
godot --headless --import
godot --headless --script res://tests/run_tests.gd
```

## Implemented so far

Movement, dash, straight and angled throws, quarter-circle curves, lobs with a
landing marker, catching, knockback (light characters slide further; being
pushed into your own goal while holding scores for the thrower), hold limit
with throw-speed decay, supersonic instant throws, rally speed-up, 3/5-point
goal zones, 2-point misses, loser serves, 30-second sets to 12 points, best of
3 sets, drawn sets, sudden death, six character archetypes, three CPU levels.

Not yet: blocking/tossing, special throws and charging, jump, slap shot, drop
shot, EX gauge, the six court variants, bonus games, art and audio.
