# Online play

Status (Oct 4, 2026): online 1v1 works on Windows with rollback netcode.
Players connect through **PlayBound Connect rooms** (WebRTC, no port
forwarding) or directly on a LAN / by address. Signing in with a PlayBound
account adds friends, presence and match invites from inside the game.

## How it fits together

```
Menus (scripts/game/online_screens.gd)
   |
Online (autoload, scripts/net/online.gd)
   |- PlayBoundApi      (scripts/net/playbound_api.gd)    JSON over HTTPS to playbound.club
   |- PlayBoundService  (scripts/net/playbound_service.gd) sign-in, friends, presence, invites, rooms
   |- DirectService     (scripts/net/direct_service.gd)    LAN host / join by address
   |
OnlineMatch (scripts/net/online_match.gd)   handshake, version check, lobby, start, rematch
   |
RollbackSession (scripts/net/rollback_session.gd)   input delay, prediction, rollback, sync, checksums
   |
Transport interface (scripts/net/transport.gd)
   |- WebRtcTransport   PlayBound Connect room: signaling + STUN/TURN (addons/webrtc_native)
   |- UdpTransport      direct UDP (LAN / forwarded port)
   |- LoopbackTransport simulated network (tests)
```

- **The sim is deterministic.** `MatchSim` advances one fixed 60 Hz tick per
  `step()` from the two players' inputs only, and can `save_state()` /
  `load_state()` for rollback. Both peers must run the same build: the
  handshake compares a hash of `data/balance.json` plus a protocol number
  and refuses mismatches.
- **Rollback.** Local input is delayed 2 frames, sent with every
  unacknowledged input (so lost packets are covered by the next one), and the
  sim runs ahead on a prediction of the opponent's input (their last one).
  When the real input differs, the sim rewinds to the saved state and
  re-simulates. The sim may run at most 8 frames past the opponent's last
  confirmed input; the peer that's further ahead waits a frame now and then.
- **Desync detection.** Every 60 confirmed frames both peers exchange a
  checksum of the full state; a mismatch shows "DESYNC DETECTED".
- **Sides.** The host plays on the left, the guest on the right.
- **Windows only for now.** The web build hides the Online menu (the WebRTC
  addon is excluded from web exports with the `web` / `no-webrtc` tags). Cross-platform play (Windows vs. Mac vs. browser)
  will need the sim moved to fixed-point maths first, because floating-point
  results can differ slightly between platforms.

## Playing online today

**With a friend anywhere (recommended):**

1. Host: **Online > Host room**. The screen shows a room code like `7KQ2MX`.
2. Friend: **Online > Join room**, type the code.
3. Both pick a player and lock in; the host picks the court and starts.
4. After the match: **Rematch** goes back to the lobby; **Leave** disconnects.

Rooms work with or without a PlayBound account.

**Signed in with PlayBound:**

- **Sign in with PlayBound** opens playbound.club/link in the browser and
  shows a code. Sign in there (or create an account), check the code
  matches, and approve; the game signs in within a few seconds and remembers
  you on this PC (the token is stored encrypted, tied to the machine). Games
  started from the PlayBound launcher can skip this: the launcher passes
  `PLAYBOUND_TOKEN` (see below).
