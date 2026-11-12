# Validation and packaging record: native-artifacts, 2026-11-11

Appended record; it does not replace [VALIDATION.md](VALIDATION.md) or [EXPORTS.md](EXPORTS.md).
Baseline: integration commit `daf6b5f` ("Merge codex/persistent-board"), branch `feature/native-artifacts`.
Machine: Linux x86_64 sandbox, 4 vCPU, shared with other workers (load average 3 to 9 during the runs), Node v22.23.4
(the docs ask for Node 24; `engines` is `>=22.13` and SQLite via `node:sqlite` works), Godot 4.6.3.stable
(`7d41c59c4`), Java 21, PostgreSQL 16.15 (CI uses 17), no Android SDK. Nothing here was run on a physical Windows PC,
Android device or gamepad.

## Results on the baseline

| Command | Result | Notes |
| --- | --- | --- |
| `npm ci` | passed | |
| `npm run lint` | passed (2.8 s) | |
| `npm run build` | passed (2.3 s) | existing large-chunk advisory only |
| `npm run test:contracts` | passed | 23 Node cases, 21 Godot cases, 9 exact round trips |
| `npm run test:classic` | passed | 83 engine, 53 match, 345 view checks; 72 positions / 1962 moves match chess.js |
| `npm run test:battle` | passed | 250 + 50 + 9 + 31 + 137 checks; 106 positions / 747 outcomes match C0 authority |
| `npm run test:multiplayer` | passed (95 s) | 62 authority, 86 roster, 30 UI checks; DTLS Classic, clock, Battle (10% loss, 40 ms) and trust scenarios; this run did not hit the packet-loss flake noted in VALIDATION.md |
| `npm run test:application` | passed (64 s) | protocol, UI, AccountApi, ranked and private Classic, ranked Battle with 4 real knockouts, outbox outage, restart abort, persistence |
| `npm run test:backend` (SQLite) | 9 passed, 1 skipped | the skipped case is the PostgreSQL-only one |
| `npm run test:backend` with `NATIVE_TEST_DATABASE_URL` (disposable local PostgreSQL 16, user `peepeechess_ci`, port 54329) | 10 of 10 passed | server installed from the distribution packages (`/usr/lib/postgresql/16/bin`), started as the `postgres` OS user with a throw-away data directory outside the repository, removed afterwards |
| `npm test` | **FAILED**, see below | Node/web part passes: 85 tests, 84 pass, 0 fail, 1 skipped (PostgreSQL-only) |

### `npm test`: why it fails on this baseline

The Godot combat harness reports `PASS: 7359 checks across 330 tests` (about 2 min), the scaled-touch check passes, but
`scripts/test-native-combat.mjs` treats any `ERROR:` line as a failure and two engine messages occur:

1. `ERROR: Window 0 spawned at invalid position: (-68, -18).` from `combat/tests/test_pads_ui.gd:233`.
   Cause (environment/test interaction, not a game fault): the wrapper disables content scaling, a headless root window
   is 64x64, and the pads suite centers an `AcceptDialog` in it. It is deterministic. Fixed in commit `41834e7` by
   excluding exactly this message (and its location/backtrace lines) from the wrapper's error scan; every other
   `ERROR:`, `SCRIPT ERROR`, `Parse Error` or `FAIL` still fails. A first attempt, resizing the root window in
   `godot/tests/run_combat_tests.gd`, removed the message but was reverted (`1b78d7a`) because it was not needed once
   the wrapper change existed and it changed engine state for all suites.
2. `ERROR: N resources still in use at exit` (N = 4 to 8) after the 900-frame standalone arena run
   (`res://combat/scenes/test_arena.tscn -- --auto=demo --frames=900`), the wrapper's fourth command. This is a **real
   but intermittent bug in combat-owned code, not fixed here**: with `--verbose` the leaked objects are
   `AudioStreamWAV` resources (`ability_lunge`, `guard_break`, `hit_leather_heavy_2`, `parry_2`, `swing_sword_1`,
   `victory`) plus `AudioStreamPlaybackWAV` playbacks that are still playing when `test_arena.gd::_process` calls
   `get_tree().quit()` at the frame limit. The test runner already avoids this (`CombatAudio.clear_library()` plus a 0.5 s
   wait before quitting, commit `c0f0f6a`), but the arena's `--frames` exit path does not. It occurred in all 6
   wrapper runs that reached the arena step (under load averages from 3 to 9); a direct arena run without `--verbose`
   once exited clean, so it depends on whether sounds are playing at the final frame. The wrapper previously never reached the arena run on
   this baseline because of message 1, so the gate was not passing before this work either.
   Suggested fix for the combat owner (not applied, it is gameplay-folder code): in the `--frames` branch of
   `godot/combat/scenes/test_arena.gd`, stop the arena's audio players, call `CombatAudio.clear_library()`, wait about
   0.5 s, then quit. Assertions were not changed or loosened for any of this.

