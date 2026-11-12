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
| CLIMB | walk (>= 0.6 s) + 7.04 m / 1.6 m/s + 0.5 s exit | ladder unrolls from the rim, winner walks to the foot (`walk` clip) **around the arena's pillars** (`PitSequence.walk_path`), **stows weapon and shield over the last 0.35 s of the walk**, climbs (`climb` clip if the model has one, else `walk` at half speed while the model rises), steps onto the tile |
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
| `godot/tests/classic/views_test.gd`, `godot/tests/battle/ui_test.gd`, `godot/tests/battle/real_combat_test.gd` | one added line each: `app.set_world_mode(false)`. These suites regression-test the original Board2D / overlay path, which stays in the repo as a fallback; no assertion was changed or removed. The world path has its own suite (`world`). |

Not edited: `battle_combat_adapter.gd`, `battle_match.gd`, `online_*`, `third_person_camera.gd`, `character_model.gd`, `combat_hud.gd`, the simulation.

How the flow drives the pit (`battle_bridge.gd`): UI "Start battle" -> `pit.begin(request)` + `flow.confirm_capture()`; the arena is mounted under the chamber
(`PitChamber` sets `embedded` and pauses its physics tick until DROP); `arena.battle_started` -> `pit.attach_arena` (fighters hidden, overlays hidden,
rig camera made current); `flow.result_ready` -> `pit.present_result`; `pit.return_ready` -> `flow.return_to_board()` (commit exactly once,
`adapter.stop()`); `flow` back to "board" without that commit (cancel, load failure, adapter failure/disconnect, chess change, resign) -> `pit.abort`.
Board input stays disabled until the pit is idle again.

## King's last stand: multi-duel sequences (battle-royal-v1, local play)

The opt-in `battle-royal-v1` ruleset (ADR `docs/architecture/BATTLE_ROYAL_V1.md`) turns a checkmate into a sequence of duels: the mated
King (attacker) fights each checking piece in turn, carrying its HP / stamina / ability cooldown. The pit presents the **whole sequence with
ONE descent**, one fight after the other in the same chamber, and ONE climb:

```
begin_sequence(info, index) + begin(duel 1)  ->  CAPTURE_FOCUS -> TRAPDOOR_OPEN -> DROP -> COMBAT -> RESOLVE
King won, more duels follow:  RESOLVE -> INTERLUDE (hold)  --next_duel(request)-->  INTERLUDE (step-in, 0.8 s) -> COMBAT -> RESOLVE ...
King won the last duel:       RESOLVE -> CLIMB -> RETURN (King morphs back, glides to ITS OWN square, the mating group vanishes) -> IDLE
King lost any duel:           RESOLVE -> CLIMB (the winning checker climbs) -> RETURN (it glides to its square; every piece is restored, the board is untouched) -> IDLE
```

`INTERLUDE` is the only new `Phase` (appended, so every existing value and the single-capture order are unchanged). The new code is one marked
block at the end of `pit_sequence.gd` (`begin_sequence`, `next_duel`, `end_sequence`, `sequence_active/index/total`, signals `duel_cleared(index)`
and `sequence_ended`) plus tiny `_seq_*` / `_return_target()` hooks in the old phase code that are no-ops for a single capture.
What the interlude does: the previous duel's HUD / result panel is hidden, the camera stays below, the match commits the won duel (the bridge
calls `flow.return_to_board()` on `duel_cleared`), `RoyalPresenter` shows the banner "KING'S LAST STAND - duel i of n" with the carried King state
for `BattleFlow.ROYAL_BANNER_SECONDS` (1.5 s), then `BattleFlow` calls the bridge's `_royal_start()` -> `pit.next_duel(request)` and restarts the
**still mounted arena in place** (`adapter.has_live_arena()` -> no `begin_load`, no scene reload; `CombatArena.start_battle` rebuilds fighters and HUD at
the start positions). When the arena runs the new battle the pit flashes both fighters in at the spawn points (`MorphFx`), glides the camera
into the new third-person pose (`rig.follow` is re-pointed) and releases the simulation. The dead checker already dissolved in RESOLVE.
The King's carried HP / stamina / cooldown reach the simulation through `game.combat_options()` (initial_hp / initial_stamina / initial_cooldown);
the presentation never invents them: the HUD bar of the King simply starts at the carried fraction ("90 / 160"), `CombatHud.set_context()` adds
the "LAST STAND / DUEL i/n" line under the timer, and the banner reads the match's `royal_progress()`.

Interruption at any point (resign, flow/adapter failure = disconnect, leaving the screen) goes through the existing `flow -> "board"` path:
`bridge._on_phase("board")` -> `pit.abort()`, which restores every piece of the sequence (`_seq_entries()`: the King and the whole mating group) to its
square, closes the trapdoor, recovers the camera and ends the sequence. A duel that is re-armed after a failure (`BattleRoyalMatch.cancel_pending`, bounded
retries) simply starts a fresh descent at the match's current duel (`begin_sequence(info, duelIndex)`).

