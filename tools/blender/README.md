# Combat asset pipeline (`tools/blender/`)

Generates the six fantasy chess fighter classes (rigged, animated GLB), their mobile LODs and
collision proxies, the stone arena, and all textures from Python. Nothing is hand-sculpted and no
external asset is downloaded. Owner: Claude Code (`docs/development/OWNERSHIP.md`).

## Reproduce

Toolchain actually used: **Blender 4.3.0** as the `bpy` module (PyPI wheel
`bpy-4.3.0-cp311-cp311-manylinux_2_28_x86_64.whl`, SHA-256 checked against PyPI metadata) with
**numpy 1.26.4** (numpy 2.x breaks Blender 4.3's compiled modules), Python 3.11, Linux x86_64.
Codex's TOOLCHAIN.md records Blender 4.3.2; the 4.3.x exporter is the same series but I did not run 4.3.2.

```sh
tools/blender/setup_env.sh .venv-blender          # venv + pinned bpy/numpy (python3.11 required)
.venv-blender/bin/python tools/blender/build_all.py            # everything, ~25 s
.venv-blender/bin/python tools/blender/build_all.py --only pawn,knight --no-lods
blender --background --python tools/blender/build_all.py -- --only arena   # a real Blender 4.3.x works too
```

Output (deterministic: fixed texture seeds, no random modelling): `godot/assets/combat/` -
`characters/<class>/<class>.glb`, `<class>_lod1.glb` (mobile), `<class>_collision.glb`,
`arena/stone_arena{,_lod1}.glb` + `stone_arena_lights.json`, `textures/*.png`,
`manifest/asset_manifest.json` (tri counts, bytes, bounds, clip frame counts, measured arena numbers).
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

## Clips (15 per class, all six classes)

`idle, walk, run, strafe_left, strafe_right` (loops), `light_1, light_2, light_3, heavy`, `block` (loop),
`parry, dodge, stagger, ability, defeat`. Pose authoring uses armature-axis rotations (`skeleton.set_pose`);
two-handed grips (Pawn spear, Bishop staff) use a two-bone IK solve so the off hand stays on the shaft
(`animation/kinematics.py`); the weapon strikes inside the `spec.MARKERS` active window (peak hand speed checked).
The `STYLE` schema each class module supplies is documented at the top of `animation/library.py`.

## Layout

`runtime.py` scene/args helpers, `skeleton.py`, `modeling.py` (bmesh primitives, skinned tubes, UVs, socket
attachment), `textures.py` (numpy + pure-Python PNG), `materials.py`, `export.py` (GLB, NLA clips, validated LODs),
`characters/{pawn,knight,bishop,rook,queen,king}.py`, `characters/base.py` (per-class pipeline, LOD1 at 40%,
convex collision hull), `animation/`, `arena.py`.

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

## Verification status (honest)

Verified here: the scripts run end to end in real Blender 4.3.0; the GLBs import into Godot 4.6.3 and pass
`godot/combat/tests/test_assets.gd` (skeleton identical across classes, all 15 clips with exact lengths, rotation-only
tracks, sockets, props following the animated hand, LOD1, collision hull, textures, tint surface, reach plausibility);
renders under Xvfb software GL were reviewed by eye (line-up, clips, a live fight with the generated arena).

NOT verified: real GPU / Android / Windows rendering or performance, mobile frame budget, the LOD1 visual quality at
distance, locomotion in motion (walk/run/strafe/dodge/ability were looked at as single still frames only, plus loop-closure checks), foot placement and cadence,
Blender 4.3.2 specifically, and Bishop/Rook/Queen/King *gameplay* (no stats/abilities in the simulation yet).

## Known art limitations

Stylized low-poly built from primitives, not sculpted or "realistic". The Rook and Queen are very dark under dim
light. Pawn tabard can clip the thighs in long strides; Bishop skirt stretches slightly in big strides; Rook tower
shield pose in `block` was not confirmed against the exact clip; King fur collar is lumpy. Heights include crests/crowns
(above the simulation's 1.8 m hurtbox, which governs combat).

## Adding or changing a class

Add `characters/<name>.py` (`NAME, PROPORTIONS, STYLE, build(arm, joints)`), add its numbers to `animation/spec.py`,
rebuild, run `godot --headless --path godot --script res://combat/tests/test_runner.gd -- assets`.
