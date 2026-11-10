"""PAWN - agile spearman. Light armour: quilted leather gambeson, one steel pauldron, leather
bracers, open helm with nasal, tabard (team Accent), scarf. Long spear on WeaponSocket_R.

Also hosts small body-building helpers that knight.py reuses (height_weights, torso, limb_tubes, ...).

Spear rest pose: shaft passes through the right hand (grip) and is carried tilted, tip forward-up
at SPEAR_ELEVATION degrees, so it clears the forearm and a left hand can reach the shaft in front
of the right. Animations that thrust should rotate the arm/hand so the shaft points at the target.
"""
from __future__ import annotations

import math

from mathutils import Vector

from .. import materials, modeling

NAME = "pawn"
PROPORTIONS = dict(scale=0.94, shoulder_width=0.95, hip_width=0.95)
SPEAR_ELEVATION = 50.0
STYLE = dict(
    weapon="spear", offhand="none", two_handed=True,
    # rest direction of the weapon axis in armature space (character faces -Y, up is +Z)
    weapon_axis=(0.0, -math.cos(math.radians(SPEAR_ELEVATION)), math.sin(math.radians(SPEAR_ELEVATION))),
    weapon_length=2.23, grip_from_butt=0.75,
)


# ---------------------------------------------------------------- shared helpers
def jc(J, name, t=0.5):
    """Point at fraction t from a bone's head to its tail."""
    h, tl = J[name]
    return h + (tl - h) * t


def height_weights(J, names):
    """Skin weights from height: blend between the named bones' mid-heights."""
    mids = [(n, (J[n][0].z + J[n][1].z) * 0.5) for n in names]

    def fn(co):
        z = co.z
        if z <= mids[0][1]:
            return {mids[0][0]: 1.0}
        if z >= mids[-1][1]:
            return {mids[-1][0]: 1.0}
        for (n0, z0), (n1, z1) in zip(mids, mids[1:]):
            if z0 <= z <= z1:
                t = (z - z0) / (z1 - z0)
                return {n0: 1.0 - t, n1: t}
        return {mids[-1][0]: 1.0}
    return fn


def torso(mb, mat, J, s, sw, levels, bones=("Hips", "Spine", "Chest", "UpperChest"), segs=12):
    """Closed elliptical loft. levels = [(z, half_width, half_depth, y_centre), ...] in base metres."""
    rings = [(Vector((0, cy * s, z * s)), Vector((rx * sw * s, 0, 0)), Vector((0, ry * s, 0)))
             for z, rx, ry, cy in levels]
    mb.ring_loft(mat, rings, segs, height_weights(J, bones))


def limb_tubes(mb, arm_mat, leg_mat, J, s, arm_r, leg_r, segs=8):
    """Skinned sleeves and trousers following the arm / leg bone chains."""
    for side in ("Left", "Right"):
        a = [(f"{side}UpperArm", J[f"{side}UpperArm"][0]), (f"{side}LowerArm", J[f"{side}LowerArm"][0]),
             (f"{side}Hand", J[f"{side}Hand"][0]), (f"{side}Hand", J[f"{side}Hand"][1])]
        mb.tube(arm_mat, a, [r * s for r in arm_r], segs=segs)
        l = [(f"{side}UpperLeg", J[f"{side}UpperLeg"][0]), (f"{side}LowerLeg", J[f"{side}LowerLeg"][0]),
             (f"{side}Foot", J[f"{side}Foot"][0]), (f"{side}Foot", J[f"{side}Foot"][1])]
        mb.tube(leg_mat, l, [r * s for r in leg_r], segs=segs)


def _rx(theta_deg, v):
    c, sn = math.cos(math.radians(theta_deg)), math.sin(math.radians(theta_deg))
    return Vector((v.x, v.y * c - v.z * sn, v.y * sn + v.z * c))


class AxisFrame:
    """Local frame for a held weapon: local z runs along the weapon axis (elevation above the
    horizontal, tipped toward -Y/forward), local x is sideways, local y is thickness."""

    def __init__(self, grip, elevation_deg):
        self.grip = Vector(grip)
        self.theta = 90.0 - elevation_deg  # Rx(theta) maps local +Z onto the weapon axis

    def pos(self, x=0.0, y=0.0, z=0.0):
        return self.grip + _rx(self.theta, Vector((x, y, z)))

    @property
    def rot(self):
        return (self.theta, 0, 0)

    @property
    def flat_rot(self):
        """For prisms whose outline is (side, along-axis)."""
        return (self.theta + 90.0, 0, 0)


