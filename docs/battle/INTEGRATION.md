# Battle Chess C0 integration

Base: integrated develop commit `b4c6dab` (including Classic `8b13047`). Feature branch:
`codex/battle-loop`. Classic remains the default and retains its 2D/3D game.

## Current dependency status

Claude's published `ccr-a4637d6e-lypbb4` branch through `5706131` is merged into
this isolated integration branch. `res://combat/arena.tscn` now supplies real
fighters, input, split-screen cameras, countdown, simulation and results. The
adapter configures White as human `kb1` and Black as human `kb2`, preventing the
arena's default AI seats from silently taking over. Real Pawn/Knight combat is
tested through the board transaction, including consecutive battles and returns.

**Full-roster acceptance remains blocked:** `FighterProfile.supports_role()`
implements only Pawn and Knight. Bishop, Rook and Queen captures cannot be played
yet. The preview queries the combat owner's capability function and explains a
missing role before disabling Start; cancellation preserves the board. The new
Blender generator sources do not implement missing fighter simulation. No
substitute fighter or production fake/random winner is used. Claude's imported
combat source, assets, tests and Blender scripts are unchanged by Codex.

## Combat handoff required

The Codex-owned adapter is `godot/app/battle_combat_adapter.gd`. Its default
scene is `res://combat/arena.tscn`; a different agreed path can be configured on
the adapter without moving or editing combat-owned files. The component must
be a PackedScene with the following root API (per the architecture contract):

```gdscript
signal combat_snapshot(snapshot: Dictionary)
signal battle_finished(result: Dictionary)
func start_battle(request: Dictionary): # void or {ok: bool, code?, message?/error?}
    # Initialize exactly the request's attacker and defender from immutable stats.
    # Run authoritative fixed 60 Hz combat, including 180 countdown ticks.
    pass
func stop_battle() -> void:
    # Stop simulation, release held input, and dispose owned runtime state.
    pass
```

The root mounts inside an independent SubViewport and can be Control or Node3D.
It owns fighter initialization, combat input, simulation, cameras and combat
rendering. The integration owns chess state, requests, scene lifetime and result
settlement. Snapshots/results must use the v1 schema, match/battle IDs, player
and piece IDs, absolute match ticks and full-precision JSON conventions. The
component must emit its countdown snapshots and honor C0's timeout/double-KO
rules. Capture outcomes never come from client UI buttons.

The adapter checks root methods/signals, loads asynchronously, binds callbacks
to a generation, ignores stopped-scene callbacks and reports loading failures.
It normalizes the combat module's `message` errors to the flow's `error` field.
Its `submit_input(packet, authenticated_player_id)` bridge validates intent-only
CombatInput and binds the supplied authenticated seat to the active battle;
local human controllers submit to the mounted offline authority. Neither path
makes a client authoritative for an online match.
The match accepts snapshots/results only from its bound authority object and
checks the frozen board, identities, revision, HP bounds, timing and terminal
cause. A terminal snapshot and result must agree. Online hosting/authentication
is separate; no client-sent result is made authoritative by this local adapter.

The real-scene tests verify both human controllers, camera setup and keyboard
input through the nested SubViewport from either board view. Controls receive standard
mouse emulation for touch. The board filters emulated mouse events when handling
raw touch gestures, and its input callbacks are disabled throughout combat. A
combat controller handling both mouse and raw touch must likewise avoid double
consumption of emulated input.
Before full acceptance, Claude must implement Bishop, Rook and Queen simulation,
their role-specific attacks/abilities and portable visuals, publish its branch,
and extend combat-owned tests. Codex can then merge that handoff, extend these
real input-driven cases to every role and rerun the complete suite. King combat
belongs to the separately versioned v2 gauntlet, not this C0 contract.

## C0 rules and lifecycle

This implements `battle-checkmate-v1` documented at C0, including its prohibition
on king duels. The newer king-gauntlet request remains a separately documented
v2 design; it is not silently mixed into C0 or Classic.

