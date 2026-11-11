# Native Windows and Android builds

Use Godot **4.6.3 stable standard**, matching standard export templates, and
OpenJDK 17 or 21. These exports use the native Godot application, not the preserved
Capacitor project in the repository's top-level `android/` directory.

## Install and build

On Linux, install `curl`, `unzip`, Python3 and a JDK, then from the repository root:

```sh
bash scripts/install-native-toolchain.sh
bash scripts/export-native.sh all
bash scripts/export-native.sh android-aab-test
```

The installer verifies the official Godot template SHA512 and Google's published
command-line-tools checksum. It downloads standard Windows x64 and Android
templates into ignored `work/toolchains/`. The Android tool installer accepts the
SDK licenses. It installs SDK platform 36, build-tools 36.1.0 and platform-tools.
The **actual pinned 4.6.3 Android source template** specifies these versions,
Gradle 8.11.1, Android Gradle Plugin 8.6.1 and NDK 29.0.14206865; older generic 4.6
documentation still lists SDK 35. The template's bundled precompiled engine avoids
compiling Godot from source. If Gradle requests its declared NDK, install
`"ndk;29.0.14206865"` with the SDK manager and allow several additional GB.
Bundle builds require a full JDK, including `javac`, rather than a JRE. The
script checks that compiler and at least 1 GiB of free disk before beginning
Gradle work; allow several GiB for a cold dependency cache. Windows and debug
APK exports use the precompiled engine templates.

Overrides: `GODOT_BIN`, `JAVA_HOME`, `ANDROID_HOME`,
`PEEPEECHESS_TOOLCHAIN_DIR`, `NATIVE_OUTPUT_DIR`, `GRADLE_USER_HOME`.
Both scripts align `ANDROID_SDK_ROOT` with the selected `ANDROID_HOME`, including
on CI machines that already have a different system SDK. Error scanning uses
Python3 and does not depend on ripgrep being installed.
All generated editor settings, Gradle dependencies and signing material stay in
ignored task-local directories. Standard unauthenticated `HTTPS_PROXY` routing
is forwarded into Gradle without disabling TLS verification. Configure private
authenticated proxies through your secure CI tooling.

Outputs in `artifacts/native/`:

| Output | Purpose |
| --- | --- |
| `Peepeechess-windows-x86_64.exe` | Native release-mode Windows x64 executable with embedded game data; unsigned |
| `Peepeechess-android-debug.apk` | Native debug APK, arm64 plus x86_64 for compatible emulator testing; disposable debug signature |
| `Peepeechess-android-test.aab` | Release-mode arm64 App Bundle, signed with the disposable test key; never a Play Store release |
| `checksums.json` | SHA256, byte count and filename for generated artifacts |

Individual commands are `export-native.sh windows`, `android-apk`,
`android-aab-test`, or `android-aab`. The script stops on Godot script/resource/
export errors and verifies Android signatures. A successful export is not a
successful device run.
The installer also pins official `bundletool 1.18.3` by SHA256. AAB builds validate
the bundle structure and save the decoded manifest alongside the output.

## Production signing

`Android Release AAB` is configured for `com.peepeechess.game`, versionCode 3,
versionName 0.3.0, minSDK 26 and targetSDK 36. Increase versionCode for every Play
upload. The non-Gradle debug APK inherits the engine template minSDK 24; the
release AAB deliberately requires Android 8.0/API 26. Supply the existing upload
key through protected environment variables:

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
adb shell am start -n com.peepeechess.game/com.godot.game.GodotAppLauncher
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
platforms. Local 2D/3D and graphics preferences do not change authoritative match
state or another player's view.

Keyboard/mouse work through the existing boards. Standard Godot focus navigation
supports d-pad and A/B; left analog stick enables a visible pointer and A clicks
either board (including the 3D raycast path). Combat owns the controller while
the virtual pointer is disabled. `PlatformInput` offers low (30 fps/no MSAA),
balanced (60 fps/2x MSAA), and high (uncapped/4x MSAA) presentation settings. Physics
and dedicated-server ticks remain 60 Hz. Actual device/controller ergonomics,
GPU performance, suspend/resume and safe-area behavior still require device QA.

## Automation

`tests/native-exports.test.ts` checks preset separation, permissions, absent
secrets and controller/quality behavior without changing the physics rate.
The `Native Windows and Android exports` workflow produces the unsigned Windows
build, debug APK and test-signed AAB as GitHub Actions artifacts. It does not
publish a release or upload anything to an app store. Artifact/device verification
results for the integrated application belong in the final task validation log.

## Actual build verification, 2026-11-11

The integrated native application source at `34d3657` was exported on Linux
with Godot 4.6.3, SDK 36/build-tools 36.1.0, Gradle 8.11.1 and a verified user-owned
Temurin JDK 21.0.13. Both app modes, the application shell, both board views,
combat arena and networking contracts are present in the packaged resources.
The output binaries remain in ignored `artifacts/native/`; they are not committed
to Git. GitHub Actions can reproduce downloadable test artifacts.

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| Windows x64 executable | 110099144 | `5860a2c661f56ab3ea03e3596bf8c47b2c9d0969aff8f92109dfe2118bb86b1b` |
| Android debug APK | 61365312 | `250821b6963e4826afda4e247ede54e3d24627f7e2b54af9784c9bad2c162bab` |
| Android test-signed AAB | 31411081 | `3854162caccc245de80a8cbc63a1acae4a6486b7bd7bc15c1e7297b30c948de5` |

The Windows PE header identifies x86_64 and its embedded Godot pack is present.
`apksigner verify` passed v2/v3 for the APK; the actual manifest contains the
expected package, landscape orientation, targetSDK 36, minSDK 24, launcher alias,
two networking permissions and arm64/x86_64 libraries. Official bundletool 1.18.3
validated the AAB and decoded its manifest: minSDK 26, targetSDK 36, landscape,
exported launcher alias and arm64 libraries. `jarsigner -verify` reports
`jar verified` with self-signed/test-key, missing-timestamp and ZIP manifest-order
warnings; this is not a production signature or store submission.

An earlier AAB attempt ran out of workspace disk during native-library merge.
After reclaiming generated scratch, the final build completed. No NDK download
was required by this precompiled-engine bundle. The SDK installer was exercised
using command-line-tools 23.0's sdkmanager compatibility entry point, which
delegates to the new Android CLI; no manual SDK fallback was needed. The new
disk/compiler guards avoid starting an AAB build with the observed missing
prerequisites.

The two export/controller automated tests and shell syntax checks passed.
No artifact was run on a physical Windows or Android device. Production
signing, store acceptance, real controller behavior and Windows-to-Android
crossplay remain device/release QA gates.
