# Move poses: the missing animation frames

Every character's sheet still borrows poses:
- lob, slap and special reuse the throw
- block reuses the catch
- knocked back reuses the dash
- charge, win and lose reuse the single idle frame

`match_view.gd` now adds squash, stretch, lean and afterimages on top of those poses. Even so, dedicated poses would read far better.

For each character, generate one more sheet beside `run-v1.png` and `actions-v1.png`:

- `tools/art/<id>_sources/moves-v1.png`: nine poses in a 3 × 3 grid
- `tools/art/<id>_sources/idle-v1.png`: three breathing frames in a 3 × 1 strip

Use the same reference (`design-v2.png`) and the same style block as that character's `actions` prompt in THIRD_ROSTER_PROMPTS.md or NEXT_CHARACTERS.md. Swap in the pose list below. When both sheets exist, the roster build can slot them into the animations that currently borrow poses.

## moves (3 × 3)

Use case: identity-preserve. Original arcade pixel art moves asset for HyperDisc Arena. Depict the EXACT adult <id> from the reference: identical face, hair, build, costume construction, colors, shoes and accessories in EVERY pose. <one-line character description from the actions prompt>. Retain deliberate crisp square pixel clusters, dark plum contour and stepped arcade shading. True transparent alpha background. No gradient, no glow, no scenery, no text, no labels, no grid lines, no disc, no ground shadow. Exactly two arms/two hands/two legs, no extra or detached hand. Full body shoes fully visible, ample transparent gutters, consistent camera facing RIGHT, body SCALE constant through all poses, no clipping. Nine keyframes in 3 columns x 3 rows. Read left-to-right top-to-bottom. Row1: LOB — deep crouch with throwing hand low behind the hip; underhand scoop rising past the knee; tall release with the arm reaching high overhead and the body stretched up on the toes. Row2: SLAP — quick flat forehand flick with the arm whipping across at waist height; BLOCK — braced stance with both forearms raised and crossed in front of the face; KNOCKED BACK — stumbling backwards off balance, torso leaning back, arms flung out, one foot lifted. Row3: WIN — big fist pump with knees bent; WIN — both arms thrown straight up cheering, mouth open; LOSE — slumped forward, hands on knees, head hanging. Leave NO disc in hands (renderer attaches disc). Same scale in every pose. Rear arm occluded naturally behind body, no ghost hands.

## idle (3 × 1)

Use case: identity-preserve. … same style block … Three idle keyframes in 3 columns x 1 row, a subtle breathing loop in the ready stance from the reference: frame 1 neutral; frame 2 chest raised, shoulders up slightly, knees straightening a touch; frame 3 halfway back down. Feet must stay planted in exactly the same spot in all three frames. Same scale in every frame.

## Slots

| Pose | Animation that gets it | Borrows now |
| --- | --- | --- |
| lob crouch, scoop, release | `lob` | throw |
| slap flick | `slap` | throw |
| block guard | `block` | catch |
| knocked back | `knock` | dash |
| fist pump, arms up | `win` (alternating) | idle |
| hands on knees | `lose` | idle |
| idle 1 to 3 | `idle`, `charge` | one idle frame |
