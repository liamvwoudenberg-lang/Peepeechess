# TODO: the one list of unfinished work (2026-11-18)

This is THE list. It replaces the scattered lists (`TODO.md`, `IMPLEMENTATION_TODO.md`, `GAME_DESIGN_TODO.md` in the repo root are kept for history only).
Rules: one line per item, `- [ ] title: what is left (source)`. `(agent-ok)` = mechanical, test-heavy or well specified, fine for a cheap helper agent.
`(owner)` = needs the human (a device, an Oracle/GitHub console click, a design decision). Tick or delete an item when it is done and merged into `main`.
Everything below is "not done"; nothing here is advertised in the game (no ranked play, crossplay or store release is implied).

## Do next (in this order)

1. [ ] **Confirm the online server works from a real PC** (owner): server at `84.235.163.83:2456` (UDP 2456 opened in the Oracle security list). Run `sudo tcpdump -ni any udp port 2456` on the VM while pressing Connect in the lobby; report the lobby message. Without this nothing online is verified (docs/deployment/VPS.md).
2. [ ] **Calibrate the duel anti-mash rules** (agent-ok for the runs, owner for the playtest): long background runs of `edge_calibrate.gd rule=skill am=on` and `anti_mash.gd mode=skill|matrix`, hit the ROADMAP step 1 numbers, then switch `anti_mash.enabled` on, regenerate the chess AI capture table, update pinned tests, redeploy the server (docs/ROADMAP.md step 1).
3. [ ] **Human playtest of Battle Chess** (owner): pacing, hit stun, aiming, every pairing, King's last stand; all balance numbers so far are bot-measured (godot/combat/BALANCE.md, docs/battle-chess/FAIRNESS_PASS.md).
4. [ ] **Gothic button system + menu banners** (UI/menus): one primary/secondary/tertiary button set in the dark arched stone plaque look, normal/hover/focus/pressed/selected/disabled; menu banners first (godot/ui/theme/peepee_theme.gd, ui_kit.gd, ui_interact.gd, title_screen.gd).
5. [ ] **Duel HUD redesign** (UI): bigger HP/stamina plates, stamina cost preview with the anti-mash chain cost, exhausted and whiff-recovery states, larger action bar, side by piece glyph, no clipping in split screen (godot/combat/presentation/combat_hud.gd).
6. [ ] **Fix "Host a game on this PC"** (owner + agent): reported not working; no relay server is deployed (tools/relay exists, docs/deployment/RELAY.md). Decide: deploy the relay, or document port forwarding and the Windows Firewall prompt in the lobby text.
7. [ ] **Fix or retire the `anim_integrity` failures** (agent-ok): 11 checks (Knight lunge timing, Rook heavy, Bishop heavy) are the only red in the combat suite; fix the clips or document them as KNOWN with proof (godot/combat/tests/test_anim_integrity.gd, godot/assets/combat/ANIMATION_INTEGRITY.md).
8. [ ] **Real-device test pass** (owner): Windows exe and Android APK (frame time, memory, touch, controller, audio, fullscreen); the Android "exits after the opening screen" report needs `adb logcat` (docs/deployment/VPS.md checklist, docs/application/TESTING_GUIDE.md).

## Online

