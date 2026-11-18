#!/usr/bin/env bash
# Download the official Godot 4.6.3 export templates (SHA-512 verified) and extract only what the dedicated-server builds need:
# linux_release.x86_64, linux_release.arm64 and version.txt.
#   tools/deploy/install_server_templates.sh [TEMPLATE_DIR]
# TEMPLATE_DIR defaults to $XDG_DATA_HOME/godot/export_templates/4.6.3.stable (where Godot looks for them).
set -euo pipefail
DEST="${1:-${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable}"
URL="https://github.com/godotengine/godot-builds/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz"
SHA512=da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68
mkdir -p "$DEST"
if [ -f "$DEST/linux_release.x86_64" ] && [ -f "$DEST/linux_release.arm64" ] && [ -f "$DEST/version.txt" ]; then
  echo "templates already present in $DEST"; exit 0
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
curl -fL --retry 3 "$URL" -o "$TMP/templates.tpz"
echo "$SHA512  $TMP/templates.tpz" | sha512sum -c -
python3 - "$TMP/templates.tpz" "$DEST" <<'PY'
import pathlib, shutil, sys, zipfile
archive, dest = sys.argv[1], pathlib.Path(sys.argv[2])
with zipfile.ZipFile(archive) as z:
    for name in ("version.txt", "linux_release.x86_64", "linux_release.arm64"):
        with z.open("templates/" + name) as src, (dest / name).open("wb") as out:
            shutil.copyfileobj(src, out)
        print("extracted", name)
(dest / "linux_release.x86_64").chmod(0o755); (dest / "linux_release.arm64").chmod(0o755)
PY
