"""ROOK - bastion tank in massive layered plate. Very broad, square silhouette (scale 1.12, wide
shoulders), great helm crowned with a crenellated battlement, stacked pauldrons with merlons, a big
TOWER SHIELD on the left forearm and a one-handed WARHAMMER on the right.

Skinned: torso, tabard, limbs. Rigid plates are weighted to the bone they sit on. Materials:
Rook_Steel, Rook_Leather, Rook_Cloth, Rook_Accent (plain team-tint colour), Rook_Ember (emissive).
"""
from __future__ import annotations

import math

from mathutils import Vector

from .. import materials
from ..modeling import MeshBuilder, attach_to_bone

NAME = "rook"
PROPORTIONS = dict(scale=1.12, shoulder_width=1.3, hip_width=1.15)

S = PROPORTIONS["scale"]
SW = PROPORTIONS["shoulder_width"]
# Rest-pose prop geometry (armature space, metres): numbers the animation layer can use.
HAMMER_X = -0.2425 * SW * S
STYLE = dict(
    # keys understood by animation.library (see its docstring)
    grip="hammer_shield", weapon_axis=(0, 0, 1), shield_normal=(0.17, -0.98, 0.0),
    stance=0.26, arm_clear=0.9, swagger=0.7, power=1.1,
    # extra rest-pose geometry for tools/tests (ignored by the library)
    archetype="bulwark", ability="fortress-guard", weapon_length=1.4 * S,
    haft_x=HAMMER_X, haft_bottom_z=0.5 * S, haft_top_z=1.82 * S, shield_size=(0.72 * S, 1.12 * S),
)


def _clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def _spine_weights(joints):
    bones = ["Hips", "Spine", "Chest", "UpperChest"]
    bounds = [joints["Spine"][0].z, joints["Chest"][0].z, joints["UpperChest"][0].z]
    blend = 0.05

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


def _skirt_weights(joints, reach=0.7):
    hips_z = joints["Hips"][0].z

    def fn(co):
        leg = _clamp((hips_z + 0.05 - co.z) / 0.45) * reach
        left = _clamp(0.5 + co.x / 0.15)
        w = {"Hips": 1.0 - leg}
        if leg > 0.0:
            w["LeftUpperLeg"] = leg * left
            w["RightUpperLeg"] = leg * (1.0 - left)
        return w
    return fn


def _between(a, b):
    d = b - a
    eul = d.to_track_quat("Z", "Y").to_euler("XYZ")
    return (a + b) * 0.5, d.length, tuple(math.degrees(x) for x in eul)


def _seg(mb, bone, mat, a, b, r1, r2, segs=8):
    c, length, rot = _between(a, b)
    mb.cyl(bone, mat, c, r1, r2, length, rot=rot, segs=segs)


def _ring_set(mb, mat, zs, rx, ry, cy, weight_fn, segs=12):
    rings = [(Vector((0, cy_, z)), Vector((rx_, 0, 0)), Vector((0, ry_, 0))) for z, rx_, ry_, cy_ in zip(zs, rx, ry, cy)]
    mb.ring_loft(mat, rings, segs, weight_fn, caps=(False, False))


