"""Pose model: a pose is a plain dict of authored targets (hand positions, weapon directions, torso /
leg angles). `solve()` turns it into bone rotations (via kinematics) and returns what
skeleton.key_pose needs. Poses blend componentwise, so attacks can be authored as a few key
poses and sampled densely (every sample is IK-solved, so arcs stay on target).

Units: degrees and metres. Character frame: out = away from the body centre for that arm,
fwd = forward, up = up. Weapon direction (az, el): az 0 = forward, positive toward the character's
LEFT; el = elevation above horizontal (90 = straight up, >90 tips back over the shoulder).
"""
from __future__ import annotations

import copy
import math

from mathutils import Matrix, Vector

from .. import skeleton
from . import kinematics as K

ANIM_BONES = [b for b in skeleton.DEFORM_BONES if b != "Root"]
SPINE_W = (("Spine", 0.30), ("Chest", 0.35), ("UpperChest", 0.35))
NECK_W = (("Neck", 0.4), ("Head", 0.6))
SOCKET_REST = {"R": "WeaponSocket_R", "L": "WeaponSocket_L"}


def blank_pose():
    return {
        "hips": (0.0, 0.0, 0.0),        # (right, fwd, up) metres, added after ground fitting
        "pelvis": (0.0, 0.0, 0.0),      # Hips own rotation (pitch, roll, yaw)
        "torso": (0.0, 0.0, 0.0),
        "head": (0.0, 0.0, 0.0),
        "legR": (0.0, 0.0, 0.0, 0.0),   # (swing fwd +, spread out +, knee flex +, toe down +)
        "legL": (0.0, 0.0, 0.0, 0.0),
        "armR": {"hand": (0.06, 0.0, -0.54), "pole": None, "wpn": None, "shield": None, "twist": 0.0, "follow": 0.0},
        "armL": {"hand": (0.06, 0.0, -0.54), "pole": None, "wpn": None, "shield": None, "twist": 0.0, "follow": 0.0},
        "ground": True,
    }


def over(pose: dict, **kw) -> dict:
    """Copy of `pose` with overrides. Arm dicts merge key by key; everything else replaces."""
    out = copy.deepcopy(pose)
    for key, value in kw.items():
        if key in ("armR", "armL") and isinstance(value, dict):
            out[key].update(value)
        else:
            out[key] = value
    return out


