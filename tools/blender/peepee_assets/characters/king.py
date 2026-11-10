"""KING - royal defensive champion. Imposing plate with gold trim, crown-inspired visored great helm
(crown points ring the helm, small cross finial), fur-style collar, heavy cloak, royal longsword.

Weapon grip convention (for the animation worker): the sword extends FORWARD (-Y in Blender, +Z in
Godot) from the fist at WeaponSocket_R, flat faces left/right, edges up/down. Arm hanging -> blade
forward from the hip; arm raised forward 90 deg -> blade UP; use wrist pitch to line the blade with
the forearm for thrusts. Body = one skinned mesh (5 material slots); the sword is a separate prop.
"""
from __future__ import annotations

import math

from mathutils import Vector

from .. import materials
from ..modeling import MeshBuilder, attach_to_bone

NAME = "king"
PROPORTIONS = dict(scale=1.06, shoulder_width=1.15, hip_width=1.05)
# Schema: animation/library.py. The longsword extends forward (-Y) from the fist at rest.
STYLE = dict(grip="sword1", weapon_axis=(0.0, -1.0, 0.0),
             stance=0.25, arm_clear=0.7, swagger=0.85, power=1.1)

S = PROPORTIONS["scale"]
SW = PROPORTIONS["shoulder_width"]
HW = PROPORTIONS["hip_width"]


def _rot_z_to(direction) -> tuple:
    e = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler("XYZ")
    return tuple(math.degrees(a) for a in e)


def _zw(anchors):
    def fn(co):
        z = co.z
        if z >= anchors[0][1]:
            return {anchors[0][0]: 1.0}
        for (b0, z0), (b1, z1) in zip(anchors, anchors[1:]):
            if z >= z1:
                t = (z0 - z) / max(z0 - z1, 1e-6)
                return {b0: 1.0 - t, b1: t}
        return {anchors[-1][0]: 1.0}
    return fn


def _seg(mb, bone, mat, p0, p1, r0, r1, t0=0.0, t1=1.0, segs=10, caps=True):
    a, b = p0.lerp(p1, t0), p0.lerp(p1, t1)
    d = b - a
    ra, rb = r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1
    mb.cyl(bone, mat, tuple((a + b) * 0.5), ra, rb, d.length, _rot_z_to(d), segs, caps)


def _ring(z, rx, ry, cy=0.0):
    return (Vector((0, cy * S, z)), Vector((rx * S, 0, 0)), Vector((0, ry * S, 0)))


