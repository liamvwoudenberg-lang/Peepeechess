"""BISHOP - arcane battle-cleric. Slim, robed, light plate over a flared tabard, wide bell sleeves,
a tall cleft-mitre hood with glowing eyes, rune trim, and a ~1.9 m crystal STAFF held two-handed.

Silhouette: tall pointed mitre on top, flared skirt at the bottom, a staff taller than the wielder.
Everything deforming (torso, skirt, limbs) is skinned to the shared skeleton; plates are rigid to
the bone they sit on. Materials: Bishop_Cloth, Bishop_Steel, Bishop_Leather, Bishop_Accent (plain
team-tint colour), Bishop_Rune (emissive, strength 1).
"""
from __future__ import annotations

import math

from mathutils import Vector

from .. import materials
from ..modeling import MeshBuilder, attach_to_bone

NAME = "bishop"
PROPORTIONS = dict(scale=1.0, shoulder_width=0.95, hip_width=0.92)

S = PROPORTIONS["scale"]
STAFF_LENGTH = 1.9
STYLE = dict(
    # keys understood by animation.library (see its docstring)
    grip="staff2", weapon_axis=(0, 0, 1), offhand_grip=0.42, stance=0.17, arm_clear=0.35, swagger=0.95, power=0.9,
    # extra rest-pose geometry for tools/tests (ignored by the library)
    archetype="caster", ability="blink", weapon_length=STAFF_LENGTH,
    shaft_x=-0.2425 * PROPORTIONS["shoulder_width"] * S, shaft_bottom_z=0.03, shaft_top_z=0.03 + STAFF_LENGTH * 0.88,
)


# ---- helpers ------------------------------------------------------------------------------------
def _clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def _spine_weights(joints):
    bones = ["Hips", "Spine", "Chest", "UpperChest"]
    bounds = [joints["Spine"][0].z, joints["Chest"][0].z, joints["UpperChest"][0].z]
    blend = 0.045

    def fn(co):
        z = co.z
        i = sum(1 for b in bounds if z >= b)
        w = {bones[i]: 1.0}
        if i > 0 and z - bounds[i - 1] < blend:
            t = 0.5 * (1 - (z - bounds[i - 1]) / blend)
            w = {bones[i]: 1 - t, bones[i - 1]: t}
        elif i < len(bounds) and bounds[i] - z < blend:
            t = 0.5 * (1 - (bounds[i] - z) / blend)
            w = {bones[i]: 1 - t, bones[i + 1]: t}
        return w
    return fn


def _skirt_weights(joints, reach=0.75):
    """Hips above the pelvis, blending to the two upper-leg bones (by side) toward the hem. The hem
    only follows a leg partially (`reach`) so a stride does not drag the whole skirt along."""
    hips_z = joints["Hips"][0].z

    def fn(co):
        leg = _clamp((hips_z + 0.04 - co.z) / 0.45) * reach
        left = _clamp(0.5 + co.x / 0.14)
        w = {"Hips": 1.0 - leg}
        if leg > 0.0:
            w["LeftUpperLeg"] = leg * left
            w["RightUpperLeg"] = leg * (1.0 - left)
        return w
    return fn


def _between(a, b):
    """(centre, length, euler degrees) for a +Z-axis primitive spanning a -> b."""
    d = b - a
    eul = d.to_track_quat("Z", "Y").to_euler("XYZ")
    return (a + b) * 0.5, d.length, tuple(math.degrees(x) for x in eul)


def _seg(mb, bone, mat, a, b, r1, r2, segs=8):
    c, length, rot = _between(a, b)
    mb.cyl(bone, mat, c, r1, r2, length, rot=rot, segs=segs)


def _ring_set(mb, mat, zs, rx, ry, cy, weight_fn, segs=12):
    rings = [(Vector((0, cy_, z)), Vector((rx_, 0, 0)), Vector((0, ry_, 0))) for z, rx_, ry_, cy_ in zip(zs, rx, ry, cy)]
    mb.ring_loft(mat, rings, segs, weight_fn, caps=(False, False))


