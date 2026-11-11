# Pit world (`godot/world/`)

Owner: Claude Code (presentation). Branch `feature/pit-world`. Peepeechess is ordinary chess on a real 3D board seen from straight
above (it reads as 2D chess). On a capture the two pieces share the contested tile, its trapdoor opens, both fall into the underground
arena, the camera dollies down after them into the third-person combat camera, the fight runs through the **unchanged**
`CombatArena`/`CombatSimulation`, then the winner climbs a ladder out of the hole, turns back into its piece, the trapdoor closes
and the camera glides back to the chess view. One persistent `Node3D` world, no loading screen, no fade, no scene switch.

**Status: implemented for local Battle Chess (AUTHORITY arena through BattleFlow + BattleCombatAdapter). Online presentation is NOT wired
(see "Online path"). Verified by headless tests and software-GL (Xvfb) screenshots only; no GPU, device or human playtest.**

## Architecture

```
ChessBoard3D (SubViewportContainer, Codex's input/selection code, unchanged API)
 `- SubViewport (own World3D)
     `- BattleWorld                      the only clock: advance(dt) = pit, trapdoor, camera, fx (fixed order)
         |- WorldEnvironment + key/fill DirectionalLight3D (render layer 2 = board only)
         |- BoardRoot                     tiles, slabs, pieces, marks (what Board3D always built)
         |   `- TrapdoorController        leaves + holed slab ring + liner; reused, never reallocated
         |- PitChamber (hidden when idle) ceiling slab with the 1 m hole, backdrop band, light shaft, ladder,
         |   `- ArenaMount                BattleCombatAdapter parents the CombatArena here (origin, unscaled)
         |- CameraRig                     the one Camera3D, seven named states
         |- MorphFx x2                    pooled flash + dust
         `- PitSequence                   the capture state machine
