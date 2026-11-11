# Peepeechess — development status

Updated by Claude Code. Branch of record for combat/integration work: `ccr-a4637d6e-lypbb4` (PR #4). Codex branches
(`codex/*`) are merged in through GitHub only; never edit another agent's worktree.

## Design decision of record (project owner, 2026-11-11)

Regular chess on a real 3D board seen from straight above, so it reads as 2D (the default view; a perspective
orbit view is also available). On a capture both pieces land on the same tile, the tile opens like trapdoors, both fall
into the underground stone arena (the existing combat arena, placed below the board), the camera dollies down after
them, the authoritative combat runs unchanged, the loser disappears and the winner climbs a ladder out of the hole,
returns to its square and the camera glides back to the top-down view. One persistent Node3D world, no loading screen,
no black fade, no scene switch, board geometry never changes (only the contested tile's trapdoor leaves move).
This supersedes the earlier "combat on the board" / "board expansion" wording.

## Done and verified (clean-checkout runs)

* Authoritative combat core (Pawn, Knight, Bishop, Rook, Queen), netcode (prediction/reconciliation/interpolation/hit
  grace/event dedupe/disconnects), arena presentation, Blender asset pipeline (6 classes, 19 clips incl. victory and
  hit reactions, LODs, collision), procedural audio (54 WAVs), touch controls, profilers. Last full run of the merged
  tree: 4482 checks across 225 tests (see "Last test runs").
* Codex's native application (menus, accounts/matchmaking protocol, ENet DTLS server, classic + battle chess) merged in
  (`integration/codex-merge`).
* PC packaging script `tools/package/build_pc.sh` (Windows + Linux; `TARGET=app|arena`).

## In progress (separate worktrees under `.worktrees/`)

| Stream | Worktree / branch | Scope |
| --- | --- | --- |
| Gameplay | `combat-core` / `feature/combat-core` | King + Royal Counter, per-role movement, `balance_v1.json`, 36-pair matchup tuning |
| Visual polish | `combat-core` / `feature/combat-core` | blending, trails, parry/block/dodge/ability VFX, hitstop, camera, CombatAudio wiring |
| Pit-battle world | `pit-world` / `feature/pit-world` | top-down 3D board, trapdoor/drop/ladder sequence, camera rig, app hook |
| Pads + controls | `pads-input` / `feature/pads-input` | two PS4 pads, rebinding, pad menu navigation, board cursor, local battle seats |
| World assets | `world-assets` / `feature/world-assets` | chess set, trapdoor, shaft, ladder, climb/fall/land clips |

## Not started / known gaps

* Computer opponent for Classic Chess (no chess AI exists in `godot/chess`).
* Board customization UI beyond what Codex's settings provide; chess clocks exist (Codex).
* Android export/APK never built or run on a device (no SDK here); Windows exe never run on Windows (built with the
  official templates, only the Linux build is executed in CI-like headless runs here).
* No human playtest of any build; balance and feel are unvalidated.
* Ranked rules, matchmaking backend deployment, accounts: Codex-owned specs only; not deployed.

## Next steps

1. Merge the finished streams into `integration/codex-merge`, run: Godot import, the full combat suite
   (`godot --headless --path godot --script res://combat/tests/test_runner.gd`), Codex's `npm run lint|test|build|
   test:contracts|test:classic|test:battle`, then push to `ccr-a4637d6e-lypbb4`.
2. Build the alpha package: `GODOT=... TEMPLATES_TPZ=... tools/package/build_pc.sh` (details in `tools/package/`).
3. Chess AI, board customization, Android export validation, performance measurements on real hardware.

## Last test runs

* Merged tree (Codex multiplayer-application + combat): 4482 checks / 225 tests, 6 failures in one touch integration
  test caused by Codex's UI content scaling; fixed in `146ccb1`, re-verification pending.
