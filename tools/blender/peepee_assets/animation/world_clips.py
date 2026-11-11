"""World clips: climb, ladder_idle, drop_fall, land (see spec.py for the ladder geometry they are authored against).

Climb model (root motion stripped): the character faces the ladder, whose rung centres are `spec.LADDER_PLANE_FWD` in front of
the character's origin. While the game moves the character up at spec.CLIMB_SPEED_MPS the contact limbs stay fixed in the
world, so relative to the body a limb that is HOLDING a rung falls by one rung spacing during half a cycle and a limb that is
REACHING rises by one spacing during the other half. Hand R + foot L reach together (group A), hand L + foot R the other half
(group B, half a cycle later). Hands and balls of the feet are placed by IK (arms: the shared two-bone solver; legs: planar
two-bone IK with a few correction iterations measured through forward kinematics), so the contact points really are on the
rung grid; dev_climb_check.py measures the slide of the contacts.
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from . import kinematics as K
from . import poses, spec
from .poses import over

H = spec.RUNG_SPACING
PLANE = spec.LADDER_PLANE_FWD
HAND_X = 0.17            # |x| of the hands on the rungs
FOOT_X = 0.15
HAND_UP_LOW = -0.03      # ideal wrist height relative to the (rest) shoulder when its rung is lowest ...
FOOT_LOW_FRAC = -0.90    # ... ideal foot-ball height relative to the hip joint, as a fraction of the leg length (negative = below)
GRIP_BELOW_WRIST = 0.07  # the rung centre is this far below the wrist joint (fist around the rung)
BALL_ABOVE_RUNG = 0.062  # the ball-of-foot joint rests this far above the rung centre (rung radius 0.022 + foot thickness)
# Grid rule (the contract with world/pit.py): rung centres are at (j + 0.5) * RUNG_SPACING. The targets below are snapped onto that
# grid in the character's root frame, so at clip phase 0 and 0.5 the character origin sits at y = n * RUNG_SPACING (halfway between two
# rungs) and moves up CLIMB_SPEED_MPS; the hips height absorbs the snap error so hands and feet each err by at most ~6 cm.


def _smooth(s: float) -> float:
    s = max(0.0, min(1.0, s))
    return s * s * (3.0 - 2.0 * s)


def _limb(u: float):
    """(rel, reach_s): rel in 0..1 = height above the lowest position as a fraction of one rung spacing; reach_s in 0..1
    while reaching (else -1). Reach during the first half of the limb's cycle, hold (linear fall, matching the body's
    constant upward speed) during the second."""
    u %= 1.0
    if u < 0.5:
        s = u * 2.0
        return _smooth(s), s
    return 1.0 - (u - 0.5) * 2.0, -1.0


def _planar_leg(l1, l2, f, u):
    """Swing (deg, + = forward) and knee flex (deg) putting the ankle at (fwd f, up u) relative to the hip joint."""
    d = max(abs(l1 - l2) + 1e-3, min(math.hypot(f, u), (l1 + l2) * 0.998))
    alpha = math.atan2(f, -u)
    beta = math.acos(max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d))))
    interior = math.acos(max(-1.0, min(1.0, (l1 * l1 + l2 * l2 - d * d) / (2 * l1 * l2))))
    return math.degrees(alpha + beta), 180.0 - math.degrees(interior)


class Climber:
    def __init__(self, solver, style):
        self.s = solver
        self.kin = solver.kin
        self.style = style
        k = self.kin
        self.l1 = k.length("LeftUpperLeg", "LeftLowerLeg")
        self.l2 = k.length("LeftLowerLeg", "LeftFoot")
        self.leg_len = self.l1 + self.l2
        self.sh_z = k.head["RightUpperArm"].z
        self.hip_z = k.head["LeftUpperLeg"].z
        # snap the contacts onto the rung grid (group B holds at phase 0: left hand and right foot one rung "below" group A)
        ideal_hand_b = self.sh_z + HAND_UP_LOW + H
        jb = round((ideal_hand_b - GRIP_BELOW_WRIST) / H - 0.5)
        self.hand_b_rung = jb
        self.hand_shift = (jb + 0.5) * H + GRIP_BELOW_WRIST - ideal_hand_b
        ideal_ball_b = self.hip_z + FOOT_LOW_FRAC * self.leg_len + H
        jf = round((ideal_ball_b - BALL_ABOVE_RUNG) / H - 0.5)
        self.foot_b_rung = jf
        self.foot_shift = (jf + 0.5) * H + BALL_ABOVE_RUNG - ideal_ball_b
        self.hips_dz = 0.5 * (self.hand_shift + self.foot_shift)

    # ---- foot ----------------------------------------------------------------------------------------------------
    def leg(self, side, ball_f, ball_u, roll, toe, hips_loc):
        """(swing, spread, knee, toe) so the ball of the foot (Toes joint) is at (fwd, up) relative to the hip joint."""
        name = "Right" if side == "R" else "Left"
        k = self.kin
        sign = 1.0 if side == "R" else -1.0
        af, au = ball_f - 0.12, ball_u + 0.05
        swing = knee = 0.0
        for _ in range(5):
            swing, knee = _planar_leg(self.l1, self.l2, af, au)
            q = {f"{name}UpperLeg": K.from_pry(-swing, sign * roll, 0), f"{name}LowerLeg": K.from_pry(knee, 0, 0),
                 f"{name}Foot": K.from_pry(toe + swing - knee, 0, 0)}
            heads, rots = k.fk(q, hips_loc)
            ball = heads[f"{name}Foot"] + rots[f"{name}Foot"] @ (k.tail[f"{name}Foot"] - k.head[f"{name}Foot"])
            hip = heads[f"{name}UpperLeg"]
            bf, bu = -(ball.y - hip.y), ball.z - hip.z
            af += ball_f - bf
            au += ball_u - bu
            out = ball.x * (1.0 if side == "L" else -1.0)       # lateral position: steer the leg's spread onto the rung
            roll = max(0.0, roll + math.degrees((FOOT_X - out) / (0.8 * self.leg_len)))
        return (swing, roll, knee, toe)

    # ---- the climbing pose -----------------------------------------------------------------------------------------
    def pose(self, u: float, base: dict, sway: float = 1.0) -> dict:
        style = self.style
        a_rel, a_s = _limb(u)            # group A: right hand + left foot
        b_rel, b_s = _limb(u + 0.5)      # group B: left hand + right foot
        p = over(base, ground=True)
        p["pelvis"] = (0.0, 0.0, 3.0 * sway * math.sin(2 * math.pi * u))
        p["torso"] = (7.0, 0.0, -5.0 * sway * math.sin(2 * math.pi * u))
        p["head"] = (-16.0, 0.0, 0.0)
        hips_off = (0.012 * sway * math.sin(2 * math.pi * u), 0.0, self.hips_dz)
        p["hips"] = hips_off
        p["ground"] = False
        hips_loc = Vector((0, 0, 0)) + K.cf(*hips_off, "R")
        # torso/pelvis rotations (needed to turn absolute hand targets into the shoulder-relative targets the solver wants)
        q = {"Hips": K.from_pry(*p["pelvis"])}
        for name, w in poses.SPINE_W:
            q[name] = K.from_pry(*(c * w for c in p["torso"]))
        heads, _rots = self.kin.fk(q, hips_loc)
        yaw = p["torso"][2] + p["pelvis"][2]
        rt = Matrix.Rotation(math.radians(yaw), 3, "Z")
        for side, rel, reach_s in (("R", a_rel, a_s), ("L", b_rel, b_s)):
            name = "Right" if side == "R" else "Left"
            sx = -1.0 if side == "R" else 1.0
            arc = 0.045 * math.sin(math.pi * reach_s) if reach_s >= 0 else 0.0
            target = Vector((sx * HAND_X, -(PLANE - arc), self.sh_z + HAND_UP_LOW + H * rel + self.hand_shift))
            v = rt.inverted() @ (target - heads[f"{name}UpperArm"])
            hand = (v.x / sx, -v.y, v.z)
            arm = dict(p["arm" + side])
            arm["hand"] = hand
            arm["pole"] = (0.30 + 0.5 * style["arm_clear"], -0.55, -0.45)   # elbows out and down
            arm["follow"] = 0.0
            if arm["wpn"] is not None:        # sling weapons back and outward so they clear the ladder and the body
                arm["wpn"] = (-150.0 if side == "R" else 150.0, 38.0)
            if arm["shield"] is not None:     # shield face to the side: it edges past the rails instead of hitting them
                arm["shield"] = (90.0, 0.0)
            p["arm" + side] = arm
        for side, rel, reach_s in (("L", a_rel, a_s), ("R", b_rel, b_s)):
            arc = 0.07 * math.sin(math.pi * reach_s) if reach_s >= 0 else 0.0
            ball_u = FOOT_LOW_FRAC * self.leg_len + H * rel + self.foot_shift - self.hips_dz
            p["leg" + side] = self.leg(side, PLANE - arc, ball_u, 9.0, 24.0, hips_loc)
        return p


# ------------------------------------------------------------------------------------------------------------------
def climb_keys(climber, base):
    return lambda ph: climber.pose(ph, base)


def ladder_idle_pose(climber, base, ph):
    p = climber.pose(0.5, base, sway=0.0)       # group A has just reached: right hand + left foot high
    s = math.sin(2 * math.pi * ph)
    t = p["torso"]
    p["torso"] = (t[0] + 0.8 * s, t[1], t[2])
    p["head"] = (p["head"][0] - 1.5 * math.sin(2 * math.pi * ph + 1.0), 0.0, 1.2 * math.sin(2 * math.pi * ph + 2.0))
    h = p["hips"]
    p["hips"] = (h[0], h[1], h[2] + 0.004 * s)
    return p


def drop_fall_pose(style, base, ph):
    """Falling, limbs splayed; a light flutter that closes the loop."""
    sp = math.degrees(math.asin(max(0.0, style["stance"] - 0.10) / 0.85))
    s = 2 * math.pi * ph
    flap = math.sin(s)
    p = over(base, ground=True)
    p["hips"] = (0.0, 0.0, 0.20)
    p["pelvis"] = (-4.0 + 2.0 * math.sin(s + 0.6), 0.0, 0.0)
    p["torso"] = (-8.0 + 2.0 * flap, 0.0, 0.0)
    p["head"] = (-14.0 + 3.0 * math.sin(s + 1.2), 0.0, 3.0 * math.sin(s + 0.3))
    p["legR"] = (10.0 + 7.0 * flap, sp + 20.0, 24.0 + 6.0 * math.sin(s + 0.8), 34.0)
    p["legL"] = (-8.0 - 7.0 * flap, sp + 24.0, 34.0 + 6.0 * math.sin(s + 2.2), 34.0)
    for side, sg, k in (("armR", 1.0, 0.0), ("armL", -1.0, 1.4)):
        arm = dict(p[side])
        arm["hand"] = (0.32 + 0.03 * math.sin(s + k), 0.08, 0.36 + 0.07 * math.sin(s + k + 0.5))
        arm["pole"] = (0.5, 0.0, -0.2)
        arm["follow"] = 0.0
        if arm["wpn"] is not None:
            arm["wpn"] = (-28.0 * sg * 1.0, 74.0)
        if arm["shield"] is not None:
            arm["shield"] = (60.0, 10.0)
        p[side] = arm
    return p


def land_keys(style, base, solver):
    sp = math.degrees(math.asin(max(0.0, style["stance"] - 0.10) / 0.85))
    air = drop_fall_pose(style, base, 0.0)

    def arms(out, fwd, up, wpn=None, shield=None):
        d = {}
        for side, sg in (("armR", -1.0), ("armL", 1.0)):
            a = {"hand": (out, fwd, up), "follow": 0.0, "pole": (0.5, -0.1, -0.5)}
            if base[side]["wpn"] is not None:
                a["wpn"] = (sg * 25.0, 20.0) if wpn is None else (sg * wpn[0], wpn[1])
            if base[side]["shield"] is not None:
                a["shield"] = (50.0, -20.0) if shield is None else shield
            d[side] = a
        return d

    contact = over(base, ground=True, hips=(0, 0.02, 0.05), torso=(12.0, 0.0, 0.0), head=(-8.0, 0.0, 0.0),
                   legR=(-10.0, sp + 10.0, 36.0, 10.0), legL=(6.0, sp + 12.0, 44.0, 10.0), **arms(0.34, 0.14, -0.14))
    crouch = over(base, ground=True, hips=(0, 0.10, 0.0), torso=(36.0, 0.0, 0.0), head=(-14.0, 0.0, 0.0),
                  legR=(-22.0, sp + 14.0, 84.0, 8.0), legL=(14.0, sp + 16.0, 92.0, 8.0), **arms(0.38, 0.22, -0.26))
    settle = over(poses.blend(crouch, base, 0.28), **arms(0.32, 0.18, -0.30))
    return [(0.0, air, "lin"), (0.13, contact, "in"), (0.30, crouch, "out"), (0.46, crouch, "lin"),
            (0.66, settle, "in_out"), (1.0, base, "in_out")]
