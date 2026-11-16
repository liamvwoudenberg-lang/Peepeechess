# Implementation audit and TODO

Reviewed 2026-11-15 against integrated `main` commit
`ab7b11814cd8f212635a813219dd8cca31bd56f3`. Work branch:
`codex/implementation-audit`. `origin/develop` is still `b4c6dab`; this branch
starts there and fast-forwards to the integrated main game without moving either
shared branch. Draft PR [#12](https://github.com/liamvwoudenberg-lang/Peepeechess/pull/12)
(`b4ec83c`) has additional visual/animation work and failing checks. Its changes
are not assumed missing or silently imported here.

Scope: native chess/AI, board/settings/UI, capture orchestration, network/client/
server, account API/storage, legacy web/online/training code, tests, CI and
packaging were inspected by source, existing test coverage and published CI.
This is a bounded audit, not proof that every possible defect has been found.
Unchecked items distinguish confirmed gaps from validation still required.
Combat-owned mechanics/assets require the handoff in `docs/development/OWNERSHIP.md`.

## Work order: playable and fun (2026-11-15)

The first milestone is a complete session: open the game, choose an opponent,
make moves, play a real capture duel, return to the correct board, finish, and
start another game. The same APK must install and exercise those flows on
Android. A successful export or a headless desktop run is not Android runtime
evidence. Human combat feel still needs playtests; automated bots cannot certify
that the game is fun.

| Order | Priority | Outcome and acceptance | Findings |
| --- | --- | --- | --- |
| 1 | P0 — complete a session | Startup, menu, Classic/Battle, capture/result/return, rematch and exit work repeatedly without crashes. Human fighters must have usable controls. Review the newer arena/menu/animation branch as one candidate; keep a runnable baseline while its failing checks are repaired. Install the actual debug APK on an Android emulator/device and retain runtime logs, screenshots and a machine-readable result. Physical phone QA remains a separate gate. | I21, I13, I14, I16, I18 |
| 2 | P0 — keep human matches alive | Reconnect safely through loss, preserve seats and input counters, settle each duel once, and show an honest failure if recovery is impossible. Local impairment tests and public-device crossplay are separate evidence. | I04, I15 |
| 3 | P1 — smooth solo play | Computer captures proceed through a short readable preview into real combat without a manual Start battle click. Replacement/cancel/pause must never start a stale duel. Verify the full fight and board return. | I07 |
| 4 | P1 — understandable, interesting decisions | Recalibrate the computer's capture model against the shipped balance; preserve the selected royal rules in search. Keep attack telegraphs, role silhouettes, camera clearance and result feedback readable while verifying the visual candidate in order 1. | I05, I06 |
| 5 | P2 — finish online mode parity | Bring online play into the pit presentation, then complete the opt-in royal allocation/wire/client path without changing legacy rules. | I09, I08 |
| 6 | P2 — comfort and accessibility | Extend reduced motion through gameplay transitions and verify no blocked input or missing settlement. | I10 |
| 7 | P2 — prepare public distribution | Finish account recovery/deletion, release identity/signing and store requirements before public/store release. These do not block an explicitly labelled offline test build. | I11, I17 |
| 8 | P3 — expand only after the core loop | Additional friend features, legacy browser/device verification and deciding the fate of unused prototypes. | I12, I19, I20 |

Active work in this pass: smooth computer captures and a repeatable Android
runtime verification path, with real battle/return checks. The network failure
remains a P0 investigation; one green CI run does not close it. Existing completed
items below remain completed. The detailed IDs are stable references, not a
second priority ranking.

## Fixes started in this audit

- [x] **I01 — Colour-blind settings reach the actual 3D/pit board.**
  Previously `board_theme_view.gd` and `board_3d.gd` hard-coded colours and did
  not refresh markers on preference/style changes. They now use the existing
  safe palette for all three styles and check markers, with live refresh and
  listener cleanup. `tests/classic/accessibility_test.gd`: 30 checks passed in
  both camera modes, including distinct capture size, default restoration and
  unchanged match state. Full `test:classic`, `npm test` and `test:ai` also passed.
- [x] **I02 — Computer clock management includes presentation delays.**
  Previously search was bounded but the 0.5–0.9 s cosmetic delay and board
  animations could consume the clock. The controller now bounds the delay with
  the search budget, limits clock spending and polls flag fall before applying a
  ready move. Timed play proceeds without waiting on animations; untimed play
  still waits. `tests/ai/opponent_clock_test.gd`: eight checks passed, including
  real asynchronous moves and expiry of a ready move. Full `test:ai` passed.
- [x] **I03 — CI exercises advertised AI and royal rules.**
  Added `test:ai` and `test:royal` as explicit steps in
  `.github/workflows/validate.yml`; both passed locally. They remain separate
  from `npm test`. Repository branch protection is an administrator setting,
  not something a workflow file can silently configure.

## Detailed implementation gaps (follow the work order above)

- [ ] **I04 — Stabilize online combat admission/prediction tests.**
  `godot/tests/network/combat_bot.gd:_invalid` sends rejection probes on the lossy
  input channel, so a missing stale/forbidden count need not mean a broken server.
  Reliable CombatInput is deliberately rejected, so simply changing their channel
  is not a fix. Use acknowledged, bounded probes or a deterministic separate
  admission scenario while retaining impaired gameplay tests. Investigate the
  timing-dependent correction bound in `online_prediction_test.gd` with tick-level
  evidence; do not just raise the tolerance. Repeat the full multiplayer gate.
  **Partial fix in this audit:** the extended run reproduced
  `invalid:b-n@60ms+2%: hard snaps 1 (stalled=false)`. Continuous error was only
  0.834 m maximum / 0.021 m mean; a separate 2.517 m catchup on resuming prediction
  was counted by the same hard-snap total. The harness now records resume hard
  snaps separately and checks continuous prediction errors with the unchanged
  limits. A Node regression rejects genuine snaps, excess error, rejected
  snapshots and inconsistent counters. The focused real-socket invalid-input
  scenario passed after the change (all admission counters exercised). The
  lossy-probe and loopback timing investigations above remain open.
  The complete standalone quick profile subsequently passed all six fights
  (normal combat at 0/60/120 ms RTT, reconnect, parry and invalid inputs).
  **Fresh additional failure:** a complete rerun passed the 40-check prediction
  test and Classic/clock socket scenarios, then White lost recovery during duel
  two under 40 ms one-way delay / 10% loss. The client reported
  `UNAUTHENTICATED: Connection recovery timed out`; the authority ended at ply 5
  with `Disconnect timeout` instead of completing all four duels. Logs were
  retained at `/tmp/peepeechess-enet-Vqe5Na` in this workspace. This is separate
  from the corrected measurement bug; no disconnect/error threshold was relaxed
  and the full multiplayer gate is **not green**. Reproduce transport recovery
  with per-connection DTLS/ENet traces before declaring the online path stable.
- [ ] **I05 — Refresh the Battle chess AI's duel model.**
  `godot/chess/ai/battle_model.gd` consumes `balance_matrix_v1.json`, whose tuning
  stamp predates the shipped attacker advantage and pacing changes in
  `combat/data/balance_v1.json`. It still rates Pawn attacking Queen at 10% while
  the current balance report measures a very different outcome. Regenerate a
  version-matched matrix with the combat owner, validate its stamp, consume it in
  search, and update the heuristic tests. Do not substitute an unmeasured target
  win rate or change combat balance in the chess evaluator.
- [ ] **I06 — Royal rules must survive AI cloning and search.**
  `ChessAI.clone_engine` turns every Battle engine into `BattleChessRules`;
  `chess_search.gd` scores mate with C0 semantics. The app offers a computer with
  King's last stand, but search does not value surviving the gauntlet. Preserve
  the selected ruleset and model its terminal outcomes; test a royal survival
  position beside an unchanged C0 mate.
- [x] **I07 — Computer-initiated captures flow without manual assistance.**
  A two-second matchup preview now enters real combat through the existing bridge.
  The player can choose Fight now; an opponent's move is not offered as a
  cancellable player move. Human-initiated/local two-player previews remain
  manual. Regression checks cover pause, cancellation, new game and unavailable
  combat. The full session smoke passed real combat, touch attack, exactly-once
  settlement, pit return, continued chess, result and rematch (33 local checks).
- [ ] **I21 — Android human fighters need actual touch controls and runtime evidence.**
  Found in this pass: `BattleCombatAdapter.start` always assigned keyboard/pad
  schemes, so a mobile human with no controller never received a TouchControls
  node. The adapter now selects touch on mobile/touchscreens while retaining
  assigned gamepads. Two local humans require two assigned controllers; Play
  explains the unsupported shared-touch case before starting. Eleven routing
  checks and the full local touch/combat loop passed. The Android runtime CI job
  now installs the actual debug APK, sends real OS taps and retains screenshots,
  logs, hash and JSON result; its installed-APK result must still be verified.
  See [the Android runtime guide](docs/application/ANDROID_RUNTIME.md).
- [ ] **I08 — Wire King's last stand into online allocations and clients.**
  Local rules and additive royal schemas exist, but allocation options, wire
  selection, lobby/client flow and two-client tests are incomplete. See
  `docs/architecture/BATTLE_ROYAL_V1.md`. Add a versioned opt-in path; preserve v1
  rejection of King combat and verify reconnect in the middle of a sequence.
- [ ] **I09 — Bring online capture presentation into the pit world.**
  `online_combat_view.gd` mounts an arena overlay; the pit bridge is local.
  Countdown and server settlement must remain authoritative during descent,
  result/climb, reconnect and skipped animation. See `godot/world/README.md`.
- [ ] **I10 — Extend and verify reduced motion for gameplay presentation.**
  `ui/theme/ui_motion.gd` honours the setting; board movement and pit/camera
  transitions use separate animation flags/durations. The current setting's
  tooltip promises screen/menu transitions only; gameplay support is an
  accessibility extension, not a broken implementation of that tooltip. Audit the complete capture
  path, connect the preference, and verify immediate settlement and input recovery
  without changing combat ticks or skipping required results.
- [ ] **I11 — Native account lifecycle.** Registration/login/logout work;
  recovery, verified contact information and account deletion are absent from
  `server/native/http.ts`, service and account UI. Implement end-to-end flows with
  credential confirmation, session revocation, retained-match policy and backend
  transaction tests. Recovery needs a configured delivery provider and product
  decisions; no dummy email success response.
- [ ] **I12 — Friends safety and messaging.** Native friends/challenges exist,
  but blocking/reporting/chat/push are absent; the legacy web service having chat
  does not implement native chat. Define scope, persist permissions and test both
  peers plus an outsider. Polling is the current notification mechanism.

## Published work and remaining verification

- [ ] **I13 — Verify Android startup exits on hardware.** Player-reported exits
  after opening/menu/game startup need logcat and a device reproduction. PR #12
  contains memory/startup changes; review those first. Confirm repeated games,
  suspend/resume and memory on the affected GPU/device. Headless success cannot
  establish the reported crash is fixed.
- [ ] **I14 — Finish PR #12's animation/environment integration.** Its recorded
  remaining failures include balance checks and a Godot shutdown abort after
  passing assertions. Review its actual CI logs and obtain the combat owner's
  handoff before edits. Verify packaged startup/exit as well as all assertions.
- [ ] **I15 — Validate real online deployment and crossplay.** Local API/ENet
  tests do not establish HTTPS/PostgreSQL backups, public UDP/DTLS reachability,
  Internet reconnection or physical Windows–Android compatibility. Deploy only
  after the concrete configuration is reviewed; record real endpoint/device logs.
- [ ] **I16 — Verify shipped binaries and human gameplay.** Windows/Android,
  real controllers, phone safe areas/performance, camera clearance, audio and
  balance need hardware/human checks. Generate downloadable Windows artifacts for
  gameplay changes, record checksums and CI links; never commit the executable or
  describe a Linux smoke test as running it on Windows.
- [ ] **I17 — Complete release identity and signing.** Native project/export and
  web package versions differ; unsigned Windows/debug Android artifacts are not
  store releases. Select release versions, signing credentials, policy/support
  details and upgrade tests. Do not invent credentials or bump store versions
  without an actual release target.
- [ ] **I18 — Reconcile integration and stale status documents.** Several
  `DEVELOPMENT_STATUS.md`/release-checklist entries describe already merged work;
  `develop` predates the current main game. Bring status forward with fresh test
  evidence; decide the shared branch/old PR cleanup separately, preserving history.

## Preserved web game and reference code

- [ ] **I19 — Run the supported browser/device flows again.** Node tests cover
  web rules/storage/permissions/training; historical screenshots do not validate
  today's live site, Redis configuration, TURN connectivity or installed APK.
  Exercise browser play, guest invites, fallback/reconnect, learning and mobile
  controls against the current build. Native account tests do not cover web IDs.
- [ ] **I20 — Decide whether to expose or retire reference prototypes.**
  Unmounted `src/components/` uses mock tournament/statistics, simulated puzzle
  opponents and variant helpers. README explicitly calls these reference code;
  they are not working production features. Keep them unexposed until real
  persistence/opponents/rules and flow tests exist; remove only with an explicit
  legacy-product decision.

## Verification record

Local checks on this audit branch (Godot 4.6.3, Node 24.22.1, Linux):

| Check | Result |
| --- | --- |
| `npm run lint`, `npm run build` | Passed; Vite retains its existing large-chunk advisory |
| `npm test` | Passed again after the metrics correction: 88 Node tests, one PostgreSQL test skipped without a database; native combat 10,583 checks / 482 tests; all UI suites passed |
| `npm run test:classic` | Passed: engine/match/views, 72 reference positions / 1,962 legal moves, 30 new accessibility checks and scene smoke |
| `npm run test:battle` | Passed: frozen transactions, real combat and 106 differential positions / 747 outcomes |
| `npm run test:contracts` | Passed: shared wire and royal fixtures and Node/Godot round trips |
| `npm run test:royal` | Passed: rules, flow, session, 133 simulation checks and 899 playable-flow checks |
| `npm run test:ai` | Passed: 42 self-play games, determinism, tactics, strength, combat/UI and eight new clock checks |
| `npm run test:application` | Passed: real Godot account UI/API, ranked/private/friend games, real combat, backend/dedicated-server restart and persistence |
| `npm run test:multiplayer` | Not green: first run exposed the corrected action-resume metric bug; full rerun passed authority/roster/UI/prediction and Classic/clock sockets but failed impaired Battle reconnection at ply 5. See I04 |
| `node scripts/test-online-combat.mjs` | Passed all six standalone quick-profile fights after the correction: normal 0/60/120 ms RTT, reconnect, parry and invalid inputs. Focused invalid-input scenario also passed |

Current integrated main already has a successful
[validation run on ab7b118](https://github.com/liamvwoudenberg-lang/Peepeechess/actions/runs/43612281443).
Older release-checklist failures are historical evidence of flakes, not a claim
that the latest main CI is red.

Published [draft PR #13](https://github.com/liamvwoudenberg-lang/Peepeechess/pull/13)
contains game changes in `a8c6ea4` and the metrics correction in `ca142c1`.
[Integration CI for ca142c1](https://github.com/liamvwoudenberg-lang/Peepeechess/actions/runs/43659261911)
was started; local results above are not a claim that this remote run has finished.
The earlier game-commit CI's PostgreSQL job passed against its real database.

[Windows prerelease](https://github.com/liamvwoudenberg-lang/Peepeechess/releases/tag/audit-2026-11-15-a8c6ea4)
for the gameplay commit `a8c6ea4` was published successfully by
[the release workflow](https://github.com/liamvwoudenberg-lang/Peepeechess/actions/runs/43658895149).
Linux package smoke, static PE/PCK checks and headless Windows runner startup
passed; no physical Windows PC was tested and the executable is unsigned.
Exact downloads and checksums are in [downloads/windows/LATEST.md](downloads/windows/LATEST.md).
No executable was committed. Later changes affect validation/documentation only.
The first publishing attempt used a shortened commit ID that checkout interpreted
as a branch; retrying with the full SHA succeeded.

Production deployment, physical devices and human playtests remain open.
