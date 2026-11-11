#!/usr/bin/env bash
# Smoke-test the exported Linux package under Xvfb (software OpenGL, dummy audio). Needs xvfb-run.
#   tools/package/smoke_linux.sh <out_dir of build_pc.sh>     (build with SMOKE=1 for the scripted check)
# 1. The distributed binary starts its real main scene (the application main menu) and runs 300 frames, exit 0, no errors.
# 2. The smoke variant (same project + tools/package/smoke/package_smoke.gd) loads the application shell, navigates the
#    menu pages, reads the packed data/audio files and starts local Classic and Battle matches.
# Writes smoke_*.log into <out_dir>; exits non-zero on any failure.
set -uo pipefail
OUT="$(realpath "${1:?usage: smoke_linux.sh <out_dir>}")"
BIN="$(ls "$OUT"/*-linux64/*.x86_64 2>/dev/null | head -1)"
[ -x "$BIN" ] || { echo "no Linux binary under $OUT/*-linux64/" >&2; exit 2; }
command -v xvfb-run >/dev/null || { echo "xvfb-run not installed" >&2; exit 2; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
export XDG_DATA_HOME="$TMP/data" XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"; mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
BAD='SCRIPT ERROR|Parse Error|^ERROR:|^FAIL|Failed to load|Cannot open file|Condition ".*" is true'
status=0
run() {  # name, binary, extra args...
  local name="$1" bin="$2"; shift 2
  timeout 300 xvfb-run -a -s "-screen 0 1280x800x24" "$bin" --rendering-driver opengl3 --audio-driver Dummy "$@" >"$OUT/smoke_$name.log" 2>&1
  local code=$?
  if [ "$code" != 0 ] || grep -E "$BAD" "$OUT/smoke_$name.log" >/dev/null; then
    echo "SMOKE $name: FAILED (exit $code)"; grep -E "$BAD|^FAIL" "$OUT/smoke_$name.log" | head -20; status=1
  else
    echo "SMOKE $name: ok (exit 0, no script/resource errors)"
  fi
}
run mainmenu "$BIN" --quit-after 300
if [ -x "$OUT/smoke/Peepeechess-smoke.x86_64" ]; then
  run scripted "$OUT/smoke/Peepeechess-smoke.x86_64" --script res://smoke/package_smoke.gd
  tail -3 "$OUT/smoke_scripted.log"
else
  echo "scripted smoke skipped: build with SMOKE=1 to create $OUT/smoke/Peepeechess-smoke.x86_64"
fi
exit $status