def _lerp(a, b, t):
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return a + (b - a) * t
    if isinstance(a, tuple) and isinstance(b, tuple) and len(a) == len(b):
        return tuple(_lerp(x, y, t) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return {k: _lerp(a[k], b[k], t) if k in b else a[k] for k in a}
    if a is None or b is None:
        # blend from/to "unset" by switching halfway (poses should keep these consistent)
        return b if t >= 0.5 else a
    return b if t >= 0.5 else a


def blend(a: dict, b: dict, t: float) -> dict:
    return _lerp(a, b, t)


def _ease(kind: str, u: float) -> float:
    if kind == "in":
        return u * u
    if kind == "out":
        return 1.0 - (1.0 - u) * (1.0 - u)
    if kind == "lin":
        return u
    return u * u * (3.0 - 2.0 * u)


def sample(keys, t: float) -> dict:
    """keys = [(t, pose, ease_into_this_key), ...] sorted by t. Returns the interpolated pose."""
    if t <= keys[0][0]:
        return keys[0][1]
    for i in range(1, len(keys)):
        t1, p1, ease = keys[i]
        t0, p0, _ = keys[i - 1]
        if t <= t1:
            u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
            return blend(p0, p1, _ease(ease, u))
    return keys[-1][1]


class Solver:
    def __init__(self, joints, style):
        self.kin = K.Kin(joints)
        self.style = style
        self.axis_r = Vector(style["weapon_axis"]).normalized()
        self.axis_l = Vector(style["weapon2_axis"]).normalized()
        self.normal = Vector(style["shield_normal"]).normalized()
        self.reach = self.kin.length("RightUpperArm", "RightLowerArm") + self.kin.length("RightLowerArm", "RightHand")

    # -- legs ------------------------------------------------------------------------------
    def _legs(self, pose, q):
        for side, name in (("R", "Right"), ("L", "Left")):
            swing, spread, knee, toe = pose["leg" + side]
            roll = spread if side == "R" else -spread
            q[f"{name}UpperLeg"] = K.from_pry(-swing, roll, 0)
            q[f"{name}LowerLeg"] = K.from_pry(knee, 0, 0)
            q[f"{name}Foot"] = K.from_pry(toe + swing - knee, 0, 0)

    # -- main --------------------------------------------------------------------------------
    def solve(self, pose: dict):
        kin, style = self.kin, self.style
        q = {}
        q["Hips"] = K.from_pry(*pose["pelvis"])
        for name, w in SPINE_W:
            q[name] = K.from_pry(*(c * w for c in pose["torso"]))
        for name, w in NECK_W:
            q[name] = K.from_pry(*(c * w for c in pose["head"]))
        self._legs(pose, q)

        hips_loc = Vector((0, 0, 0))
        if pose.get("ground", True):
            heads, rots = kin.fk(q, hips_loc)
            sole = min(heads["RightFoot"].z - kin.head["RightFoot"].z, heads["LeftFoot"].z - kin.head["LeftFoot"].z)
            # toe tips can dip below the ground while the ankle is raised: also test the toes
            for n in ("RightToes", "LeftToes"):
                tip = heads[n.replace("Toes", "Foot")] + rots[n.replace("Toes", "Foot")] @ (kin.tail[n] - kin.head[n.replace("Toes", "Foot")])
                sole = min(sole, tip.z - kin.tail[n].z)
            hips_loc = Vector((0, 0, -sole))
        r, f, u = pose["hips"]
        hips_loc = hips_loc + K.cf(r, f, u, "R")

        yaw = pose["torso"][2] + pose["pelvis"][2]
        rt = Matrix.Rotation(math.radians(yaw), 3, "Z")
        bulk = style["arm_clear"]
        for side, name, axis in (("R", "Right", self.axis_r), ("L", "Left", self.axis_l)):
            arm = pose["arm" + side]
            if side == "L" and float(arm.get("follow", 0.0)) > 0.0:
                continue   # handled after the right arm: blends toward the weapon shaft
            heads, rots = kin.fk(q, hips_loc)
            shoulder = heads[f"{name}UpperArm"]
            target = shoulder + rt @ K.cf(*arm["hand"], side)
            pole_out = 0.35 + 0.9 * bulk
            pole = rt @ K.cf(*(arm["pole"] or (pole_out, -0.35, -0.55)), side)
            wpn_dir = wpn_roll = None
            if arm["wpn"] is not None:
                az, el, roll = (arm["wpn"] + (0.0,))[:3]
                wpn_dir = rt @ K.direction(az, el)
                wpn_roll = roll
            normal_dir = None
            if arm["shield"] is not None:
                az, el = arm["shield"]
                normal_dir = rt @ K.direction(az, el)
            kin.solve_arm(name, q, hips_loc, target, pole, axis if wpn_dir is not None else None, wpn_dir,
                          wpn_roll or 0.0, self.normal if normal_dir is not None else None, normal_dir)
            if arm["twist"]:
                lo = f"{name}LowerArm"
                heads, rots = kin.fk(q, hips_loc)
                axis_l = rots[lo] @ kin.rest_dir[lo]
                tw = K.axis_angle(axis_l, arm["twist"])
                up_rot = rots[K.PARENT[lo]]
                q[lo] = up_rot.inverted() @ tw @ rots[lo]
        # left hand follows the right-hand weapon shaft (two-handed grips)
        if float(pose["armL"].get("follow", 0.0)) > 0.0:
            self._follow_shaft(q, hips_loc, rt, pose)
        out = {b: K.to_pry(q[b]) if b in q else (0.0, 0.0, 0.0) for b in ANIM_BONES}
        return out, hips_loc

    def _follow_shaft(self, q, hips_loc, rt, pose):
        kin = self.kin
        heads, rots = kin.fk(q, hips_loc)
        socket = heads["RightHand"] + rots["RightHand"] @ (self.socket_offset("R"))
        d = rots["RightHand"] @ self.axis_r
        s_l = heads["LeftUpperArm"]
        want = self.style["offhand_grip"]
        s = want
        while s > 0.12 and (socket + d * s - s_l).length > self.reach * 0.97:
            s -= 0.03
        target = socket + d * s
        weight = float(pose["armL"].get("follow", 1.0))
        if weight < 1.0:   # blend toward the authored free-hand target (smooth release/grab)
            free = s_l + rt @ K.cf(*pose["armL"]["hand"], "L")
            target = free.lerp(target, weight)
        pole_out = 0.35 + 0.9 * self.style["arm_clear"]
        pole = rt @ K.cf(pole_out, -0.35, -0.55, "L")
        kin.solve_arm("Left", q, hips_loc, target, pole)

    def socket_offset(self, side):
        n = SOCKET_REST[side]
        hand = "RightHand" if side == "R" else "LeftHand"
        return self.kin.head[n] - self.kin.head[hand]