`npm test` therefore needs that one-line-class fix before it can exit 0; all suites it runs pass.

## Packaging (tools/package/build_pc.sh)

`GODOT=... SMOKE=1 bash tools/package/build_pc.sh <out>` from the committed tree `99207e2`, 90 s on this machine:

- Windows preset: the repository's own `godot/export_presets.cfg` "Windows Desktop" (embedded PCK, product metadata,
  `custom_features=native_multiplayer`). Staging adds `*.wav` to `include_filter` (it already had `*.json`) and sets the
  console wrapper to also be exported in release (the repo's value 1 means debug exports only, so no
  `Peepeechess.console.exe` would exist for `Start-with-console.bat`). `application/modify_resources=true` produced no
  error without `rcedit` on Linux; the resource metadata is therefore probably not written into the PE (not
  verified; unsigned either way).
- Linux has no preset in the repository; `tools/package/export_presets.cfg` provides it.
- Godot exit codes are not trusted: any `ERROR:` / `SCRIPT ERROR` / `Parse Error` in the import or export log fails
  the build. None occurred.
- Archive step is deterministic (sorted entries, commit-time timestamps, fixed owner/modes). The Godot export itself is
  **not** byte-reproducible: two builds of the same commit differed inside the embedded PCK (64 bytes in size, so the
  exe/binary and the archives get different hashes); the console wrapper exe was identical. Publish the `SHA256SUMS` of the
  build that is distributed.

Artifacts of the run (not committed; scratchpad `/tmp/claude-0/-home-user-Peepeechess/bafe0bb3-0a21-590c-8ad2-776aa94941a3/scratchpad/na/pc1/`):

| File | SHA-256 |
| --- | --- |
| `Peepeechess-99207e2-win64.zip` (44,203,951 bytes) | `94c0ea467a6c9822d7ba65dae2ea8b7566abd2af6fc797371757f1c479c0ad2d` |
| `Peepeechess-99207e2-linux64.tar.gz` (35,825,453 bytes) | `2dc06a409e063dc4b0c615e9e8ed7727d355af0e143cecd377bc00ce69cf5abb` |
| `Peepeechess-99207e2-win64/Peepeechess.exe` | `1c5ea342d81c63d436e0a20edb498c71d9de96fc0b60e2a0320b69d035aa3675` |
| `Peepeechess-99207e2-win64/Peepeechess.console.exe` | `887756fb5a4462eaf50d6b658c2f69e2d5cc52cf50337dc0a92b03653ddd9349` |
| `Peepeechess-99207e2-linux64/Peepeechess.x86_64` | `cb055ee5cb6ef829c2dfd4133b5907d175c49a7a811553ed1ef00139b4f2ff1c` |

`file` identifies both Windows executables as PE32+ x86-64 (GUI and console). They are unsigned and were never run.

### Linux package smoke test (Xvfb, Mesa llvmpipe OpenGL 4.5, dummy audio)

`bash tools/package/smoke_linux.sh <out>`:

- The distributed binary starts its real main scene (application main menu) and runs 300 frames: exit 0, no
  `SCRIPT ERROR`, `ERROR:`, load or missing-file diagnostics.
- The smoke variant (same project, main scene replaced by `tools/package/smoke/package_smoke.tscn`; release export
  templates ignore `--script`) passed 22 checks, 0 failures: seven packed JSON files readable (`battle_stats.json`,
  `balance_v1.json`, audio manifest, arena light sidecar, asset and world manifests, contract schema), the combat audio
  library loads from the package (34 sounds), the application opens on Play and navigates account, settings, profile,
  history, leaderboard and back, a local Classic match starts and accepts e2-e4 and e7-e5 and rejects an illegal repeat,
  and a local Battle Chess match starts.

This proves the package contents and start-up on Linux software rendering. It does not exercise a real GPU, a fight on
screen for a long time, or any Windows behaviour.

## Android: not built here

No Android artifact could be produced. The sandbox proxy refuses the CONNECT to Google's download host:

```
$ curl -sS -I https://dl.google.com/android/repository/repository2-1.xml
curl: (56) CONNECT tunnel failed, response 403
```

Per the task, no other mirror was tried and TLS verification was not touched. Godot's own check (4.6.3 with the Android
templates installed, no SDK) fails the same way for the repository preset:

