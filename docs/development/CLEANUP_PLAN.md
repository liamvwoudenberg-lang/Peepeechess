# Cleanup and organisation plan

Status: **audit and plan only (2026-11-17). Nothing was moved or deleted.** Evidence comes from three read-only scripts in `tools/dev/`
(`find_unreferenced.py`, `check_doc_links.py`, `res_refs.py`), `gdlint` 4.5.0 run from a scratch virtualenv, and plain `du`, `wc` and `git`.
The audit ran on `origin/ccr-a734e4c7-xxj6nw` at `e96b915`. Re-run the scripts before every stage: numbers drift as other jobs merge.

Execute only after `ccr-qa-fixes` and `ccr-config` are merged (section 5, stage 0), because both touch files that stage 2 to 5 would move.

## 1. Map of the repository today

| Path | Size | What it is |
|---|---|---|
| `godot/` | 387 MB (assets 381 MB) | The Godot 4.6.3 game. 326 `.gd` files, 67.4k lines. The product. |
| `godot/assets/` | 381 MB | `environment` 230 MB (Meshy FBX and extracted PNGs), `paladins` 131 MB (GLB models, source JPGs, clips), `combat` 16 MB, `world` 5 MB, `board` 0.4 MB. |
| `godot/combat/` | 2.5 MB, 273 files | Combat core, net, AI, presentation, audio, input, data, plus 46 test files (`combat/tests`) and dev tools (`combat/tools`). Owned by Claude Code. |
| `godot/{app,chess,boards,world,ui,network,training,campaign,paladins,audio,contracts}` | 0.03 to 0.7 MB each | Application shell, chess rules/AI, 3D board, pit world, menus, networking, training, campaign, paladin models/clips, music director, wire contracts. Mostly Codex-owned. |
| `godot/tests/` | 0.9 MB, 136 files | Godot integration tests by area (`ai`, `battle`, `classic`, `network`, `royal`, `ui`) run through `scripts/test-*.mjs`. |
| `src/` | 4.1 MB, 73 TS files, 24.3k lines | The **legacy** React/Three/Capacitor web game (Classic, Battle 2D, puzzles, variants, multiplayer). |
| `server/`, `api/`, `server.ts` | 0.2 MB | Node account/online API and battle server. `server/*.ts` imports code from `src/` (see 3.7). |
| `contracts/` | 0.1 MB | TypeScript wire/application contracts (versioned). Shared with `godot/contracts`. |
| `scripts/` | 0.2 MB | npm test runners (`test-*.mjs`), export scripts, Android verifier, web build helpers. |
| `tools/` | 1.4 MB | Offline pipelines: `audio`, `blender`, `environment`, `package`, `paladins`, `relay` (Node relay), `training`, `dev` (these audit scripts). |
| `tests/` | 0.3 MB | Node tests and Python browser tests, most of them for the legacy web game, plus `native-*.test.ts`, `android_verifier_test.py`. |
| `docs/` | 16 MB | 19 sub-folders; 5 MB of screenshots under `docs/ui`. |
| `newmodels/` | **224 MB** | The user's original Meshy zips (107 MB) and the unpacked fortress (120 MB). Duplicates what is already in `godot/assets/environment`. |
| `android/`, `public/`, `capacitor.config.json`, `index.html`, `vite.config.ts`, `vercel.json`, `metadata.json` | 0.5 MB, 2.3 MB | Legacy Capacitor/web shell and its assets. |
| `review/` | small | Six old audit scripts (`browser-audit.py`, `clock-audit.mjs`, ...) at the repo root. |
| `.github/workflows/` | 4 files | `validate`, `native-exports`, `latest-windows-exe`, `release-windows`. |
| Root `*.md` | 1,147 lines in 9 files | `README`, `AGENTS`, `TODO`, `DEVELOPMENT_STATUS`, `IMPLEMENTATION_TODO`, `GAME_DESIGN_TODO`, `BATTLE-CHESS`, `MOBILE-START-HERE`, `DEPLOY-VERCEL`. |
| `.git/` | ~0.8 GB | History includes big binaries (older exe zips squashed locally; Meshy zips). Not touched. |

