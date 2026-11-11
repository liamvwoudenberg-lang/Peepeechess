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

---

# Codex recovery baseline (kept verbatim from `codex/persistent-board`)

## Recovery baseline — 2026-11-11

Latest integrated accessible native application: `cb54c28` on
`origin/codex/multiplayer-application` (PR6, not merged into develop).
Latest accessible Claude work inspected: `f8128ccb6507cc1b380994eed107128f11f879d1`
on `origin/ccr-a4637d6e-lypbb4`; already an ancestor of that application.
Develop is `b4c6dab`, main is `29e267b`. No inaccessible/unpushed Claude work is
assumed available. Existing worktrees and commits are preserved.

Active milestone: stationary board-world cameras and one genuine capture duel.
Codex branch/worktree: `codex/persistent-board`, `peepeechess-persistent-board`.
Published design/interface: docs/board-world/CONTRACT.md and game/network v2.

| Area | Recovered state |
| --- | --- |
| Classic rules/clocks | Implemented; legal moves, special rules, notation, FEN, undo, draw accounting, clocks and authoritative online state. Standard material cases verified, not exhaustive arbitrary dead-position proof. Reuse engine and shared match classes. |
| Existing board views | Shared chess state works; separate 2D Control and 3D world violate the new one-board requirement. Replace active presentation with camera modes on the existing 3D board. |
| Existing Battle rules/loop | C0 two-outcome king safety, frozen capture transactions, EP/promotion/castling/draw handling and trusted one-time settlement are reusable. Current local/online loop loads a separate arena and must change. |
| Combat | Pawn/Knight/Bishop/Rook/Queen mechanics, validated damage, stamina, parry/dodge/combos and abilities implemented. Reuse owner controllers/state machine. |
| Assets/animation/audio | Six model/rig/clip sets and procedural pipeline exist. King mechanics missing; victory/hit clips not fully driven; audio assets/player exist but are not mounted in the current app. |
| Multiplayer/backend | ENet/DTLS authority, input sequencing, snapshots, reconnects, matchmaking/accounts/PostgreSQL/ratings/history implemented. Socket presentation does not enable owner's prediction; its circular geometry also differs from the new board. |
| UI/platform | Native shell/settings/profiles/history/results and Windows/APK/test AAB builds verified on prior baseline. No physical Windows–Android crossplay, mobile GPU or controller ergonomics verification. |
| Dependencies | Godot4.6.3, Node24.22.1, full JDK21, SDK36/build-tools36.1 and templates available. Production native hosting/signing keys/devices unavailable. Disk budget requires staged builds. |

Fresh recovery checks: Classic engine83, match53, views345, Battle transactions250,
application protocol21, UI49, network authority62 and578combat checks/103tests
passed in read-only audits. Baseline full regression command is running; record
its final result before implementation validation. Published cb54c28 CI was also
verified green: foundation4m40s, PostgreSQL43s, native exports2m20s.

Planned architectural improvements: versioned board-world coordinates/negotiation;
one persistent camera/render world; reusable simulation lifecycle adapter using
square collisions and actual capture squares; seamless same-world presentation.

Remaining milestones: verify repeated local/online board encounters; wire tested
prediction/reconciliation to square topology; actual device crossplay/performance;
refreshed native artifacts. King's last stand: rules, contract, server session, flow
hooks and tests are DONE as the opt-in `battle-royal-v1` ruleset
(docs/architecture/BATTLE_ROYAL_V1.md; `npm run test:royal`); still open: a
`network/royal` wire variant so online rooms can select it, the `main.gd` menu toggle
that creates `BattleRoyalMatch`, presentation of the sequence banner, human playtests
and the King/attrition balance recommendations in godot/combat/BALANCE.md. Update this file with commits, changed paths, checks actually
run and remaining issues as each milestone lands. No completion is implied yet.
