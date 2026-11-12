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
publish a release or upload anything to an app store (the separate `Release Windows
build` workflow does publish, see the next section). Artifact/device verification
results for the integrated application belong in the final task validation log.

## Publishing a Windows release

A downloadable GitHub Release (tag, `Peepeechess-windows-x86_64.exe`, a Windows zip, a
Linux tar.gz, `SHA256SUMS.txt`) is produced by one pipeline, locally or on GitHub.
Both run the same scripts, so a local run is a faithful rehearsal of the release job.

### Build the release files locally (publishes nothing)

Needs Linux x86_64, Python 3, `curl`, `unzip` and Xvfb for the smoke test
(`apt-get install xvfb libgl1-mesa-dri libglx-mesa0`). From the repository root:

```sh
bash tools/package/build_release_local.sh v0.3.0-alpha.1
```

The script (1) finds `GODOT`/`GODOT_BIN`/`godot` or downloads the pinned official
4.6.3 editor (SHA-512 verified), (2) installs the official 4.6.3 export templates with
`scripts/install-native-toolchain.sh --templates-only` (SHA-512 verified, 1.2 GB; skipped
when already present in `PEEPEECHESS_TOOLCHAIN_DIR`, default `work/toolchains`),
(3) runs `tools/package/build_pc.sh` with `SMOKE=1` using the repository's own
`Windows Desktop` preset, (4) runs `tools/package/smoke_linux.sh` on the Linux build,
(5) runs `tools/package/inspect_exe.py` on the Windows exe and (6) runs
`tools/package/assemble_release.sh`. It stops at the first failure and never touches
`HOME`, the repository or your editor settings. Options: `GODOT`,
`PEEPEECHESS_TOOLCHAIN_DIR`, `RELEASE_OUT` (default `artifacts/release`),
`SKIP_SMOKE=1` (only where Xvfb cannot be installed; the notes then say the smoke test
did not run). Outputs, all git-ignored:

| Path under `RELEASE_OUT` | Content |
| --- | --- |
| `release/Peepeechess-windows-x86_64.exe` | the exe to publish: one file, game data embedded; byte-identical to the exe in the zip |
| `release/Peepeechess-<commit>-win64.zip` | exe, `Peepeechess.console.exe`, `Start-with-console.bat`, `PLAY.txt` |
| `release/Peepeechess-<commit>-linux64.tar.gz` | the Linux build that the smoke test ran |
| `release/SHA256SUMS.txt`, `release/RELEASE_NOTES.md` | `sha256sum -c` list and the release text (lists only checks that ran) |
| `pc/` | `build_pc.sh` output: logs, `BUILD_INFO.txt`, `exe-inspection.txt`, `smoke_*.log` |

Reference run, 2026-11-12, 4 shared vCPUs: 138 s from nothing (editor 5 s, templates 54 s,
build 63 s, smoke 14 s), 85 s when the templates are cached; exe about 109 MiB, zip about 43 MiB,
tar.gz about 35 MiB. Godot's export is not byte-reproducible (five builds of the same `godot/` tree gave five
different exe hashes and three different sizes, 114758520 to 114758584 bytes), so publish the files of one
build together with their own `SHA256SUMS.txt` and never mix files of different runs. A build from a tree with uncommitted changes in
`godot/` or `tools/` carries `-dirty` in its file names and must not be published.

### Publish from GitHub Actions

The `Release Windows build` workflow (`.github/workflows/release-windows.yml`) runs the
script above on `ubuntu-24.04` and creates the release with the workflow's own
`GITHUB_TOKEN`. Run it from **Actions, Release Windows build, Run workflow**, or through the API
(workflow `release-windows.yml`) with these inputs:

| Input | Meaning |
| --- | --- |
| `tag` (required) | new tag such as `v0.3.0-alpha.1`; the run fails at once if the tag exists, nothing is ever overwritten |
| `prerelease` (default `true`) | mark the release as a pre-release |
| `ref` (optional) | branch, tag or commit to build; empty means the ref the workflow was dispatched on. That ref must contain `tools/package/build_release_local.sh` |
| `skip_windows_smoke` (default `false`) | skip the Windows-runner check below; for use only if that check itself is broken |