WorldBattleBridge (a Node of the app)     BattleFlow <-> PitSequence glue
```

### Floating origin (important)

`CombatSimulation` works in **world space** (`global_position`, spawns at z = -/+2.6, wall colliders around the origin), so the arena stays
at the world origin, unrotated and unscaled. Instead of moving the arena under the contested tile, `BattleWorld.apply_shift(tile)` lifts the
whole board root to `y = BOARD_DEPTH` (7 m) and shifts it horizontally by `-tile.xz`, so the contested tile is exactly above the arena centre.
The camera rig moves with it (`rig.set_origin`), so the picture does not change; chess phases are expressed relative to `rig.origin`, descent
and combat poses are world space. `clear_shift()` restores `BoardRoot` to the origin at the end (invisible from above) and hides the chamber.
Idle, the board is at the origin exactly as before (Codex's tests project `Interaction.world_position()` as a global point).

### Render layers

Layer 1 chamber (arena, fighters, ladder), layer 2 board (tiles, pieces, marks), layer 4 chamber ceiling. Board lights cull to layer 2; the
embedded arena's lights cull to 1 (+4 for torches) so the arena never lights the board and vice-versa; the camera drops layer 4 whenever it is
above the ceiling (the ceiling slab is never visible from the top-down view). Falling pieces and the climbing winner are on layers 1+2.

## Camera states (`CameraRig.State`)

| State | Pose |
| --- | --- |
| `CHESS_TOP_DOWN` | straight-down perspective camera, FOV 12 deg (reads as orthographic), height fits the whole board for the window aspect; flipped board turns it 180 deg |
| `CHESS_PERSPECTIVE` | the original orbit camera (yaw / elevation / distance, FOV 45), never below the board plane |
| `CAPTURE_FOCUS` | still straight down, centred on the contested tile (visible half extent 1.7 m, same narrow FOV) |
| `COMBAT_TRANSITION` | **dolly-zoom**: height and FOV change together so the framed width at the board stays 3.4 m (u 0..0.45), then a Bezier down the 1 m shaft (clamped inside it) into the third-person pose (u 0.45..1); position, rotation and FOV all end exactly on the third-person pose |
| `COMBAT_THIRD_PERSON` | copies the pose of the arena's `ThirdPersonCamera.camera` every frame (that camera is never the active one; the rig camera is made current after the arena starts) |
| `COMBAT_VICTORY` | slow sway around the winner; slides under the shaft as the climber nears the ceiling |
| `RETURN_TO_CHESS` | reverse of the descent (up the shaft, reverse dolly-zoom, glide) ending on the remembered chess view |

`go(state, duration)` glides from the current pose; `snap_to`; `recover()` glides (or snaps when the camera is below the board) to the chess
view after an abort. A non-animated rig snaps. All maths is in `advance(dt)`: no Tween objects exist, so an interrupted transition cannot
leave anything behind.

## PitSequence phases and timings (`world_constants.gd`)

`IDLE -> CAPTURE_FOCUS -> TRAPDOOR_OPEN -> DROP -> COMBAT -> RESOLVE -> CLIMB -> RETURN -> IDLE`

| Phase | Duration | What happens |
| --- | --- | --- |
| CAPTURE_FOCUS | 0.9 s (`CAPTURE_FOCUS_TIME`) | board lifted/shifted (invisible), attacker hops onto the tile (0.5 s slide), camera zooms to the tile |
| TRAPDOOR_OPEN | 0.65 s (+ waits for the arena to be mounted, 20 s timeout) | leaves swing down, shaft liner and light beam fade in |
| DROP | 1.2 s fall + 0.7 s camera (`DROP_TIME + DESCENT_EXTRA_TIME`) | the arena's paused simulation is released (its own 3 s countdown now runs), pieces fall and tumble, drift to the sim spawns after clearing the ceiling, at the landing they flash and morph into the fighters, camera dolly-zooms down and settles into the third-person pose |
| COMBAT | until the authoritative result arrives | HUD/split-screen overlays shown, input live |
| RESOLVE | 1.3 s defeat + 0.5 s dissolve | loser's defeat plays (a timeout loser is detached and plays `defeat`), then shrinks away with dust |
| CLIMB | walk (>= 0.6 s) + 7.04 m / 1.6 m/s + 0.5 s exit | ladder unrolls from the rim, winner walks to the foot (`walk` clip), climbs (`climb` clip if the model has one, else `walk` at half speed while the model rises), steps onto the tile |
| RETURN | camera 2.0 s | winner morphs back into its mesh (0.45 s), `return_ready` is emitted (the bridge commits the result and the arena is stopped), the camera leaves through the shaft, the trapdoor closes (starts at 1.0 s, 0.7 s), board root back to the origin, `finished` |

The sequence **never decides** anything: `present_result(result)` only picks which fighter climbs (`outcome` attacker/defender from the
`BattleResult` the combat module produced; an invalid or repeated result is ignored). It never touches the match, HP or input.

Abort (`abort(reason)`, any phase) restores the piece meshes (position, rotation, scale, layers, visibility), closes the trapdoor at once,
clears the shift, hides the chamber, releases the board sync hold and recovers the camera. `world_is_chess` assertions in `test_world.gd`
check this after an abort in every phase.

## How it is hooked in (every edit outside `godot/world/`)

| File | Edit |
| --- | --- |
| `godot/boards/board_3d.gd` | builds its board inside `BattleWorld` (`scene = world.board_root`, `camera = world.rig.camera`); `set_top_down()`, `sync_hold`/`set_sync_hold()`, input ignored while a pit sequence runs, tile bodies on physics layer 128, pieces/marks tagged render layer 2, ray length 400. Public API and behaviour of the perspective view are unchanged (`yaw/elevation/distance/_orbit/square_at/pieces`). |
| `godot/app/main.gd` | `use_world` (default true) + `set_world_mode()`; `set_view()` maps "2D" to the top-down camera of the same 3D board; `_battle_phase_world()`; `_configure_battle_flow()` mounts the arena in `world.chamber.arena_mount` and creates the `WorldBattleBridge`; "Start battle" -> `_start_battle_pressed()`; "Skip animation" button. `use_world = false` restores the original Board2D + full-screen combat overlay. |
| `godot/app/battle_flow.gd` | `auto_return` (default true). The bridge sets it false so the 2 s aftermath timer does not commit/stop the arena before the climb is done. |
| `godot/combat/arena.gd`, `godot/combat/presentation/stone_arena_visuals.gd` | `embedded` flag only (commented `pit-world edit` blocks): no own `WorldEnvironment`, lights restricted to the chamber layers. Default false = unchanged. **Merge note**: the combat-core worktree also edits these files. |
| `godot/combat/tests/test_runner.gd` | registers suite `world`. |
| `godot/tests/classic/views_test.gd`, `godot/tests/battle/ui_test.gd` | one added line each: `app.set_world_mode(false)`. These suites regression-test the original Board2D / overlay path, which stays in the repo as a fallback; no assertion was changed or removed. The world path has its own suite (`world`). |

Not edited: `battle_combat_adapter.gd`, `battle_match.gd`, `online_*`, `third_person_camera.gd`, `character_model.gd`, `combat_hud.gd`, the simulation.

How the flow drives the pit (`battle_bridge.gd`): UI "Start battle" -> `pit.begin(request)` + `flow.confirm_capture()`; the arena is mounted under the chamber
(`PitChamber` sets `embedded` and pauses its physics tick until DROP); `arena.battle_started` -> `pit.attach_arena` (fighters hidden, overlays hidden,
rig camera made current); `flow.result_ready` -> `pit.present_result`; `pit.return_ready` -> `flow.return_to_board()` (commit exactly once,
`adapter.stop()`); `flow` back to "board" without that commit (cancel, load failure, adapter failure/disconnect, chess change, resign) -> `pit.abort`.
Board input stays disabled until the pit is idle again.

## Assets

`PitChamber` uses `godot/assets/world/pit/ladder_top.glb` + `ladder_segment_2m.glb` (stacked down to the floor) when present; otherwise a procedural
ladder (rails/rungs with the same 0.62 m / 0.25 m dimensions). Checked once against the generated set by copying the GLBs from the world-assets worktree
(screenshot of the climb); the assets are not in this branch. Not adopted yet (clean procedural versions are used): `trapdoor_*.glb` (hinge names match
`hinge_left`/`hinge_right`; its marble top would need `board_3d.gd` to use `materials/tile_*.tres`), `chamber_ceiling.glb`, `shaft_*`, `light_cone.glb`,
the chess set and board frame. The `climb` clip is requested at `CLIMB_SPEED / 0.4167` playback speed when the model has it.

## Quality / mobile

`BattleWorld.set_quality("low"|"high")` (default low on mobile feature): key light shadows off, fewer dust particles, no spot shadows. Nodes are built once
(chamber props lazily at the first capture) and reused; steady states do no allocation (the transitions allocate a few small pose dictionaries per frame).
The key-light shadow is the only shadow in the board scene; the arena keeps its own moon-light shadow settings (not changed).

## Tests

`godot --headless --path godot --script res://combat/tests/test_runner.gd -- world` (about 40 s): camera states and dolly-zoom invariants, phase order and
durations, result presentation (attacker/defender), interruption at 10 points across every phase (consistent top-down world, chess state untouched, no orphan
nodes, geometry identical), three captures back to back (node counts identical), top-down view hit-testing/click-to-move, and end-to-end runs through the real
`BattleFlow` + `BattleCombatAdapter` + `CombatArena` (attacker wins, defender wins in the flipped 3D view, interrupt during the descent / in combat, adapter
failure). The e2e damage-forces the loser in the real simulation (so the real `CombatSimulation` emits the result) and raises `Engine.physics_ticks_per_second`
to keep it short.

