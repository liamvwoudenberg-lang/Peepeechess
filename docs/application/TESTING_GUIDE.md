# Tester guide: install, play, report

This is for people testing the **native Godot application** (Classic Chess and Battle Chess) on Windows, Linux and
Android. It is an alpha. Read [What works and what does not](#what-works-and-what-does-not) first.

No package has been signed, no build has been run on a physical Windows PC, Android phone or real gamepad by the
developers (see [EXPORTS.md](EXPORTS.md) and the dated validation files), and online play needs a server that you or
the maintainers run. You are the first real-device test, so please report what you see.

## 1. Get a build

Builds are never committed to Git. They come from one of:

| Build | Where it comes from |
| --- | --- |
| Windows zip `Peepeechess-<commit>-win64.zip`, Linux `Peepeechess-<commit>-linux64.tar.gz` | GitHub Actions artifact **Peepeechess-pc-packages** (workflow *Native Windows and Android exports*, job `pc-packages`), or `tools/package/build_pc.sh` (below) |
| Android debug APK `Peepeechess-android-debug.apk` | GitHub Actions artifact **Peepeechess-native-test-builds** (job `export`), or `bash scripts/export-native.sh android-apk` |
| Android `.aab` | Not installable directly; for Play internal testing or `bundletool` only (see EXPORTS.md) |

Each download comes with `SHA256SUMS` or `checksums.json`. Verify before installing:

```sh
sha256sum -c SHA256SUMS            # Linux/macOS
```
```powershell
Get-FileHash Peepeechess-<commit>-win64.zip -Algorithm SHA256   # Windows: compare with the line in SHA256SUMS
```

Build the PC packages yourself (Linux, Godot 4.6.3 and its export templates installed; see
[TOOLCHAIN.md](../development/TOOLCHAIN.md)):

```sh
GODOT=/path/to/Godot_v4.6.3-stable_linux.x86_64 SMOKE=1 bash tools/package/build_pc.sh ./dist
bash tools/package/smoke_linux.sh ./dist          # needs xvfb; checks the Linux build starts and a local match runs
```

The archive step is deterministic, but Godot's export is not byte-reproducible (two builds of one commit differ inside
the embedded PCK), so your own build will have a different SHA-256 from a CI build of the same commit. Compare against
the `SHA256SUMS` that shipped with the file you downloaded. The Windows `.exe` is **unsigned**.

## 2. Install

### Windows 10/11 (x86_64)

1. Extract the zip anywhere writable (not into `Program Files`). Keep `Peepeechess.exe` and `Peepeechess.console.exe`
   in the same folder; the game data is embedded in the `.exe`.
2. Double-click `Peepeechess.exe`. SmartScreen may say "Windows protected your PC" because the file is unsigned:
   choose **More info**, then **Run anyway**.
3. If it crashes or shows a black window, start `Start-with-console.bat` instead. It opens a console that prints
   engine errors; copy that text into your bug report.
4. The renderer is OpenGL (Compatibility). Update your graphics driver if the window stays black.

### Linux (x86_64)

```sh
tar -xzf Peepeechess-<commit>-linux64.tar.gz
./Peepeechess-<commit>-linux64/Peepeechess.x86_64
```

Needs OpenGL 3.3 (software Mesa works but is slow in the 3D board and combat).

### Android 7.0+ (debug APK, minSdk 24)

Debug APK facts (from the actual build; see EXPORTS.md): package `com.peepeechess.game`, landscape, minSdk 24, targetSdk 36,
`arm64-v8a` and `x86_64` libraries (so it does **not** install on 32-bit-only phones), signed with a disposable *debug*
key (so it cannot upgrade a Play Store install and a different debug key cannot upgrade it either).

Option A, USB with `adb` (Android platform-tools on the computer):

1. On the phone: Settings, About phone, tap **Build number** seven times; then Settings, Developer options, turn on
   **USB debugging**; connect the cable and accept the RSA prompt.
2. Run:
   ```sh
   adb devices                                   # the phone must be listed as "device"
   adb install -r Peepeechess-android-debug.apk
   adb shell am start -n com.peepeechess.game/com.godot.game.GodotAppLauncher
   ```
   (The launcher can also be started by tapping the Peepeechess icon.)

Option B, sideload without a computer:

1. Download the APK on the phone (or copy it over USB / cloud storage).
2. Open it from the file manager or browser. Android asks to allow **Install unknown apps** for that app: allow it
   for this install only, then go back and confirm **Install**. Turn the permission off again afterwards.
3. If *Play Protect* warns about an app that is not from the Play Store, choose **Install anyway** (debug-signed test build).

