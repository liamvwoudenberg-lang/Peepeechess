"""QUEEN - elegant royal duelist. Slim waist, flared ornate pauldrons, segmented skirt plates,
tall coronet helm with swept spikes, short cape, TWO enchanted curved blades (emissive edge).

Weapon grip convention (for the animation worker): each blade extends FORWARD (-Y in Blender, +Z in
Godot) from the fist at the WeaponSocket, edge/spine in the vertical plane. With the arm hanging
the blade points forward from the hip; raising the arm forward 90 deg turns the blade UP.
Body = one skinned mesh (5 material slots); blades are separate props on WeaponSocket_R / _L.
"""
from __future__ import annotations

import math

from mathutils import Euler, Vector

from .. import materials, modeling
from ..modeling import MeshBuilder, attach_to_bone

NAME = "queen"
PROPORTIONS = dict(scale=1.0, shoulder_width=0.9, hip_width=0.95)
STYLE = {"weapon_r": "saber", "weapon_l": "saber", "grip": "blade_forward", "stance": "duelist", "two_handed": False}

S = PROPORTIONS["scale"]
SW = PROPORTIONS["shoulder_width"]
HW = PROPORTIONS["hip_width"]


def _rot_z_to(direction) -> tuple:
    e = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized()).to_euler("XYZ")
    return tuple(math.degrees(a) for a in e)


def _zw(anchors):
    """Z-height skin weights: anchors [(bone, z)] descending; linear blend between neighbours."""
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
    """Cylinder between two points (sub-range t0..t1), radius r0 at p0 end to r1 at p1 end."""
    a, b = p0.lerp(p1, t0), p0.lerp(p1, t1)
    d = b - a
    ra, rb = r0 + (r1 - r0) * t0, r0 + (r1 - r0) * t1
    mb.cyl(bone, mat, tuple((a + b) * 0.5), ra, rb, d.length, _rot_z_to(d), segs, caps)


def _ring(z, rx, ry, cy=0.0):
    return (Vector((0, cy * S, z)), Vector((rx * S, 0, 0)), Vector((0, ry * S, 0)))


