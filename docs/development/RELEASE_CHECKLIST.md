# Release checklist — Peepeechess native (Godot 4.6.3)

Written 2026-11-12 against `2198dc4` (the tip of the Godot line). **The game is not release-ready.** The gameplay,
rules, combat, computer opponent and local flows are implemented and pass the headless suites; what stands between this tree and a
public release is mostly hardware QA, production deployment, signing, accounts/policy work and human playtesting, plus a few finish items.

Every item names its source so it can be re-checked. Tick an item only with evidence (a CI run, a device log, a deployed URL), and
record that evidence in [`DEVELOPMENT_STATUS.md`](../../DEVELOPMENT_STATUS.md). Items marked *(owner)* need accounts, hardware,
certificates or decisions that cannot be produced from a development sandbox.

## A. Blockers — nothing ships until these are done

- [ ] **A1. Green CI on the release candidate commit, and stable timing tests.** On `2198dc4` the *Validate integration* run failed in
  `npm run test:multiplayer` (`invalid:b-n@60ms+2%: replay rejected as stale (0)`, `scripts/test-online-combat.mjs:194`); the steps after it
  (`test:backend`, `test:application`, the Godot import/scene check) were **skipped**, so they have no CI result at that commit. The previous
  commit `745603b` was green. Measured on a quiet 4-core Linux machine (2026-11-12), the same `test:multiplayer` also fails locally, but at a
  different assertion:
  * `ONLINE PREDICTION: loopback prediction never needed a correction above 0.1 m` (`godot/tests/network/online_prediction_test.gd:139`) failed
    **3 of 6 runs** (max correction 0.122, 0.122 and 0.183 m). Every figure is a whole multiple of 0.061 m (2x, 2x, 3x), so the correction is
    measured in whole simulation ticks: it looks like a one-to-three-tick timing offset between client and server, not random noise. Its cause is
    not established; either find it or justify a threshold with the measured margin.
  * The stale-replay scenario, run alone (`test-online-combat.mjs --only=invalid`), passed **6 of 6**, so the CI failure did not reproduce. It depends
    on one unreliable UDP datagram surviving a proxy that drops 2% of packets (`godot/tests/network/combat_bot.gd`, step 0: a valid input and its exact
    replay, both unreliable), which can fail without a server defect and is more likely when the 22 fights of the full profile run in parallel. Send the
    pair reliably so the assertion no longer depends on loss.
  Every other gate passed on the same tree (lint, contracts, royal, UI, AI, battle, classic, the full combat harness, backend, the real-server
  application test). Get a fully green *Validate integration* **and** *Native exports* run on one commit, twice in a row.
- [ ] **A2. Real-device QA** *(owner)*. Nothing has run on hardware (`docs/application/TESTING_GUIDE.md`, "What works and what does not"):
  Windows start-up, SmartScreen and GPU drivers on the OpenGL renderer; Android install, safe areas/notches, touch ergonomics,
  performance, thermal behaviour and suspend/resume; two real gamepads, glyph detection and rebinding; low-end and mid-range phones.
  The project uses the Compatibility renderer (`godot/project.godot`) — measure frame time on the weakest phone you intend to support.
- [ ] **A3. Production online services** *(owner)*. Deploy the persistent account API on PostgreSQL 17 (HTTPS, backups, expired-lease and
  conflicting-report monitoring) and a supervised dedicated ENet/DTLS server with a **persistent UDP endpoint** and a real certificate
  (`docs/application/BACKEND.md`, `ARCHITECTURE.md`). Then test across the public Internet and **Windows ↔ Android crossplay**; every
  online test so far ran over loopback with a simulated latency/loss proxy. The Vercel/Redis web backend does *not* serve the native app.
