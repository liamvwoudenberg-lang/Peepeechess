# Animation integrity (six fighters, LOD0 + LOD1)

Generated numbers: `manifest/animation_audit.json` (after) and `manifest/animation_audit_baseline.json` (before: the integrated baseline d95a89f, same audit tool, old
GLBs and old CharacterModel mapping). Rerun: see the end. Every measurement samples the real `CharacterModel` / `AnimationPlayer` (seek + `advance(0)`, then the
Skeleton3D pose); nothing is read from the Blender sources. Thresholds are the `TH` table in `godot/combat/tools/anim_audit.gd` (embedded in the JSON).

## Result

| | high | medium | low |
| --- | ---: | ---: | ---: |
| before (d95a89f) | 44 | 240 | 102 |
| after | **0** | **8** | 68 |

(counts include both LODs: LOD1 repeats LOD0's findings because it shares the animation data.) Suite: `test_runner.gd -- anim_integrity` fails on any high finding and on any medium finding
that is not a documented KNOWN issue (3 distinct ones remain, below); `assets`, `world_assets`, `polish` stay green (4401 checks in the combined run).

### Checks per class (pass/fail, before -> after; a coverage, b timing, c loops, d skeleton, e props, f LOD parity, g blends, h runtime fights)

| class | a | b | c | d | e | f | g | h |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| pawn | 60/0 -> **60/0** | 104/2 -> **104/2** | 36/0 -> **36/0** | 464/44 -> **498/10** | 168/10 -> **172/6** | 6/0 -> **6/0** | 67/13 -> **80/0** | 33/0 -> **33/0** |
| knight | 64/0 -> **64/0** | 116/12 -> **128/0** | 36/0 -> **36/0** | 460/48 -> **498/10** | 146/6 -> **146/6** | 7/0 -> **7/0** | 79/1 -> **80/0** | 33/0 -> **33/0** |
| bishop | 60/0 -> **60/0** | 98/8 -> **106/0** | 36/0 -> **36/0** | 466/42 -> **500/8** | 174/4 -> **176/2** | 6/0 -> **6/0** | 68/12 -> **80/0** | 33/0 -> **33/0** |
| rook | 60/0 -> **60/0** | 96/10 -> **106/0** | 36/0 -> **36/0** | 468/40 -> **498/10** | 148/4 -> **152/0** | 7/0 -> **7/0** | 79/1 -> **80/0** | 33/0 -> **33/0** |
| queen | 66/2 -> **68/0** | 144/10 -> **154/0** | 36/0 -> **36/0** | 464/44 -> **500/8** | 150/2 -> **150/2** | 7/0 -> **7/0** | 74/6 -> **80/0** | 33/2 -> **33/0** |
| king | 64/0 -> **64/0** | 112/18 -> **130/0** | 36/0 -> **36/0** | 464/44 -> **496/12** | 148/0 -> **148/0** | 6/0 -> **6/0** | 79/1 -> **80/0** | 33/0 -> **33/0** |

(`d` counts include many informational low-severity measurements; `f` is LOD1 vs LOD0 and ran only in the after/before tool the same way.)

### Timing against the authoritative frame data (LOD0)

Per attack row of AttackLibrary (lights, heavy, ability; ticks from `FighterRoster.stats_for` + `AttackDefinition.total_ticks`): the weapon tip's peak speed, measured in SIM time
through the model's own anticipation warp, must fall inside the active window +-3 ticks; the tip must reach >= 80% of `reachM * reach_mult` during the active window.

| class | attacks | peak speed in active window +-3 (before -> after) | tip reaches the hitbox (before -> after) |
| --- | ---: | ---: | ---: |
| pawn | 4 | 4 -> **4** | 3 -> **3** |
| knight | 5 | 2 -> **5** | 5 -> **5** |
| bishop | 4 | 2 -> **4** | 4 -> **4** |
| rook | 4 | 1 -> **4** | 4 -> **4** |
| queen | 6 | 5 -> **6** | 6 -> **6** |
| king | 5 | 3 -> **5** | 4 -> **5** |

Also asserted: clip length vs sim ticks (+-1 frame; +-6 for a clip shared by several chain links or an ability), playback rate in [0.75, 1.35], anticipation (the tip draws back
>= max(8 cm, 12% of the strike) before the contact window), wind-up pose change, recovery returning to the ready pose, tip inside the hit sector.

### Locomotion foot lock (LOD0): clip ground speed / nominal and mean stance-foot velocity error (m/s), before -> after

| class | walk | run | strafe | lowest sole under the floor, cm (all clips) |
| --- | ---: | ---: | ---: | ---: |
| pawn | 0.56 -> **1.00** / 1.18 -> **0.05** | 0.78 -> **0.99** / 1.89 -> **0.18** | 0.12 -> **0.96** / 1.93 -> **0.46** | -8.1 -> **-1.0** |
| knight | 0.70 -> **1.00** / 0.96 -> **0.04** | 0.82 -> **1.00** / 1.62 -> **0.14** | 0.09 -> **1.00** / 2.01 -> **0.37** | -11.9 -> **-1.1** |
| bishop | 0.77 -> **1.00** / 0.78 -> **0.03** | 0.78 -> **1.00** / 2.12 -> **0.07** | 0.10 -> **0.86** / 1.95 -> **0.55** | -14.0 -> **-0.9** |
| rook | 0.32 -> **1.00** / 1.53 -> **0.05** | 0.47 -> **1.00** / 2.65 -> **0.13** | 0.04 -> **1.00** / 2.10 -> **0.36** | -15.9 -> **-2.5** |
| queen | 0.66 -> **1.00** / 1.25 -> **0.05** | 0.87 -> **1.00** / 2.04 -> **0.16** | 0.12 -> **0.90** / 1.96 -> **0.51** | -7.9 -> **-1.3** |
| king | 0.71 -> **1.00** / 0.82 -> **0.04** | 0.74 -> **1.00** / 1.61 -> **0.11** | 0.09 -> **1.03** / 2.01 -> **0.33** | -9.9 -> **-1.2** |

## What the audit found and what was fixed

| # | finding (before) | severity | fix |
| --- | --- | --- | --- |
| 1 | Weapon snapped ~120 deg in the recovery of every attack clip: `poses._lerp` blended `wpn` tuples of different length ((az,el) vs (az,el,roll)) by switching halfway. 44 high findings: the fastest weapon motion of heavy / light_3 / lunge fell 12-24 ticks AFTER the active window (e.g. Knight heavy peak tick 51, active 35-42). | high | pad the shorter tuple (poses.py). Peaks now 31-41, inside the windows for all 28 attacks of the six classes |
| 2 | Queen link 5 (`overhead` finisher) played `light_2`; runtime fights flagged it | medium | `CharacterModel.attack_clip()` maps by animation tag (ANIMATION_CLIP) |
| 3 | Feet sank 4-16 cm through the floor in block, heavy, lunge, hit reactions (negative hips offset applied after the ground fit) | medium | ground-fitted poses ignore negative hips offsets. Worst now 1-2.5 cm |
| 4 | Walk / run / strafe: stance foot slid at 0-2x its mean speed, clip ground speed was 0.04-0.87 of the nominal speed, the swing foot dragged on the floor (6-12 foot-frames per cycle) | medium | `animation/gait.py`: planted foot moves at constant velocity at `spec.NOMINAL_SPEED_MPS`, lifted swing foot, hips follow the geometry. Nominal speeds are now 2.0 / 4.5 / 1.8 m/s (CharacterModel.NOMINAL_SPEED, cap 2.2) and strafe is 26 frames |
| 5 | Off-hand grip search stepped by 3 cm: Bishop heavy popped the left elbow 42 deg in one frame | medium | continuous solve in `_follow_shaft` |
| 6 | King: ability clip 40 f vs 56 cast ticks; the counter riposte (30-tick attack through the `ability` clip) restarted the guard raise and struck 10+ ticks off the sim's active window; dodge 26 f vs 28 | medium | ability clip 56 f with one timeline; riposte plays from frame 24 (`CharacterModel.COUNTER_RIPOSTE_START`, in the manifest); dodge 28 |
| 7 | Cross-fade out of block: 1-3 frame blends over 16-31 deg pose deltas | medium | 0.09 s into attacks/abilities/block, 0.04-0.05 s into reactions |
| 8 | Hit reactions bent the shield arm past 155 deg elbow flexion | medium | the shield arm keeps its pose |
| 9 | Bishop light_1 had no anticipation draw-back; Pawn light_3 tip short of the hitbox | medium | stronger wind-up / longer sweep |
| 10 | (informational) Godot keys carry quaternion sign flips | low | quaternion keys made sign-continuous in the export anyway; not a pass/fail check (Godot slerps the short way) |

## Visual review (Xvfb software GL, contact sheets in the scratchpad, not committed)

`godot/combat/tools/anim_sheet.gd` renders chosen frames of any clip. I reviewed per-class sheets (attacks: wind-up / pre-contact / contact / follow-through / recovery of light 1, light 3,
heavy; defence: block, parry, dodge, stagger, ability, hit reaction, defeat, victory, climb; locomotion side views) and looked closely at Knight (attacks, locomotion), King (defence sheet),
Queen (attacks) and Rook (defence). What I saw: strikes read clearly with a visible raised wind-up and a follow-through; block/parry/dodge/stagger poses are distinct; walk and run have a planted
stance foot and a lifted swing foot with bent knees; defeat falls to a lying pose; victory poses differ per class. Weak or unverified:

- Defeat: the Knight/Queen weapon sinks up to 25 cm into the floor and the Rook's hammer lies detached beside the open hand (the hand is not holding it any more). Cosmetic, known.
- The foot-locked gait needs a crouched "combat walk" (hips down ~10 cm at heel strike) to reach nominal speeds with a 0.85 m leg; cadence rises with speed (the Pawn/Queen walk at 3.66 m/s plays the walk clip at 1.8x = ~5 steps/s).
- Strafe stance is wider than idle (feet 0.6 m apart at the widest); no cross-step.
- Climb frames look like a seated pose without the ladder (expected; the ladder is in the world viewer).
- NOT reviewed: motion in real time (only stills + numbers), a real GPU, mobile frame budget, shield/sword intersections beyond the coarse ellipse test.

## Known issues (medium, in `KNOWN` of the suite)

- **pawn** `light_3`: pawn.light.3 tip reaches the sim hitbox (>= 80% of 1.95 m) (value 1.5578, limit 1.56) 
- **knight** `defeat`: props do not sink into the torso (value 0.1312, limit 0.1) deepest at frame 9
- **knight** `stagger`: props do not sink into the torso (value 0.1222, limit 0.1) deepest at frame 14
- **bishop** `walk`: swing foot clears the floor (no dragging) (value 4, limit 2) 4 foot-frames skimming the floor while moving forward, 0.10 m per cycle

Low-severity measurements still in the report: stance-foot velocity peaks at touch-down / toe-off (run up to ~0.7 m/s, strafe up to ~1.8 m/s), the Pawn/Bishop off hand drifting 0.13-0.14 m from
the shaft during heavy/ability, weapon tips below the floor in defeat, King riposte thrust step 85 deg per frame (a deliberate snap), strafe planted-frame fractions 0.73-0.88.

## Proposals (sim side; not changed here)

- Pawn / Queen / Bishop "walk" speeds (3.4-3.7 m/s) are running speeds for a 0.85 m leg: either play `run` above ~3 m/s or lower `moveSpeedMps` (balance); today the walk clip is scaled 1.7-1.8x.
- Queen link 4 (26 ticks) reuses `light_1` (29 f) and link 5 (39 ticks) `light_3` (38 f): playback 1.12x / 0.97x; give the Queen's chain `ticks_scale` that matches the clips (0.9 -> 1.0, 1.35 -> 1.3) if exact 1:1 is wanted.
- A triggered King riposte is 30 ticks while the clip has 32 frames left: 1.07x, fine.
- Stagger lasts 11-60 ticks for a 30-frame clip (0.5x-2.7x); a short and a long variant would read better.

## Rerun

```sh
godot --headless --path godot --editor --import                      # after any GLB change
godot --headless --path godot --script res://combat/tools/anim_audit.gd -- --out res://assets/combat/manifest/animation_audit.json
godot --headless --path godot --script res://combat/tests/test_runner.gd -- anim_integrity assets world_assets polish
python tools/blender/build_all.py --only pawn,knight,bishop,rook,queen,king   # then `git checkout godot/assets/combat/characters/*/*_collision.glb` (byte-only diffs)
```
