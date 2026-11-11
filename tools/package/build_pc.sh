#!/usr/bin/env bash
# Build playable PC packages (Windows x86_64 + Linux x86_64): the full application (default) or the combat arena (TARGET=arena).
#
#   GODOT=/path/to/Godot_v4.6.3-stable_linux.x86_64 \
#   TEMPLATES_TPZ=/path/to/Godot_v4.6.3-stable_export_templates.tpz \   # only needed once
#   tools/package/build_pc.sh [out_dir]
#
# Packages whatever is checked out. The repository is not modified: godot/ is copied to a staging directory,
# whose main scene is set to the combat test arena and which gets export_presets.cfg from this folder.
# Output: <out_dir>/Peepeechess-Combat-<sha>-win64.zip and ...-linux64.tar.gz (default out_dir: ./dist).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$(realpath -m "${1:-$ROOT/dist}")"
GODOT="${GODOT:?set GODOT to the Godot 4.6.3 editor binary}"
VERSION="4.6.3.stable"
TPL_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$VERSION"
SHA="$(git -C "$ROOT" rev-parse --short HEAD)"
DIRTY="$(git -C "$ROOT" status --porcelain --untracked-files=no -- godot tools | head -1)"
[ -n "$DIRTY" ] && SHA="$SHA-dirty"

if [ ! -f "$TPL_DIR/windows_release_x86_64.exe" ] || [ ! -f "$TPL_DIR/linux_release.x86_64" ]; then
  : "${TEMPLATES_TPZ:?export templates for $VERSION are not installed; set TEMPLATES_TPZ to the .tpz (check its sha512 against the Godot release SHA512-SUMS.txt)}"
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
cp -r "$ROOT/godot" "$STAGE/godot"
rm -rf "$STAGE/godot/.godot"
# TARGET=app (default): the full application (menus, Classic/Battle Chess, combat) with the project's own main scene.
# TARGET=arena: the standalone combat test arena as the main scene.
TARGET="${TARGET:-app}"
if [ "$TARGET" = "arena" ]; then
  sed -i 's#^run/main_scene=.*#run/main_scene="res://combat/scenes/test_arena.tscn"#' "$STAGE/godot/project.godot"
  NAME="Peepeechess-Combat"; TITLE="Peepeechess Combat"
else
  NAME="Peepeechess"; TITLE="Peepeechess"
fi
sed -i "s#^config/name=.*#config/name=\"$TITLE\"#" "$STAGE/godot/project.godot"
cp "$ROOT/tools/package/export_presets.cfg" "$STAGE/godot/export_presets.cfg"
sed -i "s#^application/product_name=.*#application/product_name=\"$TITLE\"#" "$STAGE/godot/export_presets.cfg"
# desktop texture compression must be enabled in the project for S3TC/BPTC export
if ! grep -q "import_s3tc_bptc" "$STAGE/godot/project.godot"; then
  if grep -q '^\[rendering\]' "$STAGE/godot/project.godot"; then
    sed -i '/^\[rendering\]/a textures/vram_compression/import_s3tc_bptc=true' "$STAGE/godot/project.godot"
  else
    printf '\n[rendering]\ntextures/vram_compression/import_s3tc_bptc=true\n' >> "$STAGE/godot/project.godot"
  fi
fi

"$GODOT" --headless --path "$STAGE/godot" --editor --import >"$OUT/import.log" 2>&1 || true

WIN="$OUT/$NAME-$SHA-win64"; LIN="$OUT/$NAME-$SHA-linux64"
rm -rf "$WIN" "$LIN"; mkdir -p "$WIN" "$LIN"
"$GODOT" --headless --path "$STAGE/godot" --export-release "Windows Desktop" "$WIN/$NAME.exe" >"$OUT/export_win.log" 2>&1
"$GODOT" --headless --path "$STAGE/godot" --export-release "Linux" "$LIN/$NAME.x86_64" >"$OUT/export_linux.log" 2>&1
sed "s/@SHA@/$SHA/g; s/@NAME@/$NAME/g; s/@TITLE@/$TITLE/g" "$ROOT/tools/package/PLAY.txt" > "$WIN/PLAY.txt"; cp "$WIN/PLAY.txt" "$LIN/PLAY.txt"
sed "s/@NAME@/$NAME/g" "$ROOT/tools/package/Start-with-console.bat" > "$WIN/Start-with-console.bat"
chmod +x "$LIN/$NAME.x86_64"
( cd "$OUT" && python3 -I -c "
import shutil,sys
shutil.make_archive('$NAME-$SHA-win64','zip','.','$NAME-$SHA-win64')
shutil.make_archive('$NAME-$SHA-linux64','gztar','.','$NAME-$SHA-linux64')" )
echo "built: $OUT/$NAME-$SHA-win64.zip  $OUT/$NAME-$SHA-linux64.tar.gz"