Expected permissions (check with `adb shell dumpsys package com.peepeechess.game | grep permission`, or Settings, Apps,
Peepeechess, Permissions): only **Internet** (`android.permission.INTERNET`) and **network state**
(`android.permission.ACCESS_NETWORK_STATE`). Nothing is asked at run time: no storage, camera, microphone or location.
If the app asks for anything else, report it as a bug. App backup is disabled.

Uninstall: `adb uninstall com.peepeechess.game` or long-press the icon. This also deletes local preferences.

## 3. Play

- **Local play** (two people on one device) needs nothing else: choose Classic or Battle on the Play page, then Local.
  Pick 2D or 3D per device; the board toolbar switches during a match.
- **Battle Chess**: a capture starts a real-time third-person duel; the winner keeps the square. Controls for keyboard,
  mouse, gamepads and touch are in [PLAYER_GUIDE.md](PLAYER_GUIDE.md), `godot/combat/CONTROLS.md` and the `PLAY.txt` inside
  the package. Settings, **Controls & controllers...** rebinds keys and pads. On Android the on-screen combat controls can
  be switched in Settings (*Touch combat controls*).
- Quality (Settings): *Low* 30 fps/no antialiasing, *Balanced* 60 fps/2x, *High* uncapped/4x. Use Low on slow phones.

### Connect to a server (online play)

Online needs **two** services (see [BACKEND.md](BACKEND.md)): the account API (HTTP) and a dedicated Godot ENet/DTLS
game server. The maintainers will give you an address.

1. Settings, **Account service URL**: enter the HTTPS address (for example `https://accounts.example.com`), **Save service address**.
   Plain `http://` is accepted only for `localhost`, `127.0.0.1` and `[::1]` (developer machines).
2. Account page: register a username, display name and a password of at least ten characters, or sign in. There is no
   password reset; write the password down. Use the same account on every device.
3. Play page: *Quick match* (ranked or unranked) or *Private match* (share the six-character invite code, expires after ten
   minutes). Both players press **Ready** in the lobby.
4. Advanced (developers only): Settings, **Advanced direct-server lobby** connects straight to a dedicated server.

Limits that matter on a phone: `127.0.0.1` on Android is the phone itself, and `adb reverse` forwards only TCP, not the
UDP used by the game server. So a physical Android device needs a server with a public HTTPS account address and a game
server reachable over UDP with a valid DTLS certificate. A server on your own PC works for Windows/Linux clients on the
same machine (loopback development mode), not for a phone.

## 4. Report a bug

Please include:

1. Build: file name and commit id (also printed in `PLAY.txt` and in the package name), and the SHA-256 if you built it yourself.
2. Platform: Windows version / Android version and phone model / Linux distribution; GPU and driver; screen size.
3. Mode and view: Classic or Battle, Local or Online, 2D or 3D, graphics quality, input device (mouse, touch, which gamepad).
4. What you did, what you expected, what happened; a screenshot or short screen recording helps. For online problems:
   the time, whether it was a quick or private match, and whether it was ranked.
5. Logs:
   - Windows: run `Start-with-console.bat` and copy the console text. Godot also keeps `godot.log` in
     `%APPDATA%\Godot\app_userdata\Peepeechess\logs\`.
   - Linux: run from a terminal and copy the output; the log is in `~/.local/share/godot/app_userdata/Peepeechess/logs/`.
   - Android: with the phone connected, start `adb logcat -c`, reproduce the problem, then `adb logcat -d -s godot > godot-log.txt`
     (also attach `adb logcat -d` if the app crashed on start, and the output of `adb shell getprop ro.product.model ro.build.version.release`).
6. Whether it is repeatable and how often.

File it in the repository's GitHub issues (or send it to the maintainers) and mention this guide's build commit.
Do not post passwords, session tokens or server secrets in a report.

## What works and what does not

Verified by automated Linux/headless tests only (the dated validation files list them): chess rules, Classic and Battle
match flow, the combat simulation, account and matchmaking services, authoritative server scenarios.

Not verified on real hardware, and where you are most likely to find problems:

- Windows start-up, SmartScreen behaviour, GPU drivers and the OpenGL renderer; the Windows build is unsigned.
- Android installation, safe areas/notches, touch ergonomics, performance and thermal behaviour, suspend/resume,
  and real controllers over Bluetooth/USB.
- Two real gamepads in Battle Chess, controller glyph detection, rebinding with real devices.
- Online play across the public Internet, DTLS certificates, Windows-to-Android crossplay, behaviour on bad networks.
- Balance and feel of Battle Chess (tuned with bots, not by human play); art is generated placeholder quality.

Not implemented yet: the trapdoor/pit transition between board and arena (captures show the older arena overlay),
a computer opponent for Classic Chess, King fights in the app (Kings never enter combat in the current C0 rules),
Windows code signing, a Play Store release, and a store-signed Android build.

Support: the Windows build runs on x86_64 only; ARM Windows relies on Windows' x64 emulation and is untested.