- **Friends** lists your PlayBound friends: who's in HyperDisc, online or
  offline. Picking one opens a room (if you aren't hosting one) and sends
  them an invite with the room code. While hosting a room, the slap button
  (Triangle / Y / I) opens the list too.
- An incoming invite pops up over any menu: **Join** connects straight to
  the friend's room; **Not now** declines.

**Same network / direct:** **Host on LAN** shows your address (UDP 7777);
**Join by address** connects to it. Over the internet that needs the port
forwarded, which is why rooms exist.

Start opens a small menu during an online match (the game keeps running);
leaving forfeits.

## Testing

- `godot --headless --script res://tests/run_tests.gd` includes rollback over
  a simulated bad network (latency, jitter, 8% loss), online-vs-offline
  equivalence, the full lobby flow and the version check.
- Two real instances on one PC, CPU-controlled, with simulated internet lag:

  ```
  godot -- --host=7777 --bot --name=MICK --netlag=80 --netloss=5 --quit-after-match
  godot -- --join=127.0.0.1:7777 --bot --name=PETE --netlag=80 --netloss=5 --quit-after-match
  ```

  Each prints `ONLINE_PROGRESS` lines and an `ONLINE_RESULT` line with the
  winner, sets, rollback stats and whether a desync happened.
- **PlayBound without the real site:** `python tools/fake_playbound.py`
  runs an in-memory stand-in (sign-in, friends, presence, invites, Connect
  rooms with signaling). Users are `tok-alice`, `tok-bob`, `tok-carol`,
  `tok-dave`, all friends with each other; rooms are numbered `HYPER1`,
  `HYPER2`, ... Two bots through a WebRTC room:

  ```
  PLAYBOUND_TOKEN=tok-alice godot -- --host-room --bot --quit-after-match --playbound-api=http://127.0.0.1:8787
  PLAYBOUND_TOKEN=tok-bob godot -- --join-room=HYPER1 --bot --quit-after-match --playbound-api=http://127.0.0.1:8787
  ```

  Signing in from the game against the fake server prints a link; opening
  it approves the code (as alice, or add `&as=bob`).

## PlayBound API used by the game

Base URL `https://playbound.club` (override with `PLAYBOUND_API_BASE` or
`--playbound-api=`). Account calls send `Authorization: Bearer <token>`.

| What | Endpoint |
| --- | --- |
| Start sign-in | `POST /api/game-auth/link` `{gameSlug, deviceName}` -> `{code, pollToken, verifyUrl, expiresInMs, intervalMs}` |
| Wait for approval | `POST /api/game-auth/link/poll` `{pollToken}` -> `pending` / `approved {token, user}` / `denied` / `expired` |
| Who am I | `GET /api/game-auth/me` -> `{user: {id, username}}` |
| Sign out | `POST /api/game-auth/logout` (revokes the token) |
| Launcher token | `POST /api/game-auth/launcher-token` `{gameSlug}` with the launcher's own token -> a game token for `PLAYBOUND_TOKEN` |
| Friends | `GET /api/friends` (polled every 15 s) |
| Presence | `POST /api/presence/start`, `/heartbeat` (60 s), `/end` (on quit) |
| Invites | `GET /api/play-invites` (polled every 5 s), `POST /api/play-invites` `{recipientId, gameSlug, connectCode}`, `POST /api/play-invites/{id}` `{action}` |
| Rooms | `POST /api/multiplayer/hyperdisc-arena/sessions`, `POST .../sessions/{code}/join`, `GET/POST .../sessions/{id}/signal` |

The game-auth endpoints, `connectCode` on invites and the `hyperdisc-arena`
Connect adapter come from PlayBound PR #1 (`game-accounts-api`). Invites also
need HyperDisc in the PlayBound game catalog (added through the admin panel).

**Connecting.** The room's signal endpoint carries the WebRTC offer, answer
and ICE candidates (the guest announces itself with `join` until the host's
offer arrives; the host answers each `join` with an offer). Connect's STUN
servers find a direct route; its TURN server relays when there isn't one.
The data channel is unordered with no retransmits, because rollback resends
inputs itself. Room creation sends the build hash as `gameVersion`, so a
friend on another version is told so instead of desyncing.

## Phone as controller

**Options > Controls > Phone as controller** shows a QR code. Scanning it
opens PlayBound's controller page (`playbound.club/c/CODE`) on the phone; no
app or account. Without a camera, go to `playbound.club/c` and type the code.
The phone takes a free player slot like a plugged-in pad (up to two phones)
and keeps working after the overlay is closed; the slap button there
disconnects them. Match play never needs a QR code; this is only for using a
phone as a gamepad.

How it works (`scripts/net/phone_controllers.gd`): the game opens a
PlayBound couch session (`POST /api/couch/sessions`), shows the returned
join link as a QR code (`scripts/game/ui/qr_code.gd`, a built-in encoder),
and polls `/api/couch/sessions/{id}/signal` for the phone's WebRTC offer. It
answers in-process (the same webrtc-native addon as rooms); the phone's
unordered `input` data channel then carries PlayBound's couch input protocol
v1 (button bitmask and sticks, see PlayBound `docs/couch-input-protocol.md`)
straight to the game. Each phone becomes a virtual controller in
`Controls` (device ids from 1000). Presses are held until the game has read
them, so a quick tap is never lost between ticks. `--phone` opens the
overlay directly; `HYPERDISC_PHONE_DEBUG=1` logs button changes.

### Later
- Matchmaking queue that ends in the same room flow.
- Recording match results and ratings (both peers report, server reconciles).
- Reporting desyncs with the frame number and build, to catch bugs.

## v0.2.4 connection fixes
Hosted Connect rooms send a keepalive every 20 seconds and are deleted on close. Failed signaling requests retry and surface errors; duplicate guest announcements no longer recreate offers, and ICE waits for the remote description. Presence registration retries after failures, and failed heartbeats retry after five seconds. Account privacy settings still control visibility.

Run tests/test_playbound_presence.gd for registration and heartbeat recovery. Opt-in tests/test_live_connect.gd creates an anonymous live room, waits 65 seconds, then connects native WebRTC peers and verifies packet delivery; it does not use player accounts. This does not replace testing two players on separate networks.