def build(arm, joints):
    J = lambda n: joints[n][0]
    T = lambda n: joints[n][1]

    steel = materials.get_material("King_Steel", (0.5, 0.5, 0.58), kind="steel", metallic=0.85, roughness=0.4, uv_m=0.6, seed=21)
    gold = materials.get_material("King_Gold", (0.86, 0.63, 0.2), kind="steel", metallic=0.9, roughness=0.3, uv_m=0.5, seed=22)
    fur = materials.get_material("King_Leather", (0.32, 0.22, 0.16), kind="leather", metallic=0.0, roughness=0.85, uv_m=0.35, seed=23)
    cloth = materials.get_material("King_Cloth", (0.16, 0.16, 0.3), kind="cloth", metallic=0.0, roughness=0.9, uv_m=0.4, seed=24)
    accent = materials.get_material("King_Accent", (0.13, 0.012, 0.04), metallic=0.1, roughness=0.7)
    mb = MeshBuilder("King_Body", [steel, gold, fur, cloth, accent])

    hz, sz, cz, uz, nz = (J(n).z for n in ("Hips", "Spine", "Chest", "UpperChest", "Neck"))
    mid = lambda n: (J(n).z + T(n).z) * 0.5
    torso_w = _zw([("UpperChest", mid("UpperChest")), ("Chest", mid("Chest")), ("Spine", mid("Spine")), ("Hips", mid("Hips"))])

    # ---- undersuit -----------------------------------------------------------------------------
    mb.ring_loft(cloth, [_ring(hz - 0.09 * S, .165 * HW, .115), _ring(hz, .18 * HW, .12), _ring(sz + 0.03 * S, .15 * HW, .105),
                         _ring(cz + 0.03 * S, .17, .115, -.008), _ring(uz + 0.02 * S, .2 * SW * 0.95, .125, -.012),
                         _ring(uz + 0.14 * S, .2 * SW * 0.95, .112, -.005), _ring(nz, .085, .075)], 10, torso_w)
    for side in ("Left", "Right"):
        mb.tube(cloth, [(f"{side}UpperArm", J(f"{side}UpperArm")), (f"{side}LowerArm", J(f"{side}LowerArm")),
                        (f"{side}Hand", J(f"{side}Hand")), (f"{side}Hand", T(f"{side}Hand"))],
                [0.062 * S, 0.05 * S, 0.04 * S, 0.036 * S], segs=10)
        mb.tube(cloth, [(f"{side}UpperLeg", J(f"{side}UpperLeg")), (f"{side}LowerLeg", J(f"{side}LowerLeg")),
                        (f"{side}Foot", J(f"{side}Foot"))], [0.105 * S * HW, 0.072 * S, 0.056 * S], segs=10)
    mb.tube(cloth, [("Neck", J("Neck")), ("Head", J("Head"))], [0.06 * S, 0.058 * S], segs=8, rings_per_segment=2)

    # ---- breastplate with gold ridge, faulds, belt --------------------------------------------
    mb.ring_loft(steel, [_ring(sz + 0.03 * S, .16 * HW, .118), _ring(cz + 0.0, .185, .132, -.008),
                         _ring(uz + 0.0, .218 * SW * 0.95, .15, -.016), _ring(uz + 0.125 * S, .215 * SW * 0.95, .135, -.01)],
                 10, torso_w, caps=(False, False))
    mb.ring_loft(gold, [_ring(uz + 0.12 * S, .222 * SW * 0.95, .14, -.01), _ring(uz + 0.15 * S, .222 * SW * 0.95, .14, -.01)], 10, torso_w, caps=(False, False))
    mb.box("Chest", gold, (0, -0.146 * S, cz + 0.07 * S), (0.028 * S, 0.02 * S, 0.3 * S), bevel=0.005)
    mb.prism("Chest", gold, (0, -0.152 * S, cz + 0.12 * S), [(0, .07), (.05, 0), (0, -.085), (-.05, 0)], 0.016 * S, rot=(90, 0, 0))
    mb.sphere("Chest", accent, (0, -0.158 * S, cz + 0.12 * S), (.018, .01, .022), segs=8, rings=4)
    for k in range(4):  # overlapping fauld lames
        z = sz + 0.02 * S - k * 0.05 * S
        r = (.168 + 0.012 * k) * HW
        mb.ring_loft(steel if k % 2 == 0 else gold, [_ring(z, r, .122 + 0.01 * k), _ring(z - 0.045 * S, r + 0.01, .128 + 0.01 * k)], 10, torso_w, caps=(False, False))
    mb.cyl("Hips", fur, (0, 0, hz + 0.05 * S), 0.18 * S * HW, 0.18 * S * HW, 0.05 * S, segs=12)
    mb.box("Hips", gold, (0, -0.18 * S, hz + 0.05 * S), (0.075 * S, 0.02 * S, 0.065 * S), bevel=0.005)

    def skirt_w(co):
        t = min(max((hz - co.z) / (0.4 * S), 0.0), 1.0)
        leg = "LeftUpperLeg" if co.x >= 0 else "RightUpperLeg"
        return {"Hips": 1.0 - 0.55 * t, leg: 0.55 * t}

    for i in range(10):  # tassets
        a = math.radians(i * 36 + 18)
        r = 0.2 * S * HW
        mb.box(None, steel if i % 2 else gold, (math.sin(a) * r, -math.cos(a) * r * 0.85, hz - 0.2 * S), (0.11 * S, 0.016 * S, 0.3 * S),
               rot=(9, 0, math.degrees(a) + 180), bevel=0.004, weights=skirt_w)
    mb.box(None, accent, (0, -0.19 * S, hz - 0.22 * S), (0.17 * S, 0.012 * S, 0.5 * S), rot=(5, 0, 0), weights=skirt_w)  # tabard
    mb.box(None, gold, (0, -0.197 * S, hz - 0.12 * S), (0.028 * S, 0.01 * S, 0.17 * S), rot=(5, 0, 0), weights=skirt_w)  # cross
    mb.box(None, gold, (0, -0.197 * S, hz - 0.09 * S), (0.095 * S, 0.01 * S, 0.028 * S), rot=(5, 0, 0), weights=skirt_w)
    mb.box(None, gold, (0, -0.196 * S, hz - 0.47 * S), (0.17 * S, 0.012 * S, 0.02 * S), rot=(5, 0, 0), weights=skirt_w)

    # ---- cloak and fur collar -------------------------------------------------------------------
    cape_w = _zw([("UpperChest", uz + 0.14 * S), ("Chest", cz), ("Spine", sz), ("Hips", hz), ("Hips", hz - 0.5 * S)])
    n_rings = 8
    for width, depth, mat, push in ((1.0, 0.009, cloth, 0.0), (0.42, 0.006, accent, 0.012)):
        rings = []
        for i in range(n_rings):
            t = i / (n_rings - 1)
            rings.append(_ring(uz + 0.14 * S - t * (uz - hz + 0.55) * S / S * 1.0, (0.2 + 0.2 * t) * SW * 0.95 * width, depth, 0.165 + 0.085 * t + push))
        mb.ring_loft(mat, rings, 8, cape_w)
    mb.box(None, gold, (0, 0.165 * S, uz + 0.17 * S), (0.46 * S * SW * 0.95, 0.024 * S, 0.02 * S), weights=cape_w)
    collar_w = _zw([("UpperChest", uz + 0.2 * S), ("UpperChest", uz)])
    for i in range(14):
        a = math.radians(i * 360 / 14)
        c = (math.sin(a) * 0.165 * S * SW * 0.95, -math.cos(a) * 0.125 * S + 0.0, uz + 0.135 * S)
        mb.sphere(None, fur, c, (0.062 * S, 0.062 * S, 0.05 * S), segs=7, rings=4, weights=collar_w)
    mb.cyl("Neck", gold, (0, 0, nz + 0.0), 0.095 * S, 0.075 * S, 0.04 * S, segs=10)

    # ---- arms ------------------------------------------------------------------------------------
    for side in ("Left", "Right"):
        sgn = 1 if side == "Left" else -1
        ua, la, hd = J(f"{side}UpperArm"), J(f"{side}LowerArm"), J(f"{side}Hand")
        _seg(mb, f"{side}LowerArm", steel, la, hd, 0.062 * S, 0.048 * S, 0.1, 0.88)
        _seg(mb, f"{side}LowerArm", gold, la, hd, 0.066 * S, 0.064 * S, 0.0, 0.1)
        _seg(mb, f"{side}LowerArm", gold, la, hd, 0.054 * S, 0.052 * S, 0.84, 0.98)
        mb.sphere(f"{side}LowerArm", steel, tuple(la + Vector((0, 0.015 * S, 0))), (0.068 * S, 0.066 * S, 0.066 * S), segs=8, rings=5)
        _seg(mb, f"{side}UpperArm", steel, ua, la, 0.068 * S, 0.06 * S, 0.3, 0.9)
        mb.box(f"{side}Hand", steel, tuple((hd + T(f"{side}Hand")) * 0.5), (0.07 * S, 0.075 * S, 0.12 * S), bevel=0.008)
        shoulder = ua + Vector((sgn * 0.045 * S, 0.0, 0.04 * S))
        mb.sphere(f"{side}UpperArm", steel, tuple(shoulder), (0.14 * S, 0.125 * S, 0.095 * S), rot=(0, -sgn * 18, 0), segs=10, rings=6)
        mb.sphere(f"{side}UpperArm", steel, tuple(shoulder + Vector((sgn * 0.05 * S, 0, -0.075 * S))), (0.125 * S, 0.115 * S, 0.05 * S), rot=(0, -sgn * 25, 0), segs=10, rings=4)
        mb.cyl(f"{side}UpperArm", gold, tuple(shoulder + Vector((sgn * 0.01 * S, 0, 0.05 * S))), 0.1 * S, 0.1 * S, 0.02 * S, rot=(0, -sgn * 18, 0), segs=12)
        mb.cone(f"{side}UpperArm", gold, tuple(shoulder + Vector((sgn * 0.02 * S, 0, 0.1 * S))), 0.03 * S, 0.09 * S, rot=(0, sgn * 10, 0), segs=6)

    # ---- legs -------------------------------------------------------------------------------------
    for side in ("Left", "Right"):
        sgn = 1 if side == "Left" else -1
        ul, ll, ft = J(f"{side}UpperLeg"), J(f"{side}LowerLeg"), J(f"{side}Foot")
        _seg(mb, f"{side}UpperLeg", steel, ul, ll, 0.115 * S * HW, 0.08 * S, 0.1, 0.82)
        mb.sphere(f"{side}LowerLeg", gold, tuple(ll + Vector((0, -0.035 * S, 0.0))), (0.07 * S, 0.066 * S, 0.07 * S), segs=8, rings=5)
        mb.cone(f"{side}LowerLeg", gold, tuple(ll + Vector((sgn * 0.07 * S, -0.02 * S, 0.0))), 0.025 * S, 0.07 * S, rot=(0, sgn * 90, 0), segs=6)
        _seg(mb, f"{side}LowerLeg", steel, ll, ft, 0.076 * S, 0.056 * S, 0.1, 0.9)
        _seg(mb, f"{side}LowerLeg", gold, ll, ft, 0.08 * S, 0.078 * S, 0.0, 0.07)
        toe = T(f"{side}Foot")
        mb.box(f"{side}Foot", steel, (ft.x, (ft.y + toe.y) * 0.5 - 0.03 * S, 0.05 * S), (0.1 * S, 0.22 * S, 0.085 * S), bevel=0.012)
        mb.box(f"{side}Foot", gold, (ft.x, ft.y - 0.07 * S, 0.075 * S), (0.05 * S, 0.1 * S, 0.02 * S), rot=(-8, 0, 0), bevel=0.004)

    # ---- great helm with crown ---------------------------------------------------------------------
    hc = (J("Head") + T("Head")) * 0.5
    mb.cyl("Head", steel, tuple(hc + Vector((0, 0.005 * S, 0.0))), 0.112 * S, 0.126 * S, 0.27 * S, segs=14)
    mb.cyl("Head", steel, tuple(hc + Vector((0, 0.005 * S, 0.145 * S))), 0.126 * S, 0.1 * S, 0.03 * S, segs=14)
    mb.box("Head", cloth, tuple(hc + Vector((0, -0.121 * S, 0.035 * S))), (0.17 * S, 0.012 * S, 0.02 * S))   # eye slit
    mb.box("Head", gold, tuple(hc + Vector((0, -0.123 * S, -0.02 * S))), (0.018 * S, 0.012 * S, 0.17 * S))   # visor ridge
    for k in range(4):
        mb.box("Head", cloth, tuple(hc + Vector((0.04 * S, -0.119 * S, -0.04 * S - 0.024 * S * k))), (0.04 * S, 0.01 * S, 0.008 * S))
        mb.box("Head", cloth, tuple(hc + Vector((-0.04 * S, -0.119 * S, -0.04 * S - 0.024 * S * k))), (0.04 * S, 0.01 * S, 0.008 * S))
    mb.cyl("Head", gold, tuple(hc + Vector((0, 0.005 * S, 0.165 * S))), 0.13 * S, 0.13 * S, 0.035 * S, segs=14)
    top = hc + Vector((0, 0.005 * S, 0.18 * S))
    for i in range(7):  # crown points ring the helm
        a = math.radians(i * 360 / 7 + 25)
        base = top + Vector((math.sin(a) * 0.118 * S, -math.cos(a) * 0.118 * S, 0.0))
        mb.cone("Head", gold, tuple(base + Vector((0, 0, 0.045 * S))), 0.026 * S, 0.1 * S, segs=4)
        mb.sphere("Head", accent if i % 2 == 0 else gold, tuple(base + Vector((0, 0, 0.1 * S))), (0.012 * S, 0.012 * S, 0.012 * S), segs=6, rings=4)
    mb.box("Head", gold, tuple(top + Vector((0, 0, 0.115 * S))), (0.022 * S, 0.022 * S, 0.11 * S), bevel=0.003)   # cross finial
    mb.box("Head", gold, tuple(top + Vector((0, 0, 0.135 * S))), (0.07 * S, 0.022 * S, 0.022 * S), bevel=0.003)
    body = mb.build(arm)

    # ---- royal longsword ---------------------------------------------------------------------------
    g = J("WeaponSocket_R")
    pm = MeshBuilder("King_Longsword", [steel, gold, fur, cloth], skinned=False)
    frame = (90, 0, -90)
    at = lambda u, v=0.0, w=0.0: tuple(Vector(g) + Vector((w, -u, v)))
    blade = [(0.07 * S, 0.026 * S), (0.92 * S, 0.024 * S), (1.1 * S, 0.0), (0.92 * S, -0.024 * S), (0.07 * S, -0.026 * S)]
    pm.prism(None, steel, at(0.0), blade, 0.012 * S, rot=frame)
    pm.prism(None, cloth, at(0.0), [(0.14 * S, 0.004 * S), (0.8 * S, 0.004 * S), (0.8 * S, -0.004 * S), (0.14 * S, -0.004 * S)], 0.0145 * S, rot=frame)
    pm.box(None, gold, at(0.06 * S), (0.022 * S, 0.026 * S, 0.24 * S), bevel=0.004)
    for sgn in (1, -1):
        pm.sphere(None, gold, at(0.06 * S, sgn * 0.125 * S), (0.018 * S, 0.018 * S, 0.018 * S), segs=6, rings=4)
    pm.cyl(None, fur, at(-0.045 * S), 0.0195 * S, 0.0195 * S, 0.2 * S, rot=(90, 0, 0), segs=8)
    pm.sphere(None, gold, at(-0.16 * S), (0.034 * S, 0.034 * S, 0.034 * S), segs=8, rings=5)
    sword = pm.build()
    attach_to_bone(sword, arm, "WeaponSocket_R")
    return {"body": body, "props": [sword]}
