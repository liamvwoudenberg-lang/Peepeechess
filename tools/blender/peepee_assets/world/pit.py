"""Pit set: trapdoor, shaft rim + tileable shaft wall, ladder (2 m segment, top section, assembled 10 m), chamber ceiling cap, light cone.

Godot-space contracts (the world presentation code relies on these names and numbers):
  trapdoor_{light,dark}.glb   root Trapdoor_<Side>; pivots `hinge_left` (x = -0.4975) and `hinge_right` (x = +0.4975) at y = 0, z = 0 (the tile
                              centre plane), each holding one leaf mesh (`leaf_left`, `leaf_right`). Rotate hinge_left.rotation.z by -90 deg and
                              hinge_right.rotation.z by +90 deg to swing the free edges DOWN into the shaft (about -100 / +100 for a full slam).
  shaft_rim.glb               square liner, opening 1.0 x 1.0, outer 1.4 (lip 1.48), top at y = -0.04 (just under the tile layer), 0.5 m tall.
  shaft_wall_segment.glb      1.0 m tall square tube (inner 1.0, outer 1.4), origin at the bottom-centre, tileable vertically (course joints every 0.25).
  ladder_*.glb                ladder plane at z = 0 (rung centres), rails at x = +-0.28, climbing direction +Y; the climber stands at z = -0.42 (its
                              origin) facing +Z. Rung centres are at y = (j + 0.5) * 0.25. Anchors: rung_NN, hand_L_NN / hand_R_NN (x = +-0.17, rung
                              centre), foot_L_NN / foot_R_NN (x = +-0.15, rung top). L = +X (the climber's left).
  chamber_ceiling.glb         16 x 16 m slab (top at y = 0, 0.6 thick) with a 1 x 1 hole at the centre and a 0.15 m collar around it.
  light_cone.glb              open square frustum, unit height, top (y = 0) 1.0 x 1.0, bottom (y = -1) 2.8 x 2.8, vertex alpha 0.55 -> 0.
"""
from __future__ import annotations

import math

import bpy

from .. import materials, runtime
from ..animation import spec
from . import board, common
from .common import WB, empty, gb, mesh_object, reparent

HINGE_X = 0.4975
RUNG = spec.RUNG_SPACING          # 0.25
RAIL_X = 0.28
HAND_X = 0.17
FOOT_X = 0.15
RUNG_R = 0.022
SEG_H = 2.0


def pit_materials() -> dict:
    g = materials.get_material
    return {
        "wood": g("Pit_Wood", (0.30, 0.20, 0.12), "wood", roughness=0.85, uv_m=0.8, seed=51),
        "iron": g("Pit_Iron", (0.20, 0.19, 0.20), "steel", metallic=0.7, roughness=0.6, uv_m=0.5, seed=52),
        "stone": g("Pit_Stone", (0.27, 0.255, 0.25), "stone_wall", roughness=0.92, uv_m=2.0, seed=53),
        "dark": g("Pit_DarkStone", (0.10, 0.095, 0.10), "stone_wall", roughness=0.95, uv_m=2.0, seed=54),
        "ladder_wood": g("Ladder_Wood", (0.34, 0.22, 0.12), "wood", roughness=0.85, uv_m=0.8, seed=55),
    }


