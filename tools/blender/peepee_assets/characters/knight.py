"""KNIGHT - heavily armoured duelist. Full plate (great helm with visor slit and a horse-mane
inspired crest, cuirass with a central ridge, tassets, big pauldrons, couters, vambraces,
gauntlets, cuisses, poleyns, greaves, sabatons), longsword on WeaponSocket_R and a kite shield on
ShieldSocket_L. The shield face and the crest mane use the team-tint `Knight_Accent` material.

Sword rest pose: blade points forward and slightly up (SWORD_ELEVATION), perpendicular to the
hanging forearm, so raising the arm 90 degrees forward brings the blade upright (guard) and a
forward-swinging arm cuts through the target. The shield sits on the forearm, face forward.
"""
from __future__ import annotations

import math

from mathutils import Vector

from .. import materials, modeling
from .pawn import AxisFrame, height_weights, jc, limb_tubes, torso

NAME = "knight"
PROPORTIONS = dict(scale=1.04, shoulder_width=1.10, hip_width=1.06)
SWORD_ELEVATION = 25.0
STYLE = dict(
    weapon="sword_shield", offhand="shield", two_handed=False,
    weapon_axis=(0.0, -math.cos(math.radians(SWORD_ELEVATION)), math.sin(math.radians(SWORD_ELEVATION))),
    weapon_length=1.3, grip_from_butt=0.15,
)


def make_materials():
    k = "Knight_"
    steel = materials.get_material(k + "Steel", (0.60, 0.62, 0.67), "steel", metallic=0.5, roughness=0.5, uv_m=0.5, seed=21)
    cloth = materials.get_material(k + "Cloth", (0.17, 0.18, 0.24), "cloth", roughness=0.95, uv_m=0.3, seed=22)
    leather = materials.get_material(k + "Leather", (0.20, 0.13, 0.09), "leather", roughness=0.85, uv_m=0.4, seed=23)
    accent = materials.get_material(k + "Accent", (0.52, 0.40, 0.14), None, roughness=0.7)
    return dict(steel=steel, cloth=cloth, leather=leather, accent=accent)