Remote branches: 35. **34 are fully merged into the working branch** (`ccr-*`, all `codex/*`, `develop`, `main`); only `deploy/oracle-always-free` is not.

## 2. Evidence: findings by category

### 2.1 Unreferenced GDScript
`python3 tools/dev/find_unreferenced.py` (roots: `project.godot`, tests, tools; references by `res://` path, class name or file name):

- **1 unreferenced script:** `godot/ui/application_theme.gd` (1.8 KB). Its own comment says the legacy builder "is kept only for reference/compat"; `res_refs.py` finds 0 references. Candidate for deletion (Codex-owned path).
- **7 `class_name`s never used outside their file** (the files are loaded by `preload` path): `CampaignPage`, `ClassicPieceMeshes`, `ContractCodec`, `NetworkRateBudget`, `NetworkWireCodec`, `StrictNetworkJson`, `TrainingPage`. Harmless; either drop the `class_name` or keep it as documentation. Low priority.
- **0 orphan `.uid` and 0 orphan `.import` sidecars.** The import state is clean.

### 2.2 Unused or redundant assets
The scan classes an asset as referenced if its `res://` path, name or directory prefix appears anywhere in the repo text. 43 files (51 MB) have none of those:

- **20 extracted Meshy textures, 45.3 MB, very likely redundant.** `godot/assets/environment/<model>/Meshy_AI_*_texture_N.png` for pillar, archway, torch sconce, ascent and banner (and `_1` to `_3` of others). The FBX `.import` files have `materials/extract=0`, i.e. the FBX uses its embedded textures; `tools/environment/extract_models.py` also wrote these PNGs next to it. Code only loads `stone_circle_0` and `fortress_0` (and the chessboard FBX). **Verify before deleting:** remove in a scratch branch, run `godot --editor --import`, then the `world`, `menu_world`, arena render and `test:ui`.
- **Probably false positives (loaded through built strings):** `*_lod1.glb` and `*_collision.glb` (`character_model.gd` formats `"%s/%s/%s%s.glb"`), `combat/textures/*_Steel|Leather|Cloth.png`, `world/board/*` tiles. Do not delete without checking the loader.
- **Referenced only by a test:** the 18 `godot/assets/paladins/<role>_Image_N.jpg` source images (52 MB) appear only in `godot/tests/paladin_memory_test.gd`. They look like extraction leftovers of the GLBs (the textures are embedded in the GLB too). Keep until the Android memory investigation (TODO) is finished, then verify by deletion in a scratch branch.
- Another 266 files (215 MB) have only name/directory mentions (dynamic loads): models, animations, textures. Listed by the script; treat as used.
- Biggest single files: `courtyard_fortress` FBX plus its 20 MB `_1.png`, six paladin GLBs of about 10 MB each, `fortress_decimated.res` (2.3 MB, the one actually used).

### 2.3 Duplicate data
- `newmodels/` (224 MB) vs `godot/assets/environment/` (230 MB): the same Meshy models twice (zips and unpacked fortress at 120 MB). `extract_models.py` can regenerate the second from the first. Decision for the owner (section 4).
- Source clips in `tools/paladins/animation_source/*.glb` (with `LICENSE.txt`) alongside the retargeted clips in `godot/assets/paladins/animations`: intentional (sources), documented in its README.

### 2.4 Code health (gdlint 4.5.0, default rules)
7,330 findings: **6,940 are "line longer than 100"**, 299 are "definition out of order", only **91 substantive**:
- 20 unused function arguments (e.g. `combat_ai.gd:377 dist`, `:400 opp`, `character_model.gd:285 kind`, `combat_vfx.gd:451 target`, `balance_data.gd:473 abilities`, `control_bindings.gd:342 device`, plus tests and `anim_audit*.gd`),
- 7 duplicated loads (`stone_arena_visuals.gd:386`, `ui_prefs.gd:127`, `title_screen.gd:13`, `test_music.gd:59,93`),
- 4 "expression not assigned" in tests (`test_pads_ui.gd:58`, `test_royal_flow.gd:167`, `test_world.gd:176`, one more),
- 3 files over 1,000 lines (`test_royal_flow.gd` 1,132, `tools/anim_audit.gd` 1,314, `ui/application.gd` 1,044), 2 functions with more than 6 returns (`submit_request`), 2 non-conforming local names (`_unused`, `P`).
The repo's style is long lines with tabs, so the default 100-column rule must be relaxed (see 3.4). `gdformat --check` would reformat most files: **do not adopt gdformat**, a mass reformat would bury history.
Debug output: only **3 `print(` calls** in non-test, non-tool game code (`server_main.gd`, `match_session.gd`, `account_backend.gd`, all server logs). **0 `TODO`/`FIXME`/`HACK`** comments in `godot/**/*.gd`. **0 `print_debug`/`breakpoint`.** The code is clean here.

