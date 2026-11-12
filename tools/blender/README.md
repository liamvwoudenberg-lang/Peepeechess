# Combat + world asset pipeline (`tools/blender/`)

Generates the six fantasy chess fighter classes (rigged, animated GLB), their mobile LODs and
collision proxies, the stone arena, the **world assets** (12-piece chess set, board dressing, pit set: trapdoor, shaft, ladder,
chamber ceiling, light cone; see `godot/assets/world/README.md`) and all textures from Python. Nothing is hand-sculpted and no
external asset is downloaded. Owner: Claude Code (`docs/development/OWNERSHIP.md`).

## Reproduce

Toolchain actually used: **Blender 4.3.0** as the `bpy` module (PyPI wheel
`bpy-4.3.0-cp311-cp311-manylinux_2_28_x86_64.whl`, SHA-256 checked against PyPI metadata) with
**numpy 1.26.4** (numpy 2.x breaks Blender 4.3's compiled modules), Python 3.11, Linux x86_64.
Codex's TOOLCHAIN.md records Blender 4.3.2; the 4.3.x exporter is the same series but I did not run 4.3.2.

```sh
tools/blender/setup_env.sh .venv-blender          # venv + pinned bpy/numpy (python3.11 required)
.venv-blender/bin/python tools/blender/build_all.py            # everything (characters + arena + world), ~32 s
.venv-blender/bin/python tools/blender/build_all.py --only world          # pieces + board + pit -> godot/assets/world, ~6 s
.venv-blender/bin/python tools/blender/build_all.py --only pieces,board,pit --world-out /tmp/scratch_world
.venv-blender/bin/python tools/blender/build_all.py --only pawn,knight --no-lods
blender --background --python tools/blender/build_all.py -- --only arena   # a real Blender 4.3.x works too
```

Output (deterministic: fixed texture seeds, no random modelling): `godot/assets/combat/` -
`characters/<class>/<class>.glb`, `<class>_lod1.glb` (mobile), `<class>_collision.glb`,
`arena/stone_arena{,_lod1}.glb` + `stone_arena_lights.json`, `textures/*.png`,
`manifest/asset_manifest.json` (tri counts, bytes, bounds, clip frame counts, measured arena numbers).
Content is deterministic (fixed seeds, no random modelling), but the GLB BYTES are not: two runs differ only in the index order of
identical triangles (checked: JSON chunk and all non-index buffer data are identical). When you regenerate, commit only the files whose
content really changed (`animation/dev_compare_clips.py [git-ref]` proves existing clips are still bit-identical).
The glTF addon prints a `Draco ... library could not be found` line; it is harmless (Draco is not used)
but will trip a naive `ERROR` grep.

## Conventions (these are contracts between the scripts and Godot)

* Blender is Z-up; characters stand on z=0, face **-Y**, left is **+X**. The exporter turns that into
  glTF/Godot **+Z forward**, matching the gameplay heading `(sin yaw, 0, cos yaw)` at yaw 0 (CONTRACTS.md),
  so a model needs no extra rotation. Units are metres. 60 fps: **one animation frame = one simulation tick**.
* One shared skeleton (`skeleton.py`): Godot humanoid names (`Hips, Spine, Chest, UpperChest, Neck, Head,
  Left/RightShoulder|UpperArm|LowerArm|Hand|UpperLeg|LowerLeg|Foot|Toes`, `Root`) plus non-deforming sockets
  `WeaponSocket_R`, `WeaponSocket_L`, `ShieldSocket_L`, `BackSocket`, `HeadTop` (28 bones, no fingers).
  Classes only change joint positions (proportions), never names or hierarchy, so every clip and every Godot-side
  attachment works on every class. Godot imports sockets as `BoneAttachment3D` with the prop as a child.
* Each body is ONE skinned mesh (<= 5 material slots); weapons/shields are separate props parented to sockets.
  A material named `<Class>_Accent` is a plain-colour team-tint surface that Godot recolours at runtime.
* Animation tracks are rotations only, plus Hips/Root translation. Attack clip lengths equal the tick lengths in
  `godot/combat/core/attack_library.gd` (Pawn/Knight). Bishop/Rook/Queen/King lengths come from the legacy config
  and are **proposals** (the simulation has no stats for them yet) - see `animation/spec.py`.

## Clips (22 per class, all six classes)

`idle, walk, run, strafe_left, strafe_right` (loops), `light_1, light_2, light_3, heavy`, `block` (loop),
`parry, dodge, stagger, ability, defeat`, the polish clips `victory, hit_react_light, hit_react_heavy`, and the world clips
`climb` (loop, 72 f), `ladder_idle` (loop, 120 f), `drop_fall` (loop, 40 f), `land` (one-shot, 36 f). The world clips are in
`animation/world_clips.py`: hands and balls of the feet are IK-placed on the ladder's rung grid (`spec.RUNG_SPACING` 0.25 m, rung plane
`spec.LADDER_PLANE_FWD` 0.42 m in front of the character, `spec.CLIMB_SPEED_MPS` 0.4167 m/s upward travel, root motion stripped;
`animation/dev_climb_check.py` prints the contact slide / grid error for all six classes). They are optional for the runtime
(not in `CharacterModel.REQUIRED_CLIPS`). Pose authoring uses armature-axis rotations (`skeleton.set_pose`);
two-handed grips (Pawn spear, Bishop staff) use a two-bone IK solve so the off hand stays on the shaft
(`animation/kinematics.py`); the weapon strikes inside the `spec.MARKERS` active window (peak hand speed checked).
The `STYLE` schema each class module supplies is documented at the top of `animation/library.py`.

