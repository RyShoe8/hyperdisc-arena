# Hyperdisc Arena

Arcade disc duel built in Godot 4.5 (Compatibility renderer). This is the
single-player prototype: coloured boxes, full core rules, one CPU opponent.

## Play

Open the folder in Godot 4.5 and press F5.

| Action | Keyboard (P1) | Controller |
| --- | --- | --- |
| Move / aim | WASD | Left stick or D-pad |
| Throw (holding) / dash (not holding) | J | A / Cross |
| Lob | K | B / Circle |
| Curve throw | Quarter-circle (down, down-forward, forward) then J | Same motion then A |

Menu: left/right picks a character, up/down picks CPU difficulty, Enter or A starts.

## Layout

| Path | What it is |
| --- | --- |
| `data/balance.json` | Every gameplay number: court, scoring, throws, lobs, knockback, characters, CPU difficulty |
| `scripts/sim/match_sim.gd` | The rules. Fixed 60 Hz ticks, no nodes or rendering, so matches can be re-simulated for rollback netcode later |
| `scripts/sim/cpu_player.gd` | CPU opponent; produces the same inputs a controller would |
| `scripts/game/main.gd` | Menu, match loop and placeholder drawing |
| `scripts/game/input_setup.gd` | Keyboard and controller bindings for players 1 and 2 |
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