### 2.5 Large files and functions (game code, excluding tests)
Top 25 by lines (all `.gd`): `combat/tools/anim_audit.gd` 1314, `combat/tests/test_royal_flow.gd` 1132, `ui/application.gd` 1044, `combat/tests/test_pads.gd` 952, `test_overlay.gd` 879, `test_pads_ui.gd` 859, `test_world.gd` 818, **`world/pit_sequence.gd` 810**, **`app/main.gd` 762**, **`combat/presentation/vfx/combat_vfx.gd` 735**, **`combat/audio/combat_audio.gd` 712**, `combat/presentation/control_overlay.gd` 658, `combat/core/combat_simulation.gd` 650, `test_net_latency.gd` 648, `ui/opening/castle_builder.gd` 619, `test_roles.gd` 609, `combat/data/balance_data.gd` 609, `ui/opening/opening_scene.gd` 597, `ui/opening/menu_world.gd` 580, `chess/ai/chess_search.gd` 576, `combat/presentation/character_model.gd` 568, `combat/arena.gd` 554, `combat/net/combat_net_client.gd` 542, `tests/ui/opening_screen_test.gd` 525, `network/client/online_lobby.gd` 523.
17 functions exceed 80 lines: `combat_ai.gd think` 155, `chess_eval.gd evaluate` 147, `chess_search.gd negamax` 135, `playability_smoke.gd run` 135, `title_screen.gd build` 125, `online_lobby.gd _build_ui` 107, `character_model.gd _drive` 103, `third_person_camera.gd _process` 101, `paladin_clips.gd _specs` 96, `arena.gd _build_presentation` 96, `board_3d.gd setup` 95, `stone_arena_visuals.gd _build_meshy` 94, `board_3d.gd sync_state` 89, `network_client.gd _packet` 88, `game_hud.gd build` 87.
Suggested splits (stage 5): `ui/application.gd` into one builder file per page (the pattern already started by `training_page.gd`, `campaign_page.gd`, `friends_page.gd`, `settings_page.gd`); `app/main.gd` into lifecycle, battle wiring and HUD wiring; `pit_sequence.gd` into phases; `combat_vfx.gd` per effect family; `combat_audio.gd` into mixer, ducking and sound table; `anim_audit.gd` into capture and report; the two large tests per feature area. Do **not** split `chess_eval/search` or `combat_ai.think` without benchmarks and golden tests.

### 2.6 Inconsistent naming and placement
- **Tests live in two trees.** `godot/combat/tests/` (46 `test_*.gd`, runner `godot/tests/run_combat_tests.gd` in the *other* tree) and `godot/tests/` (136 files by area, `*_test.gd` naming). Two naming conventions (`test_*.gd` vs `*_test.gd`).
- **Dev tools in two places:** `godot/combat/tools/` (calibration, audits, screenshot tools, 1,300-line `anim_audit`) vs top-level `tools/` (offline pipelines) vs scratch scripts that only existed in a session scratchpad.
- **`review/`** holds audit scripts that belong under `tools/audit/` (or `tools/dev/`).
- **Docs:** 9 root `.md` files; four of them are not entry points (`IMPLEMENTATION_TODO.md`, `BATTLE-CHESS.md`, `MOBILE-START-HERE.md`, `DEPLOY-VERCEL.md`, the last two for the legacy web/Capacitor build). `godot/combat/` has its own `BALANCE.md`, `NETWORKING.md`, `CODEX_HANDOFF.md`, `CONTROLS.md`, `TOUCH.md`, `README.md` (good locality, but not linked from `docs/`).
- `godot/combat/scenes/` holds one scene (`character_gallery`) while `godot/combat/tools/` also holds scenes (`arena_shots.tscn`).
- Naming: scripts are `snake_case.gd`; classes are `PascalCase`; assets mix `Meshy_AI_..._20261114_texture.fbx` (very long) with short names. Add a naming rule (3.2).

