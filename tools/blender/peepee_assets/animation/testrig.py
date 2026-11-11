"""Minimal visible test rig for clip development (NOT a character): limb tubes, a box torso/head and a
style-appropriate prop on each socket. Used by the animation worker's tests only."""
from __future__ import annotations

from pathlib import Path

from .. import export, materials, modeling, runtime, skeleton
from ..animation import library, spec


def build(cls: str, out: Path, style=None, lods=False):
    runtime.reset_scene()
    arm, joints = skeleton.build_armature("Rig_" + cls)
    mat = materials.get_material("Test_Steel_" + cls, (0.55, 0.57, 0.62), metallic=0.5, roughness=0.5)
    cloth = materials.get_material("Test_Cloth_" + cls, (0.35, 0.18, 0.18), roughness=0.9)
    gold = materials.get_material("Test_Gold_" + cls, (0.8, 0.62, 0.2), metallic=0.8, roughness=0.4)
    mb = modeling.MeshBuilder("Body_" + cls, [mat, cloth, gold])
    J = lambda n: joints[n][0]
    for side in ("Left", "Right"):
        mb.tube(mat, [(f"{side}UpperArm", J(f"{side}UpperArm")), (f"{side}LowerArm", J(f"{side}LowerArm")),
                      (f"{side}Hand", J(f"{side}Hand")), (f"{side}Hand", joints[f"{side}Hand"][1])], [0.055, 0.045, 0.04, 0.035])
        mb.tube(cloth, [(f"{side}UpperLeg", J(f"{side}UpperLeg")), (f"{side}LowerLeg", J(f"{side}LowerLeg")),
                        (f"{side}Foot", J(f"{side}Foot")), (f"{side}Toes", joints[f"{side}Toes"][1])], [0.09, 0.07, 0.05, 0.04])
        mb.box(f"{side}Foot", mat, (J(f"{side}Foot").x, -0.06, 0.05), (0.09, 0.26, 0.08))
    mb.box("Chest", cloth, (0, 0, 1.30), (0.34, 0.2, 0.40), bevel=0.02)
    mb.box("Hips", cloth, (0, 0, 1.00), (0.30, 0.18, 0.18))
    mb.box("Chest", gold, (0, 0, 1.45), (0.46, 0.2, 0.08))
    mb.sphere("Head", mat, (0, 0, 1.72), (0.12, 0.13, 0.14))
    mb.box("Head", gold, (0, -0.11, 1.74), (0.16, 0.03, 0.03))   # visor: marks the FRONT of the face
    body = mb.build(arm)
    style = library.resolve_style(cls, style)
    props = []

    def prop(name, bone, parts):
        pm = modeling.MeshBuilder(name, [mat, gold], skinned=False)
        for kind, args in parts:
            getattr(pm, kind)(None, *args)
        o = pm.build()
        modeling.attach_to_bone(o, arm, bone)
        props.append(o)

    sx = joints["WeaponSocket_R"][0]
    sl = joints["WeaponSocket_L"][0]
    g = style["grip"]
    if g == "spear2":
        prop("Spear", "WeaponSocket_R", [("box", (mat, (sx.x, 0, sx.z + 0.55), (0.035, 0.035, 2.3))), ("cone", (gold, (sx.x, 0, sx.z + 1.85), 0.07, 0.32))])
    elif g == "staff2":
        prop("Staff", "WeaponSocket_R", [("box", (mat, (sx.x, 0, sx.z + 0.45), (0.04, 0.04, 2.0))), ("sphere", (gold, (sx.x, 0, sx.z + 1.5), (0.1, 0.1, 0.1)))])
    elif g in ("sword_shield", "sword1", "dual"):
        prop("Sword", "WeaponSocket_R", [("box", (mat, (sx.x, 0, sx.z + 0.5), (0.06, 0.02, 0.95))), ("box", (gold, (sx.x, 0, sx.z + 0.02), (0.30, 0.04, 0.04)))])
        if g == "dual":
            prop("Sword2", "WeaponSocket_L", [("box", (mat, (sl.x, 0, sl.z + 0.5), (0.06, 0.02, 0.95))), ("box", (gold, (sl.x, 0, sl.z + 0.02), (0.30, 0.04, 0.04)))])
    elif g == "hammer_shield":
        prop("Hammer", "WeaponSocket_R", [("box", (mat, (sx.x, 0, sx.z + 0.4), (0.05, 0.05, 1.1))), ("box", (gold, (sx.x, 0, sx.z + 1.0), (0.12, 0.34, 0.16)))])
    if g in ("sword_shield", "hammer_shield"):
        sh = joints["ShieldSocket_L"][0]
        # face normal = (0,-1,0) (front), matching the documented default STYLE["shield_normal"]
        prop("Shield", "ShieldSocket_L", [("box", (gold, (sh.x + 0.02, sh.y - 0.08, sh.z), (0.34, 0.05, 0.62)))])
    library.add_all_clips(arm, cls, style, joints)
    out.parent.mkdir(parents=True, exist_ok=True)
    return export.export_glb(out, [arm, body] + props)
