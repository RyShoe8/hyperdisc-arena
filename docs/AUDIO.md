# Sound effects

## Sources and licence

- **Gameplay sounds** (throws, catches, walls, net, crowd, whistle):
  Sonniss GDC Game Audio Bundles, 2016 to 2020. They're royalty free and
  commercially usable, with no attribution required.
  - They may not be used for AI/ML training.
  - The source files live outside the repo in `../refs/sfx/picked/`.
- **Menu sounds:** Kenney Interface Sounds (CC0).
- **Music:** the mixtape catalog, streamed from PlayBound (see MIXTAPE.md).

There are no frisbee recordings in the bundles, so the sounds come from
other sports:

| Use | Source |
| --- | --- |
| Throws | short whooshes and a designed melee swing |
| Power throws | bigger whooshes and a whip-by |
| Specials | a sci-fi pass-by |
| Catches | a goalkeeper punch, deep punches or a body thump, over a body thud |
| Blocks | a blocked punch or a heavy metal impact |
| Walls | a football on a metal ad board, a metal slam |
| Net | a football net hit |
| Disc lands | a rock dropping into gravel |
| Goals | stadium cheer swells |
| Misses | the crowd "ohh" |
| Crowd bed | a clapping crowd loop under matches |

## Rebuilding

1. `refs/sfx/remote_zip.py index` lists every file in the bundles without
   downloading them. It reads each zip's table of contents over HTTP range
   requests.
2. `refs/sfx/make_picks.py` picks files by name for each role.
3. `remote_zip.py fetch picks.tsv` pulls only those files.
4. `python tools/audio/process_sfx.py` writes the game's WAVs to
   `assets/sfx/`. It:
   - finds where each sound starts
   - keeps the first hit, or a set length
   - mixes to mono at 44.1 kHz
   - fades out and levels it by loudness, so every take of a sound plays
     equally loud
   - crossfades the crowd bed into a loop

## In the game

`scripts/game/sfx.gd` plays named cues. Each cue layers sounds, for example:
- a throw is whoosh plus crack
- a catch is punch plus thud
- a goal is a crowd swell

Each layer picks a random take, with slight pitch and volume variation. The
cue is panned to the side of the court where it happens. Catch strength
follows the knockback. The crowd bed fades in for matches.

Throws, power throws and specials are per character. Each character has their
own takes in `assets/sfx/characters/<id>/`, which `process_sfx.py` writes from
its `CHARACTER_SOUNDS` table. The game plays the thrower's own takes, so any
character's sounds can be replaced without touching the others. For now
they're the shared takes pitched per character: Keno lowest, Tiffany highest.