# ---------------------------------------------------------------------------------------------------------------------------
def build_trapdoor(side: str, out_dir) -> dict:
    runtime.reset_scene()
    tiles = board.tile_materials()
    p = pit_materials()
    top = tiles[side]
    mats = {"top": top, "wood": p["wood"], "iron": p["iron"]}
    root = empty(f"Trapdoor_{side.capitalize()}", size=0.2)
    for name, sx in (("left", -1), ("right", 1)):
        pivot = empty(f"hinge_{name}", gb(sx * HINGE_X, 0, 0), parent=root, size=0.08)
        b = WB(f"leaf_{name}_mesh", mats)
        cx = sx * (HINGE_X / 2 + 0.0012)          # leaf spans [hinge, 0.0025 from the centre line]
        w = HINGE_X - 0.0025
        cx = sx * (0.0025 + w / 2)
        b.box(None, "top", gb(cx, 0.02, 0), (w, 0.995, 0.04), bevel=0.004)                       # tile-top slab, y in [0, 0.04]
        for z in (-0.33, 0.0, 0.33):                                                              # wood planks under it, y in [-0.04, 0]
            b.box(None, "wood", gb(cx, -0.02, z), (w - 0.01, 0.31, 0.04), bevel=0.003)
        for z in (-0.28, 0.28):                                                                   # iron cross straps on the underside
            b.box(None, "iron", gb(cx, -0.046, z), (w - 0.03, 0.06, 0.014))
        for z in (-0.22, 0.22):
            b.box(None, "iron", gb(sx * (HINGE_X - 0.11), -0.046, z), (0.22, 0.07, 0.014))          # hinge plates
            b.cyl(None, "iron", gb(sx * (HINGE_X - 0.02), 0.0, z), 0.02, 0.02, 0.34, rot=(90, 0, 0), segs=8)   # hinge barrel (inside the tile footprint)
        b.b("iron", gb(cx, -0.046, 0), (0.05, 0.4, 0.012), rot=(0, 0, 90))
        obj = mesh_object(b, parent=pivot)
        obj.name = f"leaf_{name}"
    st = common.export_scene(out_dir / f"trapdoor_{side}.glb")
    st["file"] = f"trapdoor_{side}.glb"
    return st


# (half-side, y) profiles, traversed bottom-inner -> out -> up -> in -> down the inner wall
def _grooves(ys):
    """Inner-wall points (descending y) with a V-groove at each joint height in `ys`."""
    pts = []
    for y in sorted(ys, reverse=True):
        pts += [(0.5, y + 0.012), (0.512, y), (0.5, y - 0.012)]
    return pts


def build_rim(out_dir) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    b = WB("shaft_rim_mesh", {"stone": p["stone"]})
    y_top, y_bot = -0.04, -0.54
    prof = [(0.512, y_bot), (0.70, y_bot, "stone"), (0.70, -0.14), (0.74, -0.12), (0.74, y_top), (0.52, y_top), (0.5, y_top - 0.02)]
    prof += _grooves([y_bot + 0.25])
    prof += [(0.5, y_bot + 0.012), (0.512, y_bot)]
    b.square_lathe("stone", prof)
    root = empty("ShaftRim", size=0.2)
    mesh_object(b, parent=root)
    st = common.export_scene(out_dir / "shaft_rim.glb")
    st["file"] = "shaft_rim.glb"
    return st


def build_wall_segment(out_dir) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    b = WB("shaft_wall_segment_mesh", {"stone": p["stone"]})
    prof = [(0.512, 0.0), (0.70, 0.0, "stone"), (0.70, 1.0), (0.512, 1.0), (0.5, 0.988)]
    prof += _grooves([0.75, 0.5, 0.25])
    prof += [(0.5, 0.012), (0.512, 0.0)]
    b.square_lathe("stone", prof)
    root = empty("ShaftWallSegment", size=0.2)
    mesh_object(b, parent=root)
    st = common.export_scene(out_dir / "shaft_wall_segment.glb")
    st["file"] = "shaft_wall_segment.glb"
    return st


# ---------------------------------------------------------------------------------------------------------------------------
def _ladder_geometry(b: WB, y0: float, y1: float, rung_ys, bands, hooks=False):
    rail_h = y1 - y0
    for sx in (-1, 1):
        b.box(None, "wood", gb(sx * RAIL_X, (y0 + y1) / 2, 0), (0.06, 0.07, rail_h), bevel=0.006)
        for yb in bands:
            b.box(None, "iron", gb(sx * RAIL_X, yb, 0), (0.07, 0.08, 0.05))
    for y in rung_ys:
        b.cyl(None, "wood", gb(0, y, 0), RUNG_R, RUNG_R, 2 * RAIL_X + 0.03, rot=(0, 90, 0), segs=8)
        for sx in (-1, 1):
            b.box(None, "iron", gb(sx * (RAIL_X + 0.033), y, 0), (0.012, 0.045, 0.045))   # rung end cap / peg
    if hooks:
        for sx in (-1, 1):
            b.box(None, "iron", gb(sx * RAIL_X, -0.16, 0.0415), (0.07, 0.012, 0.36))             # strap down the back of the rail
            b.box(None, "iron", gb(sx * RAIL_X, 0.046, 0.2), (0.07, 0.31, 0.012))                # arm over the rim
            b.box(None, "iron", gb(sx * RAIL_X, 0.02, 0.35), (0.07, 0.012, 0.06))                # down-turned tip
        b.box(None, "iron", gb(0, 0.046, 0.35), (2 * RAIL_X, 0.02, 0.016))                       # cross bar tying the two hooks


