# HyperDisc Arena — Design Brief

Oct 4, 2026 · @Ryan

## Name

Locked: **HyperDisc Arena** (written with a capital D). The earlier shortlist is kept below for reference only; the first pick was Overspin.

| Name | Why it works | Watch-out |
|---|---|---|
| Overspin | Names the curve shot; short, punchy, verb-able | Common sports term; check Steam and USPTO |
| Disc Royale | Instantly says disc + competition | Battle-royale connotation |
| Hot Disc | 90s arcade energy, easy to say | Generic; hard to search |
| Boardwalk Blitz | Beach / boardwalk setting, alliterative | Longer; ties the game to one theme |
| Spin Cycle | Playful, memorable | Laundry joke may undercut competitive tone |
| Slamjam | Arcade swagger, nods to the genre | Close to the Windjammers name; likely too close |

Avoid "Windjammers" and "Flying Power Disc" anywhere in the name, store page or marketing.

## Pitch and pillars

A free, fast arcade disc duel for 1v1 and 2v2: throw, curve and slam a disc past your opponent into their goal zone. Sets last 30 seconds or first to 12 points; a match is best of 3 sets. It is the first PlayBound exclusive and the free, modern home of the genre Windjammers made famous.

- **Readable in one second.** Anyone watching understands it immediately: disc goes past you, they score.
- **Easy to learn, deep to master.** Two buttons to play; timing, curves and feints separate good players.
- **Built for the couch and the party.** Local 2-4 players on one screen first; online rollback second.
- **Small and polished over big and rough.** Six characters and six courts, each tuned hard.
- **Free and fair.** No pay-to-win; any cosmetics never change hitboxes or stats.

## Base game spec (Windjammers 1994 rules)

HyperDisc Arena v1 copies the rules of Data East's Windjammers (Neo Geo, 1994) as closely as possible; only names, characters, art, audio and text are our own. Where this section and the older sections below disagree, this section wins. Numbers marked *tune* are not published anywhere and must be matched by playing the original.

### Court and camera

- Side-on 3/4 view; one player on the left half, one on the right, a low net across the centre line.
- Top and bottom walls bounce the disc. Each back wall is the goal: 3-point zones at the ends, a 5-point zone in the middle.
- A disc that hits the net, a barrier or a player's back pops up into the air; a target marker shows where it will land.

### Controls (stick + 2 buttons)

| Input | Holding the disc | Not holding the disc |
|---|---|---|
| Stick | Aims the throw (8 directions); you cannot walk while holding | Run (8 directions) |
| A | Throw. Straight, or curved if a quarter-circle (e.g. down, down-forward, forward) is entered first; each character has its own curve set | Dash / slide in the stick direction; also blocks |
| B | Lob to a target spot | — |
| A on contact, standing still | — | Block: pops the disc up into the air |
| Tap A, then a direction | — | Mini-dash that also blocks |

### Throws

- **Straight throw:** fastest option. Aim up or down to bank it off the top or bottom wall.
- **Curve throw:** quarter-circle + A; bends toward a wall. Bouncing on the outside of the curve sends it back across; on the inside it hugs the wall.
- **Lob:** high arc to a marked landing spot. Thrown immediately it lands deep on the far side; the longer you hold first, the closer to the net it lands. Uncaught, it scores 2 for the thrower.
- **Hold penalty:** you can hold the disc only a few seconds (*tune*, about 2 s), and throw speed drops sharply the longer you hold. Instant throws are the strongest.
- **Rally speed:** disc speed rises with every successive throw in a rally (*tune*).

### Defence and catching

- **Catch** by touching the disc: walk into it or dash/slide to it.
- **Knockback:** catching a strong throw pushes the catcher backward. Light characters get pushed far; a big enough mismatch carries the catcher (and disc) into their own goal.
- **Block / toss:** pressing A as the disc arrives pops it into the air instead of catching it, buying time.
- Missing an airborne disc (lob, toss or pop-up that lands on your side) gives the opponent 2 points.

### Special (super) throws