# ---------------------------------------------------------------- materials
def make_materials():
    p = "Pawn_"
    steel = materials.get_material(p + "Steel", (0.62, 0.64, 0.68), "steel", metallic=0.45, roughness=0.55, uv_m=0.5, seed=11)
    leather = materials.get_material(p + "Leather", (0.30, 0.19, 0.11), "leather", metallic=0.0, roughness=0.85, uv_m=0.4, seed=12)
    cloth = materials.get_material(p + "Cloth", (0.34, 0.31, 0.25), "cloth", metallic=0.0, roughness=0.95, uv_m=0.3, seed=13)
    skin = materials.get_material(p + "Skin", (0.55, 0.40, 0.32), None, metallic=0.0, roughness=0.8)
    accent = materials.get_material(p + "Accent", (0.46, 0.34, 0.13), None, metallic=0.0, roughness=0.7)
    wood = materials.get_material(p + "Wood", (0.36, 0.23, 0.13), "wood", metallic=0.0, roughness=0.75, uv_m=0.4, seed=14)
    return dict(steel=steel, leather=leather, cloth=cloth, skin=skin, accent=accent, wood=wood)


# ---------------------------------------------------------------- build
def build(arm, joints):
    J = joints
    s = PROPORTIONS["scale"]
    sw = PROPORTIONS["shoulder_width"]
    M = make_materials()
    st, le, cl, sk, ac = M["steel"], M["leather"], M["cloth"], M["skin"], M["accent"]
    mb = modeling.MeshBuilder("Pawn_Body", [le, st, cl, sk, ac])

    # --- gambeson torso (leather), sleeves and trousers (cloth)
    torso(mb, le, J, s, sw, [(0.88, .15, .105, 0), (1.0, .135, .095, 0), (1.12, .14, .10, 0), (1.27, .18, .12, -.01),
                             (1.40, .20, .125, -.01), (1.48, .17, .105, 0), (1.53, .075, .07, 0)])
    limb_tubes(mb, cl, cl, J, s, arm_r=[.058, .047, .040, .032], leg_r=[.095, .066, .050, .042])

    # --- belt, pouch, cross strap
    belt = height_weights(J, ("Hips", "Spine"))
    mb.ring_loft(le, [(Vector((0, 0, 1.0 * s)), Vector((.142 * sw * s, 0, 0)), Vector((0, .103 * s, 0))),
                      (Vector((0, 0, 1.06 * s)), Vector((.142 * sw * s, 0, 0)), Vector((0, .103 * s, 0)))], 12,
                 lambda co: {"Hips": 1.0})
    mb.box("Hips", ac, (0, -.108 * s, 1.03 * s), (.05 * s, .018 * s, .045 * s))
    mb.box("Hips", le, (.14 * sw * s, -.05 * s, .98 * s), (.07 * s, .09 * s, .09 * s), bevel=.006)
    mb.box("Chest", le, (0, -.135 * s, 1.30 * s), (.05 * s, .014 * s, .46 * s), rot=(0, 32, 0),
           weights=height_weights(J, ("Hips", "Spine", "Chest", "UpperChest")))

    # --- tabard (Accent, team tint) front and back, scarf
    tab = height_weights(J, ("Hips", "Spine"))
    mb.box("Hips", ac, (0, -.122 * s, 0.93 * s), (.25 * s, .016 * s, .50 * s), weights=tab)
    mb.box("Hips", ac, (0, .118 * s, 0.93 * s), (.25 * s, .016 * s, .50 * s), weights=tab)
    mb.box("Hips", le, (0, -.127 * s, .70 * s), (.26 * s, .014 * s, .04 * s), weights=tab)
    mb.box("Hips", le, (0, .123 * s, .70 * s), (.26 * s, .014 * s, .04 * s), weights=tab)
    mb.ring_loft(cl, [(Vector((0, 0, 1.50 * s)), Vector((.10 * s, 0, 0)), Vector((0, .09 * s, 0))),
                      (Vector((0, 0, 1.56 * s)), Vector((.075 * s, 0, 0)), Vector((0, .07 * s, 0)))], 10,
                 height_weights(J, ("UpperChest", "Neck")))
    mb.box("UpperChest", ac, (.06 * s, .115 * s, 1.30 * s), (.07 * s, .014 * s, .36 * s), rot=(8, 0, -6))

    # --- shoulder: one steel pauldron (left), leather pad (right)
    lu = J["LeftUpperArm"][0]
    mb.shell("LeftUpperArm", st, lu + Vector((.015 * s, 0, .03 * s)), .125 * s, 175, .21 * s, thickness=.022 * s,
             rot=(90, 20, 0), segs=7)
    mb.shell("LeftUpperArm", st, lu + Vector((.02 * s, 0, -.03 * s)), .115 * s, 165, .19 * s, thickness=.02 * s,
             rot=(90, 22, 0), segs=6)
    mb.sphere("RightUpperArm", le, J["RightUpperArm"][0] + Vector((-.01 * s, 0, .02 * s)), (.07 * s, .08 * s, .06 * s), segs=8, rings=5)

    # --- bracers, gloves, boots
    for side in ("Left", "Right"):
        lw = J[f"{side}LowerArm"]
        mb.cyl(f"{side}LowerArm", le, lw[0] + (lw[1] - lw[0]) * 0.55, .053 * s, .056 * s, .17 * s, segs=8)
        h = J[f"{side}Hand"]
        mb.box(f"{side}Hand", le, h[0] + (h[1] - h[0]) * 0.55, (.075 * s, .06 * s, .10 * s), bevel=.008)
        ll = J[f"{side}LowerLeg"]
        mb.cyl(f"{side}LowerLeg", le, ll[0] + (ll[1] - ll[0]) * 0.68, .052 * s, .07 * s, .30 * s, segs=8)
        f = J[f"{side}Foot"]
        mb.box(f"{side}Foot", le, (f[0].x, (f[0].y + f[1].y) * 0.5 - .02 * s, .055 * s), (.095 * s, .27 * s, .085 * s), bevel=.012)

    # --- head: neck, face, open helm with nasal, cheeks, neck guard, eyes
    hc = jc(J, "Head", 0.52)
    mb.cyl("Neck", sk, jc(J, "Neck", 0.5), .046 * s, .05 * s, .12 * s, segs=8)
    mb.sphere("Head", sk, hc + Vector((0, -.01 * s, -.012 * s)), (.09 * s, .10 * s, .115 * s), segs=10, rings=7)
    mb.sphere("Head", st, hc + Vector((0, .006 * s, .035 * s)), (.122 * s, .138 * s, .098 * s), segs=12, rings=7)
    mb.box("Head", st, hc + Vector((0, -.112 * s, -.03 * s)), (.018 * s, .012 * s, .095 * s))
    mb.box("Head", st, hc + Vector((.092 * s, -.03 * s, -.02 * s)), (.014 * s, .08 * s, .09 * s), rot=(0, 0, 12), mirror=True)
    mb.box("Head", le, hc + Vector((0, .11 * s, -.06 * s)), (.20 * s, .04 * s, .09 * s), bevel=.006)
    mb.box("Head", le, hc + Vector((.036 * s, -.1 * s, .002 * s)), (.026 * s, .01 * s, .012 * s), mirror=True)
    mb.cyl("Head", ac, hc + Vector((0, 0, .135 * s)), .012 * s, .008 * s, .06 * s, segs=6)

    body = mb.build(arm)

    # --- spear prop
    sp = AxisFrame(J["WeaponSocket_R"][0], SPEAR_ELEVATION)
    pm = modeling.MeshBuilder("Pawn_Spear", [M["wood"], st, le, ac], skinned=False)
    pm.cyl(None, M["wood"], sp.pos(z=.2), .021, .021, 1.9, rot=sp.rot, segs=8)       # shaft -0.75 .. 1.15
    pm.cyl(None, le, sp.pos(z=0.0), .027, .027, .26, rot=sp.rot, segs=8)             # wrapped grip
    pm.cyl(None, le, sp.pos(z=-.30), .024, .024, .06, rot=sp.rot, segs=8)
    pm.cyl(None, st, sp.pos(z=1.2), .035, .026, .12, rot=sp.rot, segs=8)             # socket
    pm.prism(None, st, sp.grip, [(-.04, 1.25), (.04, 1.25), (.052, 1.33), (0.0, 1.50), (-.052, 1.33)],
             .014, rot=sp.flat_rot)                                                  # leaf blade
    pm.prism(None, st, sp.grip, [(-.006, 1.27), (.006, 1.27), (.006, 1.44), (-.006, 1.44)], .024, rot=sp.flat_rot)  # midrib
    pm.cone(None, st, sp.pos(z=-.80), .028, .1, rot=(sp.theta + 180, 0, 0), segs=8)  # butt spike
    pm.prism(None, ac, sp.grip, [(-.014, 1.28), (-.014, 1.14), (-.22, 1.19)], .006, rot=sp.flat_rot)  # pennon
    spear = pm.build()
    modeling.attach_to_bone(spear, arm, "WeaponSocket_R")
    return {"body": body, "props": [spear]}
