"""Low-poly modeling toolkit on bmesh.

All coordinates are armature/world space in metres (Z up, character faces -Y, left = +X, feet at
z=0). Parts are added to ONE bmesh per MeshBuilder and rigidly weighted to a bone (or skinned
along a chain), so a whole character body is a single skinned mesh with a handful of material
slots. Props (weapons, shields) are separate meshes attached to socket bones.

Part helpers return nothing; call `build()` once at the end.
"""
from __future__ import annotations

import math

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

from .runtime import link, make_active
from .skeleton import ALL_BONES, mirror_name

SHARP_ANGLE = math.radians(38.0)


def _xf(center, rot=(0, 0, 0), scale=(1, 1, 1)) -> Matrix:
    m = Matrix.Translation(Vector(center)) @ Euler([math.radians(a) for a in rot], "XYZ").to_matrix().to_4x4()
    return m @ Matrix.Diagonal((*scale, 1.0))


class MeshBuilder:
    def __init__(self, name: str, materials: list, bone_names=ALL_BONES, skinned: bool = True):
        self.name = name
        self.materials = materials
        self.bm = bmesh.new()
        self.skinned = skinned
        self.group_index = {b: i for i, b in enumerate(bone_names)}
        self.deform = self.bm.verts.layers.deform.verify() if skinned else None
        self.mat_slot = {m.name: i for i, m in enumerate(materials)}
        self._parts = 0

    # ---- bookkeeping -------------------------------------------------------------------------
    def _slot(self, mat) -> int:
        key = mat if isinstance(mat, str) else mat.name
        return self.mat_slot[key]

    def _commit(self, before_faces, verts, bone, mat, weights=None) -> None:
        slot = self._slot(mat)
        for f in self.bm.faces:
            if f not in before_faces:
                f.material_index = slot
        for v in verts:
            if not v.is_valid:
                continue
            if self.skinned:
                w = weights(v.co) if weights else {bone: 1.0}
                for b, value in w.items():
                    v[self.deform][self.group_index[b]] = value
        self._parts += 1

    def _mirror_parts(self, mirror, fn, bone, center, rot, **kw):
        fn(bone, center=center, rot=rot, **kw)
        if mirror:
            c = (-center[0], center[1], center[2])
            r = (rot[0], -rot[1], -rot[2])
            kw2 = dict(kw)
            kw2["_mirrored"] = True
            fn(mirror_name(bone), center=c, rot=r, **kw2)

    # ---- primitives --------------------------------------------------------------------------
    def box(self, bone, mat, center, size, rot=(0, 0, 0), bevel=0.0, mirror=False, weights=None, _mirrored=False):
        if mirror and not _mirrored:
            return self._mirror_parts(True, lambda b, **k: self.box(b, mat, size=size, bevel=bevel, weights=weights, **k),
                                      bone, center, rot)
        before = set(self.bm.faces)
        res = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = res["verts"]
        bmesh.ops.transform(self.bm, matrix=_xf(center, rot, size), verts=verts)
        if bevel > 0.0:
            edges = list({e for v in verts for e in v.link_edges})
            out = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=1, affect="EDGES")
            verts = list({v for v in out["verts"]} | set(verts))
        self._commit(before, [v for v in verts if v.is_valid], bone, mat, weights)

    def cyl(self, bone, mat, center, r1, r2, height, rot=(0, 0, 0), segs=8, caps=True, mirror=False,
            weights=None, _mirrored=False):
        if mirror and not _mirrored:
            return self._mirror_parts(True, lambda b, **k: self.cyl(b, mat, r1=r1, r2=r2, height=height, segs=segs,
                                                                    caps=caps, weights=weights, **k), bone, center, rot)
        before = set(self.bm.faces)
        res = bmesh.ops.create_cone(self.bm, cap_ends=caps, cap_tris=False, segments=segs,
                                    radius1=r1, radius2=r2, depth=height)
        bmesh.ops.transform(self.bm, matrix=_xf(center, rot), verts=res["verts"])
        self._commit(before, res["verts"], bone, mat, weights)

    def cone(self, bone, mat, center, radius, height, rot=(0, 0, 0), segs=8, mirror=False, weights=None):
        self.cyl(bone, mat, center, radius, 0.0, height, rot, segs, True, mirror, weights)

    def sphere(self, bone, mat, center, radii, rot=(0, 0, 0), segs=10, rings=6, mirror=False, weights=None,
               _mirrored=False):
        if mirror and not _mirrored:
            return self._mirror_parts(True, lambda b, **k: self.sphere(b, mat, radii=radii, segs=segs, rings=rings,
                                                                       weights=weights, **k), bone, center, rot)
        before = set(self.bm.faces)
        res = bmesh.ops.create_uvsphere(self.bm, u_segments=segs, v_segments=rings, radius=1.0)
        bmesh.ops.transform(self.bm, matrix=_xf(center, rot, radii), verts=res["verts"])
        self._commit(before, res["verts"], bone, mat, weights)

    def prism(self, bone, mat, center, outline, depth, rot=(0, 0, 0), mirror=False, weights=None, _mirrored=False):
        """Extrudes a convex 2D outline [(x, y), ...] (local XY, centred) `depth` along local Z."""
        if mirror and not _mirrored:
            return self._mirror_parts(True, lambda b, **k: self.prism(b, mat, outline=outline, depth=depth,
                                                                      weights=weights, **k), bone, center, rot)
        before = set(self.bm.faces)
        z = depth * 0.5
        top = [self.bm.verts.new((x, y, z)) for x, y in outline]
        bot = [self.bm.verts.new((x, y, -z)) for x, y in outline]
        n = len(outline)
        self.bm.faces.new(top)
        self.bm.faces.new(list(reversed(bot)))
        for i in range(n):
            j = (i + 1) % n
            self.bm.faces.new((top[i], bot[i], bot[j], top[j]))
        verts = top + bot
        bmesh.ops.transform(self.bm, matrix=_xf(center, rot), verts=verts)
        bmesh.ops.recalc_face_normals(self.bm, faces=[f for f in self.bm.faces if f not in before])
        self._commit(before, verts, bone, mat, weights)

    def shell(self, bone, mat, center, radius, arc_deg, length, thickness=0.02, rot=(0, 0, 0), segs=6,
              mirror=False, weights=None, _mirrored=False):
        """Open curved plate (pauldron, greave, bracer): an arc of `arc_deg` about local Z, `length`
        long, centred on local +Y (the outside faces +Y)."""
        if mirror and not _mirrored:
            return self._mirror_parts(True, lambda b, **k: self.shell(b, mat, radius=radius, arc_deg=arc_deg,
                                                                      length=length, thickness=thickness, segs=segs,
                                                                      weights=weights, **k), bone, center, rot)
        before = set(self.bm.faces)
        half = math.radians(arc_deg) * 0.5
        rings = []
        for r in (radius, radius - thickness):
            row_top, row_bot = [], []
            for i in range(segs + 1):
                a = -half + 2 * half * i / segs
                x, y = math.sin(a) * r, math.cos(a) * r
                row_top.append(self.bm.verts.new((x, y, length * 0.5)))
                row_bot.append(self.bm.verts.new((x, y, -length * 0.5)))
            rings.append((row_top, row_bot))
        (ot, ob), (it, ib) = rings
        for i in range(segs):
            self.bm.faces.new((ot[i], ot[i + 1], ob[i + 1], ob[i]))
            self.bm.faces.new((it[i + 1], it[i], ib[i], ib[i + 1]))
            self.bm.faces.new((ot[i + 1], ot[i], it[i], it[i + 1]))
            self.bm.faces.new((ob[i], ob[i + 1], ib[i + 1], ib[i]))
        for a_, b_ in ((0, ot[0]), ):
            pass
        self.bm.faces.new((ot[0], ob[0], ib[0], it[0]))
        self.bm.faces.new((ob[segs], ot[segs], it[segs], ib[segs]))
        verts = ot + ob + it + ib
        bmesh.ops.transform(self.bm, matrix=_xf(center, rot), verts=verts)
        self._commit(before, verts, bone, mat, weights)

    def ring_loft(self, mat, rings, segs, weight_fn, caps=(True, True)):
        """Lofts closed rings. `rings` = [(center, axis_x, axis_y), ...] where axis vectors carry
        the radii. `weight_fn(co) -> {bone: weight}` skins each vertex."""
        before = set(self.bm.faces)
        grid = []
        for c, ax, ay in rings:
            grid.append([self.bm.verts.new(Vector(c) + ax * math.cos(2 * math.pi * k / segs)
                                           + ay * math.sin(2 * math.pi * k / segs)) for k in range(segs)])
        for i in range(len(grid) - 1):
            for k in range(segs):
                k2 = (k + 1) % segs
                self.bm.faces.new((grid[i][k], grid[i][k2], grid[i + 1][k2], grid[i + 1][k]))
        if caps[0]:
            self.bm.faces.new(list(reversed(grid[0])))
        if caps[1]:
            self.bm.faces.new(grid[-1])
        verts = [v for row in grid for v in row]
        bmesh.ops.recalc_face_normals(self.bm, faces=[f for f in self.bm.faces if f not in before])
        self._commit(before, verts, None, mat, weight_fn)

    def tube(self, mat, chain, radii, segs=8, rings_per_segment=3, squash=1.0):
        """Skinned tapered tube through a chain [(bone, point), ...]; `radii` has one value per point.
        Segment k (point k -> k+1) belongs to chain[k].bone and blends toward its neighbours near joints.
        The last point's bone only owns the cap region."""
        pts = [Vector(p) for _, p in chain]
        bones = [b for b, _ in chain]
        rings, owners = [], []
        for k in range(len(pts) - 1):
            direction = (pts[k + 1] - pts[k])
            length = direction.length
            d = direction.normalized()
            ref = Vector((0, 1, 0)) if abs(d.y) < 0.9 else Vector((1, 0, 0))
            ax = d.cross(ref).normalized()
            ay = d.cross(ax).normalized()
            steps = rings_per_segment
            for s in range(steps + (1 if k == len(pts) - 2 else 0)):
                t = s / steps
                c = pts[k] + direction * t
                r = radii[k] + (radii[k + 1] - radii[k]) * t
                rings.append((c, ax * r, ay * r * squash))
                owners.append((k, t))
        index_of = {}

        def weight_fn(co):
            # nearest ring decides the weights
            best, bi = 1e9, 0
            for i, (c, _, _) in enumerate(rings):
                dd = (co - c).length_squared
                if dd < best:
                    best, bi = dd, i
            k, t = owners[bi]
            w = {bones[k]: 1.0}
            if t > 0.75 and k + 1 < len(bones) - 1:
                blend = 0.5 * (t - 0.75) / 0.25
                w = {bones[k]: 1.0 - blend, bones[k + 1]: blend}
            elif t < 0.25 and k > 0:
                blend = 0.5 * (0.25 - t) / 0.25
                w = {bones[k]: 1.0 - blend, bones[k - 1]: blend}
            return w

        self.ring_loft(mat, rings, segs, weight_fn)

    # ---- finishing ---------------------------------------------------------------------------
    def build(self, armature=None):
        bm = self.bm
        # Box-projected UVs, scaled by each material's tile size.
        uv = bm.loops.layers.uv.verify()
        for f in bm.faces:
            n = f.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            tile = float(self.materials[f.material_index].get("uv_m", 0.5))
            for loop in f.loops:
                co = loop.vert.co
                u, v = {0: (co.y, co.z), 1: (co.x, co.z), 2: (co.x, co.y)}[axis]
                loop[uv].uv = (u / tile, v / tile)
        for e in bm.edges:
            if len(e.link_faces) == 2:
                e.smooth = e.calc_face_angle(0.0) < SHARP_ANGLE
        for f in bm.faces:
            f.smooth = True
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        for m in self.materials:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        link(obj)
        if self.skinned and armature is not None:
            for bone in self.group_index:
                obj.vertex_groups.new(name=bone)
            obj.parent = armature
            mod = obj.modifiers.new("Armature", "ARMATURE")
            mod.object = armature
        return obj


def attach_to_bone(obj, armature, bone_name: str) -> None:
    """Parents a prop to a socket bone without moving it (Blender parents to the bone TAIL, so the
    parent inverse cancels that offset)."""
    bone = armature.data.bones[bone_name]
    world = obj.matrix_world.copy()
    obj.parent = armature
    obj.parent_type = "BONE"
    obj.parent_bone = bone_name
    parent_matrix = armature.matrix_world @ bone.matrix_local @ Matrix.Translation((0.0, bone.length, 0.0))
    obj.matrix_parent_inverse = parent_matrix.inverted()
    obj.matrix_world = world


def triangles(obj) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)