1. A disc goes into the air (your own toss, an opponent's lob, or a pop-up).
2. Stand on the landing marker; your character powers up while waiting.
3. Catch it and press A to fire your character's special throw.

Each character has one special with a unique flight path. Originals for reference, with our replacement name to design:

| Original (do not use) | Flight path | Our version |
|---|---|---|
| Fire Snake | Flaming disc snakes up and down across the court | TBD |
| Sideburner | Hugs a side wall and accelerates toward the goal | TBD |
| Rocket Diagonal | Zigzags diagonally across the court | TBD |
| Thunder Loop | Big loops, bounces hard off walls | TBD |
| Missile Throw | Rapid, forceful wall-to-wall bounces | TBD |
| Blitzkrieg | Very heavy power throw; exact path to confirm in play | TBD |

### Characters

Six characters on one speed-versus-power line: two speed, two balanced, two power. Speed = run and dash speed; power = throw speed and knockback dealt; weight = knockback taken.

| Archetype (original) | Speed | Power |
|---|---|---|
| Speed A (Mita, Japan) | Very high | Very low |
| Speed B (Miller, UK) | High | Low |
| Balanced A (Costa, Spain) | Medium | Medium |
| Balanced B (Biaggi, Italy) | Medium | Medium |
| Power A (Scott, USA) | Low | High |
| Power B (Wessel, Germany) | Very low | Very high |

Our six get new names, looks and nationalities; the stat line is kept.

### Scoring and match rules

| Event | Points |
|---|---|
| Disc enters a 3-point zone | 3 |
| Disc enters the 5-point zone | 5 |
| Airborne disc lands on your side (miss) | 2 to opponent |

- **Serve:** after every point the referee hands the disc to the player who was scored on; they serve.
- **Set:** ends when a player reaches 12 points or the timer runs out. Timer default 30 s (arcade option up to 99 s); it keeps running between points.
- **Drawn set:** each player is awarded the set.
- **Match:** best of 3 sets. Still tied after set 3: sudden death, first point wins.

### Courts (6)

| Court (original) | Size | Special rule |
|---|---|---|
| Beach | Small | Standard zones |
| Lawn | Large | Standard zones |
| Tiled | Small | Zones reversed: 5s at the edges (smaller), 3 in the middle |
| Concrete | Large | Zones reversed; barriers near the walls deflect the disc |
| Clay | Large | Barriers in the middle deflect the disc |
| Stadium | Large | 5-point zone starts tiny, grows each consecutive point you score, resets when the opponent scores |

### Single-player (arcade) mode

- One match against each other character, difficulty rising each match.
- After the 2nd win: bonus game 1, dog distance (throw, then steer a dog to catch the disc, jumping obstacles with A).
- After the 4th win: bonus game 2, disc bowling (10 frames, timed; bonus frame on a 10th-frame strike; holding B lets you slide along the throw line).

### Windjammers 2 additions (in v1)

These layer on top of the 1994 rules. Every value is a balance setting in the admin area (see [Balancing admin](#balancing-admin)).

| Mechanic | Input | What it does |
|---|---|---|
| Supersonic shot | Throw instantly after a catch | Fastest normal throw; glowing trail and a character shout. Formalises the original's instant-throw bonus |
| Jump | Jump button | Catch any airborne disc before it lands, denying the opponent's lob or pop-up |
| Smash | Any button except slap shot while airborne with the disc | Fast downward shot from a jump |
| Slap shot | Slap button as the disc arrives | Return the disc instantly without catching. Up-back / down-back = steep angle with many wall bounces; up-forward / down-forward = narrow angle toward the corners |
| Drop shot | B just before the disc arrives | Gently taps it so it drops just behind the net (a bunt) |
| Charged super moves | Stand under an airborne disc to charge, then catch | Choose: power-disc special (our version of the original specials), super lob (lands and spins forward like a buzzsaw), super spin (circle + A; hits hard, bounces confusingly), super custom (release early, choose up or down start) |
| EX gauge | Fills with offensive and defensive actions | Full gauge unlocks an EX super shot per character, near-impossible to return |
| Power toss (super reset) | A + B while not holding the disc, gauge full | Defensive: spends the gauge to flip an incoming disc into the air so you can catch or charge it. Only on your half |

**Roster and courts:** Windjammers 2 has 10 characters and 10 courts (the original six plus four new). Our target stays 6 characters and 6 courts at launch, with 4 more of each as post-launch content.

Additional sources: Windjammers 2 on Wikipedia · Windjammers France: WJ2 buttons and moves · Kakuchopurei WJ2 guide · Steam community guide · Nintendo Life review

Sources (search results; the pages themselves could not be opened from this environment, so verify by playing the original): Wikipedia · Mizuumi wiki controls · Hardcore Gaming 101 · StrategyWiki · Windjammers France: the basics · Windjammers France: subtleties · Arcade Quartermaster controls

## Modes

Launch with the six character archetypes and six courts from the base game spec above; our names, looks and special-throw names are still to design.

1. **Versus (1v1, local):** the core mode; ships first.
2. **Arcade ladder vs CPU:** one match against each character plus the two bonus games, as in the original.
3. **Online ranked and casual (1v1):** after launch, using rollback netcode.
4. **Doubles (2v2, local):** ships at launch; our own addition, outside the base rules.
5. **Party mode (later):** sabotage pickups, also our own addition.

## Art and audio

Character animation is the one place to spend real money; everything else can come from asset packs. Style: bright 2D, 90s arcade, chunky outlines, readable at a glance.

| Asset | Count | Source |
|---|---|---|
| Character sprite sheets (idle, run, dash, throw, catch, power shot, win, lose) | 6 characters x 8 states | Commission one artist so the style matches |
| Character portraits for select screen | 6 | Same artist |
| Courts (background + floor + walls) | 6 | Asset packs, recoloured; or the same artist |
| Disc, trails, impact and power-shot effects | About 15 | Godot particles + free effect packs |
| UI: menus, score, timer, fonts | 1 set | Kenney UI pack + one display font |
| Logo | 1 | Commission |
| Sound effects (throw, catch, bounce, goal, crowd) | About 30 | Sonniss GDC bundles, freesound.org |
| Music (menu + one per court) | 5 tracks | Licensed royalty-free or a commissioned chiptune artist |
| Announcer lines ("Point!", "Power shot!") | About 20 | Voice actor on Fiverr |

Prototype with coloured boxes until the gameplay feels right; commission art only after the week-4 fun test.

## Tech stack and PlayBound integration

Build in Godot 4 with GDScript, using deterministic fixed-step game logic from day one so rollback netcode can be added later without a rewrite.

| Area | Choice | Why |
|---|---|---|
| Engine | Godot 4, GDScript | Free, no royalties; strong 2D; exports Windows, Mac, Linux, web |
| Game logic | Fixed 60 Hz tick, integer or fixed-point maths, no physics engine | Deterministic, so rollback works |
| Input | Godot gamepad + keyboard; phones via PlayBound Couch Mode | Controllers first, phones as a bonus |
| Online (phase 2) | Rollback netcode (GGPO-style, e.g. a Godot rollback addon or custom) | 1v1 with tiny state is the ideal case |
| Matchmaking and accounts | PlayBound platform (Next.js) + existing hosting stack | Reuses your login, parties and friends |
| Distribution | PlayBound launcher as the exclusive; web build as a demo | Drives installs to the launcher |
| Telemetry | Launcher telemetry hooks | Match length, character picks, rage-quits |

Couch Mode already sends standard gamepad buttons from phones over WebSocket, so phone play needs no new protocol work.

### Free stack

Every piece below is free at launch scale, and most of it PlayBound already runs. Weeks 1-9 need only Godot and GitHub; online services come in after launch.

| Need | Pick | Notes |
|---|---|---|
| Engine | Godot 4.x (GDScript) | MIT license, no royalties |
| Code and builds | GitHub + GitHub Actions | Exports every platform build on each push |
| Online netcode | Godot WebRTC + custom rollback | Players connect directly; match traffic avoids our servers |
| Website, sign-in, matchmaking API | Vercel (existing PlayBound app) | New pages and API routes, no new project |
| Accounts, ratings, match history | MongoDB Atlas (existing) | Free cluster is 512 MB |
| Matchmaking queue, lobby codes | Upstash Redis (existing) | Short-lived data |
| Player connection and relay | Oracle Cloud Always Free ARM server running coturn + a small Node WebSocket service | Introduces players; relays when direct connection fails |
| Connection test (STUN) | Google public STUN server | Free |
| Build downloads | Cloudflare R2 | 10 GB free, no download fees |
| Crash reports | Sentry free tier | Godot SDK available |
| Analytics | PlayBound launcher telemetry | Already built |
| Placeholder sprites, courts, UI | Kenney packs + OpenGameArt (CC0 only) | No attribution needed |
| Sound effects | ChipTone / jsfxr + freesound.org (CC0 only) | |
| Music | OpenGameArt CC0 or Kevin MacLeod | MacLeod needs a credit line |
| Fonts | Google Fonts | OFL, fine to ship |

**Watch-out:** Oracle can reclaim idle free servers. Keep the relay in Docker so it can move to a $4/month Hetzner server in minutes.

## Balancing admin

Every gameplay number lives in a versioned balance config edited from a new PlayBound admin page, so tuning never needs a game build. The game downloads the active config at startup and caches it for offline play.

**Where:** `/admin/hyperdisc/balance` in the existing platform admin, stored in MongoDB Atlas, served to the game by a Vercel API route.

**What it edits:**

| Group | Settings |
|---|---|
| Characters | Run speed, dash distance and recovery, throw speed, curve strength, knockback dealt, weight (knockback taken), jump height, special-throw parameters |
| Throws | Base disc speed, speed gain per rally throw, supersonic window, hold-time limit and speed decay, lob arc and distance curve, slap and drop-shot timing windows |
| Specials and EX | Charge time under a lob, EX gauge gain per action, EX shot speed, power-toss cost |
| Scoring and match | Zone points per court, miss points, set length, points to win a set, sets per match, sudden death on or off |
| Courts | Size, zone widths, barrier positions, Stadium zone growth per point |
| CPU | Reaction time, aim error and special-throw frequency per difficulty level |

**How it works:**

1. Edits create a new draft version; nothing changes for players until it is published.
2. Each version has a note, author and timestamp; any older version can be restored in one click.
3. Online matches lock both players to the same config version so rollback stays deterministic.
4. A beta channel lets testers play a draft before it is published.
5. A stats panel beside the editor shows pick rate, win rate and average points per character and court from match telemetry, so changes are based on data.

## Milestones, risks and open questions

Target: a local-play launch in about 10 weeks, with online play after launch. Week 4 is the go/no-go gate.

1. **Weeks 1-2, Feel prototype:** boxes on one court; throw, curve, catch, dash, scoring; 1v1 local.
2. **Weeks 3-4, Depth and gate:** lob, perfect catch, power shots, hold rule. Gate: 5 friends play 20 minutes and ask for another match.
3. **Weeks 5-7, Content:** commission art; 6 characters, 6 courts, CPU opponent, arcade ladder.
4. **Weeks 8-9, Polish:** effects, sound, music, menus, 2v2.
5. **Week 10, Launch:** release on the PlayBound launcher with a web demo.
6. **After launch:** online rollback 1v1, ranked, party mode.

**Risks:**

- **Game feel:** if the week-4 gate fails, keep tuning before buying any art.
- **Art consistency:** one artist for all characters; agree a style sheet before starting.
- **CPU opponent:** needs to be beatable but not dumb; budget a full week.
- **Rollback complexity:** keeping logic deterministic from day one is what makes it feasible.

**Open questions:**

- [x] Final name: HyperDisc Arena (locked)
- [x] Art budget and which artist: no budget; art is made in-house with Blender (installed at `D:\Blender`) plus CC0 packs, so the commission rows in Art and audio no longer apply
- [ ] Setting: on hold until the separate lore document is written
- [x] Is 2v2 a launch feature or post-launch? Launch (local 2v2)
