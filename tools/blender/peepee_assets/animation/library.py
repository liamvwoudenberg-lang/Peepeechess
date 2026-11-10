"""Animation library: every clip in spec.CLIP_NAMES for every class.

Public contract (stable):
    add_all_clips(armature, cls: str, style: dict, joints: dict) -> None

All clips are FK/IK-solved from authored hand/weapon targets (see kinematics.py, poses.py,
clips.py) and keyed with skeleton.key_pose: rotation tracks on the deform bones plus Hips location.
Frame counts come from spec.clip_frames(cls); 1 frame == 1 simulation tick (60 fps).

STYLE schema (a character module's STYLE dict; EVERY key is optional - defaults come from
CLASS_DEFAULTS[cls] and then DEFAULT_STYLE):

  grip            how the weapons are held; picks the stance and the attack kit:
                    "spear2"        two-handed spear (right hand rear, left hand slides on the shaft)
                    "sword_shield"  one-handed sword (right) + shield on the left forearm
                    "staff2"        two-handed staff
                    "hammer_shield" one-handed warhammer (right) + tower shield (left)
                    "dual"          a blade in each hand (right = WeaponSocket_R, left = WeaponSocket_L)
                    "sword1"        one-handed longsword, free left hand
  weapon_axis     (x,y,z) direction the RIGHT-hand prop's business end (spear tip / blade tip /
                  hammer head) points in the REST pose, armature coords (Z up, character faces -Y).
                  Default (0,0,1) = tip up, as modelled standing in the hand.
  weapon2_axis    same for the LEFT-hand prop ("dual" only). Default (0,0,1).
  shield_normal   (x,y,z) outward face normal of the shield in the rest pose. Default (0,-1,0)
                  (face toward the front). The block pose twists the forearm so this faces forward.
  offhand_grip    metres along the shaft (toward the tip) where the left hand holds a two-handed
                  weapon. Default 0.5. It is shortened automatically if the arm cannot reach.
  stance          half-width of the feet in metres (default 0.2).
  arm_clear       extra outward elbow clearance, 0..1 (armour bulk: 0 slim, 1 very bulky). Default 0.4.
  swagger         locomotion amplitude multiplier (0.7 heavy ... 1.2 agile). Default 1.0.
  power           attack body-motion multiplier (lean, step, torso twist). Default 1.0.

Weapons are authored "tip up" in the rest pose. The solver rotates the wrist so the weapon points
where the animation wants (e.g. forward for a thrust), so the prop only needs to be modelled upright
at the socket, with its grip at the socket bone's head.
"""
from __future__ import annotations

from .. import export, skeleton
from . import spec

DEFAULT_STYLE = {
    "grip": "sword1",
    "weapon_axis": (0.0, 0.0, 1.0),
    "weapon2_axis": (0.0, 0.0, 1.0),
    "shield_normal": (0.0, -1.0, 0.0),
    "offhand_grip": 0.5,
    "stance": 0.2,
    "arm_clear": 0.4,
    "swagger": 1.0,
    "power": 1.0,
}

CLASS_DEFAULTS = {
    "pawn": {"grip": "spear2", "offhand_grip": 0.55, "stance": 0.2, "arm_clear": 0.25, "swagger": 1.15, "power": 1.0},
    "knight": {"grip": "sword_shield", "stance": 0.24, "arm_clear": 0.6, "swagger": 0.95, "power": 1.05},
    "bishop": {"grip": "staff2", "offhand_grip": 0.5, "stance": 0.19, "arm_clear": 0.4, "swagger": 1.0, "power": 0.9},
    "rook": {"grip": "hammer_shield", "stance": 0.3, "arm_clear": 1.0, "swagger": 0.75, "power": 1.2},
    "queen": {"grip": "dual", "stance": 0.19, "arm_clear": 0.3, "swagger": 1.2, "power": 1.0},
    "king": {"grip": "sword1", "stance": 0.25, "arm_clear": 0.7, "swagger": 0.85, "power": 1.1},
}


def resolve_style(cls: str, style: dict | None) -> dict:
    out = dict(DEFAULT_STYLE)
    out.update(CLASS_DEFAULTS.get(cls, {}))
    out.update(style or {})
    return out


def add_all_clips(arm, cls, style, joints):
    try:
        from . import clips
    except ImportError:  # clips module not written yet: keep the pipeline runnable
        frames = spec.clip_frames(cls)

        def idle(a):
            skeleton.key_pose(a, "Hips", 0, location=(0, 0, 0))
            skeleton.key_pose(a, "Hips", frames["idle"], location=(0, 0, 0))
        export.add_clip(arm, "idle", idle, frames["idle"])
        return
    clips.add_all(arm, cls, resolve_style(cls, style), joints)
