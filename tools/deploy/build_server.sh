#!/usr/bin/env bash
# Build the Peepeechess dedicated server (Godot 4.6.3 "Export as dedicated server", assets stripped) for one architecture.
#
#   GODOT=/path/to/godot-4.6.3-editor tools/deploy/build_server.sh <x86_64|arm64> [out_dir]
#
# Needs the official export template linux_release.<arch> (tools/deploy/install_server_templates.sh installs it).
# Output in <out_dir> (default artifacts/server-release):
#   peepeechess-server-<arch>-<sha>.tar.gz   peepeechess-server (binary with the embedded pack) + VERSION + run-server.sh
#   peepeechess-server-<arch>-<sha>.tar.gz.sha256
# The x86_64 build is started for 3 s and must print SERVER_READY; the arm64 build is checked statically (ELF machine = AArch64),
# nothing here can run an arm64 binary.
set -euo pipefail
ARCH="${1:?usage: build_server.sh <x86_64|arm64> [out_dir]}"
case "$ARCH" in x86_64|arm64) ;; *) echo "arch must be x86_64 or arm64" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$(realpath -m "${2:-$ROOT/artifacts/server-release}")"
GODOT="${GODOT:-${GODOT_BIN:-godot}}"
case "$("$GODOT" --version 2>/dev/null)" in 4.6.3.stable.*) ;; *) echo "Godot 4.6.3 stable is required (set GODOT)" >&2; exit 2;; esac
TEMPLATES="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable"
[ -f "$TEMPLATES/linux_release.$ARCH" ] || { echo "missing $TEMPLATES/linux_release.$ARCH (run tools/deploy/install_server_templates.sh)" >&2; exit 2; }
SHA="$(git -C "$ROOT" rev-parse --short=12 HEAD)"
FULL="$(git -C "$ROOT" rev-parse HEAD)"
DIRTY=""; [ -z "$(git -C "$ROOT" status --porcelain --untracked-files=no -- godot tools/deploy)" ] || DIRTY="-dirty"
STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT" "$STAGE/pkg"
echo "== exporting Linux Server $ARCH ($SHA$DIRTY)"
(cd "$ROOT/godot" && "$GODOT" --headless --path . --import >/dev/null 2>&1 || true)
log="$STAGE/export.log"
(cd "$ROOT/godot" && "$GODOT" --headless --path . --export-release "Linux Server $ARCH" "$STAGE/pkg/peepeechess-server" > "$log" 2>&1) || { sed 's/\x1b\[[0-9;]*m//g' "$log" | tail -20 >&2; exit 1; }
if sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E "^(ERROR|SCRIPT ERROR)" ; then echo "export reported errors" >&2; exit 1; fi
[ -x "$STAGE/pkg/peepeechess-server" ] || { echo "no binary produced" >&2; exit 1; }
python3 - "$STAGE/pkg/peepeechess-server" "$ARCH" <<'PY'
import struct, sys
data = open(sys.argv[1], "rb").read(20)
machine = struct.unpack_from("<H", data, 18)[0]
want = {"x86_64": 62, "arm64": 183}[sys.argv[2]]
if data[:4] != b"\x7fELF" or machine != want:
    raise SystemExit(f"binary is not a {sys.argv[2]} ELF (machine={machine})")
print("ELF machine", machine, "ok for", sys.argv[2])
PY
cat > "$STAGE/pkg/run-server.sh" <<'RUN'
#!/usr/bin/env bash
# Starts the server with line-buffered output (the release export fully buffers stdout when it is not a terminal).
# Options: --bind=IP --port=N --certificate=PEM --private-key=PEM [--insecure-local] [--run-seconds=N]
here="$(cd "$(dirname "$0")" && pwd)"
exec stdbuf -oL -eL "$here/peepeechess-server" --headless -- "$@"
RUN
chmod +x "$STAGE/pkg/run-server.sh"
printf 'commit=%s%s\nfull_commit=%s\narch=%s\ngodot=4.6.3.stable\nbuilt=%s\n' "$SHA" "$DIRTY" "$FULL" "$ARCH" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STAGE/pkg/VERSION"
if [ "$ARCH" = x86_64 ] && [ "$(uname -m)" = x86_64 ]; then
  echo "== smoke test: starting the exported server for 3 s"
  smoke="$(XDG_DATA_HOME="$STAGE/xdg/data" XDG_CONFIG_HOME="$STAGE/xdg/config" XDG_CACHE_HOME="$STAGE/xdg/cache" timeout 30 "$STAGE/pkg/run-server.sh" --insecure-local --bind=127.0.0.1 --port=7799 --run-seconds=3 2>&1 || true)"
  grep -q "SERVER_READY protocol=peepeechess-enet-v1" <<<"$smoke" || { echo "smoke test failed:"; echo "$smoke" | head -20; exit 1; }
  grep -o "SERVER_READY.*" <<<"$smoke" | head -1
fi
TAR="$OUT/peepeechess-server-$ARCH-$SHA$DIRTY.tar.gz"
tar --sort=name --owner=0 --group=0 --numeric-owner -C "$STAGE/pkg" -czf "$TAR" peepeechess-server run-server.sh VERSION
(cd "$OUT" && sha256sum "$(basename "$TAR")" > "$(basename "$TAR").sha256")
echo "== built $TAR ($(du -h "$TAR" | cut -f1))"; cat "$TAR.sha256"
[ -z "$DIRTY" ] || echo "WARNING: the working tree was dirty: do not deploy this build" >&2
