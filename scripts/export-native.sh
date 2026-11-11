#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TARGET=${1:-all}
GODOT=${GODOT_BIN:-godot}
TOOLS=${PEEPEECHESS_TOOLCHAIN_DIR:-"$ROOT/work/toolchains"}
SDK=${ANDROID_HOME:-"$TOOLS/android-sdk"}
JAVA_SDK=${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}
OUT=${NATIVE_OUTPUT_DIR:-"$ROOT/artifacts/native"}
RUNTIME="$ROOT/work/native-export-runtime"
export XDG_DATA_HOME="$RUNTIME/data"
export XDG_CONFIG_HOME="$RUNTIME/config"
export XDG_CACHE_HOME="$RUNTIME/cache"
mkdir -p "$OUT" "$XDG_DATA_HOME/godot/export_templates" "$XDG_CONFIG_HOME/godot" "$XDG_CACHE_HOME"
if [[ "$("$GODOT" --version)" != 4.6.3.stable.* ]]; then
  echo "Godot4.6.3 standard build is required." >&2; exit 2
fi
TEMPLATES="$TOOLS/godot/templates/4.6.3.stable"
if [[ ! -d "$TEMPLATES" ]]; then echo "Run scripts/install-native-toolchain.sh first." >&2; exit 2; fi
if [[ ! -e "$XDG_DATA_HOME/godot/export_templates/4.6.3.stable" ]]; then
  ln -s "$TEMPLATES" "$XDG_DATA_HOME/godot/export_templates/4.6.3.stable"
fi
export ANDROID_HOME="$SDK"
export JAVA_HOME="$JAVA_SDK"
export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$ROOT/work/native-gradle}"
# Task-local editor settings; never changes the user's editor configuration.
python3 - "$XDG_CONFIG_HOME/godot/editor_settings-4.6.tres" "$SDK" "$JAVA_SDK" <<'PY'
import json, pathlib, sys
pathlib.Path(sys.argv[1]).write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/android_sdk_path=' + json.dumps(sys.argv[2]) + '\nexport/android/java_sdk_path=' + json.dumps(sys.argv[3]) + '\n')
PY
run_checked() {
  local log="$OUT/$1.log"; shift
  "$@" 2>&1 | tee "$log"
  if rg -q 'SCRIPT ERROR|Parse Error|Failed to load|ERROR:' "$log"; then
    echo "Godot export/import reported errors; see $log" >&2; return 1
  fi
}
debug_key() {
  local key="$ROOT/work/keys/android-debug.keystore"
  mkdir -p "$(dirname "$key")"
  if [[ ! -f "$key" ]]; then
    "$JAVA_SDK/bin/keytool" -genkeypair -noprompt -keystore "$key" -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US'
    chmod 600 "$key"
  fi
  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$key"
  export GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey
  export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android
}
prepare_gradle() {
  if [[ ! -x "$JAVA_SDK/bin/javac" ]]; then
    echo "Android App Bundle compilation needs a full JDK17/21 (javac missing from JAVA_HOME=$JAVA_SDK). A JRE can sign an APK but cannot compile Java." >&2
    return 2
  fi
  python3 - "$ROOT" <<'PY'
import shutil, sys
free = shutil.disk_usage(sys.argv[1]).free
if free < 1024 ** 3:
    raise SystemExit(f'Android bundle build requires at least 1 GiB free before starting; only {free // (1024 ** 2)} MiB available. Allow several GiB for a cold Gradle cache.')
PY
  mkdir -p "$ROOT/godot/android/build"
  if [[ ! -f "$ROOT/godot/android/build/build.gradle" ]]; then
    unzip -q "$TEMPLATES/android_source.zip" -d "$ROOT/godot/android/build"
  fi
  printf '%s\n' 4.6.3.stable > "$ROOT/godot/android/.build_version"
  touch "$ROOT/godot/android/.gdignore"
  chmod +x "$ROOT/godot/android/build/gradlew"
  mkdir -p "$GRADLE_USER_HOME"
  # Gradle/Java do not automatically honor the standard HTTPS_PROXY variables.
  # Use inherited proxy routing, never disables TLS or embeds proxy credentials.
  python3 - "$GRADLE_USER_HOME/gradle.properties" <<'PY'
import os, pathlib, sys, urllib.parse
settings = ['org.gradle.daemon=false', 'org.gradle.workers.max=2', 'org.gradle.jvmargs=-Xmx1536m']
proxy = os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy')
if proxy:
    parsed = urllib.parse.urlsplit(proxy)
    if parsed.username or parsed.password:
        raise SystemExit('Configure authenticated Gradle proxy outside this script; do not write credentials to generated configuration.')
    if parsed.hostname:
        for protocol in ('http', 'https'):
            settings += [f'systemProp.{protocol}.proxyHost={parsed.hostname}', f'systemProp.{protocol}.proxyPort={parsed.port or 80}']
pathlib.Path(sys.argv[1]).write_text('\n'.join(settings) + '\n')
PY
}
run_checked import "$GODOT" --headless --path "$ROOT/godot" --editor --import
case "$TARGET" in
  windows|all)
    run_checked windows "$GODOT" --headless --path "$ROOT/godot" --export-release 'Windows Desktop' "$OUT/Peepeechess-windows-x86_64.exe"
    ;;
esac
case "$TARGET" in
  android-apk|all)
    debug_key
    run_checked android-apk "$GODOT" --headless --path "$ROOT/godot" --export-debug 'Android Debug APK' "$OUT/Peepeechess-android-debug.apk"
    "$SDK/build-tools/36.1.0/apksigner" verify --verbose "$OUT/Peepeechess-android-debug.apk"
    ;;
  android-aab|android-aab-test)
    prepare_gradle
    if [[ "$TARGET" == android-aab-test ]]; then
      # A release-mode bundle signed only with a disposable debug key, never store-ready.
      debug_key
      export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$GODOT_ANDROID_KEYSTORE_DEBUG_PATH"
      export GODOT_ANDROID_KEYSTORE_RELEASE_USER="$GODOT_ANDROID_KEYSTORE_DEBUG_USER"
      export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD"
      BUNDLE="$OUT/Peepeechess-android-test.aab"
    else
      : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?Set the release upload keystore path}"
      : "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?Set the release upload key alias}"
      : "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?Set the release upload key password}"
      BUNDLE="$OUT/Peepeechess-android-release.aab"
    fi
    run_checked android-aab "$GODOT" --headless --path "$ROOT/godot" --export-release 'Android Release AAB' "$BUNDLE"
    "$JAVA_SDK/bin/jarsigner" -verify "$BUNDLE"
    ;;
  windows) ;;
  *) echo 'Usage: scripts/export-native.sh [all|windows|android-apk|android-aab|android-aab-test]' >&2; exit 2 ;;
esac
python3 - "$OUT" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
records=[]
for file in sorted(root.iterdir()):
    if file.suffix not in ('.exe', '.apk', '.aab'): continue
    h=hashlib.sha256()
    with file.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    records.append({'file':file.name,'bytes':file.stat().st_size,'sha256':h.hexdigest()})
(root/'checksums.json').write_text(json.dumps(records,indent=2)+'\n')
print(json.dumps(records,indent=2))
PY