- Quiet moves and castling commit immediately through the shared native rules.
- A capture must be standard-legal and leave the acting king safe in **both**
  outcomes. Check evasion, pins and discovered checks are checked before combat.
- The accepted request freezes FEN, revision, history and stable piece registry.
  EP records the actual pawn square; promotion is selected first, fights with
  pawn stats and happens only on attacker victory.
- Preview can be canceled before combat. Loading can be canceled or fail safely.
  Both leave the board unchanged and invalidate late scene callbacks/results.
- Attacker win removes the victim and moves/promotes the attacker. Defender win
  explicitly removes the attacker at origin and leaves the victim where it was.
  Both consume one ply and pass the turn; EP expires, halfmove resets, castling
  rights and Black's fullmove counter are updated deliberately.
- Combat ends with a validated result, then an aftermath display. Settlement
  occurs exactly once before the return animation. Interrupting aftermath
  commits the accepted result; it cannot discard a loss. Interrupting a return
  never reapplies it. A new match invalidates every prior battle ID.
- C0 uses automatic threefold/fifty-move/material draws and Battle-legal
  checkmate/stalemate. Chess clocks are untimed, as documented at C0. No undo or
  pause is allowed during a duel; Battle undo is disabled. Agreed draws occur
  on the board. Resignation ends the match without king removal.
- Component failure before a valid result restores the unchanged board with an
  explicit error, without inventing a winner. This local infrastructure recovery
  is not a ranked disconnect/forfeit policy or persistent crash recovery system.

C0 balance is a versioned snapshot in `godot/chess/battle_stats.json`, generated
read-only from the existing `src/battle/config.ts` by
`node --import tsx scripts/export-battle-stats.mjs --write`. Tests use `--check`, never
silently regenerate data. Speed ratings convert to m/s; durations round upward
to fixed ticks. The adapter passes these approved stats to the combat component.

## UI and shared state

Choose Classic or Battle C0 in the mode selector. Capture previews explain both
outcomes. Loading, countdown, combat, result and returning phases suspend board
move intent. Results return to the same 2D/3D view and local orientation. The
3D return animation changes only camera offset, leaving orbit preferences intact;
2D fades back in. Both views read the same survivor registry after settlement.
A failed capture is custom history, not legal SAN/PGN: Copy battle log exports
an explicit JSON chronicle. Classic's PGN behavior stays intact.

Local combat uses two human seats on one keyboard with split-screen cameras:

| Control | White (P1) | Black (P2) |
| --- | --- | --- |
| Move | WASD | Arrow keys |
| Light / heavy attack | F / G | J / K |
| Sprint / dodge | Shift / Space | Ctrl / L |
| Block / parry | Q / E | U / I |
| Ability / lock target | R / Tab | O / P |
| Orbit camera | Z / X | Comma / Period |

These controls come from Claude's `LocalInputSource`. Native combat touch controls
are not implemented there; board touch support does not imply mobile combat.

## Checks

```sh
npm ci
npm run lint
npm test
npm run build
npm run test:contracts
npm run test:classic
npm run test:battle
godot --path godot
```

`test:battle` runs C0 match/rules tests, source/replay/result validation,
consecutive battles, interruptions, UI/view preservation, real missing-scene
failure and a differential corpus against the existing C0 TypeScript authority.
`real_combat_test.gd` mounts Claude's actual arena and drives its fighters only
with contract-valid input. No HP, placement, attack state or results are injected.
It covers both outcomes, consecutive captures, EP, promotion, checkmate, input
authentication, normalized errors, teardown and both board preferences.
`npm test` also runs Claude's combat suite via `tests/combat/*.test.ts`.
`godot/tests/battle/test_combat_adapter.gd` is an explicitly injected test double,
not a combat implementation or production fallback. Native online play, physical
Windows/Android devices, exports and king-gauntlet combat are not certified here.
