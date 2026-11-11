"""The six chess pieces (light = royal, dark = skeletons), each as one lathe-based low-poly mesh.

Design brief: readable from straight above (distinct plan silhouettes) and from 45 degrees (distinct side silhouettes), ~0.7 m base
on a 1.0 m tile, pivot at the base centre on y = 0, facing Godot +Z (Blender -Y):
  pawn    round kettle-helm over a collar (concentric rings from above)
  knight  horse head lofted from a side profile with mane ridge and ears (the only asymmetric piece: an elongated plan)
  bishop  elliptical mitre with a dark slit and a finial ball (squashed plan, diagonal slit)
  rook    octagonal tower with a crenellated parapet (8-corner blocks; the notched ring is unmistakable from above)
  queen   bowl crown with 8 spikes around a jewel (sunburst plan)
  king    crown with 4 fleurons and a 3D cross (a "+" in plan view)
Every base has a trim ring (gold / bone) and, at LOD0, 12 studs of the detail colour (sapphire / crimson) so that it reads from above.
Light and dark share the geometry and differ only in materials (see `materials_for`).
"""
from __future__ import annotations

import math

from .. import materials, runtime
from . import common
from .common import WB

ROLES = ["pawn", "knight", "bishop", "rook", "queen", "king"]
BASE_RADIUS = {"pawn": 0.31, "knight": 0.34, "bishop": 0.34, "rook": 0.35, "queen": 0.36, "king": 0.36}
HEIGHT = {"pawn": 0.70, "knight": 1.0, "bishop": 1.04, "rook": 0.85, "queen": 1.19, "king": 1.31}   # design heights (m)
SEGS = {0: 24, 1: 12}


def materials_for(side: str) -> dict:
    g = materials.get_material
    if side == "light":
        return {
            "body": g("Piece_Light_Marble", (0.84, 0.80, 0.70), "marble_light", roughness=0.42, metallic=0.0, uv_m=0.6, seed=31, tex_size=256),
            "trim": g("Piece_Light_Gold", (0.86, 0.63, 0.20), None, metallic=0.9, roughness=0.32),
            "detail": g("Piece_Light_Sapphire", (0.03, 0.09, 0.34), None, metallic=0.1, roughness=0.3,
                        emission=(0.03, 0.09, 0.40), emission_strength=0.35),
            "shade": g("Piece_Light_Recess", (0.10, 0.09, 0.08), None, metallic=0.0, roughness=0.9),
        }
    return {
        "body": g("Piece_Dark_Basalt", (0.125, 0.12, 0.135), "basalt", roughness=0.5, metallic=0.1, uv_m=0.6, seed=32, tex_size=256),
        "trim": g("Piece_Dark_Bone", (0.68, 0.62, 0.50), None, metallic=0.35, roughness=0.5),
        "detail": g("Piece_Dark_Crimson", (0.30, 0.02, 0.07), None, metallic=0.1, roughness=0.35,
                    emission=(0.5, 0.03, 0.08), emission_strength=0.4),
        "shade": g("Piece_Dark_Recess", (0.012, 0.012, 0.014), None, metallic=0.0, roughness=0.9),
    }


def _base(b: WB, role: str, lod: int):
    R = BASE_RADIUS[role]
    segs = SEGS[lod]
    prof = [(0, 0), (R, 0, "body"), (R, 0.035, "body"), (R - 0.014, 0.055, "trim"), (R - 0.014, 0.098, "trim"),
            (R - 0.05, 0.118, "trim"), (R - 0.085, 0.118, "trim"), (R - 0.095, 0.132, "body"), (R - 0.11, 0.15, "body")]
    if lod == 0:   # studs of the detail colour on the rim ring
        for k in range(12):
            a = 2 * math.pi * k / 12
            r = R - 0.067
            b.b("detail", (r * math.cos(a), r * math.sin(a), 0.128), (0.034, 0.034, 0.02), rot=(0, 0, math.degrees(a)))
    return prof   # ends at (R - 0.11, 0.15): the piece continues the same profile