Jobs: `build` (script above, then uploads the files as the `release-assets` artifact),
`windows-smoke` (on `windows-latest`: verifies the artifact checksums, extracts the zip and
starts `Peepeechess.console.exe --headless --quit-after 300`, which must exit 0 without
`SCRIPT ERROR`/`ERROR:` lines), and `publish`, which runs only after both succeeded and only for a
manual dispatch. `publish` is the only job with `contents: write`; it runs no repository
code: it re-verifies `SHA256SUMS.txt`, calls `gh release create --target <built commit>`,
downloads the published exe again and compares it with the checksum list, and writes the link to the run
summary. A pull request that changes the pipeline files runs `build` and `windows-smoke` as a dry run and
publishes nothing.

`workflow_dispatch` can only be started for a workflow file that exists on the repository's
default branch (`main`; the Run workflow button needs it there). Merge the pipeline to `main`
first; if the code to release lives on another branch, merge the pipeline into that branch too
and pass it as `ref`. GitHub may also accept a dispatch against a branch that contains the file once
the workflow is known to Actions (the pull-request dry run registers it); that was not verified.

### What a tester does

Open the repository's **Releases** page, choose the release, download
`Peepeechess-windows-x86_64.exe` from its assets and double-click it. It is unsigned, so
Windows SmartScreen shows "Windows protected your PC": choose **More info**, then **Run anyway**
(some antivirus products also warn about unsigned game executables). To check the download:
`Get-FileHash .\Peepeechess-windows-x86_64.exe -Algorithm SHA256` in PowerShell must equal the line
in `SHA256SUMS.txt`. The zip is the same exe plus `Start-with-console.bat`, which prints errors for bug
reports. Windows 10/11 x64 with an OpenGL-capable GPU driver is required; online play needs a
Peepeechess server.

### What is and is not verified

| Check | Status |
| --- | --- |
| The 4.6.3 export template archive (and the editor, when the script downloads it) matches the pinned SHA-512 from the official `SHA512-SUMS.txt` | verified by the scripts whenever they download |
| Export completes without `ERROR:`/`SCRIPT ERROR` in the import and export logs | verified by `build_pc.sh` on every run |
| Exe is a PE32+ x86_64 image with the embedded pack, MD5 of every packed file, main scene, runtime data files and the Windows version resource present | verified statically by `inspect_exe.py` (the file is not executed) |
| Linux build of the same commit starts, navigates the menu and starts local Classic and Battle Chess matches | verified under Xvfb with software OpenGL by `smoke_linux.sh` |
| Windows exe starts headlessly and runs 300 frames on a Windows runner | checked by the `windows-smoke` job; that job had never run when it was written, so its first result is the proof |
| Windows exe renders and plays on a physical Windows PC with a real GPU and gamepad | **not verified**; no Windows machine and no Wine were available |
| Authenticode signature | **none**; signing needs an organization certificate and an added `signtool` step |
| Online play against a public server | not verified |

## Actual build verification, 2026-11-11

The integrated native application source at `743aaa9` (including the DTLS certificate-hostname
fix in `3e6df31`) was exported on Linux
with Godot 4.6.3, SDK 36/build-tools 36.1.0, Gradle 8.11.1 and a verified user-owned
Temurin JDK 21.0.13. Both app modes, the application shell, both board views,
combat arena and networking contracts are present in the packaged resources.
The output binaries remain in ignored `artifacts/native/`; they are not committed
to Git. GitHub Actions can reproduce downloadable test artifacts.

| Artifact | Bytes | SHA256 |
| --- | ---: | --- |
| Windows x64 executable | 110099352 | `6d4913a0a2f0a4bdf7d948c8078e5bb13adf0165cffa5a4bc5b371c521ce969d` |
| Android debug APK | 61365312 | `901af222926e0bd6d662a9d0369eb4232c11a58f2917e7cc310bc211a1cfddaf` |
| Android test-signed AAB | 31411256 | `7623abb92690036590b63307a074c1c8802516484bc6726a35869f71a29fa676` |

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

The three export/controller automated tests and shell syntax checks passed.
The diagnostics test proves that a zero-exit Godot script error fails the export
and that an inherited conflicting Android SDK root is aligned correctly.
No artifact was run on a physical Windows or Android device. Production
signing, store acceptance, real controller behavior and Windows-to-Android
crossplay remain device/release QA gates.