def _anchors(root, ys, label):
    """rung_/hand_L_/hand_R_/foot_L_/foot_R_ anchors for each rung height in `ys` (bottom to top)."""
    names = []
    for i, y in enumerate(ys):
        tag = label(i)
        for nm, x, dy in (("rung", 0.0, 0.0), ("hand_L", HAND_X, 0.0), ("hand_R", -HAND_X, 0.0),
                          ("foot_L", FOOT_X, RUNG_R), ("foot_R", -FOOT_X, RUNG_R)):
            empty(f"{nm}_{tag}", gb(x, y + dy, 0), parent=root, size=0.04)
            names.append(f"{nm}_{tag}")
    return names


def build_ladder_segment(out_dir) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    mats = {"wood": p["ladder_wood"], "iron": p["iron"]}
    b = WB("ladder_segment_mesh", mats)
    ys = [RUNG / 2 + RUNG * k for k in range(8)]
    _ladder_geometry(b, 0.0, SEG_H, ys, [0.5, 1.5])
    root = empty("LadderSegment2m", size=0.2)
    mesh_object(b, parent=root)
    _anchors(root, ys, lambda i: f"{i:02d}")
    st = common.export_scene(out_dir / "ladder_segment_2m.glb")
    st["file"] = "ladder_segment_2m.glb"
    return st


TOP_Y0, TOP_Y1 = -1.0, 0.75
TOP_RUNGS = [-0.875 + RUNG * k for k in range(7)]          # -0.875 ... 0.625 (grid: (j + 0.5) * 0.25)


def build_ladder_top(out_dir) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    b = WB("ladder_top_mesh", {"wood": p["ladder_wood"], "iron": p["iron"]})
    _ladder_geometry(b, TOP_Y0, TOP_Y1, TOP_RUNGS, [-0.5], hooks=True)
    root = empty("LadderTop", size=0.2)
    mesh_object(b, parent=root)
    _anchors(root, TOP_RUNGS, lambda i: f"{i:02d}")
    st = common.export_scene(out_dir / "ladder_top.glb")
    st["file"] = "ladder_top.glb"
    return st


def build_ladder_full(out_dir, segments=4) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    b = WB("ladder_full_mesh", {"wood": p["ladder_wood"], "iron": p["iron"]})
    y_bottom = TOP_Y0 - segments * SEG_H
    rung_ys = []
    for s in range(segments):
        y0 = y_bottom + s * SEG_H
        for k in range(8):
            rung_ys.append(y0 + RUNG / 2 + RUNG * k)
    rung_ys += TOP_RUNGS
    _ladder_geometry(b, y_bottom, TOP_Y1, rung_ys, [y_bottom + 0.5 + SEG_H * s + o for s in range(segments) for o in (0.0, 1.0)] + [-0.5], hooks=True)
    root = empty("LadderFull10m", size=0.2)
    mesh_object(b, parent=root)
    _anchors(root, rung_ys, lambda i: f"{i:03d}")
    st = common.export_scene(out_dir / "ladder_full_10m.glb")
    st["file"] = "ladder_full_10m.glb"
    st["rungs"] = len(rung_ys)
    st["length_m"] = TOP_Y1 - y_bottom
    return st


