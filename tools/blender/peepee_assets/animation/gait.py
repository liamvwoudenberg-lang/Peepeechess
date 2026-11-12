"""Foot-locked locomotion (walk / run / strafe).

The old gait swung the legs like pendulums (FK, a sine of the leg angle). A planted foot then slid backwards at a speed that varied
from zero to about twice its mean over the stance, the swing foot skimmed the floor, and the average stride was nowhere near the
ground speed the game plays the clip at (animation_audit.json "before": implied walk speed 0.7 m/s against a nominal 2.2).

Here every foot follows a trajectory in the character's ground frame and the legs are solved onto it (planar two-bone IK corrected
through forward kinematics, so the pelvis yaw, the hips' sway and bob are all accounted for):

    stance  (phase 0 .. duty)    the foot is flat on the floor and moves BACKWARDS relative to the body at exactly `nominal` m/s
                                 (constant velocity): zero slide when the game plays the clip at speed = actual / nominal
    swing   (phase duty .. 1)    the foot lifts (clearance `lift`), travels forward on a cycloid (zero velocity at both ends) and lands flat

The hips are NOT ground-fitted: their height follows the geometry. At heel strike and toe-off the leg is almost straight (distance
hip-ankle = 0.985 of the leg length), which fixes the lowest the hips must go for the stance excursion S = nominal * duty * T; they rise
over mid-stance (walk: single support) or over the flight phase (run).
"""
from __future__ import annotations

import math

from mathutils import Vector

from . import kinematics as K
from . import spec
from .poses import over

REACH = 0.985          # leg extension at heel strike / toe-off (fraction of l1 + l2)
MID_STANCE_DIP = 0.035  # hips lowering at mid-stance of a walk (knee flex ~ 17 deg)


def _planar_leg(l1, l2, f, u):
    """Swing (deg, + = forward) and knee flex (deg) putting the ankle at (fwd f, up u) relative to the hip joint."""
    d = max(abs(l1 - l2) + 1e-3, min(math.hypot(f, u), (l1 + l2) * 0.998))
    alpha = math.atan2(f, -u)
    beta = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    interior = math.acos(max(-1.0, min(1.0, (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2))))
    return math.degrees(alpha + beta), 180.0 - math.degrees(interior)


def _cycloid(u: float) -> float:
    """0..1 with zero velocity at both ends."""
    return u - math.sin(2.0 * math.pi * u) / (2.0 * math.pi)


