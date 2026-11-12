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

## Done (merged on `ccr-a4637d6e-lypbb4`; see "Verification" for what was actually run)

* Combat: six fighters (King behind `allow_experimental_roles`), data-driven balance (`godot/combat/data/balance_v1.json`),
  per-role movement, 36-pair bot matchup gate, polish (trails, impact/parry/dodge FX, hitstop, camera), procedural audio,
  Android touch controls, two-pad (DS4/Xbox) input, rebinding, pad menus + board cursor, toggleable controls overlay
  (F1 / Share / touch "?"), prediction/reconciliation/interpolation wired into the real online path (`OnlineCombatView`).
* World: top-down 3D chess board; a capture opens the contested tile like trapdoors, both pieces fall into the arena
  below, the winner climbs a ladder back and the camera returns (`godot/world/`, README there). Local play only.
* Chess opponent: six-level computer (alpha-beta, worker thread, Battle-aware capture model, `godot/chess/ai/README.md`),
  opponent selection in Classic and Battle, undo/clock/resign/draw handling, board themes + piece sets
  (`godot/boards/BOARD_THEME.md`). Levels are untuned beyond bot self-play; no Elo claims.
* UI: design-system theme (`godot/ui/theme/`), title screen, restyled application + chess HUD + settings page,
  contrast/layout/focus tests (`npm run test:ui`).
* Rules: `battle-royal-v1` King's last stand, opt-in (ADR `docs/architecture/BATTLE_ROYAL_V1.md`, contract
  `godot/contracts/royal/v1`, `npm run test:royal`). Legacy C0 untouched.
* Codex's native application, backend contracts, ENet/DTLS server merged in. Packaging: `tools/package/build_pc.sh`
  (Windows + Linux), CI updated (`.github/workflows/`), tester guide `docs/application/TESTING_GUIDE.md`.

## Verification actually run (honest list)

* Combat runner (`res://combat/tests/test_runner.gd`, also under `--fixed-fps 60`): 7,949 checks / 346 tests on the
  tree before the royal/online/artifact merges, 1 failure (pads cursor geometry, fixed); royal, net_roles, pads and
  overlay suites 1,438 checks pass after those merges.
* Codex gate pieces that passed locally on the integration tree: lint, build, test:contracts, test:battle,
  test:application, test:multiplayer; test:classic passes on a quiet machine and flakes (3D touch checks) under load.
* GitHub Actions on PR #4: native exports (Windows exe, debug APK, test-signed AAB) succeeded on `2a84383`; "Validate
  integration" failed there on a headless popup `ERROR:` that is fixed from `993ff03` on (see runs on the PR).
* Not verified anywhere: real Windows/Android hardware, real gamepads, real GPUs/phones, Windows-Android crossplay,
  human playtests, audio quality, the PostgreSQL backend in production, signing.

## Still open

| Item | State |
| --- | --- |
| Play page polish | still uses old toggle buttons ("Local ✓ / 2D board ✓"); online queue needs a spinner; disabled-button reasons only on a few buttons |
| Colour-blind option | reaches the 2D board and themed 2D highlights, not the 3D/pit board highlights |
| Chess AI | levels untuned; wall-clock budgets make moves machine-dependent; Battle: no undo, human presses Start battle when the computer captures, AI never resigns in Battle; `test:ai` not in `npm test` |
| Pit transition for ONLINE matches | not wired: `OnlineCombatView` takes any Node host now; the world must call `pit.begin / attach_arena / present_result` (see godot/world/README.md "Online path"); server countdown (180 ticks) does not wait for the pre-roll; server returns to board ~2 s after the result |
| King last-stand: menu toggle, banners, online wire format | rules/contract/server done; presentation + `network/royal` variant open; King balance recommendations (more HP / partial refresh) not applied |
| King selectable in the app / v1 server | no (v1 contract forbids it); needs a contract version |
| Contract v2 handshake (tuning stamp, `actionId`, buff field) | proposed in `docs/network/ONLINE_COMBAT.md`, not implemented (v1 is immutable) |
| Android build in the sandbox | blocked: `dl.google.com` returns 403 from the sandbox proxy; use the GitHub Actions artifact |
| Board asset adoption (GLB chess set, trapdoor/frame assets) | pit world uses procedural versions; adoption partly pending in the chess-ai worker |
| Real-device QA, performance on phones, production signing, deployment | cannot be done here |

## Next steps

1. Merge `feature/chess-ai` and `feature/ui-polish` when they report; run the full combat suite and Codex's gate on a
   quiet machine; push; read the PR's GitHub Actions results and fix what they show.
2. Wire the pit world to the online path; King last-stand menu toggle + banners.
3. Real-device testing (Windows exe from CI artifacts, Android APK from CI artifacts), controller and touch feel,
   balance playtests.

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
