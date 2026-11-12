#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/server/data work/server/config work/server/cache
export XDG_DATA_HOME="$PWD/work/server/data"
export XDG_CONFIG_HOME="$PWD/work/server/config"
export XDG_CACHE_HOME="$PWD/work/server/cache"
exec "${GODOT_BIN:-godot}" --headless --path godot --script res://network/server/server_main.gd -- "$@"
