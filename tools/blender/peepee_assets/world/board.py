"""Board dressing: tile meshes + marble tile-top textures, the carved frame / plinth, corner posts and file/rank plaques.

Godot-space contract (does NOT change Codex's board numbers): tiles are 0.995 x 0.08 x 0.995 centred on y = 0 at (i - 3.5, 0, j - 3.5),
so the playing surface is x, z in [-4, 4] and tile tops are y = +0.04. The frame's inner edge sits at |x|, |z| = 4.0 and meets the tile
top level; the base slab (grout colour) fills the board volume below the tiles. Rank r is at z = r - 4.5 (rank 8 at +Z), file a..h at x = i - 3.5,
exactly Interaction.world_position().
"""
from __future__ import annotations

import math

import bmesh
import bpy

from .. import materials, runtime
from . import common
from .common import WB, empty, gb, mesh_object, reparent

PLAQUE_RADIUS = 4.39        # centre of the plaque field (distance from the board centre axis)
FILES = "abcdefgh"


def tile_materials() -> dict:
    g = materials.get_material
    return {
        "light": g("Tile_Light", (0.70, 0.66, 0.58), "marble_light", roughness=0.5, metallic=0.0, uv_m=1.0, seed=41, tex_size=512),
        "dark": g("Tile_Dark", (0.17, 0.22, 0.23), "marble_dark", roughness=0.5, metallic=0.0, uv_m=1.0, seed=42, tex_size=512),
    }


def frame_materials() -> dict:
    g = materials.get_material
    return {
        "stone": g("Frame_Stone", (0.30, 0.275, 0.26), "stone_wall", roughness=0.9, uv_m=2.0, seed=43),
        "gold": g("Frame_Gold", (0.80, 0.58, 0.18), None, metallic=0.9, roughness=0.4),
        "grout": g("Frame_Grout", (0.03, 0.03, 0.035), None, roughness=1.0),
    }


def build_tile(side: str, out_dir) -> dict:
    runtime.reset_scene()
    mats = tile_materials()
    b = WB(f"Tile_{side.capitalize()}_Mesh", [mats[side]])
    b.box(None, mats[side], gb(0, 0, 0), (0.995, 0.995, 0.08), bevel=0.006)
    root = empty(f"Tile_{side.capitalize()}", size=0.1)
    mesh_object(b, parent=root)
    st = common.export_scene(out_dir / f"tile_{side}.glb")
    st["file"] = f"tile_{side}.glb"
    return st


# (half-side, y) profile of the frame ring, traversed bottom-inner -> out -> up -> in -> down the inner wall (see WB.lathe)
FRAME_PROFILE = [
    (4.00, -0.60), (5.00, -0.60, "stone"), (5.00, -0.22), (5.10, -0.22), (5.10, -0.06), (5.02, 0.00),      # plinth skirt
    (4.96, 0.00), (4.96, 0.10), (4.90, 0.13), (4.80, 0.13), (4.76, 0.10), (4.76, 0.075),                      # outer bead
    (4.72, 0.075, "gold"), (4.66, 0.075, "gold"), (4.64, 0.10, "stone"),                                       # carved gold inlay channel
    (4.14, 0.10), (4.10, 0.10), (4.05, 0.085), (4.00, 0.05), (4.00, -0.60),                                    # plaque field, inner bevel, inner wall
]


def build_frame(out_dir) -> dict:
    runtime.reset_scene()
    m = frame_materials()
    b = WB("BoardFrame_Mesh", m)
    b.square_lathe("stone", FRAME_PROFILE)
    root = empty("BoardFrame", size=0.2)
    mesh_object(b, parent=root)
    # base slab (visible only through the 0.005 gaps between tiles): grout colour, top at y = 0
    s = WB("BoardBase_Mesh", m)
    s.box(None, "grout", gb(0, -0.30, 0), (8.02, 8.02, 0.60))
    mesh_object(s, parent=root)
    # corner posts: carved block, gold band, pyramid cap and finial
    for sx, sz, nm in ((1, 1, "SE"), (-1, 1, "SW"), (1, -1, "NE"), (-1, -1, "NW")):
        p = WB(f"CornerPost_{nm}_Mesh", m)
        c = (sx * 4.88, 0, sz * 4.88)
        p.box(None, "stone", gb(c[0], 0.11, c[2]), (0.44, 0.44, 0.22), bevel=0.02)
        p.box(None, "gold", gb(c[0], 0.235, c[2]), (0.47, 0.47, 0.03))
        p.box(None, "stone", gb(c[0], 0.30, c[2]), (0.38, 0.38, 0.10), bevel=0.015)
        p.cone_up("stone", gb(c[0], 0.35, c[2]), 0.30, 0.16, segs=4, rot=(0, 0, 45))
        p.sph("gold", gb(c[0], 0.53, c[2]), 0.045, segs=8, rings=4)
        mesh_object(p, parent=root)
    st = common.export_scene(out_dir / "board_frame.glb")
    st["file"] = "board_frame.glb"
    return st


