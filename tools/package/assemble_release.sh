#!/usr/bin/env bash
# Turn the output of tools/package/build_pc.sh into a flat set of GitHub Release assets plus release notes.
#
#   tools/package/assemble_release.sh <build_pc out_dir> <release_dir> [tag]
#
# Reads from <out_dir> (all optional except the three build outputs): BUILD_INFO.txt, smoke_status.txt ("passed" when
# tools/package/smoke_linux.sh succeeded), smoke_scripted.log, exe-inspection.txt (tools/package/inspect_exe.py report).
# Writes into <release_dir> (recreated):
#   Peepeechess-windows-x86_64.exe   the bare, self-contained Windows executable (byte-identical to the exe inside the zip)
#   Peepeechess-<sha>-win64.zip      exe + Peepeechess.console.exe + Start-with-console.bat + PLAY.txt
#   Peepeechess-<sha>-linux64.tar.gz Linux build (the one the smoke test ran)
#   SHA256SUMS.txt                   `sha256sum -c SHA256SUMS.txt` works inside <release_dir>
#   RELEASE_NOTES.md                 only states checks that actually ran (smoke_status.txt, exe-inspection.txt)
# Never signs or uploads anything. Used by tools/package/build_release_local.sh and .github/workflows/release-windows.yml.
set -euo pipefail
PC="$(realpath "${1:?usage: assemble_release.sh <build_pc out_dir> <release_dir> [tag]}")"
REL="$(realpath -m "${2:?usage: assemble_release.sh <build_pc out_dir> <release_dir> [tag]}")"
TAG="${3:-untagged}"

one() { local m; m=("$@"); [ "${#m[@]}" = 1 ] && [ -f "${m[0]}" ] || { echo "expected exactly one of: $*" >&2; exit 2; }; printf '%s' "${m[0]}"; }
ZIP="$(one "$PC"/Peepeechess-*-win64.zip)"
TGZ="$(one "$PC"/Peepeechess-*-linux64.tar.gz)"
BASE="$(basename "$ZIP" .zip)"
EXE="$PC/$BASE/Peepeechess.exe"
[ -s "$EXE" ] || { echo "missing $EXE" >&2; exit 2; }

rm -rf "$REL"; mkdir -p "$REL"
cp "$EXE" "$REL/Peepeechess-windows-x86_64.exe"
cp "$ZIP" "$TGZ" "$REL/"
# The bare exe must be exactly the exe a tester gets from the zip.
python3 -I - "$ZIP" "$BASE/Peepeechess.exe" "$REL/Peepeechess-windows-x86_64.exe" <<'PY'
import hashlib, sys, zipfile
zip_path, member, loose = sys.argv[1:4]
a = hashlib.sha256(zipfile.ZipFile(zip_path).read(member)).hexdigest()
b = hashlib.sha256(open(loose, "rb").read()).hexdigest()
if a != b:
    sys.exit("exe inside the zip differs from the released exe")
PY
( cd "$REL" && sha256sum Peepeechess-windows-x86_64.exe "$(basename "$ZIP")" "$(basename "$TGZ")" > SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt >/dev/null )

field() { sed -n "s/^$1: *//p" "$PC/BUILD_INFO.txt" 2>/dev/null | head -1; }
sha() { sha256sum "$REL/$1" | cut -d' ' -f1; }
size() { stat -c %s "$REL/$1"; }
EXE_N=Peepeechess-windows-x86_64.exe; ZIP_N="$(basename "$ZIP")"; TGZ_N="$(basename "$TGZ")"
SMOKE="$(cat "$PC/smoke_status.txt" 2>/dev/null || echo "not run")"
SCRIPTED="$(grep -E '^Package smoke:' "$PC/smoke_scripted.log" 2>/dev/null | tail -1 || true)"
PACK="$(sed -n 's/^pack: *//p' "$PC/exe-inspection.txt" 2>/dev/null | head -1)"
INSPECT_OK="$(grep -c '^RESULT: ok' "$PC/exe-inspection.txt" 2>/dev/null || true)"

{
  echo "# Peepeechess $TAG (Windows alpha, unsigned)"
  echo
  echo "Alpha build of the native Peepeechess application: main menu, Classic Chess, Battle Chess, local play. Online play needs a"
  echo "Peepeechess server. This is a test build for playtesters, not a store release."
  echo
  echo "## Download"
  echo
  echo "| File | Bytes | SHA-256 |"
  echo "| --- | ---: | --- |"
  for n in "$EXE_N" "$ZIP_N" "$TGZ_N"; do echo "| \`$n\` | $(size "$n") | \`$(sha "$n")\` |"; done
  echo
  echo "- **Windows 10/11 x64:** download \`$EXE_N\` and double-click it (one file, the game data is embedded). Or download the zip,"
  echo "  extract it and run \`Peepeechess.exe\`; \`Start-with-console.bat\` shows a console with errors for bug reports."
  echo "- **Linux x86_64:** \`$TGZ_N\`, run \`Peepeechess.x86_64\`."
  echo "- The executable is **not code-signed**: Windows SmartScreen shows \"Windows protected your PC\"; choose *More info*, then *Run anyway*."
  echo "- Check the download: \`Get-FileHash .\\$EXE_N -Algorithm SHA256\` (PowerShell) must equal the value above and in \`SHA256SUMS.txt\`."
  echo
  echo "## Build"
  echo
  echo "- Source commit: \`$(field commit | cut -d' ' -f1)\`"
  echo "- Engine: Godot $(field godot), standard official export templates, Windows preset \`Windows Desktop\` of the repository"
  echo "- Builds are not byte-reproducible (the Godot export differs between runs); the hashes above belong to exactly these files."
  echo
  echo "## What was checked before publishing"
  echo
  if [ "$INSPECT_OK" = 1 ]; then
    echo "- Windows exe, static inspection (\`tools/package/inspect_exe.py\`, the file was not executed): valid PE32+ x86_64 image, embedded pack ($PACK) with every file's MD5 verified, main scene and runtime data files present, Windows version resource written."
  else
    echo "- Windows exe static inspection: not run."
  fi
  if [ "$SMOKE" = passed ]; then
    echo "- Linux package of this same commit, under Xvfb with software OpenGL: the main menu starts and runs 300 frames without errors, and a scripted variant navigates the menu pages, reads the packed data and starts local Classic and Battle Chess matches (${SCRIPTED:-no summary line})."
  else
    echo "- Linux package smoke test: $SMOKE."
  fi
  # .github/workflows/release-windows.yml replaces this comment with the result of its Windows-runner start check.
  echo "<!-- WINDOWS_RUNNER_CHECK -->"
  echo
  echo "## What was NOT checked"
  echo
  echo "- The Windows executable has not been run on a physical Windows PC by the developers; GPU drivers, the OpenGL compatibility renderer on real hardware, gamepads and SmartScreen/antivirus behaviour are untested."
  echo "- No code signature (Authenticode). Antivirus or SmartScreen may warn about an unsigned file."
  echo "- Balance and feel are unvalidated by human play; online play was not exercised against a public server."
} > "$REL/RELEASE_NOTES.md"

echo "release assets in $REL:"
( cd "$REL" && ls -l && cat SHA256SUMS.txt )
