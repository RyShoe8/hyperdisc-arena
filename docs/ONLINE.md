# Online play

Status (Oct 4, 2026): online 1v1 works on Windows with rollback netcode over
direct UDP (LAN, or the internet with a forwarded port). Accounts, friends,
presence and invites are waiting on the PlayBound API described below; the
game side is already written against an interface, so plugging PlayBound in
doesn't touch the netcode or menus.

## How it fits together

```
Menus (scripts/game/online_screens.gd)
   |
Online (autoload, scripts/net/online.gd)  -- picks the service: PlayBound if available, else Direct
   |                                  \
OnlineService interface                OnlineMatch (scripts/net/online_match.gd)
 (scripts/net/online_service.gd)          handshake, version check, lobby, start, rematch
   |- DirectService  (name + IP)             |
   |- PlayBoundService (stub)              RollbackSession (scripts/net/rollback_session.gd)
                                             input delay, prediction, rollback, sync, checksums
                                             |
                                          Transport interface (scripts/net/transport.gd)
                                             |- UdpTransport      direct UDP (now)
                                             |- LoopbackTransport simulated network (tests)
                                             |- (PlayBound relay / NAT-punched UDP, later)
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
- **Windows only for now.** Browsers can't open UDP sockets, so the web build
  hides the Online menu. Cross-platform play (Windows vs. Mac vs. browser)
  will need the sim moved to fixed-point maths first, because floating-point
  results can differ slightly between platforms.

## Playing online today

1. Both players: **Online** from the main menu, set a name.
2. Host: **Host game**. The screen shows your LAN address and port (UDP 7777).
3. Friend: **Join game**, type that address (or `public-ip:7777` over the
   internet, with UDP 7777 forwarded on the host's router).
4. Both pick a player and lock in; the host picks the court and starts.
5. After the match: **Rematch** goes back to the lobby; **Leave** disconnects.

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

## What the game needs from PlayBound

Every method lives on `OnlineService`; `PlayBoundService` has a TODO at each
one. Endpoints below are suggestions; anything with the same information works.

### Accounts and profile

| Game call | Needs | Notes |
| --- | --- | --- |
| `sign_in()` | A login flow that gives the game a session token | Device-code or browser redirect works well for a desktop game: the game shows a code / opens the browser, polls until the user approves. The PlayBound launcher could also pass a token on the command line so players are signed in already. |
| `create_account()` | Account creation, or a link to the sign-up page that returns into the same flow | |
| `is_signed_in()`, `profile()` | `GET /me` -> `{id, display_name, avatar_url}` | The display name replaces the local name. Token refresh as needed. |
| `sign_out()` | Revoke the token | |

### Friends and presence

| Game call | Needs | Notes |
| --- | --- | --- |
| `friends()` | `GET /friends` -> `[{id, display_name, avatar_url, online, in_game, game_id, joinable}]` | Friends are PlayBound-wide; the game filters or labels by `game_id`. |
| `friends_changed` signal | A push channel for presence and friend-list changes | WebSocket (or SSE) per signed-in session. Polling every few seconds is an acceptable first version. |
| `set_presence(status)` | `PUT /me/presence` `{game_id, status: "menus" | "online" | "in_match", joinable}` | The game calls this when entering menus, online lobby, a match. |

### Invites

| Game call | Needs | Notes |
| --- | --- | --- |
| `send_invite(friend_id)` | `POST /invites` `{to, game_id, build}` -> `{invite_id}` | Include the build hash so a friend on an older version can be told to update. |
| `invite_received` signal | Pushed over the same channel: `{invite_id, from_id, from_name, game_id, build}` | The game shows a toast and an Accept/Decline prompt. Invites should expire (e.g. 60 s). |
| `respond_to_invite(id, accept)` | `POST /invites/{id}/respond` `{accept}` | |
| `invite_answered` signal | Pushed to the inviter | |

### Connecting the two players (the important one)

After an invite is accepted, both games need to reach each other without the
players forwarding ports. The game expects PlayBound to hand back a
**Transport** that can send and receive small unreliable packets:

1. **Signaling.** A way for the two games to exchange connection details
   through PlayBound (over the push channel): each side's public address
   from a STUN check, or WebRTC offers/answers and ICE candidates.
2. **NAT traversal.** Try a direct UDP connection first (hole punching via
   the exchanged addresses, or WebRTC data channels in unreliable mode).
3. **Relay fallback.** When direct fails (strict NATs, some mobile networks),
   relay through a PlayBound TURN/relay server (the free stack plans coturn
   on an always-free server).

When that's done, `PlayBoundService` emits
`match_ready({role: "host"|"join", transport, opponent: {id, display_name}})`
and the existing lobby and rollback code take over unchanged. Packet sizes
are small: about 60 bytes 60 times a second each way during a match.

### Later (not needed for the first version)

- Matchmaking queue (`POST /queue`) that ends in the same `match_ready`.
- Recording match results and ratings (`POST /matches` from both peers,
  server reconciles).
- Reporting desyncs with the frame number and build, to catch bugs.