- [ ] Server connection from the owner's PC: see "Do next" 1; also check the lobby connect feedback text on a failed connect (godot/network/, online_lobby.gd, lobby_connect_test) (owner)
- [ ] Host a game on this PC: no relay deployed; decide relay vs port forwarding; Windows Firewall prompt not handled (source: lead, tools/relay, docs/deployment/RELAY.md) (owner)
- [ ] Redeploy the server whenever `balance_v1.json` changes: Actions > Build server package, then the steps in docs/deployment/VPS.md; the server refuses a client with different tuning (AGENTS.md section 5)
- [ ] Real-device test checklist in docs/deployment/VPS.md: run it end to end and tick it (owner)
- [ ] Accounts: docs/deployment/ACCOUNTS.md; not enabled on the VM, opens TCP 80/443, closes anonymous play when on, Let's Encrypt on sslip.io untested (owner)
- [ ] Account policy features: password recovery, deletion, email verification, friend blocking/chat, privacy policy (source: GAME_DESIGN_TODO I11/I12)
- [ ] Online duels use the older presentation and ignore AI levels: parity with the local trapdoor/pit sequence (source: IMPLEMENTATION_TODO I09, ROADMAP step 6)
- [ ] Wire King's last stand into online allocations and clients (source: IMPLEMENTATION_TODO I08)
- [ ] `test:multiplayer` known load flakes ("invalid:b-n replay rejected as stale", "virtual movement" in online-ui, prediction 0.1 m, DTLS ERROR line): reproduce under controlled latency/loss, fix the product bug or the test timing (agent-ok) (source: TODO.md, I04)
- [ ] Windows<->Android crossplay test over the internet; production API on PostgreSQL with HTTPS (owner) (source: TODO.md release plan A3)
- [ ] Network-simulator test with latency and packet loss, target zero desyncs at 150 ms / 2% loss (agent-ok) (source: ROADMAP step 6)
- [ ] Two deployment docs overlap (docs/deployment/ORACLE.md and VPS.md): merge them into one so the go-live steps exist once (agent-ok) (source: CLEANUP_PLAN decision 3)

## Combat / balance

- [ ] Duel anti-mash calibration and switch-on: see "Do next" 2. Rules are merged OFF (`anti_mash.enabled=false`); with them on a Pawn attacking the Queen wins 0% and the queen gate in `test_attacker_edge` fails (source: steps/01-duel-anti-mash, docs/ROADMAP.md)
- [ ] Regenerate the chess AI capture table after calibration: `godot/chess/ai/battle_model.gd` reads `combat/data/balance_matrix_v1.json` (agent-ok)
- [ ] Mid-game balance: Pawn is the weakest piece for a skilled fighter (Pawn attacks Pawn/Knight/Bishop 25-32%; docs/battle-chess/FAIRNESS_PASS.md); the casual bot sees a different roster than the skilled bot; needs a human playtest (owner)
- [ ] Contract stats compression (`battle_stats.json`) is not done (source: lead, docs/architecture/CONTRACTS.md)
- [ ] Pawn attacking Queen is capped at x3.0 damage; raise the cap if it should be higher (source: TODO.md)
- [ ] Rook vs Rook and Rook vs Pawn duels still run long (damage scale cannot exceed 1.0) (source: TODO.md)
- [ ] `anim_integrity` suite: 11 failing checks (Knight lunging-strike, Rook heavy, Bishop heavy timing); `ccr-qa-fixes-wip` had tuned timings and KNOWN entries for these, not merged (agent-ok)
- [ ] ROADMAP step 2: on-board abilities (Pawn Brace/Rally, Knight Lunge, Bishop Snipe, Rook Bastion, Queen Command, King Decree), Resolve cost, cooldown pips, AI use; acceptance 45-55% (docs/ROADMAP.md)
- [ ] ROADMAP step 4: visible terrain (Shrine, Fortress, Cursed ground, Narrow ring, Pit edge), 3 ranked presets, seeded casual (docs/ROADMAP.md)
- [ ] ROADMAP step 5: veterans, doctrines, sacrifice, all behind casual/chaos flags (docs/ROADMAP.md)
- [ ] ROADMAP step 6: online parity for every new mechanic, state-hash desync checks (docs/ROADMAP.md)
- [ ] Config layer from `ccr-config-wip` (SKIPPED, see below): balance/chess rules in `godot/config/*.json` with meta files, dev override, balance debug panel, config check/diff/quicksim tools, rules docs (docs/game/BALANCE_GUIDE.md etc.); needs re-basing on the fairness pass and a decision about where balance_v1.json lives (AGENTS.md says `godot/combat/data/`)
- [ ] Training: AI difficulty levels were never calibrated with people; Battle AI captures need the human to start the duel (source: godot/chess/ai/README.md)
- [ ] Variants and analytics from the old web game as Battle Chess rule sets (source: TODO.md backlog)

## UI / menus