| File | Edit (king's last stand) |
| --- | --- |
| `godot/world/pit_sequence.gd` | appended `INTERLUDE`, marked block of new methods at the end, `_seq_*` hooks (abort, advance, RESOLVE end, RETURN target/restore, `_entries()`) |
| `godot/world/battle_bridge.gd` | marked royal block: `_royal_start()` (flow's `start_override`), `_on_duel_cleared()`, `keep_arena_for_royal` |
| `godot/app/battle_flow.gd` | `start_override`, `keep_arena_for_royal`, `is_royal_duel()`, arena reuse in `confirm_capture`, no `adapter.stop()` between duels |
| `godot/app/battle_combat_adapter.gd` | `has_live_arena()` |
| `godot/combat/presentation/combat_hud.gd` | marked `set_context(text)` block |

Tests: suite `royal_flow` (`godot/combat/tests/test_royal_flow.gd`, run by `npm run test:royal`): two-duel and three-checker sequences, phase order, one descent,
interruption at 14 points (all phases, the interlude hold / step-in, the final climb and return), node-leak checks over three sequences, the real app
screen with a real `CombatArena` (arena reused across duels, carried HP verified in the real simulation, computer seats) and screenshots via
`godot/combat/tools/royal_flow_shots.gd`. Not verified: feel on a real GPU / device, human playtests.

## Assets (merged from `feature/world-assets`, `godot/assets/world/`)

Used when present, with procedural fallbacks that need no assets (tested both ways: the suite ran without them first):
`pit/ladder_top.glb` + `ladder_segment_2m.glb` stacked to the floor (ladder plane 0.42 m behind the shaft centre, climber origin at the shaft centre),
`pit/chamber_ceiling.glb` (top at y = 5.6, plus separate camera-collision boxes), `pit/shaft_rim.glb` + one `shaft_wall_segment.glb` as the liner.
The fighters' `climb` clip is requested at `CLIMB_SPEED / 0.4167` playback speed when the model has it (else the walk clip at half speed).
**Not adopted** (documented so the lead can decide): `trapdoor_*.glb` (hinge names match; but its marble top needs `board_3d.gd` to use `materials/tile_*.tres`,
otherwise the tile visibly changes at capture focus), `light_cone.glb` (the procedural cone is used; the asset's additive material blew out in a first try),
the chess set (`pieces/*.glb`, roles read well from above) and `board_frame/plaques`. Known mismatch in `board_3d.gd` (not touched): the rank Label3D "8" is at z = -3.5
while `world_position()` puts rank 8 at z = +3.5; the pit world follows `world_position()`.
The climber is 1.8 m against a 1.0 m opening, and the props were not authored for it. Measured on the real flow with `combat/tools/climb_audit.gd`
(5 winning roles), the weapon or shield reached **0.2-0.5 m sideways and 0.13-0.76 m front-to-back beyond the opening**: through the ceiling slab, the
shaft wall and the ladder (a Pawn's spear 1.0 m from the axis, a Rook's tower shield 0.95 m). The body was never the problem. The sequence therefore **stows
the props** (`set_props_stowed`, on `CharacterModel` and the procedural `FighterVisual`: they shrink to their grip over `STOW_TIME` and stay hidden for the
climb; the arena frees the fighter afterwards). With that, only bones remain at the opening: hands on the rungs 0.06 m from the wall (by the clip's design),
a Rook's forearm at 0.43 m. Nothing else is scaled, so hands and feet stay on the 0.25 m rung grid the `climb` clip was authored for (scaling the body
down would make them slide through the rungs).

The walk to the ladder foot used to be a straight line with a facing that switched target at 80% and snapped by up to 180 degrees (visible for a Black
winner walking in from z = +2.6). It is now a path that keeps pillar radius + 0.45 m body + 0.1 m margin from each of the four pillars (a duel that ends in the
corner behind a pillar would otherwise walk through it) with a facing that turns continuously. `combat/tests/test_pit_climb.gd` (suite `pit_climb`) checks the
walk path exhaustively over the arena, and for every winning role (plus a Black defender) that props are stowed before the climb, bone centres stay inside the
opening, the facing never turns more than 0.25 rad in a frame and the position never steps more than 0.12 m.

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
* The ladder top (asset) pokes 0.75 m above the board while deployed; it is hidden before the camera passes. The climber's weapon/shield used to clip through the rails; they are now stowed for the climb (see Assets).
* `ThirdPersonCamera.make_current` (polish branch) is not needed: the rig re-asserts its camera after the arena starts. Merge-compatible either way.
* Dark pieces on pale tiles from above: roles are distinguishable by their tops (cross, crenels, crown, mitre slit, horse head, dome) but flatter than the 2D art atlas.
* Resizing the window during a sequence re-frames the board (aspect changes) mid-glide.
