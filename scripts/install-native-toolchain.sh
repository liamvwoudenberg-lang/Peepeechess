#!/usr/bin/env bash
set -euo pipefail

# Linux CI/development installer. Dependencies: curl, unzip, Python3, Java17/21.
# Tools stay outside the tracked project. Existing editor/user settings are untouched.
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TOOLS=${PEEPEECHESS_TOOLCHAIN_DIR:-"$ROOT/work/toolchains"}
VERSION=$(tr -d '\r\n' < "$ROOT/.godot-version")
if [[ "$VERSION" != "4.6.3" ]]; then
  echo "Update pinned download checksums for Godot $VERSION before installing." >&2
  exit 2
fi
mkdir -p "$TOOLS/downloads" "$TOOLS/godot/templates/4.6.3.stable"
ARCHIVE="$TOOLS/downloads/Godot_v4.6.3-stable_export_templates.tpz"
TEMPLATES="$TOOLS/godot/templates/4.6.3.stable"
if [[ ! -f "$TEMPLATES/android_source.zip" || ! -f "$TEMPLATES/android_debug.apk" || ! -f "$TEMPLATES/windows_release_x86_64.exe" ]]; then
  curl -fL --retry 2 "https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz" -o "$ARCHIVE"
  python3 - "$ARCHIVE" "$TEMPLATES" <<'PY'
import hashlib, pathlib, shutil, sys, zipfile
archive, destination = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
# Official 4.6.3 SHA512-SUMS.txt; standard (not Mono) templates.
expected = 'da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68'
h = hashlib.sha512()
with archive.open('rb') as f:
    for block in iter(lambda: f.read(1024 * 1024), b''): h.update(block)
if h.hexdigest() != expected: raise SystemExit('Godot templates checksum mismatch')
names = {'version.txt', 'android_debug.apk', 'android_source.zip',
         'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe'}
with zipfile.ZipFile(archive) as z:
    for name in names:
        with z.open('templates/' + name) as src, (destination / name).open('wb') as dst:
            shutil.copyfileobj(src, dst)
archive.unlink()
PY
fi
if [[ "${1:-}" == "--templates-only" ]]; then
  echo "Templates installed: $TEMPLATES"
  exit 0
fi
SDK=${ANDROID_HOME:-"$TOOLS/android-sdk"}
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
MANAGER="$SDK/cmdline-tools/23.0/bin/sdkmanager"
if [[ ! -x "$MANAGER" ]]; then
  CLI="$TOOLS/downloads/android-commandlinetools.zip"
  curl -fL --retry 2 https://dl.google.com/android/repository/commandlinetools-linux-16111833_latest.zip -o "$CLI"
  python3 - "$CLI" "$SDK" <<'PY'
import hashlib, pathlib, shutil, sys, tempfile, zipfile
archive, sdk = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
# Google's repository2-1.xml SHA1 for Linux command-line tools23.0.
if hashlib.sha1(archive.read_bytes()).hexdigest() != 'e025545c62a8e64c7559119566a569fb1dec5f60':
    raise SystemExit('Android command-line tools checksum mismatch')
with tempfile.TemporaryDirectory(dir=archive.parent) as tmp:
    with zipfile.ZipFile(archive) as z: z.extractall(tmp)
    destination = sdk / 'cmdline-tools' / '23.0'
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(pathlib.Path(tmp) / 'cmdline-tools'), destination)
for executable in (destination / 'bin').iterdir(): executable.chmod(0o755)
archive.unlink()
PY
fi
# Installation is an explicit request to accept the Android SDK licenses.
# Tool23 delegates sdkmanager to Android CLI; --licenses is harmless there.
set +o pipefail
yes | "$MANAGER" --sdk_root="$SDK" --licenses
LICENSE_STATUS=${PIPESTATUS[1]}
set -o pipefail
if [[ "$LICENSE_STATUS" != 0 ]]; then exit "$LICENSE_STATUS"; fi
"$MANAGER" --sdk_root="$SDK" "platform-tools" "platforms;android-36" "build-tools;36.1.0"
BUNDLETOOL="$TOOLS/bundletool-all-1.18.3.jar"
if [[ ! -f "$BUNDLETOOL" ]]; then
  curl -fL --retry 2 https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar -o "$BUNDLETOOL"
fi
python3 - "$BUNDLETOOL" <<'PY'
import hashlib, pathlib, sys
if hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest() != 'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29':
    raise SystemExit('Official bundletool1.18.3 checksum mismatch')
PY
echo "Templates: $TEMPLATES"
echo "Android SDK: $SDK"
echo "Set PEEPEECHESS_TOOLCHAIN_DIR=$TOOLS and ANDROID_HOME=$SDK for export-native.sh."
