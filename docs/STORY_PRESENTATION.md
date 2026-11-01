# Story presentation revision

Story difficulty moves in equal steps from Easy to 45% of the way toward Normal
across six opponents. There are no per-opponent reaction or special-frequency spikes.
The dedicated ladder precedes the VS screen, with Mick moving toward the next rung.
Both players then run on and play their own authored celebration as an introduction.
Local intros can be skipped after 90 ticks. Online intros use synchronized session
frames and 180 extra initial READY ticks (protocol 11); both peers need this build.
Jason NightTrain's power move is THE ROADHOUSE.

## Portrait assets

The built-in image-generation tool created four identity-preserving portraits.
Canonical sources: `tools/art/characters/{alex,jimmy,jason,tango}/portrait-v1.png`.
Run `tools/art/pack_story_portraits.gd` with Godot to produce the 640-square WebP
portraits in `assets/art/characters`. Per-character HUD crops live in their JSON.
Gameplay base models and accepted animation sheets remain unchanged.

Prompt used separately for each character (Mick portrait as style reference,
existing character portrait as identity reference):

> Create one 640x640 transparent pixel-art HEAD AND SHOULDERS portrait of CHARACTER.
> Reference 1 Mick is STYLE AND FRAMING ONLY, do not include Mick. Reference 2 is
> the exact character identity to preserve, including face, hair, skin tone,
> clothing/accessories. Do not draw a full body or legs. Match Mick's large face
> scale, polished crisp 80s arcade pixel shading, three-quarter right-facing bust,
> head completely inside canvas with 30px space above, shoulders fill width at
> bottom. No text, no border, genuine alpha transparency, no white background.

Tango addition: golden brown shepherd mix, folded ears, teal collar and bone tag;
head, neck and upper chest only. The earlier combined-grid draft was discarded.

`tools/preview_story_flow.gd` captures the ladder, versus and entrance screens.
