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