def _pawn(b, lod, segs):
    prof = _base(b, "pawn", lod)
    prof += [(0.17, 0.19), (0.135, 0.26), (0.115, 0.34), (0.12, 0.38), (0.165, 0.385, "trim"), (0.17, 0.42, "trim"),
            (0.125, 0.44, "trim"), (0.20, 0.45, "trim"), (0.23, 0.455, "trim"), (0.23, 0.48, "trim"), (0.15, 0.495, "body"),
            (0.175, 0.52), (0.17, 0.56), (0.14, 0.60), (0.09, 0.635), (0.035, 0.65), (0, 0.655)]
    b.lathe("body", prof, segs)
    b.sph("trim", (0, 0, 0.668), 0.034, segs=8, rings=4)


def _knight(b, lod, segs):
    prof = _base(b, "knight", lod)
    prof += [(0.20, 0.20), (0.18, 0.30), (0.18, 0.345), (0.215, 0.35, "trim"), (0.215, 0.385, "trim"),
            (0.185, 0.40, "body"), (0, 0.40)]
    b.lathe("body", prof, segs)
    neck = [(-0.16, 0.38), (0.12, 0.38), (0.16, 0.55), (0.10, 0.78), (-0.12, 0.82), (-0.17, 0.60)]
    b.loft("body", neck, [0.30, 0.30, 0.20, 0.18, 0.20, 0.24])
    head = [(0.08, 0.68), (0.22, 0.62), (0.40, 0.64), (0.40, 0.74), (0.16, 0.90), (0.00, 0.92), (-0.04, 0.80)]
    b.loft("body", head, [0.17, 0.17, 0.12, 0.12, 0.15, 0.20, 0.20])
    n = 5 if lod == 0 else 3
    for i in range(n):   # mane ridge along the back of the neck
        t = i / max(1, n - 1)
        f, z = -0.175 + 0.07 * t, 0.50 + 0.38 * t
        b.b("trim", (0, -f, z), (0.05, 0.07, 0.12 if lod == 0 else 0.19), rot=(-14, 0, 0))
    if lod == 0:
        for sx in (-1, 1):
            b.cone_up("body", (sx * 0.06, -0.0, 0.90), 0.045, 0.10, segs=4)      # ears
            b.b("shade", (sx * 0.092, -0.15, 0.80), (0.02, 0.05, 0.04))           # eyes
            b.b("shade", (sx * 0.035, -0.40, 0.69), (0.03, 0.02, 0.025))          # nostrils
        b.b("trim", (0, -0.32, 0.69), (0.125, 0.03, 0.03))                          # noseband
        b.b("trim", (0, -0.12, 0.74), (0.20, 0.03, 0.03))                           # brow band


def _bishop(b, lod, segs):
    prof = _base(b, "bishop", lod)
    prof += [(0.19, 0.20), (0.15, 0.30), (0.125, 0.42), (0.13, 0.47), (0.18, 0.475, "trim"),
            (0.18, 0.51, "trim"), (0.14, 0.53, "body"), (0, 0.53)]
    b.lathe("body", prof, segs)
    mitre = [(0, 0.52), (0.14, 0.53), (0.20, 0.58), (0.225, 0.67), (0.205, 0.77), (0.14, 0.87), (0.07, 0.94), (0, 0.98)]
    b.lathe("body", mitre, segs, scale=(1.0, 0.70, 1.0))
    b.sph("trim", (0, 0, 1.0), 0.04, segs=8, rings=4)
    b.b("shade", (0, -0.148, 0.77), (0.028, 0.05, 0.34), rot=(0, 30, 0))                  # the mitre slit (diagonal on the front face)
    b.b("trim", (0, -0.12, 0.60), (0.30, 0.04, 0.03))                                      # lappet band


def _rook(b, lod, segs):
    prof = _base(b, "rook", lod)
    b.lathe("body", prof + [(0.0, 0.15)], segs)
    prof = [(0, 0.12), (0.26, 0.12), (0.255, 0.16), (0.235, 0.50), (0.245, 0.53, "body"), (0.31, 0.57, "trim"), (0.31, 0.68, "trim"),
            (0.28, 0.70, "trim"), (0.20, 0.70, "trim"), (0.195, 0.64, "shade"), (0, 0.64, "shade")]
    b.lathe("body", prof, 8, phase=22.5)
    for k in range(8):   # merlons on the octagon corners; crenels sit on the flats
        a = math.radians(22.5 + 45 * k)
        r = 0.262
        b.b("body", (r * math.cos(a), r * math.sin(a), 0.775), (0.15, 0.075, 0.15), rot=(0, 0, math.degrees(a) + 90))
    b.b("shade", (0, -0.239, 0.36), (0.04, 0.03, 0.14))                                   # arrow slit
    if lod == 0:
        b.b("shade", (-0.17, -0.17, 0.34), (0.04, 0.03, 0.12), rot=(0, 0, 45))
        b.b("shade", (0.17, -0.17, 0.34), (0.04, 0.03, 0.12), rot=(0, 0, -45))




