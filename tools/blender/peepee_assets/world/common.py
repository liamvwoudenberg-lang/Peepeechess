"""Shared helpers for the world asset generators (chess pieces, board dressing, pit set).

Space: Blender is Z-up; the glTF exporter maps Blender (x, y, z) -> Godot (x, z, -y). The generators think in Blender terms but
every contract is stated in Godot terms: Godot +Y is up, Godot +Z is "forward" (Blender -Y, the direction a piece faces).
Units are metres; the board tile is 1.0 m, tile tops are at Godot y = +0.04 (tile boxes are 0.08 tall, centred on y = 0).
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from .. import export, materials, modeling, runtime, textures

WORLD_ROOT = runtime.REPO_ROOT / "godot" / "assets" / "world"
TILE = 1.0
TILE_TOP_Y = 0.04


def set_root(root: Path) -> Path:
    """Redirects every world output (GLBs, textures) under `root`; returns it."""
    global WORLD_ROOT
    WORLD_ROOT = Path(root).resolve()
    textures.TEXTURE_DIR = WORLD_ROOT / "textures"
    return WORLD_ROOT


def to_godot(v) -> tuple:
    return (round(v[0], 5), round(v[2], 5), round(-v[1], 5))


def gb(x, y, z):
    """Godot (x, y up, z) -> Blender coordinates."""
    return (x, -z, y)


class WB(modeling.MeshBuilder):
    """MeshBuilder (static, un-skinned) plus lathe / loft helpers. Material arguments are materials or names."""

    def __init__(self, name, mats):
        self.alias = dict(mats) if isinstance(mats, dict) else {}
        mats = list(mats.values()) if isinstance(mats, dict) else list(mats)
        super().__init__(name, mats, bone_names=[], skinned=False)

    def _slot(self, mat) -> int:
        if isinstance(mat, str) and mat in self.alias:
            mat = self.alias[mat]
        return super()._slot(mat)

    # profile = [(r, z) | (r, z, mat), ...]; the segment ending at a point uses that point's material (default `mat`).
    # Traverse it bottom-axis -> outward -> up -> inward (counter-clockwise in (r, z)) so normals face out.
    def lathe(self, mat, pts, segs=20, center=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), phase=0.0):
        bm = self.bm
        rings = []
        for p in pts:
            r, z = p[0], p[1]
            if r < 1e-6:
                rings.append([bm.verts.new((0.0, 0.0, z))])
            else:
                rings.append([bm.verts.new((r * math.cos(math.radians(phase) + 2 * math.pi * k / segs),
                                            r * math.sin(math.radians(phase) + 2 * math.pi * k / segs), z)) for k in range(segs)])
        new_faces = []
        for i in range(1, len(pts)):
            a, b = rings[i - 1], rings[i]
            slot = self._slot(pts[i][2] if len(pts[i]) > 2 else mat)
            if len(a) == 1 and len(b) == 1:
                continue
            for k in range(segs):
                k2 = (k + 1) % segs
                try:
                    if len(a) == 1:
                        f = bm.faces.new((a[0], b[k2], b[k]))
                    elif len(b) == 1:
                        f = bm.faces.new((a[k], a[k2], b[0]))
                    else:
                        f = bm.faces.new((a[k], a[k2], b[k2], b[k]))
                except ValueError:
                    continue
                f.material_index = slot
                new_faces.append(f)
        verts = [v for ring in rings for v in ring]
        bmesh.ops.remove_doubles(bm, verts=verts, dist=1e-5)      # welds the closing ring and the axis points
        bmesh.ops.transform(bm, matrix=modeling._xf(center, rot, scale), verts=[v for v in verts if v.is_valid])
        self._parts += 1

    def square_lathe(self, mat, pts, center=(0, 0, 0)):
        """Lathe with 4 segments turned into a square ring: profile x = HALF-side length (not circumradius)."""
        k = math.sqrt(2.0)
        self.lathe(mat, [((p[0] * k, p[1]) + tuple(p[2:])) for p in pts], segs=4, center=center, phase=45.0)

    def loft(self, mat, poly, widths, center=(0, 0, 0)):
        """Convex side-view polygon [(fwd, z), ...] (fwd = Godot +Z = Blender -Y) extruded along x with a width per vertex."""
        bm = self.bm
        before = set(bm.faces)
        left = [bm.verts.new((center[0] - w / 2, center[1] - f, center[2] + z)) for (f, z), w in zip(poly, widths)]
        right = [bm.verts.new((center[0] + w / 2, center[1] - f, center[2] + z)) for (f, z), w in zip(poly, widths)]
        n = len(poly)
        bm.faces.new(right)
        bm.faces.new(list(reversed(left)))
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((left[i], right[i], right[j], left[j]))
        new = [f for f in bm.faces if f not in before]
        bmesh.ops.recalc_face_normals(bm, faces=new)
        slot = self._slot(mat)
        for f in new:
            f.material_index = slot
        self._parts += 1

    def b(self, mat, center, size, rot=(0, 0, 0), bevel=0.0):
        self.box(None, mat, center, size, rot, bevel)

    def cone_up(self, mat, base_center, radius, height, segs=6, rot=(0, 0, 0)):
        c = (base_center[0], base_center[1], base_center[2] + height / 2)
        self.cyl(None, mat, c, radius, 0.0, height, rot, segs, True)

    def sph(self, mat, center, r, segs=10, rings=6):
        self.sphere(None, mat, center, (r, r, r), segs=segs, rings=rings)


def empty(name, loc=(0, 0, 0), parent=None, size=0.05, rot=(0, 0, 0)):
    o = bpy.data.objects.new(name, None)
    o.empty_display_type = "ARROWS"
    o.empty_display_size = size
    o.location = loc
    o.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    runtime.link(o)
    if parent is not None:
        reparent(o, parent)
    return o


def reparent(obj, parent):
    """Parent keeping the object's current world transform."""
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_parent_inverse = parent.matrix_world.inverted()
    obj.matrix_world = world


def mesh_object(builder: WB, name=None, parent=None):
    obj = builder.build()
    if name:
        obj.name = name
        obj.data.name = name
    if parent is not None:
        reparent(obj, parent)
    return obj


def all_objects():
    return list(bpy.context.scene.objects)


def stats_for(objs) -> dict:
    tris, mats, lo, hi = 0, set(), Vector((1e9, 1e9, 1e9)), Vector((-1e9, -1e9, -1e9))
    seen = {}
    unique = 0
    for o in objs:
        if o.type != "MESH":
            continue
        tris += modeling.triangles(o)
        if o.data.name not in seen:
            unique += modeling.triangles(o)
        mats.update(m.name for m in o.data.materials if m)
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            for i in range(3):
                lo[i] = min(lo[i], w[i])
                hi[i] = max(hi[i], w[i])
        seen[o.data.name] = True
    return {"tris": tris, "tris_unique_meshes": unique, "materials": sorted(mats), "bounds_min": list(to_godot(lo)), "bounds_max": list(to_godot(hi))}


def export_scene(path: Path, objs=None) -> dict:
    objs = objs if objs is not None else all_objects()
    size = export.export_glb(path, objs, animations=False)
    st = stats_for(objs)
    st["bytes"] = size
    # Godot-space bounds: swap because of the Blender->Godot axis mapping (min/max already converted per axis with z negated)
    lo, hi = st["bounds_min"], st["bounds_max"]
    st["bounds_min"] = [lo[0], lo[1], min(lo[2], hi[2])]
    st["bounds_max"] = [hi[0], hi[1], max(lo[2], hi[2])]
    st["nodes"] = sorted(o.name for o in objs)
    return st


def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