def build(arm, joints):
    J = lambda n: joints[n][0]       # joint head (armature space)
    T = lambda n: joints[n][1]       # joint tail

    steel = materials.get_material("Queen_Steel", (0.46, 0.47, 0.55), kind="steel", metallic=0.85, roughness=0.42, uv_m=0.6, seed=11)
    gold = materials.get_material("Queen_Gold", (0.72, 0.52, 0.17), kind="steel", metallic=0.9, roughness=0.32, uv_m=0.5, seed=12)
    leather = materials.get_material("Queen_Leather", (0.17, 0.10, 0.09), kind="leather", metallic=0.0, roughness=0.8, uv_m=0.5, seed=13)
    cloth = materials.get_material("Queen_Cloth", (0.24, 0.12, 0.33), kind="cloth", metallic=0.0, roughness=0.9, uv_m=0.4, seed=14)
    accent = materials.get_material("Queen_Accent", (0.13, 0.012, 0.04), metallic=0.1, roughness=0.7)
    glow = materials.get_material("Queen_Glow", (0.2, 0.5, 1.0), emission=(0.25, 0.6, 1.0), emission_strength=1.0, roughness=0.3)
    mb = MeshBuilder("Queen_Body", [steel, gold, leather, cloth, accent])

    hz, sz, cz, uz, nz = (J(n).z for n in ("Hips", "Spine", "Chest", "UpperChest", "Neck"))
    mid = lambda n: (J(n).z + T(n).z) * 0.5
    torso_w = _zw([("UpperChest", mid("UpperChest")), ("Chest", mid("Chest")), ("Spine", mid("Spine")), ("Hips", mid("Hips"))])

    # ---- undersuit (dark cloth, skinned) ------------------------------------------------------
    mb.ring_loft(cloth, [_ring(hz - 0.09 * S, .15 * HW, .105), _ring(hz, .165 * HW, .11), _ring(sz + 0.03 * S, .104 * HW, .08),
                         _ring(cz + 0.03 * S, .135, .098, -.006), _ring(uz + 0.02 * S, .165 * SW, .112, -.01),
                         _ring(uz + 0.14 * S, .17 * SW, .10, -.005), _ring(nz, .07, .066)], 10, torso_w)
    for side in ("Left", "Right"):
        sgn = 1 if side == "Left" else -1
        mb.tube(cloth, [(f"{side}UpperArm", J(f"{side}UpperArm")), (f"{side}LowerArm", J(f"{side}LowerArm")),
                        (f"{side}Hand", J(f"{side}Hand")), (f"{side}Hand", T(f"{side}Hand"))],
                [0.052 * S, 0.042 * S, 0.034 * S, 0.03 * S], segs=10)
        mb.tube(cloth, [(f"{side}UpperLeg", J(f"{side}UpperLeg")), (f"{side}LowerLeg", J(f"{side}LowerLeg")),
                        (f"{side}Foot", J(f"{side}Foot"))],
                [0.092 * S * HW, 0.062 * S, 0.048 * S], segs=10)
    mb.tube(cloth, [("Neck", J("Neck")), ("Head", J("Head"))], [0.052 * S, 0.05 * S], segs=8, rings_per_segment=2)

    # ---- cuirass: waisted plate with gold bands and a crest --------------------------------
    mb.ring_loft(steel, [_ring(sz + 0.045 * S, .112 * HW, .088), _ring(cz + 0.0, .15, .112, -.006),
                         _ring(uz + 0.0, .178 * SW, .128, -.012), _ring(uz + 0.12 * S, .18 * SW, .118, -.008)],
                 10, torso_w, caps=(False, False))
    mb.ring_loft(gold, [_ring(sz + 0.04 * S, .116 * HW, .092), _ring(sz + 0.065 * S, .116 * HW, .092)], 10, torso_w, caps=(False, False))
    mb.ring_loft(gold, [_ring(uz + 0.115 * S, .184 * SW, .122, -.008), _ring(uz + 0.145 * S, .184 * SW, .122, -.008)], 10, torso_w, caps=(False, False))
    mb.prism("Chest", gold, (0, -0.132 * S, cz + 0.09 * S), [(0, .06), (.04, 0), (0, -.075), (-.04, 0)], 0.016 * S, rot=(90, 0, 0))
    mb.sphere("Chest", accent, (0, -0.138 * S, cz + 0.09 * S), (.016, .01, .02), segs=8, rings=4)
    # gorget
    mb.cyl("Neck", gold, (0, 0, nz + 0.015 * S), 0.085 * S, 0.062 * S, 0.05 * S, segs=10)
    mb.cyl("Neck", steel, (0, 0, nz + 0.0), 0.095 * S, 0.085 * S, 0.035 * S, segs=10)

    # ---- belt, tabard, skirt plates -------------------------------------------------------------
    mb.cyl("Hips", leather, (0, 0, hz + 0.045 * S), 0.158 * S * HW, 0.158 * S * HW, 0.05 * S, segs=12)
    mb.box("Hips", gold, (0, -0.16 * S, hz + 0.045 * S), (0.06 * S, 0.016 * S, 0.055 * S), bevel=0.004)

    def skirt_w(co):
        t = min(max((hz + 0.02 * S - co.z) / (0.32 * S), 0.0), 1.0)
        leg = "LeftUpperLeg" if co.x >= 0 else "RightUpperLeg"
        return {"Hips": 1.0 - 0.55 * t, leg: 0.55 * t}

    for i in range(10):
        a = math.radians(i * 36 + 18)
        r = 0.185 * S * HW
        c = (math.sin(a) * r, -math.cos(a) * r * 0.82, hz - 0.1 * S)
        plate_mat = gold if i % 5 == 0 else steel
        mb.box(None, plate_mat, c, (0.095 * S, 0.013 * S, 0.27 * S), rot=(12 if math.cos(a) > 0.3 else 10, 0, math.degrees(a) + 180),
               bevel=0.004, weights=skirt_w)
    # front tabard (team accent), hangs between the legs' front plates
    mb.box(None, accent, (0, -0.155 * S, hz - 0.14 * S), (0.085 * S, 0.01 * S, 0.34 * S), rot=(6, 0, 0), weights=skirt_w)
    mb.box(None, gold, (0, -0.16 * S, hz - 0.31 * S), (0.09 * S, 0.012 * S, 0.018 * S), rot=(6, 0, 0), weights=skirt_w)

    # ---- cape (short, from the shoulder blades) -------------------------------------------------
    cape_w = _zw([("UpperChest", uz + 0.12 * S), ("Chest", cz), ("Spine", sz), ("Hips", hz)])
    for width, depth, mat, push in ((1.0, 0.007, cloth, 0.0), (0.4, 0.005, accent, 0.01)):
        rings = []
        for i in range(5):
            u = i / 4
            rings.append(_ring(uz + 0.1 * S - u * 0.46 * S, (0.15 + 0.07 * u) * width, depth, 0.135 + 0.04 * u + push))
        mb.ring_loft(mat, rings, 8, cape_w)
    mb.box(None, gold, (0, 0.128 * S, uz + 0.165 * S), (0.27 * S, 0.02 * S, 0.018 * S), weights=cape_w)

    # ---- arms: vambraces, cuffs, elbow cops, gauntlets, flared ornate pauldrons --------------
    for side in ("Left", "Right"):
        sgn = 1 if side == "Left" else -1
        ua, la, hd = J(f"{side}UpperArm"), J(f"{side}LowerArm"), J(f"{side}Hand")
        _seg(mb, f"{side}LowerArm", steel, la, hd, 0.05 * S, 0.04 * S, 0.12, 0.85)
        _seg(mb, f"{side}LowerArm", gold, la, hd, 0.054 * S, 0.052 * S, 0.0, 0.1)
        _seg(mb, f"{side}LowerArm", gold, la, hd, 0.046 * S, 0.044 * S, 0.84, 0.97)
        mb.sphere(f"{side}LowerArm", steel, tuple(la + Vector((0, 0.012 * S, 0))), (0.056 * S, 0.056 * S, 0.056 * S), segs=8, rings=5)
        _seg(mb, f"{side}UpperArm", steel, ua, la, 0.056 * S, 0.05 * S, 0.3, 0.88)
        hand_c = (hd + T(f"{side}Hand")) * 0.5
        mb.box(f"{side}Hand", leather, tuple(hand_c), (0.055 * S, 0.06 * S, 0.1 * S), bevel=0.006)
        # pauldron: layered dome + flared gold fin + spikes
        shoulder = ua + Vector((sgn * 0.035 * S, 0.0, 0.035 * S))
        mb.sphere(f"{side}UpperArm", steel, tuple(shoulder), (0.105 * S, 0.1 * S, 0.075 * S), rot=(0, -sgn * 20, 0), segs=10, rings=5)
        mb.sphere(f"{side}UpperArm", gold, tuple(shoulder + Vector((sgn * 0.045 * S, 0, -0.045 * S))), (0.085 * S, 0.092 * S, 0.02 * S),
                  rot=(0, -sgn * 28, 0), segs=10, rings=3)
        mb.prism(f"{side}UpperArm", gold, tuple(shoulder + Vector((sgn * 0.07 * S, 0, 0.1 * S))),
                 [(-.05 * S, -.04 * S), (.05 * S, -.05 * S), (.035 * S, .14 * S), (-.01 * S, .2 * S)], 0.012 * S,
                 rot=(90, sgn * 32, 0))
        for j, (dx, dz, tilt) in enumerate(((0.1, 0.04, 62), (0.085, 0.085, 42))):
            mb.cyl(f"{side}UpperArm", gold, tuple(shoulder + Vector((sgn * dx * S, 0, dz * S))), 0.014 * S, 0.0, 0.11 * S,
                   rot=(0, sgn * tilt, 0), segs=6)

    # ---- legs: cuisses, poleyns, greaves, boots ---------------------------------------------
    for side in ("Left", "Right"):
        ul, ll, ft = J(f"{side}UpperLeg"), J(f"{side}LowerLeg"), J(f"{side}Foot")
        _seg(mb, f"{side}UpperLeg", steel, ul, ll, 0.1 * S * HW, 0.07 * S, 0.12, 0.8)
        mb.sphere(f"{side}LowerLeg", gold, tuple(ll + Vector((0, -0.03 * S, 0.0))), (0.06 * S, 0.055 * S, 0.06 * S), segs=8, rings=5)
        _seg(mb, f"{side}LowerLeg", steel, ll, ft, 0.066 * S, 0.05 * S, 0.12, 0.88)
        _seg(mb, f"{side}LowerLeg", gold, ll, ft, 0.07 * S, 0.068 * S, 0.0, 0.07)
        toe = T(f"{side}Foot")
        mb.box(f"{side}Foot", leather, (ft.x, (ft.y + toe.y) * 0.5 - 0.03 * S, 0.045 * S), (0.085 * S, 0.2 * S, 0.075 * S), bevel=0.01)
        mb.box(f"{side}Foot", steel, (ft.x, (ft.y + toe.y) * 0.5 - 0.075 * S, 0.062 * S), (0.07 * S, 0.1 * S, 0.03 * S), rot=(-8, 0, 0), bevel=0.005)

    # ---- helm: swept coronet, cheek guards, face mask with eye slit ----------------------------
    hc = (J("Head") + T("Head")) * 0.5
    mb.sphere("Head", steel, tuple(hc + Vector((0, 0.01 * S, 0.02 * S))), (0.112 * S, 0.128 * S, 0.125 * S), segs=12, rings=7)
    mb.prism("Head", steel, tuple(hc + Vector((0, -0.105 * S, -0.015 * S))), [(-.08 * S, .1 * S), (.08 * S, .1 * S), (.065 * S, -.07 * S), (0, -.115 * S), (-.065 * S, -.07 * S)],
             0.022 * S, rot=(90, 0, 0))
    mb.box("Head", cloth, tuple(hc + Vector((0, -0.118 * S, 0.018 * S))), (0.13 * S, 0.01 * S, 0.014 * S))
    mb.box("Head", gold, tuple(hc + Vector((0, -0.12 * S, -0.04 * S))), (0.014 * S, 0.012 * S, 0.1 * S))
    for sgn in (1, -1):
        mb.box("Head", steel, tuple(hc + Vector((sgn * 0.108 * S, -0.03 * S, -0.04 * S))), (0.016 * S, 0.1 * S, 0.1 * S), rot=(0, 0, sgn * 8), bevel=0.004)
    mb.cyl("Head", gold, tuple(hc + Vector((0, 0.005 * S, 0.078 * S))), 0.117 * S, 0.117 * S, 0.022 * S, segs=14)
    top = hc + Vector((0, 0.005 * S, 0.085 * S))
    for i in range(9):
        a = math.radians(i * 40 + 20)
        base = top + Vector((math.sin(a) * 0.105 * S, -math.cos(a) * 0.105 * S, 0))
        back = max(0.0, math.cos(a)) * 0.22  # rear spikes sweep back more and rise higher
        direction = Vector((math.sin(a) * 0.35, -math.cos(a) * 0.35 + back, 1.0))
        mb.cyl("Head", gold, tuple(base + direction.normalized() * 0.065 * S), 0.016 * S, 0.0, (0.13 + 0.09 * back) * S,
               rot=_rot_z_to(direction), segs=6)
    mb.cyl("Head", gold, tuple(top + Vector((0, -0.02 * S, 0.12 * S))), 0.013 * S, 0.0, 0.2 * S, rot=(-8, 0, 0), segs=6)
    mb.sphere("Head", accent, tuple(hc + Vector((0, -0.112 * S, 0.075 * S))), (0.014 * S, 0.01 * S, 0.014 * S), segs=6, rings=4)
    body = mb.build(arm)

    # ---- the two enchanted sabres ----------------------------------------------------------------
    props = []
    for side, socket in (("R", "WeaponSocket_R"), ("L", "WeaponSocket_L")):
        g = J(socket)
        pm = MeshBuilder(f"Queen_Blade_{side}", [steel, gold, leather, glow], skinned=False)
        frame = (90, 0, -90)  # local X -> forward(-Y), local Y -> up, local Z -> thickness
        origin = Vector(g)

        def at(u, v=0.0, w=0.0):
            return tuple(origin + Vector((w, -u, v)))

        # blade outline in (u forward, v up): curved spine, tapering edge, pointed tip
        n = 9
        length = 0.92 * S
        spine = [(0.05 * S + length * i / n, 0.012 * S + 0.1 * S * (i / n) ** 2.2) for i in range(n + 1)]
        edge = [(u, v - 0.062 * S * (1.0 - (i / n) ** 1.6)) for i, (u, v) in enumerate(spine)]
        outline = [(u - 0.0, v) for u, v in spine] + [(u, v) for u, v in reversed(edge[:-1])]
        pm.prism(None, steel, at(0.0), outline, 0.012 * S, rot=frame)
        glow_band = [(u, v - 0.05 * S * (1.0 - (i / n) ** 1.6)) for i, (u, v) in enumerate(spine) if 1 <= i <= n - 1]
        glow_band_top = [(u, v - 0.038 * S * (1.0 - (i / n) ** 1.6)) for i, (u, v) in enumerate(spine) if 1 <= i <= n - 1]
        pm.prism(None, glow, at(0.0), glow_band + list(reversed(glow_band_top)), 0.016 * S, rot=frame)
        pm.box(None, gold, at(0.05 * S), (0.018 * S, 0.016 * S, 0.14 * S), rot=(0, 0, 0), bevel=0.003)
        pm.sphere(None, gold, at(0.05 * S, 0.07 * S), (0.014 * S, 0.014 * S, 0.014 * S), segs=6, rings=4)
        pm.sphere(None, gold, at(0.05 * S, -0.07 * S), (0.014 * S, 0.014 * S, 0.014 * S), segs=6, rings=4)
        pm.cyl(None, leather, at(-0.035 * S), 0.0185 * S, 0.0185 * S, 0.17 * S, rot=(90, 0, 0), segs=8)
        pm.sphere(None, gold, at(-0.13 * S), (0.026 * S, 0.026 * S, 0.026 * S), segs=8, rings=5)
        pm.sphere(None, glow, at(-0.155 * S), (0.012 * S, 0.012 * S, 0.012 * S), segs=6, rings=4)
        blade = pm.build()
        attach_to_bone(blade, arm, socket)
        props.append(blade)
    return {"body": body, "props": props}