- [ ] Gothic button restyle: dark arched stone plaque, silver filigree border, deep blue-violet glass interior, Gothic lettering, teal wisps (reference image is in the chat, not in the repo); one button system with 6 states; menu banners first (owner provides the image again)
- [ ] Duel HUD redesign: see "Do next" 5 (godot/combat/presentation/combat_hud.gd)
- [ ] Minimal HUD from `ui-polish` was dropped as superseded by main's floating HUD (godot/ui/game_hud.gd); if the plates/overlay-menu/idle-fade ideas are wanted, redo them on the new HUD (the old code is in git history, commit fca64d2 and 738519e)
- [ ] Menu polish: tab row wraps at 1280 px, page footer clipped, Play page ticked chips, Settings layout wastes space, Campaign page text-only (source: TODO.md 2026-11-17 review)
- [ ] Check every PrimaryButton over dark panels for contrast (source: TODO.md)
- [ ] Audit all menus for one visual language: typography, spacing, states, empty/error/loading (source: GAME_DESIGN_TODO P1)
- [ ] Keyboard/screen-reader/controller/touch accessibility review; colour-blind settings for all 3D highlights (source: GAME_DESIGN_TODO)
- [ ] Optional onboarding for chess movement, capture battles, controls (source: GAME_DESIGN_TODO)
- [ ] Verify the HUD at phone and desktop sizes, high UI scaling, safe areas, split-screen (agent-ok, screenshots) (source: GAME_DESIGN_TODO)
- [ ] Cinematic 3D menu: flights never watched in motion; clickable props tested numerically only; typography needs a font; owner answers to the open questions in docs/ui/CINEMATIC_MENU.md (owner)
- [ ] Localization workflow if an international release is wanted (owner decision)

## Presentation / audio

- [ ] Board look decision (owner): `BoardLook.SCENERY_ENABLED=false`: ui-polish's procedural dais/walls/braziers (godot/boards/board_scenery.gd, board_fx.gd) are built but switched off because main's courtyard + Meshy fortress already fill the scene; pick one or make them cooperate, then look at it in a real build
- [ ] Look at the merged board in a real GPU build: marble/slate squares + Meshy slab, taller pieces + footprint rings, camera 1.13/12.7, ring marks; nothing of this was seen in motion (owner)
- [ ] Wave-1 cinematic overlays (capture intro, finishing blow, result, loading) and graphics presets only tested headless; watch them (owner)
- [ ] Trapdoor / pit-fall animation vs the new Meshy arena (needs a precise report) (source: TODO.md)
- [ ] Verify the fortress walls, the pit camera and the arena camera in motion; Meshy chessboard tray is OFF (source: TODO.md)
- [ ] Audio: Sonniss build script (`tools/audio/build_sonniss.py`, from `audio-sounds`, never run end to end; the 187 MB of raw WAVs stay on that branch, not in main); run it, map sounds, listen on headphones and speakers; generated music/impacts never listened to (owner for listening)
- [ ] Audio buses (Music/SFX/UI/Ambience) and the Ambience slider are merged; check ducking and settings persistence on a device (source: claude/wave1-anim-audio)
- [ ] Replace procedural combat animation (strafe = walk, simplified block/attack) and the box sword with finished assets; Kinemiq/free-game-animations not integrated (owner downloads the dataset)
- [ ] ROADMAP step 3: duel presentation (camera push-in ring, presentation clock slow-mo/hit-stop, piece personality, board memory, dynamic audio layers, versus card, replay camera) (docs/ROADMAP.md)
- [ ] Reduced motion for gameplay presentation (source: IMPLEMENTATION_TODO I10)
- [ ] Controller rumble and Android haptics on real devices (owner)

## Content / world

- [ ] Verify the enlarged pieces and tighter framing on narrow phones/tablets and all camera angles (source: GAME_DESIGN_TODO)
- [ ] Make king/queen and all roles distinguishable from above on both square colours; crest legibility at playing size (source: GAME_DESIGN_TODO)
- [ ] Courtyard lighting, shadows, dark-team visibility, seams at tactical and close camera (source: GAME_DESIGN_TODO)
- [ ] Castling and long slides: pieces path around others (merged in 6ded615) - verify in motion and with promotions/en passant (source: TODO.md)
- [ ] Campaign: twelve scripted duels merged; human playtest of pacing, boons, bosses (owner) (source: docs/application/CAMPAIGN.md)
- [ ] Training mode and lessons: human check (owner)
- [ ] Onboarding text and tooltips per mode (source: GAME_DESIGN_TODO)