- [ ] **A4. Signing and distribution** *(owner)*. Create the Android upload key and enrol in Play App Signing; the repo only has a disposable
  test key. Current identifiers: `com.peepeechess.game`, `versionCode 3`, `versionName 0.3.0`, min SDK 26, target SDK 36
  (`godot/export_presets.cfg`, `docs/application/EXPORTS.md`) — bump `versionCode` for every upload. Obtain a Windows Authenticode
  certificate (the exe is unsigned and will trigger SmartScreen). Prepare store listings, screenshots and age rating.
- [ ] **A5. Accounts and policy.** Password recovery, account deletion and email verification are **not implemented**
  (`docs/application/BACKEND.md`). Stores generally require an in-app account-deletion path for apps that create accounts, a privacy
  policy and a data-safety declaration — confirm the current Google Play / Microsoft Store rules at submission time. Add edge IP
  limiting and abuse controls in front of the API (the doc lists them as deployment work) and decide what chat/name moderation, if any,
  is needed.
- [ ] **A6. Human playtests and balance.** Balance and feel were tuned with bots only (`TESTING_GUIDE.md`). Run structured playtests of
  Classic and Battle, local and online, with both mouse/keyboard and gamepad/touch. The computer-opponent levels are untuned beyond bot
  self-play and use wall-clock budgets, so strength varies by machine (`godot/chess/ai/README.md`). Apply or reject the King/attrition
  recommendations in `godot/combat/BALANCE.md`.
- [ ] **A7. Decide the online presentation.** The trapdoor/pit transition works for **local** play only. Online captures still use the older
  arena overlay. Either wire `OnlineCombatView` to the pit (`godot/world/README.md`, "Online path"; the server countdown of 180 ticks does
  not wait for the pre-roll and the server returns to the board about 2 s after the result) or ship online with the overlay and say so.

## B. Finish items — should be done for a quality release

- [ ] **B1. Play page polish.** It still uses the old toggle buttons ("Local ✓ / 2D board ✓"); the online queue needs a spinner; the
  reason a button is disabled is shown on only a few buttons (`DEVELOPMENT_STATUS.md`).
- [ ] **B2. Colour-blind option** reaches the 2D board and themed 2D highlights but not the 3D / pit board highlights.
- [ ] **B3. Computer opponent in Battle.** No undo in Battle; the human must press *Start battle* when the computer captures; the AI never
  resigns in Battle; the AI searches with C0 (checkmate) semantics, so it treats a mate as a win and does not know a King may survive under
  King's last stand; a reactive-style computer King never attacks, so low-level computer Kings are weak. Add `npm run test:ai` to the CI gate (it is not in `npm test`).
- [ ] **B4. King's last stand online.** Rules, contract, local flow and presentation are done. The wire contract
  (`peepeechess-enet-royal-v1`) exists, but the codec, per-connection selection in `dedicated_server.gd`, an optional `ruleset` field in the
  backend allocation, lobby/client handling and a two-client loopback test are missing (`docs/architecture/BATTLE_ROYAL_V1.md`, "Remaining").
  Also open there: skipping the animation during a non-final duel re-descends for the next duel, and split-screen cameras were never
  screenshotted. The King is not selectable in the v1 server by design.
- [x] **Online play against friends** (done 2026-11-12, `ccr-a734e4c7-xxj6nw`): friends by username, requests, presence, challenges with colour choice,
  accept into the ordinary online match. Verified with 13 backend tests on SQLite and real PostgreSQL 16, 83 UI checks and the real-server end-to-end
  test (`docs/application/PLAYER_GUIDE.md`, `BACKEND.md`). **Still open for it:** blocking/reporting players, friend chat, push notifications (clients
  poll), and the online pit transition (A7). Test on real devices and across the Internet with A3.
- [x] **Ladder climb passes through the environment** (done 2026-11-12): props stowed for the climb, the walk avoids the pillars, no facing snap;
  `pit_climb` suite. Not yet seen by a person on a real GPU or device (B7).