## Animation integrity audit

`godot/combat/tools/anim_audit.gd` (+ `anim_audit_runtime.gd`) measures every clip of every class and LOD through the real `CharacterModel` /
`AnimationPlayer`: coverage and silent fallbacks, clip length and weapon contact vs the simulation's frame data, loop seams, skeleton
sanity (finite values, bone lengths, isolated rotation pops, knee/elbow limits, foot slide / drag / ground penetration), props and sockets,
LOD parity, cross-fade pose deltas, and seeded AI-vs-AI fights plus scripted move-set scenarios through the full presentation. Results:
`godot/assets/combat/ANIMATION_INTEGRITY.md` (tables, findings, visual review) and `godot/assets/combat/manifest/animation_audit.json`.

```sh
godot --headless --path godot --script res://combat/tools/anim_audit.gd -- --out res://assets/combat/manifest/animation_audit.json
godot --headless --path godot --script res://combat/tools/anim_audit.gd -- --classes knight --lod 0 --no-runtime     # quick look
godot --headless --path godot --script res://combat/tools/anim_audit.gd -- --assets /tmp/scratch/characters --no-runtime  # a scratch build (build_all.py --out /tmp/scratch)
godot --headless --path godot --script res://combat/tests/test_runner.gd -- anim_integrity                                 # the asserting suite
xvfb-run -a godot --path godot --rendering-driver opengl3 --script res://combat/tools/anim_sheet.gd -- class=knight clips="light_1:0,8,14;heavy:20,36" out=/tmp/sheet.png
```

Workflow: change `animation/*`, rebuild (`build_all.py`), rerun the audit; a scratch build can be audited before it replaces the committed GLBs.
Generator rules the audit enforces: tuples blended in `poses._lerp` must be padded, never snapped; quaternion keys stay sign-continuous;
ground-fitted poses never carry a negative hips offset; locomotion goes through `animation/gait.py` (its nominal speeds in `spec.py` must equal
`CharacterModel.NOMINAL_SPEED`, asserted by `test_anim_integrity`).

## Layout

`runtime.py` scene/args helpers, `skeleton.py`, `modeling.py` (bmesh primitives, skinned tubes, UVs, socket
attachment), `textures.py` (numpy + pure-Python PNG), `materials.py`, `export.py` (GLB, NLA clips, validated LODs),
`characters/{pawn,knight,bishop,rook,queen,king}.py`, `characters/base.py` (per-class pipeline, LOD1 at 40%,
convex collision hull), `animation/`, `arena.py`, and `world/` (`common.py` WB builder with lathe / square-lathe / loft, `pieces.py`,
`board.py`, `pit.py`, `textures_world.py` marble + basalt, `build.py` driver writing `godot/assets/world/manifest/world_manifest.json`).

