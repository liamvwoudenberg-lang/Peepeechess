"""Runtime helpers shared by every generator script.

Works the same under `blender --background --python build_all.py -- ARGS` and when the
Blender-as-a-module wheel is used (`python build_all.py ARGS`).

Coordinate conventions (Blender -> glTF/Godot with the exporter's default +Y up):
  * Blender is Z-up. Characters stand on z=0, are centred on x=0 and FACE -Y.
  * glTF/Godot then see them facing +Z, which is the gameplay heading at yaw=0
    (CONTRACTS.md: heading = (sin(yaw), 0, cos(yaw))).
  * The character's LEFT is +X in both spaces.
  * Units are metres.
"""
from __future__ import annotations

import sys
import time
from pathlib import Path

import bpy

# tools/blender/peepee_assets/runtime.py -> repository root is three parents up.
REPO_ROOT = Path(__file__).resolve().parents[3]
ASSET_ROOT = REPO_ROOT / "godot" / "assets" / "combat"
FPS = 60  # one animation frame == one 60 Hz simulation tick

_T0 = time.time()


def script_args(argv=None):
    """Arguments after `--` (blender -P) or after the script name (python)."""
    argv = list(sys.argv if argv is None else argv)
    if "--" in argv:
        return argv[argv.index("--") + 1:]
    return argv[1:]


def log(message: str) -> None:
    print(f"[assets +{time.time() - _T0:6.1f}s] {message}", flush=True)


def reset_scene() -> None:
    """Empty scene, metric units, 60 fps. Nothing from earlier builds can leak into the next."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def link(obj, collection=None):
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def make_active(obj) -> None:
    for other in bpy.context.view_layer.objects:
        other.select_set(False)
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def triangle_count(obj) -> int:
    """Triangles after triangulation (what the GPU actually draws)."""
    mesh = obj.data
    return sum(len(p.vertices) - 2 for p in mesh.polygons)
