#!/usr/bin/env bash
# One command from a checkout to publishable Windows (and Linux) release assets. Linux x86_64 host.
#
#   tools/package/build_release_local.sh [tag]
#
#   1. Godot 4.6.3 editor: $GODOT / $GODOT_BIN, else `godot` on PATH, else the pinned official editor is downloaded
#      (SHA-512 verified) into $PEEPEECHESS_TOOLCHAIN_DIR/godot-editor.
#   2. Official 4.6.3 export templates: scripts/install-native-toolchain.sh --templates-only (SHA-512 verified). Skipped when
#      they are already in $PEEPEECHESS_TOOLCHAIN_DIR, so a second run does not download 1.2 GB again.
#   3. tools/package/build_pc.sh with SMOKE=1: Windows zip (+ console exe), Linux tar.gz, smoke variant.
#   4. tools/package/smoke_linux.sh: the Linux build starts under Xvfb and runs local Classic and Battle matches.
#   5. tools/package/inspect_exe.py: static PE/PCK check of the Windows exe (nothing here can run a Windows program).
#   6. tools/package/assemble_release.sh: flat assets, SHA256SUMS.txt and RELEASE_NOTES.md.
#
# Environment (all optional):
#   GODOT / GODOT_BIN            Godot 4.6.3 standard editor binary
#   PEEPEECHESS_TOOLCHAIN_DIR    cache for templates/editor, default <repo>/work/toolchains (git-ignored)
#   RELEASE_OUT                  output directory, default <repo>/artifacts/release (git-ignored); pc/ and release/ below it
#   SKIP_SMOKE=1                 skip step 4 (needed only where xvfb-run is not installed); the release notes then say so
# The task-local Godot settings/cache (XDG_*) live in $RELEASE_OUT/runtime; HOME and the user's editor are never touched.
# The repository itself is not modified. Nothing is uploaded or signed; see docs/application/EXPORTS.md for publishing.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TAG="${1:-local-$(git -C "$ROOT" rev-parse --short HEAD)}"
[[ "$TAG" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || { echo "tag must match [A-Za-z0-9][A-Za-z0-9._-]* (max 64): $TAG" >&2; exit 2; }
TOOLS="${PEEPEECHESS_TOOLCHAIN_DIR:-$ROOT/work/toolchains}"
OUT="$(realpath -m "${RELEASE_OUT:-$ROOT/artifacts/release}")"
VERSION="$(tr -d '\r\n' < "$ROOT/.godot-version")"
[ "$VERSION" = "4.6.3" ] || { echo "pinned checksums below are for Godot 4.6.3, .godot-version says $VERSION" >&2; exit 2; }
TEMPLATES="$TOOLS/godot/templates/$VERSION.stable"
EDITOR_ZIP_SHA512=a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c
EDITOR_URL="https://github.com/godotengine/godot-builds/releases/download/$VERSION-stable/Godot_v$VERSION-stable_linux.x86_64.zip"

phase() { printf '\n== %s ==\n' "$*"; PHASE_START=$SECONDS; }
done_phase() { printf '   (%ds)\n' $((SECONDS - PHASE_START)); }
TOTAL_START=$SECONDS

if [ "${SKIP_SMOKE:-0}" != 1 ] && ! command -v xvfb-run >/dev/null; then
  echo "xvfb-run is not installed (apt-get install xvfb libgl1-mesa-dri libglx-mesa0); install it or set SKIP_SMOKE=1" >&2; exit 2
fi
for tool in python3 curl; do command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 2; }; done

# ---- 1. editor ---------------------------------------------------------------------------------------------------
phase "Godot $VERSION editor"
GODOT="${GODOT:-${GODOT_BIN:-}}"
[ -n "$GODOT" ] || GODOT="$(command -v godot || true)"
if [ -z "$GODOT" ]; then
  GODOT="$TOOLS/godot-editor/godot"
  if [ ! -x "$GODOT" ]; then
    command -v unzip >/dev/null || { echo "unzip is required to unpack the editor" >&2; exit 2; }
    mkdir -p "$TOOLS/downloads" "$TOOLS/godot-editor"
    curl -fL --retry 2 "$EDITOR_URL" -o "$TOOLS/downloads/godot-editor.zip"
    echo "$EDITOR_ZIP_SHA512  $TOOLS/downloads/godot-editor.zip" | sha512sum -c -
    unzip -q -o "$TOOLS/downloads/godot-editor.zip" -d "$TOOLS/godot-editor"
    mv "$TOOLS/godot-editor/Godot_v$VERSION-stable_linux.x86_64" "$GODOT"
    chmod +x "$GODOT"; rm -f "$TOOLS/downloads/godot-editor.zip"
  fi
fi
GODOT="$(realpath "$GODOT")"
case "$("$GODOT" --version 2>/dev/null)" in
  "$VERSION".stable.*) echo "using $GODOT ($("$GODOT" --version))" ;;
  *) echo "$GODOT is not Godot $VERSION stable (standard build): $("$GODOT" --version 2>&1 | head -1)" >&2; exit 2 ;;