- [ ] **B5. Contract v2 handshake** (tuning stamp, `actionId`, buff-remaining field) is proposed in `docs/network/ONLINE_COMBAT.md` and not
  implemented; v1 is immutable. Decide whether the release needs it.
- [ ] **B6. Art and audio.** Art is described as generated placeholder quality; audio quality was never judged by a person. Board asset
  adoption (GLB chess set, trapdoor/frame assets) is partly pending — the pit world uses procedural versions.
- [ ] **B7. Rendered 3D check on real GPUs.** The pit/trapdoor/ladder sequence has only been rendered in software GL under Xvfb.
- [ ] **B8. Refresh the version strings.** `godot/project.godot` still says `0.3.0-multiplayer`; the root `package.json` says `0.1.0`
  (`sovereigns-gambit`). Pick the release version and keep the exports, project and docs consistent.
- [ ] **B9. Crash and bug intake.** The tester guide routes reports to GitHub issues with manual log collection; no crash reporting is
  documented. Decide whether the release needs automated reporting and a support address.

## C. Repository housekeeping

- [ ] **C1. Finish landing the Godot line.** PR #4 was merged into `main` (`c711908`, 2026-11-12), so `main` now carries the Godot app; before
  that it pointed at the old web v1.3 (`29e267b`). Still to do: open a PR for `ccr-a734e4c7-xxj6nw` (friends, the ladder fix, the release checklist;
  it sits cleanly on `main`); `AGENTS.md` still names `develop` as the integration base, so decide whether `develop` is retired or brought to `main`;
  close PRs #2, #5 and #6 (every `codex/*` branch is already contained in `main`) and delete merged remote branches. *(owner decision; none of this
  was done automatically)*
- [ ] **C2. Decide the fate of the legacy web/Capacitor game.** It is preserved on purpose (`AGENTS.md`, `REPOSITORY_AUDIT.md`). If it
  keeps shipping it needs its own go-live work: Upstash Redis on Vercel, managed TURN, a persistent Node host for Battle Chess rooms, a
  release-signed APK (`DEPLOY-VERCEL.md`, `MOBILE-START-HERE.md`). If it is retired, say so in the README.
- [ ] **C3. Unreferenced legacy code, kept deliberately for now.** `src/components/*.tsx` (10 files) are imported by nothing in the
  running web app; the analytics/variant/tournament/puzzle modules they use are otherwise used only by `src/tests/`. `metadata.json`
  is referenced by nothing. Remove them only together with a decision on C2.
- [ ] **C4. CI hygiene.** GitHub warns that `actions/checkout@v4`, `setup-node@v4` and `cache@v4` target the deprecated Node 20 runtime.
  `npm audit` reports one moderate advisory and nothing high or critical: `ajv` 8.17.1 (GHSA-2g4f-4pwh-qvx6, a ReDoS that only applies with
  the `$data` option, which no validator in this repo enables). A non-major fix exists in 8.20.0; bump it with the contract suites as the check.
- [ ] **C5. Keep the status documents honest.** After each milestone update `DEVELOPMENT_STATUS.md` with commits, checks actually run and
  remaining issues, as its header requires. `docs/development/VALIDATION.md` is still dated 2026-11-07 (the foundation snapshot).

## D. Release process

- [ ] Freeze a release-candidate commit; tag it; write the changelog.
- [ ] Rebuild the Windows exe, APK and AAB from that exact commit in CI and record their SHA-256 values.
- [ ] Closed beta (for example Play internal testing plus a Windows tester build) using `docs/application/TESTING_GUIDE.md`; fix the
  findings; repeat A1.
- [ ] Final regression: the full gate listed in `AGENTS.md` (`lint`, `test`, `build`, `test:contracts`, `test:classic`, `test:battle`,
  `test:multiplayer`, `test:backend`, `test:application`, the Godot import/scene check) plus `test:ui`, `test:ai` and `test:royal`.
- [ ] Publish; keep a rollback build and the previous signed artifacts.