### 2.7 The legacy web game
`src/` (24.3k lines), `index.html`, `vite.config.ts`, `public/`, `android/` (Capacitor), `capacitor.config.json`, `tests/*.py` browser tests, `tests/*.test.ts`, `scripts/pwa-build.mjs`, `scripts/draw-legions.ts`, `scripts/render-*.py`, `vercel.json`. **It is not dead:** `npm test` and `npm run build` still run it, `server/battleServer.ts`, `onlineService.ts`, `store.ts`, `chessService.ts` import from `src/`, and `AGENTS.md` says to preserve it while the Godot client is migrated. `docs/development/RELEASE_CHECKLIST.md` C2/C3 lists it as an open decision (10 unreferenced React components under `src/components`). **No change without the owner's decision.**

### 2.8 Documentation
`python3 tools/dev/check_doc_links.py` checked 384 references in 62 Markdown files: **5 broken**:
- `IMPLEMENTATION_TODO.md`: `tests/ai/opponent_clock_test.gd`, `tests/classic/accessibility_test.gd` (missing the `godot/` prefix).
- `MOBILE-START-HERE.md`: `android/app/build/outputs/apk/debug/app-debug.apk` (a build output; say so).
- `TODO.md` and `docs/deployment/RELAY.md`: `docs/deployment/ORACLE.md` exists only on the unmerged `deploy/oracle-always-free` branch.
Also stale: `DEVELOPMENT_STATUS.md` and `docs/development/RELEASE_CHECKLIST.md` still say version `0.3.0` in places (a session bumped Godot/Android to 0.4.0-rc1), and `AGENTS.md` still describes a React/Three/Capacitor "preserve" rule.

### 2.9 CI and tooling
Four workflows; `native-exports.yml` already carries the Android emulator job. `package.json` `lint` is only `tsc --noEmit`: **no ESLint, Prettier, `.editorconfig` or GDScript lint** exist. `npm test` mixes legacy and native runners. GitHub warns that `checkout@v4`, `setup-node@v4`, `cache@v4` use Node 20 (RELEASE_CHECKLIST C4).

## 3. Target layout, conventions and lint

### 3.1 Target layout (proposed)
```
godot/
  app/ boards/ world/ chess/ network/ training/ campaign/ paladins/ audio/ contracts/ ui/ combat/   (as today)
  config/                     balance + rules (from the ccr-config job)
  tests/
    combat/                   <- godot/combat/tests/*  (git mv; keep names, rename test_X.gd -> X_test.gd)
    chess/ ai/ battle/ classic/ network/ royal/ ui/ ...   (as today)
    run_combat_tests.gd       (runner stays)
  tools/                      <- godot/combat/tools/* (calibration, audits, screenshot tools)
  assets/
    environment/<model>/      one .fbx (embedded textures) + .import; no extracted PNG copies unless loaded by code
docs/
  README.md                   index of everything below
  game/ architecture/ application/ network/ development/ deployment/ ui/ history/   (merge the small legacy folders into history/)
tools/
  audio/ blender/ environment/ package/ paladins/ relay/ training/ dev/ audit/ (<- review/)
scripts/                      npm runners only (test-*.mjs, export-*.sh, verify-android.py)
```
Root keeps: `README.md`, `AGENTS.md`, `TODO.md`, `DEVELOPMENT_STATUS.md`, `GAME_DESIGN_TODO.md`, `package.json` and config files. `IMPLEMENTATION_TODO.md`, `BATTLE-CHESS.md`, `MOBILE-START-HERE.md`, `DEPLOY-VERCEL.md` move under `docs/` (`docs/history/` or `docs/legacy-web/`).

