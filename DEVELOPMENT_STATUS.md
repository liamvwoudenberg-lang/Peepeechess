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

## Update 2026-11-12 (Claude Code, branch `ccr-a734e4c7-xxj6nw`, on top of `2198dc4`)

This branch is the Godot line (`ccr-a4637d6e-lypbb4`, which already contained `main`, `develop` and every `codex/*` branch) plus the work below.
PR #4 (the Godot line) was merged into `main` as `c711908` while this was in progress, so `main` is now the Godot line and this branch is
four commits on top of it (`git log 2198dc4..HEAD`). No PR has been opened for them.

* **Online play against friends.** Friends by username, requests, presence, challenges with a colour choice, accepted through the ordinary
  private join into the unchanged ticket -> ENet lobby -> dedicated server path; always unranked. Backend in `server/native/`, page in
  `godot/ui/friends_page.gd`, HTTP in `contracts/application/v1/README.md`, how to use it in `docs/application/PLAYER_GUIDE.md`.
  Open: blocking/reporting players, friend chat, push notifications (clients poll), real-device and Internet testing.
* **Ladder climb passes through the environment.** Three causes, all measured with `godot/combat/tools/climb_audit.gd` on the real flow:
  (1) the winner's weapon or shield reached 0.2-0.5 m sideways and 0.13-0.76 m front-to-back beyond the 1 m opening, through the ceiling
  slab, the shaft wall and the ladder (the body fit; the props did not): they are now stowed for the climb; (2) the walk to the ladder foot
  was a straight line and crosses a pillar when the duel ends in the corner behind it: it now detours; (3) the facing snapped by up to
  180 degrees at 80% of the walk (Black winners): it now turns continuously. Suite `pit_climb` (52 checks); mutation-checked: re-introducing
  each bug makes it fail (18, 3 and 2 failed checks). Seen only in software GL screenshots and numbers, not by a person on a real GPU.
* **Repository.** Release checklist `docs/development/RELEASE_CHECKLIST.md`; stale README/TESTING_GUIDE claims fixed; two historical notes moved
  to `docs/history/`.

* **Attacker's advantage (Battle Chess).** Measured first: the attacker had none (49%/48% win rate with a casual/skilled bot) and the roster was
  unbalanced (a Pawn attacking a Queen won 1 in 100). Now a data table of damage multipliers per attacker/defender pairing boosts the weaker side
  (`attacker_edge` in `godot/combat/data/balance_v1.json`, applied in `CombatSimulation._apply_hit`); validated on independent seeds: mean 62.8%,
  every pairing 56-72%. A per-seat stamina rule (attacker unlimited, defender limited) was built, measured and ships **neutral**: it helped only
  casual play. Details, tables and limits in `godot/combat/BALANCE.md`; suite `attacker_edge`. Bot-measured only.
* **3D opening screen.** `godot/ui/opening/` (merged from `claude/opening-screen`), shown once per run.
* **Windows release pipeline.** `tools/package/build_release_local.sh`, `.github/workflows/release-windows.yml` (merged from `claude/windows-release`),
  see `docs/application/EXPORTS.md`.

Verification actually run on this branch (Linux sandbox, Godot 4.6.3, Node 22, 4 cores; 2026-11-13, on the attacker-advantage commit plus the
merged opening screen and Windows pipeline): lint; contracts; royal; UI (theme 234, layout 182, opening screen 151, application 85, views 345,
online 30, battle 31); AI; battle; classic; backend; `test:application` end to end with the real dedicated server (friends scenario included);
Godot import and scene load with no script errors; and `npm test` (87 Node tests, the full combat harness **10,055 checks in 464 tests, 0 failures**,
including the new `attacker_edge` suite, plus the UI suites). Two soak floors (events per fight) were relaxed in `test_soak.gd` / `test_roles.gd`
because a boosted Pawn can legitimately end a Knight in two hits. **`test:multiplayer` is flaky and did not pass reliably** (see below).

`test:multiplayer`, measured (RELEASE_CHECKLIST A1): on the unmodified commit `ae8191b` it passed 4 of 5 full runs (the failure was the reconnect
event-overlap ratio, now fixed in `scripts/test-online-combat.mjs`: that scenario cuts one client off for 4 s on purpose, so the ratio failed 4 runs in
10). On the attacker-advantage tree it passed only about 1 run in 10, failing on a rotating set of timing assertions that also fail on the unmodified
tree: the 0.1 m loopback prediction check (2 of 7 direct runs with fresh Godot user directories on BOTH trees: 0.122/0.183 m vs 0.122/0.244 m), the
`invalid:b-n@60ms+2%` stale/forbidden counters (the scenario passes 8 of 8 on both trees when run alone; it failed in 2 of 3 full runs on this tree and once in
CI on `2198dc4`), and a DTLS `TLS handshake error -30464` line that the script's `^ERROR:` filter flags. The sample sizes cannot separate the two trees
(prediction check about 6 of 19 vs 2 of 17 runs), so a small effect of the new default cannot be ruled out. Sending the invalid probes three times over did
not help and was reverted. Nothing in the changed prediction code path is active when no stamina rule is configured (the multiplier is 1.0).

CI note: GitHub's *Validate integration* is red on `2198dc4` (`test:multiplayer`, `invalid:b-n@60ms+2%`) and skipped the backend, application and
Godot-import steps after it. See RELEASE_CHECKLIST A1. Not fixed here.

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
| King last-stand: online wire format | local play DONE (toggle on Play page + New game dialog, banner, HUD, one-descent pit sequence, computer opponent; `royal_flow` suite); `network/royal` wire variant + online presentation open; no human playtest; King balance recommendations not applied |
| King selectable in the app / v1 server | no (v1 contract forbids it); needs a contract version |
| Contract v2 handshake (tuning stamp, `actionId`, buff field) | proposed in `docs/network/ONLINE_COMBAT.md`, not implemented (v1 is immutable) |
| Android build in the sandbox | blocked: `dl.google.com` returns 403 from the sandbox proxy; use the GitHub Actions artifact |
| Board asset adoption (GLB chess set, trapdoor/frame assets) | pit world uses procedural versions; adoption partly pending in the chess-ai worker |
| Friends | built and verified headless and end to end; open: blocking/reporting, friend chat, push notifications (polling only), real devices and the Internet |
| Ladder climb | fixed and test-covered (`pit_climb`); open: a person's look on a real GPU/device, and the online pit transition above |
| Timing-sensitive multiplayer tests | `test:multiplayer` fails intermittently (see RELEASE_CHECKLIST A1); CI is red on `2198dc4` until it is stabilised |
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
`network/royal` wire variant so online rooms can select it (local play now has the Play-page/New-game toggle, the sequence banner/HUD and the one-descent pit presentation, suite `royal_flow`), human playtests
and the King/attrition balance recommendations in godot/combat/BALANCE.md. Update this file with commits, changed paths, checks actually
run and remaining issues as each milestone lands. No completion is implied yet.
