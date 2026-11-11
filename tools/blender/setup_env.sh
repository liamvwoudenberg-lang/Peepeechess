#!/usr/bin/env bash
# Creates an isolated Python 3.11 environment with Blender-as-a-module (bpy 4.3.0) and runs the build.
#   tools/blender/setup_env.sh [VENV_DIR]     -> sets up (default .venv-blender, git-ignored by name below)
#   VENV_DIR/bin/python tools/blender/build_all.py [--only pawn,knight|arena] [--no-lods]
# A plain `blender --background --python tools/blender/build_all.py -- ...` (Blender 4.3.x) also works.
# numpy MUST be 1.26.x: pip would otherwise pick numpy 2.x, which Blender 4.3's compiled modules reject.
set -euo pipefail
VENV="${1:-.venv-blender}"
python3.11 -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade pip
"$VENV/bin/python" -m pip install -r "$(dirname "$0")/requirements.txt"
"$VENV/bin/python" -I -c "import bpy; print('bpy', bpy.app.version_string)"