### 3.2 Conventions to document in `docs/development/CONVENTIONS.md`
- Files `snake_case.gd`; classes `PascalCase`; constants `UPPER_SNAKE`; private members `_leading_underscore`; tests `<subject>_test.gd` under `godot/tests/<area>/`; dev tools under `godot/tools/` or `tools/<area>/`, never beside game code.
- One responsibility per file; soft limit 600 lines for game code, 1,000 for tests; functions over 80 lines need a reason in a comment.
- Asset names short and lowercase (`stone_circle.fbx`); keep the vendor name in a README, not the file name.
- Every moved file: `git mv`, then rewrite references with a script (`res://`, `preload`, `load`, `.tscn`, `.tres`, `project.godot`, docs), then `godot --editor --import` and the full gate.

### 3.3 Style and lint
- **GDScript:** adopt **`gdlint`** (gdtoolkit 4.5.0 installs fine with pip, Godot 4.x syntax) with a repo config that fits the existing style: raise `max-line-length` to about 200, disable `class-definitions-order`, keep unused-argument, duplicated-load, expression-not-assigned, naming and `max-file-lines` (1,500 for tests). Verify the config keys with `gdlint --help` (a quick first attempt at a relaxed config did not change the counts; confirm the config file name and key spelling before relying on it). Run it in CI as **non-blocking** first, then block on the 91 substantive findings after stage 2. **Do not adopt `gdformat`** (reformats most files).
- **TypeScript/JS:** keep `tsc --noEmit`; add `.editorconfig`; optional ESLint with a minimal recommended config only if the legacy web game stays.
- **Python:** `ruff check` with the default rules for `tools/` and `scripts/` (not yet installed here).
- **Docs:** keep `check_doc_links.py` in CI (read-only, exit 0 today; add a `--strict` flag later).

### 3.4 Automatic-safe subset vs needs the owner

| Item | Safe automatically? | Who owns the path |
|---|---|---|
| Fix the 5 broken doc references; add `docs/README.md`; move the four root docs under `docs/` | yes | `docs/**` and root: Codex |
| Add `.editorconfig`, gdlint config, CI non-blocking lint job; add `tools/dev/` (done) | yes | `.github/**`, root config: Codex |
| Prefix unused arguments with `_`, remove 7 duplicated loads, fix 4 unassigned expressions, drop 7 unused `class_name`s | yes (behaviour-neutral; run the gate) | mixed: `godot/combat/**` Claude; `godot/ui,network,boards,chess,app/**` Codex: **needs a handoff for Codex paths** |
| Delete `godot/ui/application_theme.gd` | yes after `res_refs.py` re-check | Codex (`godot/ui/**`) |
| Delete the 20 redundant extracted Meshy PNGs (45 MB) and stop `extract_models.py` writing them | yes after scratch-branch verification | `godot/assets/environment`: unlisted, so Codex |
| Move `godot/combat/tests` to `godot/tests/combat` and `godot/combat/tools` to `godot/tools` | **needs handoff**: ownership table gives `godot/combat/**` and `tests/combat/**, godot/combat/tests/**` to Claude and `godot/tests/**` to Codex | both |
| Split `ui/application.gd`, `app/main.gd`, `world/pit_sequence.gd`, `network/online_lobby.gd` | **needs handoff** (Codex-owned) | Codex |
| Split `combat_vfx.gd`, `combat_audio.gd`, `anim_audit.gd` | needs coordination with the combat owner | Claude |
| Delete the legacy web game (`src/`, `android/`, `public/`, web `tests/`, `server/` coupling) | **owner decision** | Codex |
| Delete `newmodels/` | **owner decision** | n/a |
| Delete remote branches, local worktrees | **owner decision** (34 merged branches are only labels now; AGENTS.md forbids forced removals) | n/a |
| Rewrite history to shrink `.git` | **no** (published history must not be rewritten) | n/a |