class Gait:
    def __init__(self, solver, style):
        self.kin = solver.kin
        self.style = style
        k = self.kin
        self.l1 = k.length("LeftUpperLeg", "LeftLowerLeg")
        self.l2 = k.length("LeftLowerLeg", "LeftFoot")
        self.leg = self.l1 + self.l2
        self.ankle_h = k.head["LeftFoot"].z
        self.hip_z = k.head["LeftUpperLeg"].z
        self.hip_x = abs(k.head["LeftUpperLeg"].x)
        self.foot_x = abs(k.head["LeftFoot"].x)
        self.toe_len = k.head["LeftFoot"].y - k.tail["LeftToes"].y        # ankle -> toe tip, horizontally (armature -Y is forward)

    # ---- one leg onto a target ankle position (armature axes, absolute, floor at z = 0) -------------------------------
    def _solve_leg(self, side, target: Vector, toe: float, hips_loc: Vector, q_hips, roll: float):
        name = "Right" if side == "R" else "Left"
        sign = 1.0 if side == "R" else -1.0
        k = self.kin
        heads, _r = k.fk({"Hips": q_hips}, hips_loc)
        hip0 = heads[f"{name}UpperLeg"]
        af = -(target.y - hip0.y)
        au = target.z - hip0.z
        out_t = (target.x - hip0.x) * (-1.0 if side == "R" else 1.0)
        swing = knee = 0.0
        for _ in range(6):
            swing, knee = _planar_leg(self.l1, self.l2, af, au)
            q = {"Hips": q_hips, f"{name}UpperLeg": K.from_pry(-swing, sign * roll, 0), f"{name}LowerLeg": K.from_pry(knee, 0, 0),
                 f"{name}Foot": K.from_pry(toe + swing - knee, 0, 0)}
            heads, _rots = k.fk(q, hips_loc)
            ank = heads[f"{name}Foot"]
            hip = heads[f"{name}UpperLeg"]
            af += -(target.y - ank.y)          # forward error (forward is -Y)
            au += target.z - ank.z
            out_c = (ank.x - hip.x) * (-1.0 if side == "R" else 1.0)
            roll = max(0.0, roll + math.degrees((out_t - out_c) / (0.9 * self.leg)))
        return (swing, roll, knee, toe)

    # ---- the gait pose -----------------------------------------------------------------------------------------
    def pose(self, kind: str, phase: float, base: dict, extra: dict) -> dict:
        """`base`: ready pose; `extra`: {"hips_r", "pelvis", "lift", "bob", "swagger"} style numbers from clips.loco_pose."""
        style = self.style
        n = spec.LOOP_FRAMES[kind]
        T = n / 60.0
        v = spec.NOMINAL_SPEED_MPS[kind]
        beta = spec.GAIT_DUTY[kind]
        S = v * beta * T                                  # stance excursion (m)
        if kind in ("strafe_left", "strafe_right"):
            d = Vector((1.0, 0.0, 0.0)) if kind == "strafe_left" else Vector((-1.0, 0.0, 0.0))   # armature axes: left = +X
            half_w = max(self.foot_x, style["stance"]) + 0.07
        else:
            d = Vector((0.0, -1.0, 0.0))                  # forward is -Y
            half_w = max(self.foot_x, style["stance"] - 0.02)
        is_run = kind == "run"
        lift = max(extra["lift"], 0.9) * (0.16 if is_run else 0.075) * self.leg / 0.85
        # hips: lowest needed at heel strike / toe-off, rising over mid-stance (walk) / flight (run)
        reach_x = S * 0.5 + (max(0.0, half_w - self.hip_x) if kind in ("strafe_left", "strafe_right") else 0.0)   # strafing also reaches sideways
        d_req = math.sqrt(max((REACH * self.leg) ** 2 - reach_x ** 2, 0.0))
        dip_end = self.leg - d_req
        if is_run:
            rise = 0.05 * extra["bob"]
            dip_base = dip_end + 0.26 * rise + 0.01
            hips_u = lambda ph: -dip_base + rise * (0.5 - 0.5 * math.cos(4.0 * math.pi * (ph - beta * 0.5)))
        else:
            rise = max(0.0, dip_end - MID_STANCE_DIP)
            hips_u = lambda ph: -dip_end + rise * (0.5 + 0.5 * math.cos(4.0 * math.pi * (ph - beta * 0.5)))
        p = over(base, ground=False)
        pelvis = extra["pelvis"](phase)
        p["pelvis"] = pelvis
        hr = extra["hips_r"](phase)
        p["hips"] = (hr, 0.0, hips_u(phase))
        hips_loc = Vector((0, 0, 0)) + K.cf(*p["hips"], "R")
        q_hips = K.from_pry(*pelvis)
        for side, sign in (("R", -1.0), ("L", 1.0)):
            ph = (phase + (0.0 if side == "R" else 0.5)) % 1.0
            if ph < beta:                                 # stance: constant backward velocity, flat foot
                s = S * 0.5 - S * (ph / beta)
                height = 0.0
                toe = 0.0
            else:                                         # swing: cycloid forward, lifted, toe-off pitch then toe-up before landing
                u = (ph - beta) / (1.0 - beta)
                u0 = 0.12                                  # the foot leaves the floor BEFORE it travels (no toe dragging at toe-off)
                s = -S * 0.5 + S * _cycloid(max(0.0, (u - u0) / (1.0 - u0)))
                height = lift * math.sin(math.pi * u) ** 0.9
                toe = 22.0 * max(0.0, 1.0 - u / 0.12) - 10.0 * math.sin(math.pi * min(1.0, max(0.0, (u - 0.72) / 0.28)))
            # a foot pitched toe-down at lift-off pivots on its toe tip: the ankle rises by toe_len * sin(pitch) or the toe would dig in
            height = max(height, self.toe_len * math.sin(math.radians(max(0.0, toe))))
            pos = Vector((sign * half_w, 0.0, self.ankle_h + height)) + d * s
            if kind in ("strafe_left", "strafe_right"):
                pos.y += -0.04 * math.sin(math.pi * max(0.0, (ph - beta) / (1.0 - beta))) if ph >= beta else 0.0
            roll0 = math.degrees(math.asin(max(0.0, min(0.9, (half_w - self.hip_x) / (0.9 * self.leg)))))
            p["leg" + side] = self._solve_leg(side, pos, toe, hips_loc, q_hips, roll0)
        return p
