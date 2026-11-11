"""Driver for the world assets: writes <root>/{pieces,board,pit}/*.glb, textures, materials/*.tres and manifest/world_manifest.json."""
from __future__ import annotations

import json
from pathlib import Path

import bpy

from .. import runtime, textures
from ..animation import spec
from . import board, common, pieces, pit

SEED_NOTE = "texture seeds are fixed in the generators (Tile_Light 41, Tile_Dark 42, Piece_Light_Marble 31, Piece_Dark_Basalt 32, ...)"


def build(which, root=None):
    old_dir = textures.TEXTURE_DIR
    root = common.set_root(root or common.WORLD_ROOT)
    manifest_path = root / "manifest" / "world_manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    try:
        if "pieces" in which:
            runtime.log("building world pieces")
            manifest["pieces"] = pieces.build_all(root / "pieces")
            manifest["piece_design"] = {"base_radius_m": pieces.BASE_RADIUS, "height_m": pieces.HEIGHT}
        if "board" in which:
            runtime.log("building world board dressing")
            manifest["board"] = board.build_all(root / "board", root)
        if "pit" in which:
            runtime.log("building world pit set")
            manifest["pit"] = pit.build_all(root / "pit", root)
            manifest["ladder"] = {
                "rung_spacing_m": spec.RUNG_SPACING, "rail_x_m": pit.RAIL_X, "hand_x_m": pit.HAND_X, "foot_x_m": pit.FOOT_X,
                "rung_radius_m": pit.RUNG_R, "climber_origin_z_m": -spec.LADDER_PLANE_FWD,
                "rung_centre_rule": "y = (j + 0.5) * rung_spacing in the ladder frame; the climber origin is at y = n * rung_spacing at clip phase 0 and 0.5",
                "climb_clip_frames": spec.CLIMB_TICKS, "climb_speed_mps": round(spec.CLIMB_SPEED_MPS, 5),
                "segment_length_m": pit.SEG_H, "top_section_y": [pit.TOP_Y0, pit.TOP_Y1],
            }
            manifest["trapdoor"] = {"hinge_x_m": common.TILE / 2 - 0.0025, "open_rotation_deg": {"hinge_left_z": -90.0, "hinge_right_z": 90.0},
                                    "thickness_m": 0.08}
        manifest["generator"] = {"blender": bpy.app.version_string, "script": "tools/blender/build_all.py", "note": SEED_NOTE}
        manifest_path.parent.mkdir(parents=True, exist_ok=True)
        manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    finally:
        textures.TEXTURE_DIR = old_dir
    return manifest
