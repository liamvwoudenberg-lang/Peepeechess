#!/usr/bin/env bash
# Exports the real Windows pack and checks every shipped feature is inside it (godot/tools/product_check.gd).
set -euo pipefail
pack="${TMPDIR:-/tmp}/peepeechess-product.pck"
godot --headless --path godot --export-pack "Windows Desktop" "$pack" >/dev/null 2>&1
godot --headless --main-pack "$pack" --script res://tools/product_check.gd