esac
done_phase

# ---- 2. export templates -------------------------------------------------------------------------------------------
phase "export templates $VERSION"
need=(windows_release_x86_64.exe windows_release_x86_64_console.exe linux_release.x86_64 version.txt)
missing=0; for f in "${need[@]}"; do [ -s "$TEMPLATES/$f" ] || missing=1; done
if [ "$missing" = 1 ]; then
  PEEPEECHESS_TOOLCHAIN_DIR="$TOOLS" bash "$ROOT/scripts/install-native-toolchain.sh" --templates-only
else
  echo "templates already installed in $TEMPLATES (not downloading again)"
fi
for f in "${need[@]}"; do [ -s "$TEMPLATES/$f" ] || { echo "template missing after install: $TEMPLATES/$f" >&2; exit 1; }; done
[ "$(tr -d '\r\n' < "$TEMPLATES/version.txt")" = "$VERSION.stable" ] || { echo "template version.txt is not $VERSION.stable" >&2; exit 1; }
done_phase

# ---- 3. build ------------------------------------------------------------------------------------------------------
phase "build Windows + Linux packages (tools/package/build_pc.sh)"
mkdir -p "$OUT"
export XDG_DATA_HOME="$OUT/runtime/data" XDG_CONFIG_HOME="$OUT/runtime/config" XDG_CACHE_HOME="$OUT/runtime/cache"
mkdir -p "$XDG_DATA_HOME/godot/export_templates" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
ln -sfn "$TEMPLATES" "$XDG_DATA_HOME/godot/export_templates/$VERSION.stable"
rm -rf "$OUT/pc" "$OUT/release"
# TARGET=app: the full application (never the combat test arena); PRESETS=repo: fail instead of silently falling back to
# tools/package/export_presets.cfg when the repository's own "Windows Desktop" preset is missing.
GODOT="$GODOT" SMOKE=1 TARGET=app PRESETS=repo bash "$ROOT/tools/package/build_pc.sh" "$OUT/pc"
done_phase
ZIP="$(ls "$OUT"/pc/Peepeechess-*-win64.zip)"
EXE="$OUT/pc/$(basename "$ZIP" .zip)/Peepeechess.exe"
case "$ZIP" in *-dirty-*) echo "WARNING: godot/ or tools/ has uncommitted changes (-dirty in the file names); do not publish this build." >&2 ;; esac

# ---- 4. Linux smoke test -------------------------------------------------------------------------------------------
phase "Linux package smoke test (tools/package/smoke_linux.sh)"
if [ "${SKIP_SMOKE:-0}" = 1 ]; then
  echo "skipped (SKIP_SMOKE=1)"; echo "skipped" > "$OUT/pc/smoke_status.txt"
elif bash "$ROOT/tools/package/smoke_linux.sh" "$OUT/pc"; then
  echo passed > "$OUT/pc/smoke_status.txt"
else
  echo "FAILED: Linux smoke test; logs are $OUT/pc/smoke_*.log" >&2; echo failed > "$OUT/pc/smoke_status.txt"; exit 1
fi
done_phase

# ---- 5. static check of the exe ------------------------------------------------------------------------------------
phase "static check of the Windows exe (tools/package/inspect_exe.py)"
python3 -I "$ROOT/tools/package/inspect_exe.py" "$EXE" | tee "$OUT/pc/exe-inspection.txt"
done_phase

# ---- 6. assets -----------------------------------------------------------------------------------------------------
phase "release assets"
bash "$ROOT/tools/package/assemble_release.sh" "$OUT/pc" "$OUT/release" "$TAG"
done_phase

printf '\nDone in %ds. Publish-ready files: %s\n  smoke: %s   static exe check: ok   tag used in the notes: %s\n' \
  $((SECONDS - TOTAL_START)) "$OUT/release" "$(cat "$OUT/pc/smoke_status.txt")" "$TAG"