def _glyph_mesh(ch: str):
    curve = bpy.data.curves.new(f"glyph_{ch}", "FONT")
    curve.body = ch
    curve.size = 0.27
    curve.extrude = 0.012
    curve.resolution_u = 2
    curve.align_x = "CENTER"
    curve.align_y = "CENTER"
    obj = bpy.data.objects.new(f"glyph_src_{ch}", curve)
    runtime.link(obj)
    mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    mesh.name = f"glyph_{ch}"
    bpy.data.objects.remove(obj)
    bpy.data.curves.remove(curve)
    return mesh


def build_plaques(out_dir) -> dict:
    runtime.reset_scene()
    g = materials.get_material
    slab_mat = g("Plaque_Stone", (0.16, 0.15, 0.15), "stone_floor", roughness=0.85, uv_m=1.0, seed=44)
    gold = g("Plaque_Gold", (0.86, 0.63, 0.20), None, metallic=0.9, roughness=0.32)
    sb = WB("plaque_slab", [slab_mat])
    sb.box(None, slab_mat, gb(0, 0.115, 0), (0.46, 0.34, 0.03), bevel=0.006)
    tmp = sb.build()
    slab_mesh = tmp.data
    bpy.data.objects.remove(tmp)
    glyphs = {ch: _glyph_mesh(ch) for ch in FILES + "12345678"}
    for m in glyphs.values():
        m.materials.append(gold)
    root = empty("BoardPlaques", size=0.2)

    def plaque(name, ch, x, z, slab_yaw, glyph_yaw):
        node = empty(name, gb(x, 0, z), parent=root)
        slab = bpy.data.objects.new(name + "_slab", slab_mesh)
        slab.location = gb(x, 0, z)
        slab.rotation_euler = (0, 0, math.radians(slab_yaw))
        runtime.link(slab)
        reparent(slab, node)
        glyph = bpy.data.objects.new(name + "_glyph", glyphs[ch])
        glyph.location = gb(x, 0.13, z)
        glyph.rotation_euler = (0, 0, math.radians(glyph_yaw))
        runtime.link(glyph)
        reparent(glyph, node)

    for i, f in enumerate(FILES):
        x = i - 3.5
        plaque(f"plaque_file_{f}_s", f, x, PLAQUE_RADIUS, 0.0, 0.0)          # near edge (+Z), upright for a camera on +Z
        plaque(f"plaque_file_{f}_n", f, x, -PLAQUE_RADIUS, 180.0, 180.0)     # far edge (-Z), upright for a camera on -Z
    for r in range(1, 9):
        z = r - 4.5
        # E/W plaques: the slab is turned 90 degrees (long side along z); the glyph stays upright for a +Z camera
        plaque(f"plaque_rank_{r}_w", str(r), -PLAQUE_RADIUS, z, 90.0, 0.0)
        plaque(f"plaque_rank_{r}_e", str(r), PLAQUE_RADIUS, z, 90.0, 0.0)
    st = common.export_scene(out_dir / "board_plaques.glb")
    st["file"] = "board_plaques.glb"
    return st


def tile_material_tres(side: str, rel_tex: str) -> str:
    return (f'[gd_resource type="StandardMaterial3D" load_steps=2 format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{rel_tex}" id="1_tex"]\n\n'
            f'[resource]\nresource_name = "Tile_{side.capitalize()}"\nalbedo_texture = ExtResource("1_tex")\n'
            f'roughness = 0.5\ntexture_filter = 5\n')


def build_all(out_dir, root) -> dict:
    out = {}
    for side in ("light", "dark"):
        out[f"tile_{side}"] = build_tile(side, out_dir)
        runtime.log(f"board tile_{side}: {out[f'tile_{side}']['tris']} tris")
    out["board_frame"] = build_frame(out_dir)
    out["board_plaques"] = build_plaques(out_dir)
    runtime.log(f"board frame {out['board_frame']['tris']} tris, plaques {out['board_plaques']['tris']} tris")
    mat_dir = root / "materials"
    mat_dir.mkdir(parents=True, exist_ok=True)
    for side in ("light", "dark"):
        (mat_dir / f"tile_{side}.tres").write_text(tile_material_tres(side, f"res://assets/world/textures/Tile_{side.capitalize()}.png"))
    return out
