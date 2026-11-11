#!/usr/bin/env bash
# Build playable PC packages (Windows x86_64 .zip + Linux x86_64 .tar.gz).
#
#   GODOT=/path/to/Godot_v4.6.3-stable_linux.x86_64 \
#   [TEMPLATES_TPZ=/path/to/Godot_v4.6.3-stable_export_templates.tpz] \   # only needed until templates are installed
#   [TARGET=app|arena] [PRESETS=auto|repo|tools] [SMOKE=1] \
#   tools/package/build_pc.sh [out_dir]
#
# TARGET=app (default)  the full application (main menu, Classic/Battle Chess, combat) with the project's main scene.
# TARGET=arena          the standalone combat test arena as the main scene.
# PRESETS=auto|repo|tools  Windows preset source: auto (default) uses the repository's own godot/export_presets.cfg
#                       "Windows Desktop" preset when it exists, else the fallback in tools/package/export_presets.cfg.
#                       The Linux preset always comes from tools/package/export_presets.cfg (the repo has none).
# SMOKE=1               also export a Linux "smoke" variant (the same project with tools/package/smoke/package_smoke.tscn as main scene,
#                       never shipped) into <out_dir>/smoke/ for tools/package/smoke_linux.sh.
#
# The repository is not modified: godot/ is exported from git (git archive HEAD when godot/ is clean, otherwise a copy of
# the working tree) into <out_dir>/stage and every adjustment is made there.
# Output (SHA = short commit id, "-dirty" if godot/ or tools/ has uncommitted changes):
#   <out_dir>/<Name>-<SHA>-win64.zip, <Name>-<SHA>-linux64.tar.gz, SHA256SUMS, BUILD_INFO.txt
# The archive step is deterministic (sorted entries, timestamps = commit time, fixed owner/modes; SOURCE_DATE_EPOCH
# overrides the time): the same exported files always give the same zip/tar.gz. The Godot export itself is NOT
# byte-reproducible: two builds of one commit differ inside the embedded PCK (observed: 64 bytes in size, binaries and
# archives get different SHA-256). Publish the SHA256SUMS of the build you distribute. Windows binaries are unsigned.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(realpath -m "${1:-$ROOT/dist}")"
GODOT="${GODOT:?set GODOT to the Godot 4.6.3 editor binary}"
VERSION="4.6.3.stable"
TARGET="${TARGET:-app}"
PRESETS="${PRESETS:-auto}"
TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION"
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
FULL_SHA="$(git -C "$ROOT" rev-parse HEAD)"
DIRTY="$(git -C "$ROOT" status --porcelain --untracked-files=no -- godot tools | head -1)"
[ -n "$DIRTY" ] && SHA="$SHA-dirty"
EPOCH="${SOURCE_DATE_EPOCH:-$(git -C "$ROOT" log -1 --format=%ct)}"
export TZ=UTC LC_ALL=C

case "$("$GODOT" --version 2>/dev/null)" in
  "$VERSION".*) ;;
  *) echo "GODOT must be Godot $VERSION (standard build); got: $("$GODOT" --version 2>&1 | head -1)" >&2; exit 2 ;;
esac

if [ ! -f "$TPL_DIR/windows_release_x86_64.exe" ] || [ ! -f "$TPL_DIR/windows_release_x86_64_console.exe" ] || [ ! -f "$TPL_DIR/linux_release.x86_64" ]; then
  : "${TEMPLATES_TPZ:?export templates for $VERSION are not installed in $TPL_DIR; set TEMPLATES_TPZ to the .tpz (check its sha512 against the Godot release SHA512-SUMS.txt)}"
  mkdir -p "$TPL_DIR"
  python3 -I - "$TEMPLATES_TPZ" "$TPL_DIR" <<'PY'
import sys, zipfile, os
z = zipfile.ZipFile(sys.argv[1]); dst = sys.argv[2]
keep = ("version.txt", "windows_release_x86_64.exe", "windows_release_x86_64_console.exe", "windows_debug_x86_64.exe",
        "windows_debug_x86_64_console.exe", "linux_release.x86_64", "linux_debug.x86_64")
for n in z.namelist():
    if os.path.basename(n) in keep:
        open(os.path.join(dst, os.path.basename(n)), "wb").write(z.read(n))
PY
fi

STAGE="$OUT/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
if [ -z "$DIRTY" ] && git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$ROOT" archive --format=tar HEAD godot | tar -x -C "$STAGE"        # exactly the committed tree
  SOURCE_KIND="git archive $FULL_SHA"
else
  cp -r "$ROOT/godot" "$STAGE/godot"; SOURCE_KIND="working tree copy (uncommitted changes present)"
fi
rm -rf "$STAGE/godot/.godot" "$STAGE/godot/android"

if [ "$TARGET" = "arena" ]; then
  sed -i 's#^run/main_scene=.*#run/main_scene="res://combat/scenes/test_arena.tscn"#' "$STAGE/godot/project.godot"
  NAME="Peepeechess-Combat"; TITLE="Peepeechess Combat"
else
  NAME="Peepeechess"; TITLE="Peepeechess"
