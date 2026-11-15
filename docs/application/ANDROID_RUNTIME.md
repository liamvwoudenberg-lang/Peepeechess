# Verify an installed Android build

The **Native Windows and Android exports** workflow now has an `android-runtime`
job. It downloads the same debug APK produced by `export`, installs it on an
Android 15 / API 35 x86_64 emulator, and exercises the actual running app. An APK
export alone does not pass this job.

The job retains `Peepeechess-android-runtime-evidence` for 30 days:

- `verification.json`: APK SHA-256, device/API/ABI, emulator/device classification,
  the app's checks and final pass/fail result.
- Eight PNGs: opening, menu, Classic 3D, combat, battle result, returned board,
  rematch and final menu. Nearly uniform/blank images fail the checker.
- `events.jsonl` and `logcat.txt`: this run's structured checks and app-process logs.

## What the session checks

The normal application opens its normal castle/menu. OS-level taps select a
piece and commit `e4`. The same app opens a 3D board and starts Battle against the
computer. A small legal position reaches a capture quickly through normal match
admission. The computer's capture enters combat automatically; an OS-level tap
presses the real touch attack control. The actual simulation must change health
and produce a legitimate terminal result. Nothing injects a winner or damage.

The pit must return the winner and settle exactly one chess ply. Chess must
continue, a finished game must show its result, and the new-game dialog must
restore the full board. The app then returns to its real menu. Missing stages,
an incomplete result, script/runtime errors, a crash, or a blank screenshot fail
the verifier. Screenshots are captured before the app advances to the next stage.

The test uses a private `user://playability-smoke.request` file written through
`adb run-as`. The normal **debug APK** has a debug-only loader for the smoke
runner; release builds ignore it. No separate APK, replacement main scene,
permissive activity or Android intent-security bypass is used. Use a fresh test
install: the smoke session changes its local settings and matches, and uses no
online account.

## Run it on a connected phone or emulator

Install Android platform-tools (`adb`) and Python 3. Use the APK from the same
commit whose checks you are reviewing. The debug APK includes ARM64 and x86_64;
the release AAB remains ARM64. Minimum Android API is 26.

```sh
adb devices
python3 scripts/verify-android.py \
  --apk artifacts/native/Peepeechess-android-debug.apk \
  --serial YOUR_DEVICE_SERIAL \
  --output artifacts/android-device-check
```

With exactly one connected device, `--serial` is optional. The verifier refuses
an already installed package by default. `--reuse-test-install` is available for
an existing **disposable debug-test profile**; it does not uninstall the app or
clear its data automatically. A release/signed installation may need a separate
test device because Android refuses updates signed with another key.

Keep `verification.json`, all screenshots and the logs when reporting a result.
The APK checksum connects that evidence to the exact tested binary. Physical
phone testing should additionally exercise suspend/resume, rotations, safe
areas, audio, sustained frame rate, heat and longer matches. An emulator pass
does not certify those hardware behaviours or ARM64-specific driver behaviour.

## Check the harness without an Android SDK

```sh
npm run test:playability
```

This runs mobile-seat routing and interrupted computer-capture regressions, the
full local session in headless Godot, and checker tests that reject desktop,
incomplete and blank-frame evidence. Its result explicitly says Linux/headless;
it cannot supply an Android verification pass.