def _queen(b, lod, segs):
    prof = _base(b, "queen", lod)
    prof += [(0.20, 0.20), (0.15, 0.30), (0.125, 0.42), (0.135, 0.50), (0.19, 0.505, "trim"),
            (0.19, 0.54, "trim"), (0.14, 0.56, "body"), (0.17, 0.62), (0.21, 0.72), (0.245, 0.84), (0.265, 0.93),
            (0.27, 0.95, "trim"), (0.27, 0.98, "trim"), (0.235, 0.985, "trim"), (0.225, 0.93, "body"), (0, 0.90, "body")]
    b.lathe("body", prof, segs)
    n = 8
    for k in range(n):
        a = 2 * math.pi * (k + 0.5) / n
        b.cone_up("trim", (0.245 * math.cos(a), 0.245 * math.sin(a), 0.98), 0.036, 0.20 if lod == 0 else 0.18, segs=4 if lod else 6)
        if lod == 0:
            b.sph("detail", (0.245 * math.cos(a), 0.245 * math.sin(a), 1.19), 0.02, segs=6, rings=3)
    b.sph("detail", (0, 0, 0.99), 0.07, segs=10 if lod == 0 else 8, rings=6 if lod == 0 else 4)


def _king(b, lod, segs):
    prof = _base(b, "king", lod)
    prof += [(0.20, 0.20), (0.155, 0.30), (0.13, 0.42), (0.14, 0.50), (0.20, 0.505, "trim"),
            (0.20, 0.54, "trim"), (0.145, 0.56, "body"), (0.18, 0.64), (0.23, 0.76), (0.26, 0.88), (0.27, 0.94),
            (0.28, 0.955, "trim"), (0.28, 0.99, "trim"), (0.24, 0.995, "trim"), (0.23, 0.94, "body"), (0, 0.90, "body")]
    b.lathe("body", prof, segs)
    for k in range(4):
        a = 2 * math.pi * k / 4
        b.cone_up("trim", (0.255 * math.cos(a), 0.255 * math.sin(a), 0.99), 0.05, 0.15, segs=4)
    b.sph("trim", (0, 0, 1.03), 0.075, segs=10 if lod == 0 else 8, rings=6 if lod == 0 else 4)
    b.b("trim", (0, 0, 1.22), (0.07, 0.07, 0.22))
    b.b("trim", (0, 0, 1.255), (0.25, 0.07, 0.07))        # arm along x
    b.b("trim", (0, 0, 1.255), (0.07, 0.25, 0.07))        # arm along y -> a "+" from above
    b.b("detail", (0, -0.04, 1.255), (0.05, 0.02, 0.05))   # gem on the cross face


BUILD = {"pawn": _pawn, "knight": _knight, "bishop": _bishop, "rook": _rook, "queen": _queen, "king": _king}


def build_piece(role: str, side: str, lod: int, out_dir) -> dict:
    runtime.reset_scene()
    mats = materials_for(side)
    b = WB(f"Piece_{role.capitalize()}_{side.capitalize()}_Mesh", mats)
    BUILD[role](b, lod, SEGS[lod])
    root = common.empty(f"Piece_{role.capitalize()}_{side.capitalize()}", size=0.1)
    mesh = common.mesh_object(b, parent=root)
    mesh.name = f"Piece_{role.capitalize()}_{side.capitalize()}_Mesh"
    suffix = "_lod1" if lod else ""
    path = out_dir / f"{role}_{side}{suffix}.glb"
    st = common.export_scene(path)
    st["file"] = path.name
    return st


def build_all(out_dir) -> dict:
    out = {}
    for role in ROLES:
        for side in ("light", "dark"):
            for lod in (0, 1):
                st = build_piece(role, side, lod, out_dir)
                out[f"{role}_{side}{'_lod1' if lod else ''}"] = st
                runtime.log(f"piece {st['file']}: {st['tris']} tris, h={st['bounds_max'][1]:.2f}")
    return out
