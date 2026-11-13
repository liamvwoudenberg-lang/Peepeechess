#!/usr/bin/env bash
# Put the Windows build where anyone can download it from the repository itself.
#
#   tools/package/publish_download.sh <release_dir from build_release_local.sh>
#
# Writes (replacing the previous build) into downloads/windows/:
#   Peepeechess-windows-x86_64.zip   the single Windows exe, zipped (GitHub refuses files over 100 MB; the bare exe is ~115 MB)
#   SHA256SUMS.txt                   hashes of the zip and of the exe inside it
#   LATEST.md                        commit, date, how to run, what was NOT checked
# Then `git add downloads/windows && git commit`. Run it only from the committed tree the build was made from.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REL="${1:?usage: publish_download.sh <release_dir>}"
EXE="$REL/Peepeechess-windows-x86_64.exe"
[ -f "$EXE" ] || { echo "no $EXE (run tools/package/build_release_local.sh first)" >&2; exit 2; }
command -v zip >/dev/null || { echo "zip is required" >&2; exit 2; }
OUT="$ROOT/downloads/windows"
mkdir -p "$OUT"; rm -f "$OUT"/*.zip "$OUT"/SHA256SUMS.txt
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
cp "$EXE" "$WORK/Peepeechess.exe"
(cd "$WORK" && zip -q -9 "$OUT/Peepeechess-windows-x86_64.zip" Peepeechess.exe)
SIZE=$(stat -c %s "$OUT/Peepeechess-windows-x86_64.zip")
[ "$SIZE" -lt 95000000 ] || { echo "zip is $SIZE bytes: too close to GitHub's 100 MB file limit" >&2; exit 3; }
EXE_SHA=$(sha256sum "$EXE" | cut -d' ' -f1); ZIP_SHA=$(sha256sum "$OUT/Peepeechess-windows-x86_64.zip" | cut -d' ' -f1)
{ echo "$ZIP_SHA  Peepeechess-windows-x86_64.zip"; echo "$EXE_SHA  Peepeechess.exe (inside the zip)"; } > "$OUT/SHA256SUMS.txt"
COMMIT=$(git -C "$ROOT" rev-parse HEAD)
DIRTY=""; [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ] || DIRTY=" (WORKING TREE WAS DIRTY: do not publish)"
cat > "$OUT/LATEST.md" <<MD
# Latest Windows build

- Download: [\`Peepeechess-windows-x86_64.zip\`](Peepeechess-windows-x86_64.zip) (unzip, double-click \`Peepeechess.exe\`; one self-contained file)
- Built from commit \`$COMMIT\`$DIRTY on $(date -u +%Y-%m-%d)
- SHA-256 of the zip: \`$ZIP_SHA\`; of \`Peepeechess.exe\`: \`$EXE_SHA\`
- Unsigned: Windows SmartScreen shows "Windows protected your PC"; choose *More info*, then *Run anyway*.
- Never run on a real Windows PC by the developers (built and checked on Linux: static PE check, Linux build smoke test).
- Builds are not byte-reproducible. Older builds: see the git history of this folder.
MD
echo "wrote $OUT ($SIZE bytes zip)"; ls -la "$OUT"