# ---------------------------------------------------------------------------------------------------------------------------
def build_ceiling(out_dir) -> dict:
    runtime.reset_scene()
    p = pit_materials()
    b = WB("chamber_ceiling_mesh", {"dark": p["dark"], "stone": p["stone"]})
    prof = [(0.5, -0.6), (8.0, -0.6, "dark"), (8.0, 0.0), (0.76, 0.0), (0.70, 0.15, "stone"), (0.56, 0.15), (0.5, 0.10), (0.5, -0.6, "dark")]
    b.square_lathe("dark", prof)
    for z in (-4.0, 0.0, 4.0):                                      # underside beams (coffer ribs)
        b.box(None, "stone", gb(0, -0.77, z), (16.0, 0.34, 0.35), bevel=0.01)
        b.box(None, "stone", gb(z, -0.77, 0), (0.34, 16.0, 0.35), bevel=0.01)
    root = empty("ChamberCeiling", size=0.3)
    mesh_object(b, parent=root)
    st = common.export_scene(out_dir / "chamber_ceiling.glb")
    st["file"] = "chamber_ceiling.glb"
    return st


def build_light_cone(out_dir) -> dict:
    import bmesh
    runtime.reset_scene()
    mat = bpy.data.materials.new("LightCone_Additive")
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    vc = nodes.new("ShaderNodeVertexColor")
    vc.layer_name = "Color"
    links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(vc.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Emission Color"].default_value = (1.0, 0.92, 0.7, 1.0)
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 1.0
    mat.blend_method = "BLEND"
    mat["note"] = "Godot: set blend_mode = Add, shading_mode = Unshaded (see godot/assets/world/materials/light_cone.tres)"
    bm = bmesh.new()
    top, bot = 0.5, 1.4
    ring_t = [bm.verts.new(gb(x, 0, z)) for x, z in ((-top, -top), (top, -top), (top, top), (-top, top))]
    ring_b = [bm.verts.new(gb(x, -1.0, z)) for x, z in ((-bot, -bot), (bot, -bot), (bot, bot), (-bot, bot))]
    faces = []
    for i in range(4):
        j = (i + 1) % 4
        faces.append(bm.faces.new((ring_t[i], ring_b[i], ring_b[j], ring_t[j])))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    layer = bm.loops.layers.color.new("Color")
    for f in bm.faces:
        for loop in f.loops:
            alpha = 0.55 if loop.vert in ring_t else 0.0
            loop[layer] = (1.0, 0.92, 0.7, alpha)
    mesh = bpy.data.meshes.new("light_cone_mesh")
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    obj = bpy.data.objects.new("light_cone_mesh", mesh)
    runtime.link(obj)
    root = empty("LightCone", size=0.2)
    reparent(obj, root)
    st = common.export_scene(out_dir / "light_cone.glb")
    st["file"] = "light_cone.glb"
    return st


LIGHT_CONE_TRES = '''[gd_resource type="StandardMaterial3D" format=3]

[resource]
resource_name = "LightCone_Additive"
transparency = 1
blend_mode = 1
cull_mode = 2
shading_mode = 0
vertex_color_use_as_albedo = true
albedo_color = Color(1, 0.92, 0.7, 1)
disable_receive_shadows = true
'''


def build_all(out_dir, root) -> dict:
    out = {}
    for side in ("light", "dark"):
        out[f"trapdoor_{side}"] = build_trapdoor(side, out_dir)
    out["shaft_rim"] = build_rim(out_dir)
    out["shaft_wall_segment"] = build_wall_segment(out_dir)
    out["ladder_segment_2m"] = build_ladder_segment(out_dir)
    out["ladder_top"] = build_ladder_top(out_dir)
    out["ladder_full_10m"] = build_ladder_full(out_dir)
    out["chamber_ceiling"] = build_ceiling(out_dir)
    out["light_cone"] = build_light_cone(out_dir)
    mat_dir = root / "materials"
    mat_dir.mkdir(parents=True, exist_ok=True)
    (mat_dir / "light_cone.tres").write_text(LIGHT_CONE_TRES)
    for k, v in out.items():
        runtime.log(f"pit {k}: {v['tris']} tris")
    return out