def build(arm, joints):
    J = {k: v[0] for k, v in joints.items()}
    T = {k: v[1] for k, v in joints.items()}
    steel = materials.get_material("Rook_Steel", (0.27, 0.28, 0.31), kind="steel", metallic=0.88, roughness=0.5, uv_m=0.7)
    leather = materials.get_material("Rook_Leather", (0.13, 0.09, 0.07), kind="leather", roughness=0.88, uv_m=0.5)
    cloth = materials.get_material("Rook_Cloth", (0.11, 0.11, 0.13), kind="cloth", roughness=0.95, uv_m=0.4)
    accent = materials.get_material("Rook_Accent", color=(0.8, 0.64, 0.25), metallic=0.5, roughness=0.55)
    ember = materials.get_material("Rook_Ember", color=(0.9, 0.35, 0.08), emission=(1.0, 0.45, 0.1), emission_strength=1.0, roughness=0.5)
    mb = MeshBuilder("Rook_Body", [steel, leather, cloth, accent, ember])
    spine_w = _spine_weights(joints)
    skirt_w = _skirt_weights(joints)
    z = lambda v: v * S  # torso heights scale with the character

    # -- torso: heavy padded gambeson under the plate ---------------------------------------------
    _ring_set(mb, cloth, [z(0.98), z(1.10), z(1.26), z(1.42), z(1.53)],
              [0.215, 0.20, 0.25, 0.285, 0.26], [0.16, 0.15, 0.17, 0.185, 0.165], [0.0, 0.0, -0.005, -0.01, 0.0], spine_w, segs=12)
    # tabard front + back in team colour (hangs from the belt over the tassets)
    _ring_set(mb, accent, [z(1.04), z(0.86), z(0.68), z(0.54)], [0.105, 0.118, 0.128, 0.132], [0.008] * 4,
              [-0.188, -0.215, -0.235, -0.24], skirt_w, segs=6)
    _ring_set(mb, cloth, [z(1.04), z(0.80), z(0.56)], [0.15, 0.17, 0.18], [0.01] * 3, [0.19, 0.215, 0.23], skirt_w, segs=6)

    # -- belt and fauld (waist plates) ---------------------------------------------------------------
    _ring_set(mb, leather, [z(1.03), z(1.08)], [0.215, 0.214], [0.158, 0.157], [0.0, 0.0], spine_w, segs=12)
    for dz in (0.0, -0.065):
        mb.box("Hips", steel, (0, -0.0, z(0.99) + dz), (0.43, 0.33, 0.06), bevel=0.012)
    mb.box("Spine", accent, (0, -0.17, z(1.055)), (0.07, 0.02, 0.06), bevel=0.005)

    # -- legs: leather under-layer, cuisse + poleyn + greave + sabaton -----------------------------
    for side in ("Left", "Right"):
        sx = 1 if side == "Left" else -1
        ul, ll, ft = J[f"{side}UpperLeg"], J[f"{side}LowerLeg"], J[f"{side}Foot"]
        mb.tube(leather, [(f"{side}UpperLeg", ul), (f"{side}LowerLeg", ll), (f"{side}Foot", ft)], [0.11, 0.085, 0.065], segs=8)
        _seg(mb, f"{side}UpperLeg", steel, ul + (ll - ul) * 0.05, ll + (ul - ll) * 0.12, 0.128, 0.115, segs=8)  # cuisse
        mb.sphere(f"{side}LowerLeg", steel, ll + Vector((0, -0.045, 0.0)), (0.12, 0.105, 0.105), segs=8, rings=5)  # poleyn
        mb.box(f"{side}LowerLeg", steel, ll + Vector((0.0, -0.1, -0.02)), (0.08, 0.035, 0.12), bevel=0.008)       # knee fin
        _seg(mb, f"{side}LowerLeg", steel, ll + (ft - ll) * 0.14, ft + (ll - ft) * 0.05, 0.1, 0.075, segs=8)     # greave
        mb.box(f"{side}Foot", steel, (ft.x, -0.085, 0.085), (0.14, 0.31, 0.13), bevel=0.018)                      # sabaton
        mb.box(f"{side}Foot", steel, (ft.x, -0.235, 0.07), (0.11, 0.09, 0.09), bevel=0.014)
        # tasset hanging from the fauld
        mb.box(f"{side}UpperLeg", steel, (ul.x + 0.075 * sx, -0.095, z(0.80)), (0.2, 0.035, 0.32), rot=(-4, 0, 6 * sx), bevel=0.01)
        mb.box(f"{side}UpperLeg", accent, (ul.x + 0.075 * sx, -0.116, z(0.80)), (0.19, 0.006, 0.026))

    # -- arms: leather sleeve + rerebrace + couter + vambrace + gauntlet + stacked pauldron ---------
    for side in ("Left", "Right"):
        sx = 1 if side == "Left" else -1
        ua, la, hd, ht = J[f"{side}UpperArm"], J[f"{side}LowerArm"], J[f"{side}Hand"], T[f"{side}Hand"]
        mb.tube(leather, [(f"{side}UpperArm", ua), (f"{side}LowerArm", la), (f"{side}Hand", hd), (f"{side}Hand", ht)],
                [0.07, 0.06, 0.05, 0.045], segs=8)
        _seg(mb, f"{side}UpperArm", steel, ua + (la - ua) * 0.22, ua + (la - ua) * 0.92, 0.095, 0.085, segs=8)  # rerebrace
        mb.sphere(f"{side}LowerArm", steel, la + Vector((0.0, 0.03, 0.0)), (0.1, 0.1, 0.1), segs=8, rings=5)    # couter
        _seg(mb, f"{side}LowerArm", steel, la + (hd - la) * 0.14, hd + (la - hd) * 0.06, 0.092, 0.078, segs=8)  # vambrace
        mb.box(f"{side}Hand", steel, (hd + ht) * 0.5 + Vector((0, -0.01, 0.0)), (0.105, 0.115, 0.15), bevel=0.016)  # gauntlet
        mb.box(f"{side}Hand", steel, hd + Vector((0, -0.015, -0.02)), (0.12, 0.06, 0.05), bevel=0.01)              # cuff
        # stacked pauldron lames
        for k, (rx, ry, rz, dz) in enumerate(((0.225, 0.2, 0.13, 0.05), (0.2, 0.18, 0.085, -0.05), (0.175, 0.16, 0.07, -0.125))):
            mb.sphere(f"{side}UpperArm", steel, ua + Vector((0.03 * sx, 0, dz)), (rx, ry, rz), segs=10, rings=5)
        mb.sphere(f"{side}UpperArm", accent, ua + Vector((0.036 * sx, 0, -0.01)), (0.2, 0.185, 0.014), segs=10, rings=3)
        for dx in (-0.075, 0.0, 0.075):  # merlons on the pauldron cap
            mb.box(f"{side}UpperArm", steel, ua + Vector((0.03 * sx + dx * sx * 1.2, 0, 0.165)), (0.055, 0.055, 0.07), bevel=0.006)

    # -- cuirass, backplate, gorget ----------------------------------------------------------------
    mb.sphere("UpperChest", steel, (0, -0.075 * S, z(1.40)), (0.265, 0.135, 0.2), segs=14, rings=8)
    mb.sphere("Chest", steel, (0, -0.062 * S, z(1.245)), (0.22, 0.115, 0.125), segs=12, rings=6)
    mb.sphere("UpperChest", steel, (0, 0.075 * S, z(1.39)), (0.255, 0.13, 0.19), segs=12, rings=7)
    mb.box("UpperChest", accent, (0, -0.205, z(1.40)), (0.035, 0.012, 0.3), bevel=0.004)  # centre ridge
    mb.cyl("Neck", steel, (0, 0, J["Neck"].z + 0.01), 0.14, 0.115, 0.1, segs=10)         # bevor / gorget
    mb.cyl("Neck", steel, (0, 0, J["Neck"].z + 0.065), 0.15, 0.15, 0.02, segs=10, caps=False)

    # -- great helm with a battlement crown ----------------------------------------------------------
    hc = (J["Head"] + T["Head"]) * 0.5
    mb.cyl("Head", steel, hc + Vector((0, 0, -0.005)), 0.18, 0.168, 0.34, segs=12)
    mb.cyl("Head", steel, hc + Vector((0, 0, 0.175)), 0.172, 0.172, 0.03, segs=12)                 # crown rim
    mb.box("Head", ember, hc + Vector((0, -0.172, 0.025)), (0.2, 0.02, 0.026))                       # eye slit
    mb.box("Head", steel, hc + Vector((0, -0.178, 0.0)), (0.034, 0.02, 0.32), bevel=0.004)           # nasal bar
    mb.box("Head", steel, hc + Vector((0, -0.176, 0.045)), (0.22, 0.02, 0.018), bevel=0.004)         # brow
    for k in range(5):  # breathing slits
        mb.box("Head", leather, hc + Vector((0.05 * (k - 2) * 0.9, -0.17, -0.1)), (0.014, 0.014, 0.05))
    for k in range(8):  # merlons
        a = math.radians(45 * k)
        mb.box("Head", steel, hc + Vector((math.sin(a) * 0.15, math.cos(a) * 0.15, 0.225)), (0.09, 0.07, 0.085),
               rot=(0, 0, -math.degrees(a)), bevel=0.006)
    mb.cyl("Head", accent, hc + Vector((0, 0, 0.2)), 0.158, 0.158, 0.012, segs=12, caps=False)
    body = mb.build(arm)

    # -- WARHAMMER (WeaponSocket_R) -------------------------------------------------------------------
    wood = materials.get_material("Rook_Wood", (0.22, 0.14, 0.09), kind="wood", roughness=0.8, uv_m=0.5)
    hb = MeshBuilder("Rook_Warhammer", [steel, wood, leather, accent, ember], skinned=False)
    x = HAMMER_X
    bottom, top = 0.5 * S, 1.78 * S
    hb.cyl(None, wood, (x, 0, (bottom + top) * 0.5), 0.034, 0.03, top - bottom, segs=8)               # haft
    hb.cyl(None, leather, (x, 0, 0.98 * S), 0.04, 0.04, 0.24, segs=8)                                 # grip wrap
    hb.cone(None, steel, (x, 0, bottom - 0.05), 0.04, 0.12, rot=(180, 0, 0), segs=6)                  # butt spike
    for dz in (0.7 * S, 1.4 * S):
        hb.cyl(None, steel, (x, 0, dz), 0.045, 0.045, 0.03, segs=8)
    hz = top + 0.04
    hb.box(None, steel, (x, -0.115, hz), (0.19, 0.26, 0.27), bevel=0.016)                             # striking block
    hb.box(None, accent, (x, -0.247, hz + 0.115), (0.17, 0.008, 0.02))                                # trim top
    hb.box(None, accent, (x, -0.247, hz - 0.115), (0.17, 0.008, 0.02))                                # trim bottom
    hb.box(None, steel, (x, 0.04, hz), (0.13, 0.12, 0.2), bevel=0.01)                                  # waist of the head
    hb.cone(None, steel, (x, 0.27, hz), 0.085, 0.36, rot=(-90, 0, 0), segs=6)                           # back spike
    hb.cone(None, steel, (x, -0.0, hz + 0.19), 0.045, 0.16, segs=6)                                   # top spike
    for sx in (-1, 1):                                                                                # langets down the haft
        hb.box(None, steel, (x + 0.03 * sx, 0, hz - 0.28), (0.012, 0.03, 0.34))
    hb.sphere(None, ember, (x, -0.25, hz), (0.03, 0.012, 0.03), segs=6, rings=4)
    hammer = hb.build()
    attach_to_bone(hammer, arm, "WeaponSocket_R")

    # -- TOWER SHIELD (ShieldSocket_L) ---------------------------------------------------------------
    sb = MeshBuilder("Rook_TowerShield", [steel, leather, accent, ember], skinned=False)
    sock = J["ShieldSocket_L"]
    w, h = 0.36 * S, 0.56 * S
    outline = [(-w, -h), (w, -h), (w, h * 0.46), (w * 0.78, h * 0.86), (0, h * 1.04), (-w * 0.78, h * 0.86), (-w, h * 0.46)]
    centre = Vector((sock.x + 0.1, sock.y - 0.14, 0.98 * S))
    yaw = 10
    face = centre + Vector((0, 0, 0))
    sb.prism(None, steel, face, outline, 0.045, rot=(90, 0, yaw))
    rim = [(x * 1.07, y * 1.035) for x, y in outline]
    sb.prism(None, leather, face + Vector((0.012 * math.sin(math.radians(yaw)), 0.014, 0)), rim, 0.03, rot=(90, 0, yaw))  # dark rim / back board
    fwd = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0))
    right = Vector((math.cos(math.radians(yaw)), math.sin(math.radians(yaw)), 0))
    sb.sphere(None, steel, face + fwd * 0.04 + Vector((0, 0, 0.1 * S)), (0.11, 0.06, 0.11), rot=(0, 0, yaw), segs=10, rings=6)  # boss
    sb.sphere(None, ember, face + fwd * 0.085 + Vector((0, 0, 0.1 * S)), (0.03, 0.015, 0.03), rot=(0, 0, yaw), segs=6, rings=4)
    sb.box(None, accent, face + fwd * 0.026 + Vector((0, 0, -0.04 * S)), (0.05, 0.012, 1.0 * S), rot=(0, 0, yaw))  # vertical band
    sb.box(None, accent, face + fwd * 0.026 + Vector((0, 0, 0.18 * S)), (0.5 * S, 0.012, 0.05), rot=(0, 0, yaw))  # cross band
    for dx, dz in ((-0.3, 0.38), (0.3, 0.38), (-0.3, -0.45), (0.3, -0.45)):
        sb.sphere(None, steel, face + fwd * 0.03 + right * dx * S + Vector((0, 0, dz * S)), (0.025, 0.02, 0.025), segs=6, rings=4)
    sb.box(None, leather, face - fwd * 0.04 + Vector((0, 0, 0.0)), (0.07, 0.03, 0.4), rot=(0, 0, yaw))             # arm strap (back)
    shield = sb.build()
    attach_to_bone(shield, arm, "ShieldSocket_L")
    return {"body": body, "props": [hammer, shield]}