# ---- build --------------------------------------------------------------------------------------
def build(arm, joints):
    J = {k: v[0] for k, v in joints.items()}
    T = {k: v[1] for k, v in joints.items()}
    cloth = materials.get_material("Bishop_Cloth", (0.17, 0.11, 0.25), kind="cloth", roughness=0.95, uv_m=0.4)
    steel = materials.get_material("Bishop_Steel", (0.30, 0.31, 0.37), kind="steel", metallic=0.85, roughness=0.42, uv_m=0.6)
    leather = materials.get_material("Bishop_Leather", (0.14, 0.095, 0.075), kind="leather", roughness=0.85, uv_m=0.5)
    accent = materials.get_material("Bishop_Accent", color=(0.82, 0.66, 0.26), metallic=0.55, roughness=0.5)
    rune = materials.get_material("Bishop_Rune", color=(0.15, 0.4, 0.9), emission=(0.3, 0.62, 1.0), emission_strength=1.0, roughness=0.4)
    mb = MeshBuilder("Bishop_Body", [cloth, steel, leather, accent, rune])
    spine_w = _spine_weights(joints)
    skirt_w = _skirt_weights(joints)

    # -- torso (cloth under-robe) ------------------------------------------------------------------
    _ring_set(mb, cloth, [0.98, 1.10, 1.26, 1.42, 1.53], [0.165, 0.148, 0.172, 0.19, 0.17],
              [0.115, 0.105, 0.115, 0.125, 0.11], [0.0, 0.0, -0.005, -0.01, 0.0], spine_w, segs=12)
    # belt + sash
    _ring_set(mb, leather, [1.035, 1.075], [0.158, 0.156], [0.112, 0.11], [0.0, 0.0], spine_w, segs=12)
    mb.box("Spine", accent, (0, -0.118, 1.055), (0.06, 0.02, 0.06), bevel=0.004)  # buckle

    # -- robe skirt (moderate flare, hem above the shins) + hem rune trim ------------------------------
    _ring_set(mb, cloth, [1.03, 0.89, 0.72, 0.56, 0.44, 0.40], [0.17, 0.20, 0.235, 0.262, 0.28, 0.285],
              [0.125, 0.148, 0.172, 0.19, 0.2, 0.203], [0.0] * 6, skirt_w, segs=14)
    _ring_set(mb, rune, [0.425, 0.40], [0.279, 0.289], [0.198, 0.207], [0.0, 0.0], skirt_w, segs=14)
    # tabard in team colour down the front, with a rune stripe
    _ring_set(mb, accent, [1.03, 0.82, 0.62, 0.46, 0.405], [0.07, 0.082, 0.095, 0.103, 0.105],
              [0.006] * 5, [-0.137, -0.172, -0.2, -0.212, -0.215], skirt_w, segs=6)
    _ring_set(mb, rune, [0.97, 0.44], [0.014, 0.018], [0.004, 0.004], [-0.15, -0.222], skirt_w, segs=4)
    # open side slits expose the leg: dark leggings were built below, trousers cloth over the thigh
    mb.box("Hips", cloth, (0, 0.2, 0.62), (0.3, 0.012, 0.52))  # back drape panel (rigid, hangs behind)

    # -- legs (under the robe, boots visible at the hem) -------------------------------------------
    for side in ("Left", "Right"):
        ul, ll, ft = J[f"{side}UpperLeg"], J[f"{side}LowerLeg"], J[f"{side}Foot"]
        mb.tube(leather, [(f"{side}UpperLeg", ul), (f"{side}LowerLeg", ll), (f"{side}Foot", ft)], [0.085, 0.065, 0.05], segs=8)
        sx = 1 if side == "Left" else -1
        mb.box(f"{side}Foot", leather, (ft.x, -0.075, 0.075), (0.105, 0.27, 0.11), bevel=0.012)
        mb.box(f"{side}Foot", steel, (ft.x, -0.20, 0.06), (0.09, 0.07, 0.07), bevel=0.01)  # toe cap
        _seg(mb, f"{side}LowerLeg", steel, ll + (ft - ll) * 0.08 + Vector((0, -0.01, 0)), ll + (ft - ll) * 0.85, 0.07, 0.056)  # greave
        mb.sphere(f"{side}LowerLeg", steel, ll + Vector((0, -0.04, 0.0)), (0.075, 0.07, 0.07), segs=8, rings=5)  # knee cop

    # -- arms: leather under-sleeve, wide cloth bell sleeve, rune cuff, glove, plates ---------------
    for side in ("Left", "Right"):
        ua, la, hd = J[f"{side}UpperArm"], J[f"{side}LowerArm"], J[f"{side}Hand"]
        hand_tail = T[f"{side}Hand"]
        mb.tube(leather, [(f"{side}UpperArm", ua), (f"{side}LowerArm", la), (f"{side}Hand", hd), (f"{side}Hand", hand_tail)],
                [0.045, 0.04, 0.034, 0.03], segs=8)
        mb.tube(cloth, [(f"{side}UpperArm", ua + Vector((0, 0, 0.01))), (f"{side}LowerArm", la), (f"{side}LowerArm", hd + Vector((0, 0, 0.1)))],
                [0.068, 0.082, 0.125], segs=10, rings_per_segment=3)
        # rune cuff ring at the bell mouth
        c = hd + Vector((0, 0, 0.115))
        mb.cyl(f"{side}LowerArm", rune, c, 0.128, 0.13, 0.014, segs=12, caps=False)
        # glove / hand
        mb.sphere(f"{side}Hand", leather, (hd + hand_tail) * 0.5, (0.04, 0.05, 0.065), segs=8, rings=5)
        # pauldron + rerebrace
        mb.sphere(f"{side}UpperArm", steel, ua + Vector((0.012 * (1 if side == "Left" else -1), 0, 0.025)),
                  (0.098, 0.088, 0.062), rot=(0, 0, 0), segs=10, rings=6)
        mb.sphere(f"{side}UpperArm", accent, ua + Vector((0.026 * (1 if side == "Left" else -1), 0, -0.005)),
                  (0.07, 0.075, 0.02), segs=10, rings=4)
        _seg(mb, f"{side}LowerArm", steel, la + Vector((0, 0, 0.19)) * 0 + (hd - la) * 0.18, la + (hd - la) * 0.62, 0.052, 0.05)

    # -- cuirass, backplate, gorget (light plate over the robe) ------------------------------------
    mb.sphere("UpperChest", steel, (0, -0.052, 1.405), (0.178, 0.09, 0.15), segs=12, rings=7)
    mb.sphere("Chest", steel, (0, -0.044, 1.255), (0.145, 0.078, 0.095), segs=12, rings=6)
    mb.sphere("UpperChest", steel, (0, 0.05, 1.40), (0.17, 0.085, 0.15), segs=12, rings=6)
    mb.cyl("Neck", steel, (0, 0, J["Neck"].z + 0.015), 0.085, 0.07, 0.085, segs=10)
    mb.cyl("Neck", accent, (0, 0, J["Neck"].z + 0.065), 0.092, 0.092, 0.014, segs=10, caps=False)
    for x, h in ((0.0, 0.24),):  # glowing rune spine down the cuirass
        mb.box("UpperChest", rune, (x, -0.143, 1.39), (0.014, 0.012, h))
    mb.box("UpperChest", rune, (0, -0.146, 1.42), (0.11, 0.012, 0.014))
    mb.box("Chest", rune, (0, -0.121, 1.26), (0.06, 0.012, 0.012))
    mb.sphere("UpperChest", rune, (0, -0.142, 1.51), (0.022, 0.012, 0.022), segs=6, rings=4)  # sternum gem

    # -- head: back-cowl hood, visible shadowed face with glowing eyes, tall cleft mitre ------------------
    hc = (J["Head"] + T["Head"]) * 0.5
    mb.shell("Head", cloth, hc + Vector((0, 0.01, -0.005)), 0.165, 250, 0.36, thickness=0.03, segs=8)   # cowl (opens to the front)
    mb.sphere("Head", cloth, hc + Vector((0, 0.07, 0.0)), (0.15, 0.1, 0.17), segs=10, rings=6)           # hood back fill
    mb.sphere("Head", leather, hc + Vector((0, -0.03, -0.01)), (0.1, 0.105, 0.128), segs=10, rings=7)    # face
    mb.box("Head", leather, hc + Vector((0, -0.125, -0.04)), (0.03, 0.04, 0.06), bevel=0.006)             # nose bridge
    for sx in (1, -1):
        mb.box("Head", rune, hc + Vector((0.042 * sx, -0.128, 0.015)), (0.04, 0.012, 0.014), rot=(0, 0, -14 * sx))
    # mantle over the shoulders
    mb.sphere("UpperChest", cloth, (0, 0.005, 1.505), (0.225, 0.155, 0.062), segs=12, rings=5)
    mb.cyl("Head", accent, hc + Vector((0, 0.01, 0.12)), 0.17, 0.17, 0.03, segs=14, caps=False)  # mitre band
    base_z = hc.z + 0.12
    arch = [(-0.13, 0.0), (0.13, 0.0), (0.115, 0.13), (0.07, 0.25), (0.0, 0.34), (-0.07, 0.25), (-0.115, 0.13)]
    # front and back panels lean together: the cleft shows from the side, the arch from the front
    mb.prism("Head", cloth, Vector((0, -0.085, base_z)), arch, 0.03, rot=(80, 0, 0))
    mb.prism("Head", cloth, Vector((0, 0.1, base_z)), arch, 0.03, rot=(100, 0, 0))
    mb.prism("Head", accent, Vector((0, -0.093, base_z + 0.012)), [(x * 0.62, y * 0.8 + 0.02) for x, y in arch], 0.012, rot=(80, 0, 0))
    mb.box("Head", cloth, (0.0, 0.1, base_z - 0.06), (0.1, 0.03, 0.24), rot=(0, 0, 0))  # lappet hanging behind
    mb.sphere("Head", rune, Vector((0, -0.096, base_z + 0.17)), (0.02, 0.014, 0.034), segs=6, rings=4)
    mb.sphere("Head", accent, Vector((0.0, 0.03, base_z + 0.3)), (0.02, 0.02, 0.02), segs=6, rings=4)
    body = mb.build(arm)

    # -- STAFF prop (WeaponSocket_R), ~1.9 m with a crystal head ------------------------------------
    wood = materials.get_material("Bishop_Wood", (0.2, 0.13, 0.08), kind="wood", roughness=0.8, uv_m=0.5)
    pb = MeshBuilder("Bishop_Staff", [wood, steel, accent, rune, leather], skinned=False)
    x = -0.2425 * PROPORTIONS["shoulder_width"] * S
    z0 = 0.03
    pb.cyl(None, wood, (x, 0, z0 + 0.82), 0.03, 0.026, 1.64, segs=8)            # shaft
    pb.cone(None, steel, (x, 0, z0 - 0.02), 0.03, 0.09, rot=(180, 0, 0), segs=8)  # ferrule spike
    pb.cyl(None, leather, (x, 0, 0.9), 0.034, 0.034, 0.2, segs=8)                # grip wrap
    for dz in (0.52, 1.28):
        pb.cyl(None, accent, (x, 0, dz), 0.04, 0.04, 0.025, segs=8)
    top = z0 + 1.64
    pb.cyl(None, steel, (x, 0, top + 0.02), 0.055, 0.03, 0.07, segs=8)            # collar
    pb.cyl(None, accent, (x, 0, top + 0.065), 0.06, 0.06, 0.016, segs=10)
    for k in range(4):                                                            # cradle claws
        ang = 45 + 90 * k
        ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
        base = Vector((x + ca * 0.05, sa * 0.05, top + 0.08))
        tip = Vector((x + ca * 0.03, sa * 0.03, top + 0.34))
        c, length, rot = _between(base, tip)
        pb.cyl(None, steel, c, 0.018, 0.004, length, rot=rot, segs=5)
    pb.sphere(None, rune, (x, 0, top + 0.19), (0.058, 0.058, 0.115), segs=6, rings=5)  # crystal
    pb.cone(None, accent, (x, 0, top + 0.37), 0.03, 0.09, segs=6)
    staff = pb.build()
    attach_to_bone(staff, arm, "WeaponSocket_R")
    return {"body": body, "props": [staff]}
