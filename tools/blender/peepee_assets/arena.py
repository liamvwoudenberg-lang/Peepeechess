"""Medieval dark-fantasy combat arena "stone-v1" (visuals matching godot/combat/arenas/stone_arena.gd).

Collision contract the visuals must respect (Godot coords; Blender y = -Godot z):
  * floor top at height 0; flat disc.
  * circular wall, INNER face at radius 7.1 (24 segments), height 3.0, thickness 0.6.
  * four pillars radius 0.55, height 3.5, centred at (+-3.4, +-3.4).
  * fighters' centres never exceed 6.72 (wall minus body), so anything protruding from the inner wall
    face is kept to <= 0.06 m (banners, plaques, door, chains) or sits above head height.

Output: one STRUCTURE mesh (floor, wall, merlons, pillars, piers) and one PROPS mesh (decor), each
merged by material. build(out_dir) writes stone_arena.glb (LOD0), stone_arena_lod1.glb (mobile),
stone_arena_lights.json (Godot-space light/fog suggestions) and returns manifest stats.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector

from . import export, materials, modeling, runtime

WALL_R = 7.1
WALL_SEGS = 24
WALL_H = 3.0
WALL_T = 0.6
PILLAR_R = 0.55
PILLAR_H = 3.5
PILLAR_XY = [(3.4, 3.4), (-3.4, 3.4), (3.4, -3.4), (-3.4, -3.4)]  # symmetric: Godot (x,z) == Blender (x,-y)


def g2b(x, z, h=0.0):
    """Godot ground position (x, z) -> Blender (x, y=-z, z=h)."""
    return (x, -z, h)


def _materials():
    g = materials.get_material
    return {
        "floor": g("Arena_FloorStone", (0.30, 0.285, 0.275), "stone_floor", metallic=0.0, roughness=0.92, uv_m=2.0, seed=11),
        "wall": g("Arena_WallStone", (0.30, 0.285, 0.30), "stone_wall", roughness=0.95, uv_m=2.0, seed=12),
        "pillar": g("Arena_PillarStone", (0.36, 0.34, 0.36), "stone_wall", roughness=0.9, uv_m=1.6, seed=13),
        "rubble": g("Arena_Rubble", (0.18, 0.17, 0.17), "stone_wall", roughness=1.0, uv_m=0.8, seed=14),
        "statue": g("Arena_Statue", (0.38, 0.38, 0.36), "stone_floor", roughness=0.85, uv_m=1.2, seed=15),
        "iron": g("Arena_Iron", (0.36, 0.28, 0.24), "steel", metallic=0.6, roughness=0.65, uv_m=0.6, seed=16),
        "wood": g("Arena_Wood", (0.40, 0.27, 0.15), "wood", roughness=0.85, uv_m=0.8, seed=17),
        "gold": g("Arena_Gold", (0.42, 0.27, 0.06), None, metallic=0.85, roughness=0.45, emission=(0.5, 0.3, 0.05), emission_strength=0.6),
        "flame": g("Arena_Flame", (1.0, 0.45, 0.12), None, roughness=0.5, emission=(1.0, 0.5, 0.12), emission_strength=1.2),
        "coal": g("Arena_Coal", (0.5, 0.12, 0.05), None, roughness=0.6, emission=(0.9, 0.25, 0.08), emission_strength=1.5),
        "bannerA": g("Arena_BannerA", (0.55, 0.42, 0.18), None, roughness=1.0),
        "bannerB": g("Arena_BannerB", (0.16, 0.03, 0.2), None, roughness=1.0),
        "bone": g("Arena_Bone", (0.6, 0.55, 0.42), None, roughness=0.8),
        "dark": g("Arena_Dark", (0.03, 0.028, 0.025), None, roughness=1.0),
    }


# LOD1 collapses rarely-seen materials into common ones (fewer draw calls).
LOD1_ALIAS = {"pillar": "wall", "rubble": "wall", "statue": "wall", "coal": "flame", "dark": "iron", "bone": "wall"}


class Arena:
    def __init__(self, lod: int):
        self.lod = lod
        self.hi = lod == 0
        self.mats = _materials()
        slots = list(self.mats.values())
        self.structure = modeling.MeshBuilder("Arena_Structure", slots, bone_names=[], skinned=False)
        self.props = modeling.MeshBuilder("Arena_Props", slots, bone_names=[], skinned=False)
        self.lights = []

    def m(self, key):
        return self.mats[LOD1_ALIAS.get(key, key) if not self.hi else key]

    def seg(self, n_hi, n_lo=None):
        return n_hi if self.hi else (n_lo or max(6, n_hi // 2))

    # ---- helpers ----------------------------------------------------------------------------
    def torus(self, b, mat, radius, minor_w, minor_h, z, rings=48, segs=4):
        """Flat inlaid ring (closed loop of small cross-sections)."""
        ring_list = []
        n = rings if self.hi else 24
        for i in range(n + 1):
            a = 2 * math.pi * (i % n) / n
            c = Vector((math.sin(a) * radius, -math.cos(a) * radius, z))
            radial = Vector((math.sin(a), -math.cos(a), 0))
            ring_list.append((c, radial * minor_w, Vector((0, 0, 1)) * minor_h))
        b.ring_loft(mat, ring_list, segs, None, caps=(False, False))

    # ---- structure --------------------------------------------------------------------------
    def floor(self):
        b = self.structure
        b.cyl(None, self.m("floor"), (0, 0, -0.2), 7.5, 7.5, 0.4, segs=self.seg(48, 24))
        # outer courtyard ground so nothing floats over a void
        b.cyl(None, self.m("rubble"), (0, 0, -0.45), 16.0, 16.0, 0.1, segs=self.seg(32, 16))

    def wall(self):
        b = self.structure
        L = 2.0 * WALL_R * math.tan(math.pi / WALL_SEGS) * 1.1
        for i in range(WALL_SEGS):
            a = 2 * math.pi * i / WALL_SEGS
            c = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R + WALL_T / 2)
            b.box(None, self.m("wall"), (c.x, c.y, WALL_H / 2), (L, WALL_T, WALL_H), rot=(0, 0, math.degrees(a)))
            if i % 2 == 0:  # merlons
                b.box(None, self.m("wall"), (c.x, c.y, WALL_H + 0.25), (L * 0.5, WALL_T, 0.5), rot=(0, 0, math.degrees(a)),
                      bevel=0.015 if self.hi else 0.0)
            if self.hi:  # outer cornice course
                o = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R + WALL_T + 0.07)
                b.box(None, self.m("wall"), (o.x, o.y, WALL_H - 0.12), (L, 0.16, 0.24), rot=(0, 0, math.degrees(a)))
        # buttress piers outside the wall (visible above the parapet from inside)
        for k in range(8):
            a = 2 * math.pi * (k + 0.5) / 8
            c = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R + WALL_T + 0.45)
            b.box(None, self.m("wall"), (c.x, c.y, 1.9), (0.8, 0.8, 3.8), rot=(0, 0, math.degrees(a)), bevel=0.02 if self.hi else 0.0)
            b.cone(None, self.m("wall"), (c.x, c.y, 4.1), 0.62, 0.7, rot=(0, 0, 45), segs=4)

    def pillars(self):
        b = self.structure
        for px, pz in PILLAR_XY:
            x, y, _ = g2b(px, pz)
            n = self.seg(16, 10)
            b.cyl(None, self.m("pillar"), (x, y, 0.15), 0.75, 0.7, 0.3, segs=n)             # base
            b.cyl(None, self.m("pillar"), (x, y, PILLAR_H / 2), PILLAR_R, PILLAR_R, PILLAR_H, segs=n)  # shaft == collision
            b.cyl(None, self.m("pillar"), (x, y, 3.3), 0.62, 0.69, 0.22, segs=n)           # capital
            b.box(None, self.m("pillar"), (x, y, 3.55), (1.5, 1.5, 0.16), rot=(0, 0, 45 if self.hi else 0))  # abacus
            if self.hi:
                b.cyl(None, self.m("pillar"), (x, y, 3.05), 0.6, 0.6, 0.08, segs=n)         # neck ring

    # ---- props ------------------------------------------------------------------------------
    def floor_decor(self):
        b = self.props
        gold = self.m("gold")
        self.torus(b, gold, 6.4, 0.075, 0.006, 0.004)
        if self.hi:
            self.torus(b, gold, 6.15, 0.025, 0.005, 0.004)
        for gz in (-2.6, 2.6):  # spawn marks
            x, y, _ = g2b(0, gz)
            self.torus_at(b, gold, x, y, 0.45, 0.04)
        # central drain
        b.cyl(None, self.m("dark"), (0, 0, 0.003), 0.38, 0.38, 0.006, segs=self.seg(20, 10))
        if self.hi:
            for k in range(4):
                b.box(None, self.m("iron"), (0, 0, 0.008), (0.7, 0.045, 0.01), rot=(0, 0, 45 * k + 22.5))
            # floor cracks
            for cx, cy, ang, ln in [(2.0, 1.2, 30, 1.4), (-1.5, -2.0, 110, 1.1), (4.5, -1.0, 70, 1.6), (-4.0, 2.5, 150, 1.3),
                                    (0.8, -4.3, 10, 0.9), (-2.2, 4.4, 95, 1.2)]:
                b.box(None, self.m("dark"), (cx, cy, 0.003), (ln, 0.018, 0.005), rot=(0, 0, ang))
                b.box(None, self.m("dark"), (cx + 0.4 * math.cos(math.radians(ang + 40)), cy + 0.4 * math.sin(math.radians(ang + 40)), 0.003),
                      (ln * 0.5, 0.012, 0.005), rot=(0, 0, ang + 40))

    def torus_at(self, b, mat, cx, cy, radius, w):
        n = 20 if self.hi else 12
        rl = []
        for i in range(n + 1):
            a = 2 * math.pi * (i % n) / n
            c = Vector((cx + math.sin(a) * radius, cy - math.cos(a) * radius, 0.004))
            rl.append((c, Vector((math.sin(a), -math.cos(a), 0)) * w, Vector((0, 0, 1)) * 0.005))
        b.ring_loft(mat, rl, 4, None, caps=(False, False))

    def torches(self):
        b = self.props
        for px, pz in PILLAR_XY:
            x, y, _ = g2b(px, pz)
            P = Vector((x, y, 0))
            inward = (-P).normalized()
            mount = P + inward * (PILLAR_R + 0.08)
            mz = 2.2
            b.cyl(None, self.m("iron"), (mount.x, mount.y, mz), 0.045, 0.035, 0.45, segs=6)
            b.cyl(None, self.m("iron"), (mount.x, mount.y, mz + 0.24), 0.11, 0.07, 0.12, segs=self.seg(8, 6))
            b.sphere(None, self.m("flame"), (mount.x, mount.y, mz + 0.4), (0.1, 0.1, 0.15), segs=self.seg(8, 6), rings=self.seg(6, 4))
            # iron strap to the pillar
            if self.hi:
                b.box(None, self.m("iron"), (P.x + inward.x * 0.5, P.y + inward.y * 0.5, mz - 0.1), (0.05, 0.05, 0.05), rot=(0, 0, 0))
            self.lights.append({"kind": "torch", "blender": (mount.x, mount.y, mz + 0.5), "color": (1.0, 0.66, 0.34), "energy": 1.9, "range": 8.0})

    def braziers(self):
        b = self.props
        for k in range(4):
            a = math.radians(45 + 90 * k)
            c = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R + WALL_T / 2)
            z0 = WALL_H
            for t in range(3):
                ta = a + 2 * math.pi * t / 3
                b.cyl(None, self.m("iron"), (c.x + math.cos(ta) * 0.17, c.y + math.sin(ta) * 0.17, z0 + 0.17), 0.025, 0.02, 0.34, segs=5,
                      rot=(math.degrees(math.sin(ta)) * 0.15, -math.degrees(math.cos(ta)) * 0.15, 0))
            b.cyl(None, self.m("iron"), (c.x, c.y, z0 + 0.4), 0.2, 0.3, 0.2, segs=self.seg(10, 6))
            b.sphere(None, self.m("coal"), (c.x, c.y, z0 + 0.5), (0.24, 0.24, 0.1), segs=self.seg(8, 6), rings=4)
            b.cone(None, self.m("flame"), (c.x, c.y, z0 + 0.72), 0.16, 0.45, segs=self.seg(8, 5))
            self.lights.append({"kind": "brazier", "blender": (c.x, c.y, z0 + 0.9), "color": (1.0, 0.55, 0.25), "energy": 2.4, "range": 10.0})

    def banners(self):
        b = self.props
        outline = [(-0.55, 1.0), (0.55, 1.0), (0.55, -0.7), (0.0, -1.1), (-0.55, -0.7)]
        for i in range(4):
            a = 2 * math.pi * i / 4 + math.pi / 4 + math.radians(22.5)   # between braziers
            r = WALL_R - 0.045
            c = Vector((math.sin(a), -math.cos(a), 0)) * r
            mat = self.m("bannerA" if i % 2 == 0 else "bannerB")
            b.prism(None, mat, (c.x, c.y, 1.75), outline, 0.025, rot=(90, 0, math.degrees(a)))
            b.cyl(None, self.m("wood"), (c.x, c.y, 2.78), 0.02, 0.02, 1.25, rot=(0, 90, math.degrees(a)), segs=6)  # rod (tangent)
            b.sphere(None, self.m("gold"), (c.x, c.y, 1.75), (0.14, 0.2, 0.012), rot=(90, 0, math.degrees(a)), segs=8, rings=4)  # sigil

    def gate_and_alcove(self):
        b = self.props
        # Gate on Godot +x (angle 90 deg): dark door flush with the wall face, stone archivolt, iron bands.
        def at(a_deg, depth):
            a = math.radians(a_deg)
            return Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R - depth), a
        arch = [(-0.8, 0.0), (0.8, 0.0), (0.8, 1.6)] + [(0.8 * math.cos(t), 1.6 + 0.8 * math.sin(t)) for t in
                                                         [math.radians(d) for d in (30, 60, 90, 120, 150)]] + [(-0.8, 1.6)]
        # convex by construction (rectangle + semicircle); drop the duplicate (0.8,1.6)/(−0.8,1.6) corners' non-convexity
        arch = [(-0.8, 0.0), (0.8, 0.0), (0.8, 1.6)] + [(0.8 * math.cos(math.radians(d)), 1.6 + 0.8 * math.sin(math.radians(d))) for d in (30, 60, 90, 120, 150)] + [(-0.8, 1.6)]
        c, a = at(90, 0.03)
        b.prism(None, self.m("dark"), (c.x, c.y, 0.0), arch, 0.03, rot=(90, 0, math.degrees(a)))
        c2, _ = at(90, 0.055)
        for zz in (0.5, 1.2, 1.9):
            b.box(None, self.m("iron"), (c2.x, c2.y, zz), (1.5, 0.025, 0.08), rot=(0, 0, math.degrees(a)))
        # archivolt voussoirs (protrude <= 0.06 inward)
        n = 11 if self.hi else 7
        for k in range(n):
            t = math.pi * k / (n - 1)
            local_x, local_z = 0.95 * math.cos(t), 1.6 + 0.95 * math.sin(t)
            tang = Vector((math.cos(a), math.sin(a), 0))
            p = at(90, 0.02)[0] + tang * local_x
            b.box(None, self.m("wall"), (p.x, p.y, local_z), (0.22, 0.08, 0.24), rot=(0, math.degrees(0), math.degrees(a)))
        for sx in (-0.95, 0.95):
            p = at(90, 0.02)[0] + Vector((math.cos(a), math.sin(a), 0)) * sx
            b.box(None, self.m("wall"), (p.x, p.y, 0.8), (0.22, 0.08, 1.6), rot=(0, 0, math.degrees(a)))
        # Niche opposite the gate (Godot -x): dark recess panel with a small candle.
        c3, a3 = at(270, 0.03)
        niche = [(-0.45, 0.0), (0.45, 0.0), (0.45, 1.0)] + [(0.45 * math.cos(math.radians(d)), 1.0 + 0.45 * math.sin(math.radians(d))) for d in (45, 90, 135)] + [(-0.45, 1.0)]
        b.prism(None, self.m("dark"), (c3.x, c3.y, 1.6), niche, 0.03, rot=(90, 0, math.degrees(a3)))
        cand = at(270, 0.08)[0]
        b.box(None, self.m("wood"), (cand.x, cand.y, 2.1), (0.3, 0.16, 0.04), rot=(0, 0, math.degrees(a3)))   # shelf above head height
        b.cyl(None, self.m("bone"), (cand.x, cand.y, 2.2), 0.03, 0.03, 0.16, segs=6)
        b.sphere(None, self.m("flame"), (cand.x, cand.y, 2.32), (0.025, 0.025, 0.045), segs=6, rings=4)
        self.lights.append({"kind": "candle", "blender": (cand.x, cand.y, 2.4), "color": (1.0, 0.7, 0.4), "energy": 0.5, "range": 3.0})

    def wall_decor(self):
        b = self.props
        # Weapon racks: flat plaques on the wall face (<= 0.06 protrusion) with weapon silhouettes.
        for deg in (150, 330):
            a = math.radians(deg)
            c = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R - 0.025)
            tang = Vector((math.cos(a), math.sin(a), 0))
            b.box(None, self.m("wood"), (c.x, c.y, 1.6), (1.5, 0.05, 0.12), rot=(0, 0, math.degrees(a)))
            b.box(None, self.m("wood"), (c.x, c.y, 1.0), (1.5, 0.05, 0.12), rot=(0, 0, math.degrees(a)))
            for k, ln in enumerate((1.8, 1.5, 1.9, 1.3)):
                p = c + tang * (-0.55 + 0.37 * k) + Vector((math.sin(a), -math.cos(a), 0)) * 0.012
                b.cyl(None, self.m("iron" if k % 2 else "wood"), (p.x, p.y, 1.3), 0.015, 0.015, ln, segs=5, rot=(0, 0, 0))
                b.cone(None, self.m("iron"), (p.x, p.y, 1.3 + ln / 2 + 0.1), 0.028, 0.2, segs=5)
        # Hanging chains from the parapet.
        if self.hi:
            for deg in (30, 70, 110, 200, 250, 290, 340):
                a = math.radians(deg)
                c = Vector((math.sin(a), -math.cos(a), 0)) * (WALL_R - 0.03)
                for j in range(9):
                    b.box(None, self.m("iron"), (c.x, c.y, 2.95 - 0.1 * j), (0.05, 0.016, 0.09), rot=(0, 0, math.degrees(a) + (90 if j % 2 else 0)))
        # Skulls & bones at the wall base, rubble (all <= 0.12 m tall).
        for deg, rr in [(20, 6.95), (115, 6.9), (200, 6.97), (300, 6.93)]:
            a = math.radians(deg)
            c = Vector((math.sin(a), -math.cos(a), 0)) * rr
            b.sphere(None, self.m("bone"), (c.x, c.y, 0.07), (0.09, 0.1, 0.08), segs=self.seg(8, 6), rings=self.seg(5, 4))
            b.box(None, self.m("bone"), (c.x, c.y, 0.03), (0.07, 0.07, 0.05))
            for q in range(2):
                b.cyl(None, self.m("bone"), (c.x + 0.18 + 0.1 * q, c.y - 0.08 * q, 0.025), 0.018, 0.018, 0.3, rot=(0, 90, 40 + 70 * q), segs=5)
        for deg, rr, s in [(60, 6.9, 0.15), (95, 6.95, 0.12), (165, 6.88, 0.18), (240, 6.93, 0.14), (275, 6.9, 0.16), (320, 6.96, 0.13)]:
            a = math.radians(deg)
            c = Vector((math.sin(a), -math.cos(a), 0)) * rr
            b.box(None, self.m("rubble"), (c.x, c.y, 0.05), (s, s * 0.8, 0.1), rot=(8, 6, deg * 3))
            b.box(None, self.m("rubble"), (c.x + 0.2, c.y + 0.1, 0.03), (s * 0.6, s * 0.6, 0.06), rot=(0, 0, deg * 5))

    def statue(self):
        """Broken statue on a plinth OUTSIDE the wall, visible above the parapet."""
        b = self.props
        for deg in (135, 315):
            a = math.radians(deg)
            c = Vector((math.sin(a), -math.cos(a), 0)) * 9.6
            b.box(None, self.m("statue"), (c.x, c.y, 0.9), (1.3, 1.3, 1.8), rot=(0, 0, deg), bevel=0.03 if self.hi else 0.0)
            b.cyl(None, self.m("statue"), (c.x, c.y, 2.35), 0.3, 0.38, 1.1, segs=self.seg(10, 6))           # legs / robe
            b.box(None, self.m("statue"), (c.x, c.y, 3.1), (0.72, 0.4, 0.6), rot=(0, 0, deg), bevel=0.02 if self.hi else 0.0)  # torso
            b.cyl(None, self.m("statue"), (c.x + 0.45, c.y, 3.0), 0.1, 0.09, 0.7, rot=(0, 25, deg), segs=6)   # one arm
            b.box(None, self.m("rubble"), (c.x + 0.9, c.y - 0.5, 0.12), (0.4, 0.35, 0.24), rot=(5, 10, 40))   # fallen head block
            b.sphere(None, self.m("statue"), (c.x + 1.2, c.y - 0.2, 0.2), (0.2, 0.22, 0.24), segs=self.seg(8, 6), rings=self.seg(5, 4))

    def build_all(self):
        self.floor()
        self.wall()
        self.pillars()
        self.floor_decor()
        self.torches()
        self.braziers()
        self.banners()
        self.gate_and_alcove()
        self.wall_decor()
        if self.hi or True:
            self.statue()
        s = self.structure.build()
        p = self.props.build()
        return s, p


def _measure(structure) -> dict:
    """Collision-relevant measurements straight from the generated structure mesh (Blender space)."""
    verts = [structure.matrix_world @ v.co for v in structure.data.vertices]
    seg = 2 * math.pi / WALL_SEGS
    inner = []
    for v in verts:
        r = math.hypot(v.x, v.y)
        if r > 6.9 and 2.95 < v.z < 3.55:
            ang = math.atan2(v.x, -v.y) % (2 * math.pi)   # Godot-style angle
            i = round(ang / seg)
            n = Vector((math.sin(i * seg), -math.cos(i * seg), 0))
            d = v.x * n.x + v.y * n.y
            if d > 6.9:
                inner.append(d)
    pillars = []
    for px, pz in PILLAR_XY:
        x, y, _ = g2b(px, pz)
        rr = [math.hypot(v.x - x, v.y - y) for v in verts if math.hypot(v.x - x, v.y - y) < 0.58]
        pillars.append({"godot_xz": [px, pz], "shaft_radius": round(max(rr), 4)})
    floor_top = max(v.z for v in verts if math.hypot(v.x, v.y) < 6.0 and v.z < 0.1)
    return {"wall_inner_radius": round(min(inner), 4), "pillars": pillars, "floor_top": round(floor_top, 4)}


def _godot_lights(lights):
    out = []
    for l in lights:
        x, y, z = l["blender"]
        out.append({"kind": l["kind"], "position": [round(x, 3), round(z, 3), round(-y, 3)], "color": list(l["color"]),
                    "energy": l["energy"], "range": l["range"]})
    return out


def build(out_dir: Path) -> dict:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    stats = {"collision_contract": {"wall_inner_radius": WALL_R, "wall_height": WALL_H, "pillar_radius": PILLAR_R,
                                    "pillar_height": PILLAR_H, "pillars": PILLAR_XY, "floor_top": 0.0}}
    lights = []
    for lod, name in ((0, "stone_arena.glb"), (1, "stone_arena_lod1.glb")):
        runtime.reset_scene()
        arena = Arena(lod)
        structure, props = arena.build_all()
        tris = modeling.triangles(structure) + modeling.triangles(props)
        used = set()
        for o in (structure, props):
            used |= {o.data.materials[p.material_index].name for p in o.data.polygons}
        size = export.export_glb(out_dir / name, [structure, props], animations=False)
        stats[f"lod{lod}"] = {"file": name, "tris": tris, "bytes": size, "materials_used": sorted(used),
                              "objects": 2, "draw_calls_max": sum(
                                  len({o.data.materials[p.material_index].name for p in o.data.polygons}) for o in (structure, props))}
        if lod == 0:
            stats["measured"] = _measure(structure)
            lights = _godot_lights(arena.lights)
        runtime.log(f"arena lod{lod}: {tris} tris, {size} bytes")
    sidecar = {
        "note": "Godot-space (x, y, z). Instantiate OmniLight3D per entry; fog/ambient are suggestions matching stone_arena_visuals.gd.",
        "lights": lights,
        "directional": {"rotation_degrees": [-55.0, -35.0, 0.0], "color": [0.72, 0.78, 1.0], "energy": 0.75, "shadows": True},
        "ambient": {"color": [0.34, 0.36, 0.48], "energy": 0.85},
        "fog": {"color": [0.07, 0.08, 0.13], "density": 0.012},
        "background": [0.025, 0.03, 0.05],
        "flicker": {"amplitude": 0.16, "hz": 11.0},
    }
    (out_dir / "stone_arena_lights.json").write_text(json.dumps(sidecar, indent=2) + "\n")
    stats["lights"] = len(lights)
    return stats
