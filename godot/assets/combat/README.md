# Generated combat assets

Everything here is produced by `tools/blender/` (see its README for the exact command, toolchain and
conventions). Do not hand-edit; change the generator and rebuild. Source of truth is the committed GLBs and their
`.glb.import` files; the PNGs Godot extracts next to each GLB on import are derived and git-ignored.

| Path | Contents |
| --- | --- |
| `characters/<class>/<class>.glb` | LOD0 rigged + animated character (22 clips: 15 gameplay + victory, hit reactions + the world clips climb, ladder_idle, drop_fall, land), props on socket bones |
| `characters/<class>/<class>_lod1.glb` | mobile variant (~40% triangles, same skeleton and clips) |
| `characters/<class>/<class>_collision.glb` | tiny convex hull for physics proxies (`Mesh.create_convex_shape()`) |
| `arena/stone_arena{,_lod1}.glb`, `stone_arena_lights.json` | arena geometry + light/fog suggestions (Godot space) |
| `textures/*.png` | procedural 256 px tileable textures (inputs to the GLBs) |
| `manifest/asset_manifest.json` | tri counts, bounds, clip frame counts, generator version |

Classes: pawn, knight, bishop, rook, queen, king. All share one skeleton (Godot humanoid bone names + weapon/shield
sockets), so clips and attachments are interchangeable.

## Using them in Godot

* In the game: `CombatArena` prefers `CharacterModel` (`godot/combat/presentation/character_model.gd`) and falls back to
  the procedural placeholder if a GLB is missing. It loads the imported scene, or parses the GLB at runtime when the
  editor import has not run. `CharacterModel.prefer_lod1 = true` selects the mobile LODs (arena too).
* Animation sync: attack/parry/dodge/stagger/ability/defeat clips are paced to the simulation tick counts and
  re-synced from `state_ticks`; locomotion clips scale with speed (nominal 2.2 / 5.0 / 2.0 m/s for walk / run / strafe).
  Loop modes are set at load (idle, walk, run, strafe, block loop; others do not).
* Team tint: surfaces whose material name ends with `_Accent` take the team colour.
* Review tool: `godot --path godot res://combat/scenes/character_gallery.tscn` (Left/Right changes clip).
* Validation: `godot --headless --path godot --script res://combat/tests/test_runner.gd -- assets`.

## World clips (pit sequence)

`drop_fall` (loop, 40 f), `land` (one-shot, 36 f = 0.6 s), `climb` (loop, 72 f = 1.2 s per two rungs) and `ladder_idle` (loop, 120 f) exist for all six
classes in both LODs. They are not in `CharacterModel.REQUIRED_CLIPS` (optional; `has_clip()` is false on an old GLB); `CharacterModel.LOOPING` now includes
the three loops. Root motion is stripped: the game moves the character (climb at 0.4167 m/s, origin at y = n * 0.25 m at phase 0 / 0.5 and 0.42 m
in front of the ladder plane, see `godot/assets/world/README.md`). Existing clips are unchanged (verified bit-identical per clip).
The new world models (chess set, board, ladder, trapdoor ...) live in `godot/assets/world/`.

## Status

Only Pawn and Knight can fight today (the simulation has no stats or abilities for the other four). The other four
models, their clips, and the arena are generated, imported and tested, but not used in a real battle. Art is
stylized low-poly; see `tools/blender/README.md` for verified vs unverified items.
