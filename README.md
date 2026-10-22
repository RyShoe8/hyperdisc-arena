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

## Play modes

Main menu: **Story, 2 Player, Multiplayer, Tutorial, Mixtapes, Quit**.
Start / Options on the main menu opens settings (graphics, audio, controls and
move list). Settings also remains available while paused. Quit is omitted in
browser builds.

- **Story:** Continue, New Story, or Quick Match vs CPU. Story faces the roster
  sequentially with a 10% CPU skill increase per opponent and saves after wins.
- **2 Player:** Head to Head (local 1v1) or Team Up vs CPU (both humans on the
  same side in doubles). Each opens one setup screen for characters, court,
  CPU difficulty and player assignments.
- **Multiplayer:** Local Doubles (up to four humans, with CPU fill) or Online
  Lobbies. Online retains host/join, public lobby, friends/invites and direct
  LAN/address connections. Choose singles/doubles inside the online lobby.
  Browser builds show local doubles; online explains that the desktop game is
  required. Online doubles uses two machines with a local or CPU partner per
  machine; four independent clients are not supported.
- **Tutorial:** Interactive Move Lessons or Doubles Basics.
- **Mixtapes:** the existing music library and deck editor.

Local setup: up/down chooses a row; left/right changes its value. On a fighter
row, the menu action button cycles CPU / Player 1-4, skipping players already assigned. Extra
controllers can press Start to join an empty CPU slot. Back returns to the
submenu that opened setup. Team A uses slots 1/3, Team B uses 2/4.

Doubles uses one disc, shared scoring, independent power meters, and existing
set rules. Teammates can move through each other. CPU partners cover separate
lanes. Passing is not included. Online peers must use the same updated build.

Verify with Godot `--headless --path . --script tests/test_modes.gd`.

## Controls

Controllers are the primary input. Player 1 is the first controller plus the
keyboard; players 2–4 use the remaining controllers (players 1–2 also have keyboard bindings). Controllers can be plugged in or
out at any time, and unplugging one mid-match pauses the game. Every action
can be rebound per player, for controller and keyboard, under
**Options > Controls**.

| Action | Controller (Xbox / PlayStation) | Keyboard P1 | Keyboard P2 |
| --- | --- | --- | --- |
| Move / aim | Left stick or D-pad | WASD | Arrows |
| Throw (holding), dash (moving), block (standing still) | A / Cross | J | Numpad 1 |
| Lob (holding), drop shot (as it arrives) | B / Circle | K | Numpad 2 |
| Menu action (menus only) | X / Square | L | Numpad 3 |
| Slap shot (as it arrives), power throw (holding, meter full) | Y / Triangle or RB / R1 | I | Numpad 5 |
| Pause | Start / Options | Esc or Enter | Backspace |

Moves that combine buttons:

- **Curve:** quarter-circle (down, down-forward, forward) then throw.
- **Supersonic:** throw the instant you catch.
- **Smash:** throw while in the air.
- **Special:** stand on the landing marker of an airborne disc until it
  charges, catch it, then throw. Lob instead for a super lob that lands and
  spins on like a buzzsaw.
- **Power toss:** power meter full, press throw and lob together as the disc
  comes in to flip it up over yourself.

The pause menu has the full move list, using your current buttons.
**Options > Moves** and **Pause > Move list** also have a looping video for
every move. Use up/down to pick one; the bot's input and timing captions
follow your current controller or keyboard labels. Clips are included in
the download, so playback also works offline.

## Tutorial

Choose **Tutorial** from the main menu for 16 interactive exercises. Each
lesson explains one move, shows the controller buttons and stick motion,
and verifies the move using the real match simulation before unlocking
the next lesson. Prompts follow your controller labels and custom bindings;
keyboard input switches prompts to your keys.

Defensive drills show the actual move radius and a live **PRESS NOW** cue.
Quick returns show the remaining held-disc time. Jumping and aerial
move drills have been removed; dive with a direction plus Throw. Failed attempts can be retried
without advancing. Progress resumes at the next unlocked lesson when you
reopen the tutorial. Start / Options / Escape exits at any time.

For visual checks, `--tutorial=N` after Godot's `--` opens a particular
exercise (zero-based), and works with the existing `--shots` / `--out` flags.

To regenerate the 16 move clips after a rules or art change:

1. Run Godot with `--path . --script tools/capture_moves.gd -- --out=ABSOLUTE_DIR`.
2. Run Godot with `--headless --path . --script tools/build_move_timelines.gd -- --out=ABSOLUTE_DIR`.
3. Run `python tools/encode_moves.py ABSOLUTE_DIR` (requires `imageio-ffmpeg`,
   or pass `--ffmpeg PATH`). This writes silent 640x360, 30 fps Theora clips
   and their input timelines to `assets/moves`. Clip files use Git LFS.

## Online play (Windows)

**Online** in the main menu: **Host room** gives you a code to share and
your friend picks **Join room** and types it; it works over the internet
with no router setup (PlayBound Connect, WebRTC). **Sign in with PlayBound**
adds your friends list and in-game match invites. LAN and join-by-address
are there too. Both players pick, the host picks the court and starts.
Matches use rollback netcode, so they stay responsive over normal internet
latency. See [docs/ONLINE.md](docs/ONLINE.md) for how it works.

No controller? **Options > Controls > Phone as controller** shows a QR code:
scan it and your phone becomes a gamepad through PlayBound (no app or account).

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
| `scripts/net/` | Online: rollback session, lobby, transports (WebRTC rooms, UDP, simulated), PlayBound client (sign-in, friends, presence, invites, rooms), direct connect |
| `scripts/game/online_screens.gd` | Online menu, PlayBound sign-in, friends and invites, rooms / LAN, lobby and the online match loop |
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
- `--phone` opens the phone-as-controller QR code
- `--screen=title|main|select|court|vs|options|online|friends` open a screen directly
- `--shots=60,240 --out=DIR` save screenshots at those ticks, then quit
- `--host[=port]`, `--join=address`, `--host-room`, `--join-room=CODE`,
  `--playbound-api=URL`, `--bot`, `--name=NAME`, `--netlag=MS`,
  `--netloss=PERCENT`, `--quit-after-match` drive online play from the command
  line (two CPU-controlled instances can play each other; see docs/ONLINE.md)