## 4. Decisions needed from the owner
1. **Legacy web game:** keep (it still feeds `npm test`, `build` and the Node server), freeze it under `legacy/` (move, keep working), or retire it after the Godot client ships?
2. **`newmodels/`:** delete (the zips are your originals; they stay in your downloads and in git history), or keep as the source of truth and untrack the unpacked `godot/assets/environment` extras?
3. **Remote branches:** delete the 34 merged branches (history stays in `develop`/`main`), or keep them as bookmarks? And what to do with `deploy/oracle-always-free` (not merged; `ORACLE.md` is referenced by two docs)?
4. **Test and tool folders:** approve moving `godot/combat/tests` to `godot/tests/combat` and `godot/combat/tools` to `godot/tools` (a cross-owner move: Codex and Claude both need to confirm they stopped editing those paths).
5. **Assets:** approve deleting the redundant Meshy PNGs after the verification, and the paladin `*_Image_N.jpg` after the Android memory investigation.
6. **Style:** approve gdlint (non-blocking first) and **no** gdformat.

## 5. Execution plan (stages, risk, gate)
Rules for every stage: one commit per stage, `git mv` only, update every reference by script (`tools/dev/res_refs.py` lists them), never rewrite published history, never force-push, never remove a worktree with uncommitted work. Branch from the newest `ccr-a734e4c7-xxj6nw` after stage 0.

**Gate after each stage (from `AGENTS.md`):** `npm run lint`, `npm test`, `npm run build`, `npm run test:contracts`, `npm run test:classic`, `npm run test:battle`, `npm run test:ui`, the headless Godot import (`godot --headless --path godot --editor --import`) and scene smoke commands in `docs/development/TOOLCHAIN.md`, the Godot suites `world`, `balance`, `attacker_edge`, `piece_identity`, `campaign`, `training_ui`, `pads_ui`, `paladin_anim`, and `npm run test:multiplayer` for any stage touching `godot/network`. Stage 3 and 4 also need the Android emulator job.

| Stage | Content | Risk | Size | Extra check |
|---|---|---|---|---|
| 0 | Merge `ccr-qa-fixes` and `ccr-config`; freeze other jobs; re-run the three tools | low | none | tools output saved to the PR |
| 1 | Docs and tooling: fix 5 broken refs, `docs/README.md` index, move four root docs, `.editorconfig`, gdlint config + non-blocking CI job, `review/` to `tools/audit/`, `CONVENTIONS.md` | very low | about 30 files | `check_doc_links.py` returns 0 broken |
| 2 | Code hygiene: unused arguments, duplicated loads, unassigned expressions, `class_name` cleanup, delete `application_theme.gd` | low | about 25 files, under 200 changed lines | gdlint: 0 substantive findings |
| 3 | Assets: delete 20 redundant Meshy PNGs (about 45 MB), update `extract_models.py`, shorten names only if every reference is rewritten | medium | 40 files | `find_unreferenced.py` re-run; render the arena, hall and board; Android emulator job |
| 4 | Move `godot/combat/tests` to `godot/tests/combat` and `godot/combat/tools` to `godot/tools`; unify test naming | medium (many paths; needs both owners) | about 120 files renamed | full Godot suites; `scripts/test-*.mjs` paths |
| 5 | Split the large files in 2.5, one file per commit, behaviour-neutral | medium to high | about 10 files | golden tests for AI, `test:battle`, `test:multiplayer`, menu and world suites |
| 6 | Owner-decision items: legacy folder, `newmodels/`, branches | depends | up to 224 MB | per the decision |

Merge-conflict mitigation: do stages 1 to 3 first (small, mostly additive or deletions), land them quickly; do stage 4 in one sitting while no job has an open branch touching `godot/combat/{tests,tools}` or `godot/tests` (check `git branch -r --no-merged`); announce the freeze in `TODO.md`; for each moved file keep a one-line pointer in the commit message so `git log --follow` works.

## 6. Tools added in this audit
`tools/dev/find_unreferenced.py` (unreferenced scripts, classes, assets, orphan sidecars; `--json`), `tools/dev/check_doc_links.py` (broken Markdown links and backticked repo paths), `tools/dev/res_refs.py` (every reference to a path or class before a move). All read-only. Limits: they match text, so assets loaded through built strings are reported as "name/directory mention", and `.import` dependency graphs are not parsed; confirm every candidate by deleting it in a scratch branch and running import plus the gate.
