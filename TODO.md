# Peepeechess TODO (2026-11-14, written when the weekly usage limit was nearly reached)

Branch `ccr-a734e4c7-xxj6nw` is the working branch; `GAME_DESIGN_TODO.md` (Codex, branch `codex/game-design-audit`) is the broader design/release backlog.
Everything below was only tested headless or in software rendering; nothing has run on a real PC, GPU, phone or controller.

## In progress / unmerged work (each lives in its own branch or worktree, committed but not merged)
- [ ] **Environment models** (user's Meshy models are imported in `godot/assets/environment/`): integrate the Weathered Chessboard under the 8x8 grid and the
      castle courtyard fortress around the board (decimate it first: 1.25 M triangles), and compose the underground arena from stone circle / pillar / archway /
      torch sconce / banner / ascent. Two forks started; their partial commits are in worktree branches `worktree-agent-ad6550a91a8adc350` (board + courtyard)
      and `worktree-agent-ad4bf466d7f511044` (arena). Keep simulation geometry and the ladder climb path unchanged.
- [ ] **Recalibrate the attacker table** after hit stun, narrower attack arcs and less aim assist: `edge_calibrate.gd rule=initiative` (targets: stronger piece attacking ~70%,
      mirror ~60%, weaker attacking ~50%), then `merge_edge.py --write`, update `SHIPPED_STAMP` in `test_balance.gd` and the queen gate in `test_attacker_edge.gd`.
      Until then the attacker gate and queen gate fail (e.g. Bishop attacking Queen 0%).
- [ ] **Combat Training mode + AI difficulty levels** (Easy/Normal/Hard/Expert, adaptive option, lessons, objectives from real combat events, saved progress):
      framework and lessons committed on `worktree-agent-af3743e8cc9cc7d36` (not merged, suites not verified green); the training UI (menu entry, lesson select, HUD, ratings,
      free practice) is not built.
- [ ] **Oracle Always Free deployment** (branch `deploy/oracle-always-free`, not merged, nothing run against Oracle): server exports x86_64/arm64, memory measurement, VM scripts,
      systemd units, deploy workflow, hourly A1 provisioning workflow, Windows PowerShell bootstrap, guide. Only the server build tooling is committed so far; the rest still has to be written and tested.
- [ ] **Codex branches** (`codex/castle-menu`, `codex/visual-polish`, `codex/game-design-audit`): review and merge; check for conflicts with the paladin/pit work.
- [ ] **Kinemiq/free-game-animations** (Hugging Face): not integrated by anyone; not reachable from the build container. Download it into the repo, then retarget useful clips onto the Mixamo paladin skeleton.

## Gameplay and balance
- [ ] Human playtest of Battle Chess: pacing (~28 s bot duels), hit stun, aiming (narrow arcs), attacker initiative, every pairing, abilities, King's last stand. All numbers are bot-measured.
- [ ] Pawn attacking Queen is capped at x3.0 damage; raise the cap if it should be higher.
- [ ] Rook vs Rook and Rook vs Pawn duels still run long (damage scale cannot go above 1.0).
- [ ] Replace the procedural combat animation (strafe = walk, simplified block/attack poses) and the box sword with finished assets.
- [ ] Verify the pit camera (kept inside the chamber and clear of pillars) and the arena camera in motion; the "see through the wall" report was not reproduced exactly.
- [ ] Castling and sliding moves: pieces walk straight over other pieces; make them path around.

## Release and platform
- [ ] **Android exits after the opening screen** (reported): get `adb logcat`; likely memory (character textures ~127 MB source, ~170 MB imported). Try compressed/lossy import for Android, check the new environment textures too.
- [ ] Run the Windows exe and the Android APK on real hardware (frame time, memory, controller, touch, audio, fullscreen).
- [ ] `test:multiplayer` flakes (0.1 m prediction check, `invalid:b-n` stale counter, DTLS handshake `ERROR:` line): reproduce under controlled latency/loss; decide product bug vs test timing.
- [ ] Release operations: signing (Android upload key, Windows Authenticode), versioning (`project.godot` still says 0.3.0), a public download path (the rolling `latest-windows` release only exists once the workflow runs on `main`).
- [ ] Production online services (account API on PostgreSQL, dedicated server with a persistent UDP endpoint and a real certificate), Windows<->Android crossplay test over the internet.
- [ ] Account deletion, password recovery, friend blocking/chat, store listings, privacy policy.

## Polish
- [ ] Menu polish from the cinematic brief: staggered menu entry, mouse parallax, board/pit lighting pass, UI sounds, music slider in Settings, victory title animations.
- [ ] Audio pass on headphones/speakers (generated music and impacts have never been listened to).
- [ ] Opening screen and menus on real GPUs and phones.
- [ ] Online presentation parity with the local trapdoor/pit sequence.

## Repository hygiene
- [ ] The exe is built by GitHub Actions (artifact `Peepeechess-windows-x86_64`, workflow "Latest Windows exe"); never commit it (over GitHub's 100 MB file limit).
- [ ] `newmodels/` (user's zips, 234 MB) and `godot/assets/environment/` (unpacked copies, ~228 MB) both live in git now; decide whether to keep both.
- [ ] Remove stale worktrees/branches under `.claude/worktrees/` once their work is merged or abandoned (non-forced).

- [x] Board + courtyard from the Meshy models (godot/boards/meshy_courtyard.gd): placed numerically, NOT visually checked. Verify scale/orientation of the fortress and board base in a screenshot (constants at the top of the file).

## Open at the end of the 2026-11-14 session (read this first when continuing)
- [ ] **Trapdoor / pit-fall animation is not adjusted to the new Meshy arena** (user report; needs a specific look: hole size, leaf swing, light shaft, or the drop point).
- [ ] Verify the new fortress courtyard and the arena walls in a real build (walls of the fortress were never rendered); the Meshy chessboard tray is OFF (rims cover the tiles) - rework or drop it.
- [ ] Battle Chess in the 2D view crashed on "start battle": fix in app/main.gd forces the 3D view during a duel and restores 2D afterwards. Check it in the build.
- [ ] Menu contrast: Classic/Battle buttons had dark text on a dark plaque; light text override added in ui/theme/title_screen.gd. Check other PrimaryButton uses over dark panels.
- [ ] Rendering quality: MSAA 4x + 16x anisotropic added; consider high-quality texture compression and a higher-poly fortress if it still looks soft; measure phone performance.
- [ ] Attacker-edge table recalibration to the user's targets (Queen attacking ~70%, defending ~50%) after hit stun and aiming; update SHIPPED_STAMP in test_balance.gd and the Queen gate in test_attacker_edge.gd.
- [ ] Training mode + 4 AI difficulty levels with adaptive option and lessons (branch worktree-agent-af3743e8cc9cc7d36, unmerged).
- [ ] Oracle Always Free deployment (branch deploy/oracle-always-free): server exports, systemd, deploy workflow with rollback, hourly A1 provisioning; ask before creating any infrastructure.
- [ ] Multiplayer test flakes; Android crash investigation (suspected texture memory); Kinemiq animations (needs the user to download the dataset).
- [ ] Builds: confirm the latest Windows exe (`latest-windows` release) and Android apk (`latest-android`) were produced from the newest commit; never run on real devices.

## Release plan (2026-11-16) - what is left to ship, split by who can do it
Versions are bumped to 0.4.0-rc1 (Godot), 0.4.0 / code 4 (Android + Windows presets). Full gate and owner items: `docs/development/RELEASE_CHECKLIST.md`.

Done by agents this session (all headless/software-GL tested only): Codex branches merged (castle menu, visual polish, design audit, implementation audit, paladin animation),
Meshy arena + fortress courtyard, training mode + 4 AI levels (merged `5871e52`), Oracle deployment tooling (branch `deploy/oracle-always-free` `ca9ad53`), 2D-view battle fix, menu contrast.
Running: attacker-table recalibration (scratchpad shards; finish with merge_edge.py --write, SHIPPED_STAMP, queen gate).

**Agents can still do**
- [x] Recalibration applied 2026-11-16 (stamp balance-v1:b56c6911a70dfd79): Queen ~70% attacking / ~50% defending by the bot mean; bots only, still needs a human playtest. Note merge_edge.py --write drops blocks after attacker_edge (hit_stun was re-added by hand).
- [ ] Full gate on the release candidate: `npm run lint`, `npm test`, `npm run build`, `npm run test:contracts`, `test:classic`, `test:battle` + Godot import/scene smoke (TOOLCHAIN.md).
- [ ] Multiplayer test flakes (prediction 0.1 m check, `invalid:b-n` counter, DTLS ERROR line) -> A1.
- [ ] Play page polish (old toggle buttons, queue spinner) -> B1; computer opponent in Battle (undo, auto start) -> B3.
- [ ] Online duels use the older presentation and ignore AI levels -> A7/B4/B5 (contract change is Codex-owned).
- [ ] Account policy features: password recovery, deletion, email verification (backend + UI) -> A5.
- [ ] Crash reporting / log collection -> B9. CI Node-20 action bumps -> C4. Remove stale worktrees/branches -> C1/C3.
- [ ] Trapdoor/pit-fall animation vs the new arena (needs a precise user report).

**Needs the owner (cannot be done from this container)**
- [ ] Real-device QA on Windows, Android (adb logcat for the exit-after-opening-screen report), controllers, touch -> A2.
- [ ] Production services: PostgreSQL API + HTTPS, Oracle server go-live steps in `docs/deployment/ORACLE.md`, certificates -> A3.
- [ ] Signing: Android upload key + Play App Signing, Windows Authenticode -> A4.
- [ ] Store listings, privacy policy, human playtests and balance sign-off, listen to the audio -> A5/A6/B6.
- [ ] Download Kinemiq/free-game-animations if wanted (container cannot reach Hugging Face).

## Improvement backlog (user-approved 2026-11-16, in this order of work)
### Feel and polish (biggest visible gains)
- [x] (merged `ccr-juice`; sweep/king-falls camera never rendered, legacy overlay has no sweep) **Hit feedback**: hitstop, screen shake, camera punch-ins on heavy hits, impact sparks and layered impact sound per weapon hit (hit stun exists; the juice around it is thin).
- [x] (merged `ccr-anim-ik`; partly: block/defeat/hit-reaction unchanged, foot sliding only reduced, victory/dodge not looked at, nothing watched in motion) **Animation**: hands on ladder rungs via IK (Godot 4.6 TwoBoneIK3D), ground-contact IK for the feet, proper block / parry / dodge / victory / defeat animations replacing the procedural ones; Kinemiq pack if the user downloads it.
- [x] (merged; measured only, still needs a human listen; `ONLINE UI` virtual-movement test is flaky) **Audio**: listen-and-fix pass on generated music, impacts and UI sounds, plus a music slider in Settings.
- [x] (merged `ccr-juice`; needs a look in a real pit sequence and angle tuning) **Cinematic moments**: camera sweep when a capture is declared, a victory screen, a short king-falls cutscene for checkmate duels.
### Gameplay depth
- [x] (merged `ccr-piece-identity`: Knight lunge, Bishop beam, Rook guard-break, Pawn surge; bots use them; recalibrated, stamp balance-v1:7a1e47e27f4d0966; bots only, never played by hand) **Piece identity in combat**: more distinct move sets (Knight charge, Bishop ranged strike, Rook guard-break) so pairings differ in feel, not only in numbers. Changes balance: recalibrate afterwards.
- [x] (merged: comeback bonus below 40% health, sudden-death ramp after 40 s) **Pacing**: Rook duels still run long; comeback mechanic or sudden-death phase. Changes balance: recalibrate afterwards.
- [x] (merged, headless-tested only, not seen in motion) **Pieces walking around each other**: castling and sliding moves currently walk straight over other pieces.
- [x] (merged `ccr-campaign`: 12 duels, boons, unlocks, saved run; no chess-only goals yet, skins not applied to models, never played by hand) **Roguelike / campaign mode**: short campaign of scripted fights with unlockable pieces or arenas (builds on the training lessons).
- [ ] **Variants**: bring the old web game's variants and analytics back as Battle Chess rule sets.

### Added 2026-11-16
- [x] (merged `ccr-host-play`; loopback-tested only) **Host-your-own-PC online play**: Play -> Online -> "Host a game on this PC", friends paste the invite. Needs a real two-machine test over a real router (UPnP/port-forward), Windows Firewall, Android hosting untested. See docs/application/HOSTING_GUIDE.md.
- [ ] Meshy chessboard merged (`ccr-meshy-board`): carved slab under the tiles, hides while the trapdoor is open. Not watched in motion; top-down/2D/low views not rendered.
- [ ] `overlay` suite: hot-seat split-screen check "each panel is inside its player's half of (64.0, 64.0)" failed in the Meshy-board job but PASSED in my run of world+overlay on the merged tree (1123 checks); possibly window-size dependent. Recheck.
- [ ] Online fix merged (`ccr-online-fix`): sealed invites (PCHESS2 + word code), no automatic public-IP lookup, hidden address, 15-min expiry, guest lock. Two-process localhost tests pass. NOT implemented: relay mode (designed in docs/network/HOSTING_SECURITY.md). Untested: real router/UPnP, internet, Android hosting, exported build. `test:multiplayer` exits 1 with one of three flakes each full run (DTLS handshake ERROR line, ONLINE UI virtual movement, prediction 0.122 m vs 0.1 m): diagnose and fix or relax with justification.
- [ ] **GO LIVE for online play (owner action)**: `ccr-relay-play` merged (relay play, no port forwarding). Deploy `tools/relay/relay.mjs` once (docs/deployment/RELAY.md: free PaaS render.yaml/fly.toml, or the Oracle VM + Caddy for wss://), then paste the wss:// address into Settings > Online relay (or set `peepeechess/network/relay_url` in the export). Tested only over localhost processes; relay carries the game over TCP (lossy links stall more). Multiplayer flakes fixed (3 clean full `test:multiplayer` runs; `invalid:b-n` stale replay could still be rare).
