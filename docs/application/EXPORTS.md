# Native Windows and Android builds

Use Godot **4.6.3 stable standard**, matching standard export templates, and
OpenJDK17 or21. These exports use the native Godot application, not the preserved
Capacitor project in the repository's top-level `android/` directory.

## Install and build

On Linux, install `curl`, `unzip`, Python3 and a JDK, then from the repository root:

```sh
bash scripts/install-native-toolchain.sh
bash scripts/export-native.sh all
bash scripts/export-native.sh android-aab-test
```

The installer verifies the official Godot template SHA512 and Google's published
command-line-tools checksum. It downloads standard Windowsx64 and Android
templates into ignored `work/toolchains/`. The Android tool installer accepts the
SDK licenses. It installs SDK platform36, build-tools36.1.0 and platform-tools.
The **actual pinned4.6.3 Android source template** specifies these versions,
Gradle8.11.1, Android Gradle Plugin8.6.1 and NDK29.0.14206865; older generic4.6
documentation still lists SDK35. The template's bundled precompiled engine avoids
compiling Godot from source. If Gradle requests its declared NDK, install
`"ndk;29.0.14206865"` with the SDK manager and allow several additional GB.

Overrides: `GODOT_BIN`, `JAVA_HOME`, `ANDROID_HOME`,
`PEEPEECHESS_TOOLCHAIN_DIR`, `NATIVE_OUTPUT_DIR`, `GRADLE_USER_HOME`.
All generated editor settings, Gradle dependencies and signing material stay in
ignored task-local directories. Standard unauthenticated `HTTPS_PROXY` routing
is forwarded into Gradle without disabling TLS verification. Configure private
authenticated proxies through your secure CI tooling.

Outputs in `artifacts/native/`:

| Output | Purpose |
| --- | --- |
| `Peepeechess-windows-x86_64.exe` | Native release-mode Windowsx64 executable with embedded game data; unsigned |
| `Peepeechess-android-debug.apk` | Native debug APK, arm64 plus x86_64 for compatible emulator testing; disposable debug signature |
| `Peepeechess-android-test.aab` | Release-mode arm64 App Bundle, signed with the disposable test key; never a Play Store release |
| `checksums.json` | SHA256, byte count and filename for generated artifacts |

Individual commands are `export-native.sh windows`, `android-apk`,
`android-aab-test`, or `android-aab`. The script stops on Godot script/resource/
export errors and verifies Android signatures. A successful export is not a
successful device run.

## Production signing

`Android Release AAB` is configured for `com.peepeechess.game`, versionCode3,
versionName0.3.0, minSDK26 and targetSDK36. Increase versionCode for every Play
upload. Supply the existing upload key through protected environment variables:

```sh
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH=/secure/path/upload.jks
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=upload
# Set GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD through a secret manager/CI secret.
bash scripts/export-native.sh android-aab
```

The release command refuses missing credentials. Do not commit keystores,
passwords or `.godot/export_credentials.cfg`. Production keys must be backed up
securely and reused across updates. Windows Authenticode signing is a separate
release step requiring an organization certificate. No Windows signing
certificate or Android production key is included.

## Install test builds

On Windows, extract/download the executable and run it. The unsigned build may
trigger SmartScreen; distribute signed releases after review. Windows drivers
must support the Compatibility renderer's OpenGL requirements.

For an Android device with USB debugging enabled:

```sh
adb devices
adb install -r artifacts/native/Peepeechess-android-debug.apk
adb shell am start -n com.peepeechess.game/com.godot.game.GodotApp
```

Alternatively transfer the APK and permit that file manager/browser to install
unknown apps. An AAB cannot be installed directly; use Play internal testing or
official `bundletool` with the appropriate signing key to create APK sets.
No emulator image, physical Windows machine or Android device is implied by the
presence of an exported artifact.

## Presentation and input

The project uses landscape orientation, expanding canvas scaling, explicit
touch input on both boards and combat, and Compatibility rendering. Android
exports request Internet and network-state permissions only and disable backup
of local profile/session data. Production account APIs use HTTPS; dedicated
server transport remains the same authenticated ENet/DTLS protocol on both
platforms. Local2D/3D and graphics preferences do not change authoritative match
state or another player's view.

Keyboard/mouse work through the existing boards. Standard Godot focus navigation
supports d-pad and A/B; left analog stick enables a visible pointer and A clicks
either board (including the3D raycast path). Combat owns the controller while
the virtual pointer is disabled. `PlatformInput` offers low(30fps/no MSAA),
balanced(60fps/2x MSAA), and high(uncapped/4x MSAA) presentation settings. Physics
and dedicated-server ticks remain60Hz. Actual device/controller ergonomics,
GPU performance, suspend/resume and safe-area behavior still require device QA.

## Automation

`tests/native-exports.test.ts` checks preset separation, permissions, absent
secrets and controller/quality behavior without changing the physics rate.
The `Native Windows and Android exports` workflow produces the unsigned Windows
build, debug APK and test-signed AAB as GitHub Actions artifacts. It does not
publish a release or upload anything to an app store. Artifact/device verification
results for the integrated application belong in the final task validation log.