## Build / deploy / cleanup

- [ ] Windows exe: after pushing `main`, check Actions > Latest Windows exe succeeded (artifact `Peepeechess-windows-x86_64`); it has never been run on a real Windows PC (owner)
- [ ] Android APK/emulator CI (`android-runtime`): last run failed on OS touch dispatching a combat attack; `ccr-touch-fix` was investigating; signing keys, versioning (`project.godot` says 0.3.0), store listings (owner)
- [ ] Windows Authenticode, Android upload key, release identity (owner) (source: IMPLEMENTATION_TODO I17)
- [ ] Delete the merged remote branches on GitHub (owner; the proxy refuses `git push origin --delete`): list in docs/development/WORK_IN_PROGRESS.md
- [ ] CLEANUP_PLAN stage 1: docs index, fix 5 broken doc refs, move root docs, `.editorconfig`, gdlint non-blocking CI, `review/` scripts to `tools/audit/`, `CONVENTIONS.md` (agent-ok)
- [ ] CLEANUP_PLAN stage 2: unused arguments, duplicated loads, unassigned expressions, delete `ui/application_theme.gd` (agent-ok)
- [ ] CLEANUP_PLAN stage 3: delete ~20 redundant Meshy PNGs (45 MB) after verifying renders; paladin `*_Image_N.jpg` after the Android memory check (owner approves)
- [ ] CLEANUP_PLAN stage 4: move `godot/combat/tests` to `godot/tests/combat` and `godot/combat/tools` to `godot/tools` (only with no open branch touching them) (agent-ok, risky)
- [ ] CLEANUP_PLAN stage 5: split the large files, behaviour-neutral, one per commit (agent-ok, golden tests)
- [ ] CLEANUP_PLAN stage 6 (owner): `newmodels/` 224 MB duplicate of `godot/assets/environment`; legacy `src/` web game keep/freeze/retire; stale remote branches
- [ ] `ccr-old-fortress-wip` (SKIPPED): holds `tools/environment/decimate_fortress.gd` plus two Python wheels (17 MB, never commit) and an older `fortress_decimated.res`; main already uses the Meshy fortress, so likely delete the branch (owner)
- [ ] `ccr-qa-fixes-wip` (SKIPPED): balance numbers there predate the fairness pass (would undo it); only `godot/combat/tools/qa_smoke.gd` was taken. Its `battle2d` case fails headless ("start battle reaches combat (phase countdown)"): investigate whether it is a tool problem or a real 2D-battle regression (agent-ok)
- [ ] CI Node-20 action bumps, crash reporting / log collection (source: TODO.md C4/B9)
- [ ] Stale `.claude/worktrees` cleanup, non-forced (source: TODO.md)
- [ ] Production release operations: versioning, download path, release checklist (docs/development/RELEASE_CHECKLIST.md) (owner)

## Tests

- [ ] `anim_integrity` (11 failing checks): see Combat/balance
- [ ] `npm run test:multiplayer` was NOT run for the 2026-11-18 branch merges (they touched no network code); run it alone before the next release (~12 min)
- [ ] Combat suite process ends with a heap error message after printing its summary ("corrupted size vs. prev_size" / "malloc_consolidate"); harmless to results so far, find the cause (agent-ok)
- [ ] `overlay` suite: hot-seat split-screen "each panel is inside its player's half" failed once in a Meshy-board job; possibly window-size dependent; recheck (agent-ok) (source: TODO.md)
- [ ] Re-run the anti-mash harness numbers once calibrated and add acceptance tests for them (ROADMAP step 1 acceptance: timing beats masher >= 70%, matrix 35-65% except Pawn-Queen 15-25%, median <= 35 s, timeouts < 5%, attacker 47-52%) (agent-ok)
- [ ] Android emulator CI: leaving a match hit an audio ERROR (guarded in db31b92, not re-run) (source: TODO.md)
- [ ] Human playtests cannot be automated: balance sign-off, art quality, audio (owner)