## Measured (from the manifest)

| Class | LOD0 body tris | LOD1 | props | hull verts | body half-width | height (with crest) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Pawn | 1876 | 728 | 162 | 77 | 0.28 | 1.78 |
| Knight | 3192 | 1250 | 412 | 88 | 0.39 | 1.99 |
| Bishop | 3260 | 1293 | 312 | 77 | 0.35 | 2.18 |
| Rook | 3880 | 1535 | 678 | 84 | 0.48 | 2.19 |
| Queen | 3580 | 1392 | 752 | 55 | 0.37 | 2.02 |
| King | 4698 | 1830 | 236 | 79 | 0.46 | 2.19 |

Arena: ~8.0k tris LOD0, ~3.9k LOD1, <= 16 draw calls; measured wall inner radius 7.0998 (collision 7.1),
pillar radius 0.5501 at (+-3.4, +-3.4), floor at y=0.

## World assets (summary; details and node names in `godot/assets/world/README.md`)

12 chess pieces (+ LOD1) as lathe-based low-poly meshes (<= 1620 tris, base ~0.7 m, heights 0.70 / 1.00 / 1.04 / 0.85 / 1.19 / 1.31), marble tile
textures (512 px, seamless), a carved frame with corner posts and 32 plaques (Blender built-in font converted to mesh), a two-leaf trapdoor with hinge
pivots, shaft rim and wall segment, a modular 10 m ladder with per-rung anchors, a ceiling cap with a one-tile hole and a light-cone helper.
Checked by `godot --headless --path godot --script res://combat/tests/test_runner.gd -- world_assets`; screenshots with
`godot/combat/tools/world_viewer.gd` (modes pieces, piece, board, trapdoor, ladder, shaft, climb, fall).

## Verification status (honest)

Verified here: the scripts run end to end in real Blender 4.3.0; the GLBs import into Godot 4.6.3 and pass
`godot/combat/tests/test_assets.gd` (skeleton identical across classes, all 15 gameplay clips plus the polish clips `victory`, `hit_react_light` (14 f), `hit_react_heavy` (24 f) with exact lengths, rotation-only
tracks, sockets, props following the animated hand, LOD1, collision hull, textures, tint surface, reach plausibility);
renders under Xvfb software GL were reviewed by eye (line-up, clips, a live fight with the generated arena).

NOT verified: real GPU / Android / Windows rendering or performance, mobile frame budget, the LOD1 visual quality at
distance, locomotion in motion (walk/run/strafe/dodge/ability were looked at as single still frames only, plus loop-closure checks), foot placement and cadence,
Blender 4.3.2 specifically. The new clips (victory, hit reactions, heavier anticipation, the King's 40-frame counter stance, per-class locomotion/idle styles) were checked by `animation/dev_timing_check.py` (all 24 attack clips peak hand speed inside the active window) and as still frames only, never in motion.

Scratch builds: `python build_all.py --out DIR` writes everything under DIR (world assets under DIR/world) and never touches `godot/assets`.

The four world clips (climb, ladder_idle, drop_fall, land) were measured numerically (contact slide, rung-grid error, loop closure; all six classes) and
looked at as still frames in Godot under Xvfb software GL (side and front views, ladder from `world/pit.py`); never reviewed in motion. Big props (Rook
shield, Pawn spear, Queen blades) overlap the ladder or the body during the climb; the knees brush the rung plane.

## Known art limitations

Stylized low-poly built from primitives, not sculpted or "realistic". The Rook and Queen are very dark under dim
light. Pawn tabard can clip the thighs in long strides; Bishop skirt stretches slightly in big strides; Rook tower
shield pose in `block` was not confirmed against the exact clip; King fur collar is lumpy. Heights include crests/crowns
(above the simulation's 1.8 m hurtbox, which governs combat).

## Adding or changing a class

Add `characters/<name>.py` (`NAME, PROPORTIONS, STYLE, build(arm, joints)`), add its numbers to `animation/spec.py`,
rebuild, run `godot --headless --path godot --script res://combat/tests/test_runner.gd -- assets`.