fi
sed -i "s#^config/name=.*#config/name=\"$TITLE\"#" "$STAGE/godot/project.godot"
# Windows preset: the repository's own (canonical) one when present; includes *.json/*.wav so runtime-read files are packed.
WIN_PRESET="$(python3 -I "$ROOT/tools/package/stage_presets.py" "$ROOT/godot/export_presets.cfg" "$ROOT/tools/package/export_presets.cfg" \
  "$STAGE/godot/export_presets.cfg" "$TITLE" "$PRESETS")"
# desktop texture compression must be enabled in the project for S3TC/BPTC export
if ! grep -q "import_s3tc_bptc" "$STAGE/godot/project.godot"; then
  if grep -q '^\[rendering\]' "$STAGE/godot/project.godot"; then
    sed -i '/^\[rendering\]/a textures/vram_compression/import_s3tc_bptc=true' "$STAGE/godot/project.godot"
  else
    printf '\n[rendering]\ntextures/vram_compression/import_s3tc_bptc=true\n' >> "$STAGE/godot/project.godot"
  fi
fi

# Godot logs "ERROR:" lines for real export/import problems; a zero exit code alone is not trusted.
check_log() {
  if grep -E 'SCRIPT ERROR|Parse Error|^ERROR:|Failed to export|Cannot export' "$1" >&2; then
    echo "Godot reported errors, see $1" >&2; exit 1
  fi
}
"$GODOT" --headless --path "$STAGE/godot" --editor --import >"$OUT/import.log" 2>&1 || true
check_log "$OUT/import.log"

WIN="$OUT/$NAME-$SHA-win64"; LIN="$OUT/$NAME-$SHA-linux64"
rm -rf "$WIN" "$LIN"; mkdir -p "$WIN" "$LIN"
"$GODOT" --headless --path "$STAGE/godot" --export-release "Windows Desktop" "$WIN/$NAME.exe" >"$OUT/export_win.log" 2>&1
check_log "$OUT/export_win.log"
"$GODOT" --headless --path "$STAGE/godot" --export-release "Linux" "$LIN/$NAME.x86_64" >"$OUT/export_linux.log" 2>&1
check_log "$OUT/export_linux.log"
[ -s "$WIN/$NAME.exe" ] && [ -s "$LIN/$NAME.x86_64" ] || { echo "export produced no binary" >&2; exit 1; }

if [ "${SMOKE:-0}" = "1" ]; then
  SM="$OUT/smoke"; rm -rf "$SM"; mkdir -p "$SM/project"
  cp -a "$STAGE/godot/." "$SM/project/"
  mkdir -p "$SM/project/smoke"; cp "$ROOT/tools/package/smoke/package_smoke."{gd,tscn} "$SM/project/smoke/"
  sed -i 's#^run/main_scene=.*#run/main_scene="res://smoke/package_smoke.tscn"#' "$SM/project/project.godot"
  "$GODOT" --headless --path "$SM/project" --editor --import >"$OUT/import_smoke.log" 2>&1 || true
  "$GODOT" --headless --path "$SM/project" --export-release "Linux" "$SM/Peepeechess-smoke.x86_64" >"$OUT/export_smoke.log" 2>&1
  check_log "$OUT/export_smoke.log"
  rm -rf "$SM/project"
fi

sed "s/@SHA@/$SHA/g; s/@NAME@/$NAME/g; s/@TITLE@/$TITLE/g" "$ROOT/tools/package/PLAY.txt" > "$WIN/PLAY.txt"; cp "$WIN/PLAY.txt" "$LIN/PLAY.txt"
sed "s/@NAME@/$NAME/g" "$ROOT/tools/package/Start-with-console.bat" | sed 's/$/\r/' > "$WIN/Start-with-console.bat"
chmod +x "$LIN/$NAME.x86_64"
python3 -I "$ROOT/tools/package/make_archive.py" zip    "$WIN" "$OUT/$NAME-$SHA-win64.zip"      "$EPOCH"
python3 -I "$ROOT/tools/package/make_archive.py" tar.gz "$LIN" "$OUT/$NAME-$SHA-linux64.tar.gz" "$EPOCH"

( cd "$OUT" && sha256sum "$NAME-$SHA-win64.zip" "$NAME-$SHA-linux64.tar.gz" "$NAME-$SHA-win64/$NAME.exe" \
    "$NAME-$SHA-win64/$NAME.console.exe" "$NAME-$SHA-linux64/$NAME.x86_64" > SHA256SUMS )
cat > "$OUT/BUILD_INFO.txt" <<EOF
name:            $NAME ($TARGET)
commit:          $FULL_SHA${DIRTY:+ (godot/ or tools/ had uncommitted changes)}
source:          $SOURCE_KIND
godot:           $("$GODOT" --version | head -1)
windows preset:  $WIN_PRESET (godot/export_presets.cfg "Windows Desktop" when "repo")
archive epoch:   $EPOCH
signing:         none (unsigned Windows binary, no code signature)
EOF
cat "$OUT/SHA256SUMS"
echo "built: $OUT/$NAME-$SHA-win64.zip  $OUT/$NAME-$SHA-linux64.tar.gz"