## Online path (not wired)

`OnlineCombatView` mounts a PRESENTATION arena in a separate `SubViewport` (`own_world_3d`) inside the lobby, which has its own Board2D/Board3D. What is missing:
1. `online_lobby.gd` builds boards itself and does not use `main.gd`'s world mode; it would call `board_3d.set_top_down()` and keep `board_2d` hidden.
2. `OnlineCombatView.setup(client, host: SubViewport)` is typed to a `SubViewport`; it must accept `world.chamber.arena_mount` (a `Node3D`) and call `pit.begin(frame.state.battle)` when the
   phase becomes `combat`, `pit.attach_arena(arena)` after `start_battle`, and `pit.present_result(frame.state.combat.result)` in `aftermath`.
3. The server's 3 s countdown starts when the server starts the duel, not when the pit releases the arena: the pre-roll (about 3.5 s) can finish after the countdown, so
   either the server grants a presentation delay (a `ClockSync`/phase field) or the client must show the fight while the camera is still arriving. A PRESENTATION arena has no local
   simulation to pause.
4. There is no `return_to_board()` on the client: the server moves the phase back to `board`; the bridge's logic (`pit.finished` releases the board sync hold) works, but a server that
   returns to `board` while the climb is still playing needs a "fast-forward to RETURN" path (not implemented; `abort()` is the only shortcut and it restores the chess view at once).
5. `online_ui_test.gd` asserts the old overlay structure (`combat_container`, hidden boards), so it must be adapted together with the lobby.

## Known issues / not verified

* Not human-playtested; frame cost, camera comfort and the look on real GPUs/Android are unvalidated (software GL only, 1280x800 Xvfb).
* Local two-human battles (the adapter configures both seats as humans) use the arena's own split-screen layer: the rig camera shows the descent, then the two
  per-player `ThirdPersonCamera` views cover it. Only a single human/AI seat gives the single third-person camera the rig follows. The adapter is not mine to change.
* The combat view lives in the board panel (about 890x560 on a 1280x800 window), not full screen; the HUD scales with the panel.
* The ladder top (asset) pokes 0.75 m above the board while deployed; it is hidden before the camera passes. The climber's weapon/shield clip through the rails for some roles (asset note).
* `ThirdPersonCamera.make_current` (polish branch) is not needed: the rig re-asserts its camera after the arena starts. Merge-compatible either way.
* Dark pieces on pale tiles from above: roles are distinguishable by their tops (cross, crenels, crown, mitre slit, horse head, dome) but flatter than the 2D art atlas.
* Resizing the window during a sequence re-frames the board (aspect changes) mid-glide.