def build(arm, joints):
    J = joints
    s = PROPORTIONS["scale"]
    sw = PROPORTIONS["shoulder_width"]
    M = make_materials()
    st, cl, le, ac = M["steel"], M["cloth"], M["leather"], M["accent"]
    mb = modeling.MeshBuilder("Knight_Body", [st, cl, le, ac])

    # --- arming doublet, sleeves, hose (cloth) under the plate
    torso(mb, cl, J, s, sw, [(0.88, .18, .12, 0), (1.0, .165, .11, 0), (1.12, .17, .115, 0), (1.27, .21, .14, -.01),
                             (1.40, .235, .15, -.015), (1.48, .20, .12, 0), (1.53, .085, .075, 0)])
    limb_tubes(mb, cl, cl, J, s, arm_r=[.066, .054, .046, .036], leg_r=[.10, .072, .055, .046])

    # --- cuirass (skinned plate) with ridge, gorget, belt
    torso(mb, st, J, s, sw, [(1.14, .192, .13, 0), (1.22, .215, .152, -.018), (1.32, .258, .172, -.03),
                             (1.42, .262, .166, -.024), (1.49, .225, .128, -.005)])
    mb.box("Chest", st, (0, -.196 * s, 1.31 * s), (.04 * s, .05 * s, .30 * s), rot=(-6, 0, 0), bevel=.008,
           weights=height_weights(J, ("Spine", "Chest", "UpperChest")))
    torso(mb, st, J, s, sw, [(1.49, .135, .115, 0), (1.56, .092, .08, 0)], bones=("Chest", "UpperChest", "Neck"), segs=10)
    mb.ring_loft(le, [(Vector((0, 0, 1.02 * s)), Vector((.185 * sw * s, 0, 0)), Vector((0, .125 * s, 0))),
                      (Vector((0, 0, 1.09 * s)), Vector((.185 * sw * s, 0, 0)), Vector((0, .125 * s, 0)))], 12,
                 lambda co: {"Hips": 1.0})
    mb.box("Hips", ac, (0, -.128 * s, 1.055 * s), (.07 * s, .02 * s, .06 * s), bevel=.005)

    # --- tassets (rigid to Hips) and surcoat panel (team Accent)
    for i, (z, w) in enumerate(((.98, .30), (.88, .28), (.78, .26))):
        mb.box("Hips", st, (0, -.14 * s, z * s), (w * sw * s, .022 * s, .105 * s), rot=(-6 - 3 * i, 0, 0), bevel=.006)
    for i, z in enumerate((.97, .86)):
        mb.box("Hips", st, (.21 * sw * s, -.02 * s, z * s), (.025 * s, .17 * s, .105 * s), rot=(0, -5, 0), bevel=.006, mirror=True)
    mb.box("Hips", ac, (0, .128 * s, .86 * s), (.24 * s, .016 * s, .56 * s), weights=height_weights(J, ("Hips", "Spine")))

    # --- pauldrons, rerebraces, couters, vambraces, gauntlets (mirrored)
    lu = J["LeftUpperArm"][0]
    mb.shell("LeftUpperArm", st, lu + Vector((.035 * s, 0, -.025 * s)), .125 * s, 165, .26 * s, thickness=.026 * s,
             rot=(90, 28, 0), segs=8, mirror=True)
    mb.shell("LeftUpperArm", st, lu + Vector((.05 * s, 0, -.075 * s)), .125 * s, 150, .24 * s, thickness=.022 * s,
             rot=(90, 34, 0), segs=8, mirror=True)
    mb.shell("LeftUpperArm", st, lu + Vector((.065 * s, 0, -.12 * s)), .12 * s, 135, .22 * s, thickness=.02 * s,
             rot=(90, 40, 0), segs=8, mirror=True)
    for side in ("Left", "Right"):
        ua, la, hd = J[f"{side}UpperArm"], J[f"{side}LowerArm"], J[f"{side}Hand"]
        mb.cyl(f"{side}UpperArm", st, ua[0] + (ua[1] - ua[0]) * 0.55, .068 * s, .07 * s, .20 * s, segs=10)
        mb.sphere(f"{side}LowerArm", st, la[0], (.07 * s, .07 * s, .07 * s), segs=8, rings=5)
        mb.cyl(f"{side}LowerArm", st, la[0] + (la[1] - la[0]) * 0.55, .052 * s, .07 * s, .24 * s, segs=10)
        mb.box(f"{side}Hand", st, hd[0] + (hd[1] - hd[0]) * 0.5, (.09 * s, .07 * s, .12 * s), bevel=.012)
        mb.box(f"{side}Hand", le, hd[0] + (hd[1] - hd[0]) * 0.1, (.085 * s, .065 * s, .04 * s))
        # legs: cuisse, poleyn (knee), greave, sabaton
        ul, ll, ft = J[f"{side}UpperLeg"], J[f"{side}LowerLeg"], J[f"{side}Foot"]
        mb.cyl(f"{side}UpperLeg", st, ul[0] + (ul[1] - ul[0]) * 0.42, .098 * s, .106 * s, .30 * s, segs=10)
        mb.sphere(f"{side}LowerLeg", st, ll[0] + Vector((0, -.025 * s, 0)), (.08 * s, .075 * s, .075 * s), segs=8, rings=5)
        mb.cyl(f"{side}LowerLeg", st, ll[0] + (ll[1] - ll[0]) * 0.55, .06 * s, .08 * s, .36 * s, segs=10)
        mb.box(f"{side}Foot", st, (ft[0].x, (ft[0].y + ft[1].y) * 0.5 - .03 * s, .05 * s), (.105 * s, .30 * s, .085 * s), bevel=.014)
        mb.cone(f"{side}Foot", st, (ft[0].x, ft[1].y - .07 * s, .035 * s), .04 * s, .09 * s, rot=(90, 0, 0), segs=6)

    # --- great helm: dome, visor slit, breaths, reinforcement bands, base ring
    hc = jc(J, "Head", 0.52)
    mb.cyl("Neck", cl, jc(J, "Neck", 0.5), .05 * s, .055 * s, .12 * s, segs=8)
    mb.sphere("Head", st, hc + Vector((0, 0, -.012 * s)), (.138 * s, .152 * s, .14 * s), segs=14, rings=8)
    mb.cyl("Head", st, hc + Vector((0, 0, -.115 * s)), .142 * s, .14 * s, .06 * s, segs=14)
    mb.box("Head", le, hc + Vector((0, -.15 * s, .015 * s)), (.17 * s, .03 * s, .024 * s))
    mb.box("Head", st, hc + Vector((0, -.153 * s, -.055 * s)), (.026 * s, .018 * s, .18 * s), bevel=.003)
    mb.box("Head", st, hc + Vector((0, -.152 * s, .05 * s)), (.2 * s, .02 * s, .026 * s))
    for i in range(4):
        mb.box("Head", le, hc + Vector((.065 * s, -.145 * s, (-.04 - .026 * i) * s)), (.012 * s, .02 * s, .012 * s), mirror=True)

    # --- horse-mane crest: steel ridge + Accent fins flowing back
    top = hc + Vector((0, 0, .105 * s))
    mb.box("Head", st, top + Vector((0, 0, -.005 * s)), (.022 * s, .30 * s, .026 * s), bevel=.004)
    for i in range(9):
        y = (-.13 + .033 * i) * s
        h = (.035 + .03 * math.sin(math.pi * i / 8.0) + (.01 if i > 5 else 0.0)) * s
        sweep = (.01 + .012 * i) * s  # fins lean backward (+Y) toward the tail
        mb.prism("Head", ac, top + Vector((0, y, 0)),
                 [(-.026 * s, 0), (.026 * s, 0), (.026 * s + sweep, h), (-.01 * s + sweep, h + .02 * s)],
                 .016 * s, rot=(90, 0, 90))
    for i in range(3):  # tail strands hanging behind the helm
        mb.prism("Head", ac, hc + Vector((0, (.16 + .02 * i) * s, (.06 - .06 * i) * s)),
                 [(-.02 * s, 0), (.02 * s, 0), (.02 * s, -.14 * s), (-.01 * s, -.17 * s)], .014 * s, rot=(90, 0, 90))

    body = mb.build(arm)

    # --- longsword prop
    sf = AxisFrame(J["WeaponSocket_R"][0], SWORD_ELEVATION)
    pm = modeling.MeshBuilder("Knight_Sword", [st, le, ac], skinned=False)
    pm.prism(None, st, sf.grip, [(-.032, .12), (.032, .12), (.03, .95), (0.0, 1.22), (-.03, .95)], .009, rot=sf.flat_rot)  # blade
    pm.prism(None, st, sf.grip, [(-.007, .14), (.007, .14), (.007, 1.0), (-.007, 1.0)], .016, rot=sf.flat_rot)            # fuller ridge
    pm.box(None, st, sf.pos(z=.115), (.25, .034, .03), rot=sf.rot, bevel=.004)                                              # cross-guard
    pm.cyl(None, le, sf.pos(z=-.02), .019, .019, .22, rot=sf.rot, segs=8)                                                   # grip
    pm.sphere(None, ac, sf.pos(z=-.15), (.034, .034, .034), segs=8, rings=5)                                                # pommel
    sword = pm.build()
    modeling.attach_to_bone(sword, arm, "WeaponSocket_R")

    # --- kite shield on the left forearm (face forward, -Y)
    sock = J["ShieldSocket_L"][0]
    cx, cy, cz = sock.x + .03 * s, sock.y - .105 * s, sock.z - .03 * s
    kite = [(-.20, .30), (.20, .30), (.225, .12), (.13, -.2), (0, -.44), (-.13, -.2), (-.225, .12)]
    rim = [(x * 1.07, y * 1.05 + (.01 if y > 0 else 0)) for x, y in kite]
    shm = modeling.MeshBuilder("Knight_Shield", [ac, st, le], skinned=False)
    shm.prism(None, st, (cx, cy + .014, cz), rim, .022, rot=(90, 0, 0))
    shm.prism(None, ac, (cx, cy, cz), kite, .03, rot=(90, 0, 0))
    shm.box(None, st, (cx, cy - .024, cz - .02), (.034, .012, .66), bevel=.003)
    shm.box(None, st, (cx, cy - .024, cz + .12), (.34, .012, .034), bevel=.003)
    shm.sphere(None, st, (cx, cy - .036, cz + .02), (.058, .03, .058), segs=10, rings=6)
    shm.box(None, le, (cx, cy + .035, cz + .02), (.05, .03, .30))
    shield = shm.build()
    modeling.attach_to_bone(shield, arm, "ShieldSocket_L")
    return {"body": body, "props": [sword, shield]}