```
ERROR: Cannot export project with preset "Android Debug APK" due to configuration errors:
Invalid Android SDK path in Editor Settings. Missing 'platform-tools' directory!
Unable to find Android SDK platform-tools' adb command. ...
Invalid Android SDK path in Editor Settings. Missing 'build-tools' directory!
Unable to find Android SDK build-tools' apksigner command. ...
```

The release AAB additionally needs Google's Maven repository (`dl.google.com/dl/android/maven2`) for the Android Gradle
plugin, which is on the same blocked host. The existing evidence is Codex's recorded build in
[EXPORTS.md](EXPORTS.md) (APK 61,365,312 bytes `901af222...`, test-signed AAB 31,411,256 bytes `7623abb9...`, from
commit `743aaa9`, SDK 36 / build-tools 36.1.0); those files are not in this sandbox and are not the current tree.
The Android presets themselves are covered by `tests/native-exports.test.ts` (passes).

Commands for someone with access to `dl.google.com` (JDK 17 or 21 with `javac`, `curl`, `unzip`, Python 3, 6 GiB free):

```sh
export GODOT_BIN=/path/to/Godot_v4.6.3-stable_linux.x86_64
bash scripts/install-native-toolchain.sh          # verifies the templates (SHA-512), cmdline-tools (SHA-1 from Google's
                                                  # repository2-1.xml) and bundletool (SHA-256), accepts the SDK licenses,
                                                  # installs platform-tools, platforms;android-36, build-tools;36.1.0
export ANDROID_HOME="$PWD/work/toolchains/android-sdk" PEEPEECHESS_TOOLCHAIN_DIR="$PWD/work/toolchains"
bash scripts/export-native.sh android-apk        # debug APK + apksigner verify
bash scripts/export-native.sh android-aab-test   # test-signed AAB + bundletool validate + manifest dump
sha256sum artifacts/native/*.apk artifacts/native/*.aab
# manifest/permission/ABI checks:
"$ANDROID_HOME/build-tools/36.1.0/aapt2" dump badging artifacts/native/Peepeechess-android-debug.apk | grep -E "package|sdkVersion|uses-permission|native-code"
```

Expected from the presets: package `com.peepeechess.game`, versionCode 3 / 0.3.0, landscape, permissions INTERNET and
ACCESS_NETWORK_STATE only, APK minSdk 24 with arm64-v8a and x86_64, AAB minSdk 26 / targetSdk 36 with arm64-v8a.
The scripts create the debug keystore in the ignored `work/keys/`; no key material is in Git. The GitHub workflow
runs the same commands (job `export`).

## CI changes (additive; need GitHub runners to verify)

Workflow files parse as YAML (PyYAML); they were not executed.

- `validate.yml`: concurrency group (cancels superseded PR runs), `foundation` timeout 15 to 60 min (the sequence
  lint, `npm test` ~2.5 min, classic, battle, multiplayer ~1.5 min, backend, application ~1 min runs 6 to 10 minutes on
  four cores here; shared runners are slower), per-step timeouts, cache of the pinned Godot editor. The Godot SHA-256 in
  that file matches the zip used here (`d0bc2113...`), as does the SHA-512 in `native-exports.yml` (`a0352...`).
  Note: with the arena exit leak above, `npm test` will stay red in CI until the combat owner fixes it.
- `native-exports.yml`: path triggers for `tools/package/**` and `.godot-version`, concurrency, 30 to 60 min timeout,
  cache for the Android toolchain and Gradle, bundletool validation/manifest files added to the upload, new job
  `pc-packages` (installs templates, runs `build_pc.sh` with `SMOKE=1`, Xvfb smoke test, uploads zip, tar.gz,
  `SHA256SUMS`, `BUILD_INFO.txt` and logs), and a non-blocking `windows-smoke` job (`continue-on-error`) that unpacks the
  zip on `windows-latest` and runs `Peepeechess.console.exe --headless --quit-after 300`.
  Untested: the whole `pc-packages` and `windows-smoke` jobs, the caches, `apt` package names for Xvfb, and running
  on Windows at all.
- `scripts/install-native-toolchain.sh` now also extracts `linux_release.x86_64` (needed by `build_pc.sh`) and re-downloads
  the template archive when it or the Windows console template is missing.
- `postgres` job unchanged (PostgreSQL 17 service). The local 16.15 run above is the equivalent check.

## Open items

- Combat owner: the arena exit leak above (blocks `npm test`).
- The untracked `godot/contracts/v2/codec.gd.uid` appears after every import; it is generated metadata missing from
  the baseline commit (Codex-owned contract folder, not committed here).
- Android artifacts for the current tree, real-device runs, Windows execution, gamepad hardware, code signing.
