"""Clip authoring. See library.py for the STYLE schema and poses.py for the pose model.

Timing: every clip has spec.clip_frames(cls)[name] frames. Attack clips place the wind-up peak at the
sim's `startup_end`, drive the strike through the active window [startup_end, active_end] and are
back to ready by 1.0 (spec.MARKERS), so the visible swing matches the hit window.
"""
from __future__ import annotations

import math

from .. import export, skeleton
from . import poses, spec
from .poses import blank_pose, over

STEP = 2   # sample every other frame (plus the last); every sample is IK-solved


# ------------------------------------------------------------------------------------------
# Ready stances per grip
# ------------------------------------------------------------------------------------------
def _spread(style):
    return math.degrees(math.asin(max(0.0, style["stance"] - 0.10) / 0.85))


def legs_pose(style, sw_r=-8.0, kn_r=16.0, sw_l=12.0, kn_l=20.0, toe_r=0.0, toe_l=0.0):
    sp = _spread(style)
    return {"legR": (sw_r, sp, kn_r, toe_r), "legL": (sw_l, sp, kn_l, toe_l)}


def ready(style) -> dict:
    g = style["grip"]
    p = over(blank_pose(), **legs_pose(style))
    p["torso"] = (4.0, 0.0, 0.0)
    p["head"] = (-3.0, 0.0, 0.0)
    if g == "spear2":
        p["armR"].update(hand=(0.0, 0.22, -0.40), wpn=(0, 25, 0))
        p["armL"]["follow"] = 1.0
    elif g == "staff2":
        p["armR"].update(hand=(0.05, 0.20, -0.40), wpn=(0, 72, 0))
        p["armL"]["follow"] = 1.0
    elif g == "sword_shield":
        p["armR"].update(hand=(0.05, 0.32, -0.28), wpn=(0, 62, 0))
        p["armL"].update(hand=(0.05, 0.17, -0.08), pole=(0.3, -0.3, -0.9), shield=(0, -38))
    elif g == "hammer_shield":
        p["armR"].update(hand=(0.05, 0.30, -0.30), wpn=(0, 52, 0))
        p["armL"].update(hand=(0.05, 0.17, -0.08), pole=(0.3, -0.3, -0.9), shield=(0, -38))
    elif g == "dual":
        p["armR"].update(hand=(0.12, 0.30, -0.24), wpn=(-10, 52, 0))
        p["armL"].update(hand=(0.12, 0.30, -0.24), wpn=(10, 52, 0))
    else:  # sword1
        p["armR"].update(hand=(0.05, 0.30, -0.26), wpn=(0, 58, 0))
        p["armL"].update(hand=(0.10, 0.20, -0.30))
    return p


def A(hand=None, wpn=None, torso=None, hips=None, legs=None, head=None, armL=None, pelvis=None, twist=None,
      ground=None, shield=None):
    """Authoring shorthand for a pose override (right arm = the main weapon arm)."""
    d = {}
    arm = {}
    if hand is not None:
        arm["hand"] = hand
    if wpn is not None:
        arm["wpn"] = wpn
    if arm:
        d["armR"] = arm
    if armL:
        d["armL"] = armL
    if shield is not None:
        d.setdefault("armL", {})["shield"] = shield
    for k, v in (("torso", torso), ("hips", hips), ("legs", legs), ("head", head), ("pelvis", pelvis), ("ground", ground)):
        if v is not None:
            d[k] = v
    return d


def build_pose(style, base, ov, power=True):
    """Applies an override dict (with the pseudo-key `legs` = (swR, knR, swL, knL)) to `base`."""
    ov = dict(ov)
    if power:
        pw = style["power"]
        if "torso" in ov:
            ov["torso"] = tuple(c * pw for c in ov["torso"])
        if "hips" in ov:
            r, f, u = ov["hips"]
            ov["hips"] = (r, f * pw, u)
    legs = ov.pop("legs", None)
    if legs is not None:
        ov.update(legs_pose(style, *legs))
    return over(base, **ov)


# ------------------------------------------------------------------------------------------
# Attack kits:  kit[grip][clip] = (wind, hit, end) override dicts
# ------------------------------------------------------------------------------------------
LUNGE_LEGS_WIND = (-4, 22, 6, 30)
LUNGE_LEGS_HIT = (-26, 8, 34, 42)

SPEAR = {
    "light_1": (
        A(hand=(0.0, 0.06, -0.40), wpn=(0, 18), torso=(5, 0, -14), hips=(0, -0.07, 0), legs=(-12, 22, 6, 24)),
        A(hand=(0.0, 0.52, -0.20), wpn=(0, 10), torso=(10, 0, 10), hips=(0, 0.20, 0), legs=(-22, 10, 26, 34)),
        A(hand=(0.0, 0.50, -0.22), wpn=(0, 12), torso=(8, 0, 8), hips=(0, 0.20, 0), legs=(-22, 10, 26, 34))),
    "light_2": (
        A(hand=(0.06, 0.08, -0.46), wpn=(0, 6), torso=(8, 0, -12), hips=(0, -0.06, -0.03), legs=(-12, 26, 6, 28)),
        A(hand=(0.04, 0.50, -0.36), wpn=(0, -2), torso=(14, 0, 8), hips=(0, 0.20, -0.03), legs=(-22, 14, 28, 38)),
        A(hand=(0.04, 0.48, -0.36), wpn=(0, -4), torso=(12, 0, 8), hips=(0, 0.20, -0.03), legs=(-22, 14, 28, 38))),
    "light_3": (
        A(hand=(0.22, 0.30, -0.24), wpn=(-78, 8), torso=(2, 0, -38), hips=(0, -0.03, 0), legs=(-10, 20, 8, 26)),
        A(hand=(-0.02, 0.42, -0.28), wpn=(0, 6), torso=(4, 0, 4), hips=(0, 0.10, 0), legs=(-14, 18, 18, 30)),
        A(hand=(-0.12, 0.30, -0.28), wpn=(72, 6), torso=(4, 0, 34), hips=(0, 0.08, 0), legs=(-14, 18, 18, 30))),
    "heavy": (
        A(hand=(0.0, -0.02, -0.42), wpn=(0, 28), torso=(10, 0, -24), hips=(0, -0.18, -0.06), legs=(-10, 30, 4, 38)),
        A(hand=(0.0, 0.53, -0.22), wpn=(0, 5), torso=(22, 0, 14), hips=(0, 0.42, -0.04), legs=LUNGE_LEGS_HIT),
        A(hand=(0.0, 0.52, -0.24), wpn=(0, 6), torso=(20, 0, 12), hips=(0, 0.40, -0.04), legs=LUNGE_LEGS_HIT)),
}
STAFF = {
    "light_1": (
        A(hand=(0.05, 0.10, -0.40), wpn=(0, 40), torso=(4, 0, -12), hips=(0, -0.05, 0)),
        A(hand=(0.04, 0.50, -0.18), wpn=(0, 22), torso=(8, 0, 8), hips=(0, 0.16, 0), legs=(-16, 10, 22, 30)),
        A(hand=(0.04, 0.48, -0.20), wpn=(0, 24), torso=(6, 0, 6), hips=(0, 0.16, 0), legs=(-16, 10, 22, 30))),
    "light_2": (
        A(hand=(0.22, 0.28, -0.22), wpn=(-70, 20), torso=(2, 0, -34), hips=(0, -0.03, 0)),
        A(hand=(-0.02, 0.42, -0.26), wpn=(0, 10), torso=(3, 0, 4), hips=(0, 0.08, 0)),
        A(hand=(-0.12, 0.32, -0.26), wpn=(70, 14), torso=(3, 0, 30), hips=(0, 0.06, 0))),
    "light_3": (
        A(hand=(0.08, 0.05, 0.30), wpn=(0, 100), torso=(-8, 0, -6), hips=(0, -0.05, 0.0), head=(-8, 0, 0)),
        A(hand=(0.05, 0.48, -0.02), wpn=(0, 35), torso=(18, 0, 2), hips=(0, 0.16, -0.03), legs=(-16, 12, 26, 32)),
        A(hand=(0.05, 0.46, -0.28), wpn=(0, -20), torso=(22, 0, 2), hips=(0, 0.16, -0.05), legs=(-16, 12, 26, 32))),
    "heavy": (
        A(hand=(0.08, 0.02, 0.38), wpn=(0, 118), torso=(-14, 0, -8), hips=(0, -0.08, 0.0), head=(-12, 0, 0)),
        A(hand=(0.05, 0.52, -0.05), wpn=(0, 25), torso=(24, 0, 4), hips=(0, 0.24, -0.06), legs=(-20, 14, 32, 40)),
        A(hand=(0.05, 0.48, -0.32), wpn=(0, -40), torso=(28, 0, 4), hips=(0, 0.24, -0.08), legs=(-20, 14, 32, 40))),
}
SLASH = {   # one-handed sword (sword_shield, sword1); the hammer reuses it with bigger arcs
    "light_1": (
        A(hand=(0.24, 0.08, 0.10), wpn=(-36, 82), torso=(2, 0, -24), hips=(0, -0.04, 0), legs=(-10, 20, 8, 24)),
        A(hand=(-0.04, 0.50, -0.10), wpn=(24, 22), torso=(6, 0, 14), hips=(0, 0.14, 0), legs=(-16, 12, 24, 30)),
        A(hand=(-0.16, 0.40, -0.28), wpn=(56, -8), torso=(8, 0, 24), hips=(0, 0.14, 0), legs=(-16, 12, 24, 30))),
    "light_2": (
        A(hand=(-0.10, 0.28, -0.10), wpn=(50, 40), torso=(2, 0, 22), hips=(0, -0.03, 0), legs=(-10, 18, 8, 24)),
        A(hand=(0.30, 0.46, -0.14), wpn=(-26, 15), torso=(4, 0, -12), hips=(0, 0.12, 0), legs=(-14, 14, 22, 28)),
        A(hand=(0.40, 0.30, -0.30), wpn=(-62, -6), torso=(6, 0, -24), hips=(0, 0.12, 0), legs=(-14, 14, 22, 28))),
    "light_3": (
        A(hand=(0.10, 0.04, 0.36), wpn=(0, 112), torso=(-8, 0, -6), hips=(0, -0.05, 0), head=(-6, 0, 0)),
        A(hand=(0.05, 0.50, 0.04), wpn=(0, 30), torso=(16, 0, 2), hips=(0, 0.18, -0.03), legs=(-18, 12, 28, 34)),
        A(hand=(0.05, 0.45, -0.30), wpn=(0, -38), torso=(22, 0, 2), hips=(0, 0.18, -0.05), legs=(-18, 12, 28, 34))),
    "heavy": (
        A(hand=(0.10, 0.00, 0.42), wpn=(0, 128), torso=(-16, 0, -8), hips=(0, -0.10, -0.04), head=(-10, 0, 0), legs=(-6, 26, 4, 36)),
        A(hand=(0.05, 0.55, 0.00), wpn=(0, 22), torso=(24, 0, 4), hips=(0, 0.30, -0.06), legs=(-22, 14, 34, 44)),
        A(hand=(0.05, 0.50, -0.34), wpn=(0, -62), torso=(30, 0, 4), hips=(0, 0.30, -0.08), legs=(-22, 14, 34, 44))),
}
HAMMER = {
    "light_1": (
        A(hand=(0.26, 0.06, -0.02), wpn=(-62, 18), torso=(2, 0, -34), hips=(0, -0.05, 0), legs=(-10, 24, 8, 26)),
        A(hand=(0.0, 0.46, -0.20), wpn=(0, 6), torso=(6, 0, 6), hips=(0, 0.12, 0), legs=(-14, 18, 20, 30)),
        A(hand=(-0.14, 0.34, -0.26), wpn=(66, 0), torso=(8, 0, 30), hips=(0, 0.12, 0), legs=(-14, 18, 20, 30))),
    "light_2": (
        A(hand=(-0.10, 0.24, -0.12), wpn=(60, 20), torso=(2, 0, 28), hips=(0, -0.04, 0), legs=(-10, 22, 8, 24)),
        A(hand=(0.28, 0.44, -0.18), wpn=(-20, 8), torso=(4, 0, -14), hips=(0, 0.12, 0), legs=(-14, 18, 20, 30)),
        A(hand=(0.40, 0.30, -0.28), wpn=(-66, 0), torso=(6, 0, -28), hips=(0, 0.12, 0), legs=(-14, 18, 20, 30))),
    "light_3": (
        A(hand=(0.10, 0.02, 0.38), wpn=(0, 118), torso=(-12, 0, -6), hips=(0, -0.06, -0.02), head=(-8, 0, 0)),
        A(hand=(0.05, 0.50, 0.02), wpn=(0, 28), torso=(20, 0, 2), hips=(0, 0.20, -0.05), legs=(-16, 16, 26, 34)),
        A(hand=(0.05, 0.45, -0.34), wpn=(0, -50), torso=(26, 0, 2), hips=(0, 0.20, -0.07), legs=(-16, 16, 26, 34))),
    "heavy": (
        A(hand=(0.10, -0.02, 0.44), wpn=(0, 132), torso=(-20, 0, -10), hips=(0, -0.12, -0.05), head=(-12, 0, 0), legs=(-6, 30, 4, 40)),
        A(hand=(0.05, 0.56, 0.00), wpn=(0, 20), torso=(30, 0, 4), hips=(0, 0.34, -0.10), legs=(-24, 16, 36, 50)),
        A(hand=(0.05, 0.50, -0.36), wpn=(0, -70), torso=(36, 0, 4), hips=(0, 0.34, -0.12), legs=(-24, 16, 36, 50))),
}
DUAL = {
    "light_1": (
        A(hand=(0.28, 0.08, 0.06), wpn=(-40, 78), torso=(2, 0, -26), hips=(0, -0.03, 0), legs=(-10, 18, 6, 22)),
        A(hand=(-0.06, 0.50, -0.10), wpn=(22, 20), torso=(5, 0, 14), hips=(0, 0.14, 0), legs=(-16, 12, 22, 30)),
        A(hand=(-0.18, 0.40, -0.26), wpn=(56, -8), torso=(6, 0, 24), hips=(0, 0.14, 0), legs=(-16, 12, 22, 30))),
    "light_2": (   # left blade (mirror of light_1 on the left arm; armL carries the weapon)
        A(armL={"hand": (0.28, 0.08, 0.06), "wpn": (40, 78)}, torso=(2, 0, 26), hips=(0, -0.03, 0), legs=(-10, 18, 6, 22)),
        A(armL={"hand": (-0.06, 0.50, -0.10), "wpn": (-22, 20)}, torso=(5, 0, -14), hips=(0, 0.14, 0), legs=(-16, 12, 22, 30)),
        A(armL={"hand": (-0.18, 0.40, -0.26), "wpn": (-56, -8)}, torso=(6, 0, -24), hips=(0, 0.14, 0), legs=(-16, 12, 22, 30))),
    "light_3": (   # both blades cross in an X
        A(hand=(0.34, 0.05, 0.10), wpn=(-50, 70), armL={"hand": (0.34, 0.05, 0.10), "wpn": (50, 70)}, torso=(-4, 0, 0), hips=(0, -0.06, 0), legs=(-8, 20, 6, 26)),
        A(hand=(-0.10, 0.48, -0.02), wpn=(28, 30), armL={"hand": (-0.10, 0.48, -0.02), "wpn": (-28, 30)}, torso=(14, 0, 0), hips=(0, 0.18, -0.03), legs=(-18, 12, 26, 34)),
        A(hand=(-0.16, 0.44, -0.22), wpn=(48, 0), armL={"hand": (-0.16, 0.44, -0.22), "wpn": (-48, 0)}, torso=(16, 0, 0), hips=(0, 0.18, -0.04), legs=(-18, 12, 26, 34))),
    "heavy": (
        A(hand=(0.20, 0.0, 0.40), wpn=(-12, 118), armL={"hand": (0.20, 0.0, 0.40), "wpn": (12, 118)}, torso=(-16, 0, 0), hips=(0, -0.10, -0.04), head=(-10, 0, 0), legs=(-6, 26, 4, 34)),
        A(hand=(-0.05, 0.54, 0.0), wpn=(14, 24), armL={"hand": (-0.05, 0.54, 0.0), "wpn": (-14, 24)}, torso=(24, 0, 0), hips=(0, 0.30, -0.06), legs=(-22, 14, 34, 44)),
        A(hand=(-0.12, 0.48, -0.30), wpn=(30, -40), armL={"hand": (-0.12, 0.48, -0.30), "wpn": (-30, -40)}, torso=(30, 0, 0), hips=(0, 0.30, -0.08), legs=(-22, 14, 34, 44))),
}
KITS = {"spear2": SPEAR, "staff2": STAFF, "sword_shield": SLASH, "sword1": SLASH, "hammer_shield": HAMMER, "dual": DUAL}


def attack_keys(style, cls, clip):
    """Wind-up -> strike -> recover. Anticipation (readability for the opponent):
      * the wind-up pose is exaggerated for heavies and finishers (extrapolated past the authored pose),
      * long wind-ups first make a small COUNTER-MOVE the opposite way (classic anticipation),
      * and the peak is HELD for 2-4 frames when the startup is long enough to afford it.
    Clip length and the strike-in-the-active-window property are unchanged (see dev_timing_check.py)."""
    g = style["grip"]
    base = ready(style)
    wind_o, hit_o, end_o = KITS[g][clip]
    se, ae, cancel = spec.MARKERS[cls][clip]
    n = spec.clip_frames(cls)[clip]
    startup = se * n
    wind, hit, end = (build_pose(style, base, o) for o in (wind_o, hit_o, end_o))
    exag = {"heavy": 1.16, "light_3": 1.08}.get(clip, 1.0)
    if cls in ("rook", "knight", "king"):
        exag *= 1.04
    wind_x = poses.blend(base, wind, exag) if exag != 1.0 else wind
    prep = poses.blend(base, wind_x, 0.6)
    tmid = se + 0.3 * (ae - se)
    hold = 4 if startup >= 24 else 3 if startup >= 17 else 2 if startup >= 12 else 0
    t_peak = se * (0.66 if hold else 0.72)
    keys = [(0.0, base, "lin")]
    if startup >= 14:
        keys.append((se * 0.16, poses.blend(base, wind_x, -0.10), "out"))   # counter-move
    keys += [(se * 0.45, prep, "in_out"), (t_peak, wind_x, "out")]
    if hold:
        keys.append((t_peak + hold / n, poses.blend(wind_x, hit, 0.04), "lin"))   # held peak (tiny creep keeps it alive)
    keys += [
        (se, poses.blend(wind_x, hit, 0.4), "in"),
        (tmid, hit, "lin"),
        (ae, end, "out"),
        (min(cancel, 0.97), poses.blend(end, base, 0.6), "in_out"),
        (1.0, base, "in_out"),
    ]
    return keys


# ------------------------------------------------------------------------------------------
# Locomotion (periodic functions of phase)
# ------------------------------------------------------------------------------------------
def loco_pose(style, kind, phase):
    sw = style["swagger"]
    base = ready(style)
    p = 2 * math.pi * phase
    sp = _spread(style)
    stride, bobk, swayk, leank, lift = (style.get("stride", 1.0), style.get("bob", 1.0), style.get("sway", 1.0),
                                          style.get("lean", 1.0), style.get("lift", 1.0))
    if kind in ("walk", "run"):
        a, k = (22.0, 34.0) if kind == "walk" else (44.0, 78.0)
        a *= sw * stride
        k *= lift
        lean = (3.0 if kind == "walk" else 14.0) * leank
        bob = (0.018 if kind == "walk" else 0.04) * bobk
        def leg(ph):
            swing = a * math.sin(ph)
            knee = k * max(0.0, math.cos(ph)) ** 0.8 + (10 if kind == "walk" else 24)
            toe = 18.0 * max(0.0, -math.sin(ph)) if kind == "run" else 8.0 * max(0.0, -math.sin(ph))
            return (swing, sp, knee, toe)
        pose = over(base, legR=leg(p), legL=leg(p + math.pi))
        pose["hips"] = (0.01 * math.sin(p), 0.0, bob * math.cos(2 * p) * sw)
        pose["torso"] = (base["torso"][0] + lean, 0.0, 6.0 * sw * swayk * math.sin(p) * (1.0 if kind == "walk" else 1.6))
        pose["pelvis"] = (0.0, 0.0, -5.0 * sw * swayk * math.sin(p))
        pose["hips"] = (0.01 * swayk * math.sin(p) + (0.012 * swayk * math.sin(p) if kind == "walk" else 0.0), 0.0, bob * math.cos(2 * p) * sw)
        pose["head"] = (-3.0 - lean * 0.6, 0.0, -pose["torso"][2] * 0.4)
        if kind == "run":
            for side in ("armR", "armL"):
                if pose[side]["follow"] < 0.5:
                    h = pose[side]["hand"]
                    pose[side]["hand"] = (h[0], h[1] - 0.05, h[2] - 0.02 + 0.015 * math.sin(2 * p))
        return pose
    # strafe: sidesteps with a cross-step; left = toward the character's left
    s = 1.0 if kind == "strafe_left" else -1.0
    lead = "legL" if s > 0 else "legR"
    trail = "legR" if s > 0 else "legL"
    amp = 16.0 * sw * stride
    pose = over(base)
    pose[lead] = (6 * math.sin(p), sp + amp * (0.5 + 0.5 * math.sin(p)), 18 + 22 * max(0.0, math.cos(p)), 0.0)
    pose[trail] = (-6 * math.sin(p), max(sp - amp * 0.7 * (0.5 + 0.5 * math.sin(p)), -4.0), 18 + 22 * max(0.0, -math.cos(p)), 0.0)
    pose["hips"] = (0.0, 0.0, 0.015 * sw * math.cos(2 * p))
    pose["torso"] = (4.0, -s * 3.0 * math.sin(p), 4.0 * math.sin(p))
    return pose


def idle_pose(style, phase):
    """Breathing loop with class character: Rook slow and heavy, Bishop hovers, Pawn/Queen shift weight,
    King nearly still. Purely periodic in `phase`, so the loop closes."""
    base = ready(style)
    p = 2 * math.pi * phase
    amp = style.get("idle_amp", 1.0)
    out = over(base)
    out["torso"] = (base["torso"][0] + 1.2 * amp * math.sin(p), 0.0, 1.0 * amp * math.sin(p))
    out["head"] = (base["head"][0] - 0.8 * amp * math.sin(p), 0.0, 1.5 * amp * math.sin(p + 1.0))
    hover = style.get("idle_hover", 0.0) * (0.5 + 0.5 * math.sin(p))
    out["hips"] = (style.get("idle_sway", 0.0) * math.sin(p), 0.0, 0.004 * amp * math.sin(p) + hover)
    for side in ("armR", "armL"):
        if out[side]["follow"] < 0.5:
            h = out[side]["hand"]
            out[side]["hand"] = (h[0], h[1], h[2] + 0.008 * amp * math.sin(p + 0.5))
    return out


# ------------------------------------------------------------------------------------------
# Block / parry / dodge / stagger / ability / defeat
# ------------------------------------------------------------------------------------------
def block_pose(style):
    g = style["grip"]
    base = ready(style)
    legs = (-10, 24, 4, 32)
    if g in ("sword_shield", "hammer_shield"):
        o = A(hand=(0.12, 0.26, -0.18), wpn=(-18, 72), armL={"hand": (0.04, 0.14, 0.10), "pole": (0.2, -0.3, -0.9), "shield": (0, 6)},   # forearm UP so the shield face can look forward
              torso=(10, 0, 6), head=(-6, 0, 0), hips=(0, 0.02, -0.04), legs=legs)
    elif g in ("spear2", "staff2"):
        o = A(hand=(0.10, 0.30, -0.12), wpn=(88, 10), torso=(8, 0, 4), hips=(0, 0.0, -0.04), legs=legs)
    elif g == "dual":
        o = A(hand=(-0.04, 0.38, -0.02), wpn=(38, 55), armL={"hand": (-0.04, 0.38, -0.02), "wpn": (-38, 55)},
              torso=(8, 0, 0), hips=(0, 0.0, -0.04), legs=legs)
    else:
        o = A(hand=(0.02, 0.34, -0.04), wpn=(0, 82), armL={"hand": (0.0, 0.34, -0.14)}, torso=(8, 0, 2), hips=(0, 0.0, -0.04), legs=legs)
    return build_pose(style, base, o, power=False)


def block_loop(style, phase):
    b = block_pose(style)
    p = 2 * math.pi * phase
    out = over(b)
    out["torso"] = (b["torso"][0] + 0.8 * math.sin(p), b["torso"][1], b["torso"][2])
    out["hips"] = (0.0, b["hips"][1], b["hips"][2] + 0.006 * math.sin(p))
    return out


def parry_keys(style, cls, frames):
    base = ready(style)
    g = style["grip"]
    if g in ("sword_shield", "hammer_shield"):
        o = A(hand=(-0.04, 0.46, -0.04), wpn=(52, 38), armL={"hand": (0.04, 0.24, 0.08), "pole": (0.2, -0.3, -0.9), "shield": (0, 8)},
              torso=(6, 0, 18), hips=(0, 0.08, -0.02), legs=(-12, 18, 20, 26))
    elif g in ("spear2", "staff2"):
        o = A(hand=(-0.02, 0.38, -0.12), wpn=(62, 40), torso=(6, 0, 16), hips=(0, 0.06, -0.02), legs=(-12, 18, 20, 26))
    elif g == "dual":
        o = A(hand=(-0.12, 0.44, -0.06), wpn=(58, 40), armL={"hand": (0.10, 0.40, -0.04), "wpn": (-10, 60)},
              torso=(6, 0, 18), hips=(0, 0.06, -0.02), legs=(-12, 18, 20, 26))
    else:
        o = A(hand=(-0.04, 0.44, -0.06), wpn=(56, 40), torso=(6, 0, 16), hips=(0, 0.06, -0.02), legs=(-12, 18, 20, 26))
    peak = build_pose(style, base, o)
    window = spec.STATS[cls][2] / frames
    return [(0.0, base, "lin"), (0.12, peak, "out"), (max(window, 0.3), peak, "lin"),
            (0.62, poses.blend(peak, base, 0.5), "in_out"), (1.0, base, "in_out")]


def dodge_keys(style):
    base = ready(style)
    arms = {"armR": {"hand": (0.14, 0.12, -0.34)}, "armL": {"hand": (0.14, 0.12, -0.34)}}
    tuck = over(base, torso=(30.0, 0.0, 0.0), head=(-18.0, 0.0, 0.0), hips=(0, -0.05, -0.22), ground=False,
                legR=(-10, _spread(style) + 8, 74, 0), legL=(26, _spread(style) + 8, 84, 0), **arms)
    low = over(base, torso=(38.0, 0.0, 0.0), head=(-24.0, 0.0, 0.0), hips=(0, 0.10, -0.12), ground=False,
               legR=(-30, _spread(style) + 12, 40, 20), legL=(38, _spread(style) + 12, 48, 0), **arms)
    land = over(base, torso=(16.0, 0.0, 0.0), hips=(0, 0.04, -0.06), legR=(-10, _spread(style) + 4, 34, 0), legL=(18, _spread(style) + 4, 40, 0))
    return [(0.0, base, "lin"), (0.18, tuck, "out"), (0.45, low, "in_out"), (0.78, land, "in_out"), (1.0, base, "in_out")]


def stagger_keys(style):
    base = ready(style)
    hit = over(base, torso=(-26.0, 4.0, -10.0), head=(-22.0, 0.0, 12.0), hips=(0, -0.12, -0.04),
               legR=(-18, _spread(style) + 4, 24, 0), legL=(8, _spread(style) + 4, 12, 0),
               armR={"hand": (0.36, -0.06, -0.30), "wpn": None if base["armR"]["wpn"] is None else (-30, 50)},
               armL={"hand": (0.34, -0.04, -0.30), "follow": 0.0, "shield": (-40, -30) if base["armL"]["shield"] else None,
                     "wpn": (40, 40) if base["armL"]["wpn"] else None})
    return [(0.0, base, "lin"), (0.14, hit, "out"), (0.5, poses.blend(hit, base, 0.3), "in_out"), (1.0, base, "in_out")]


def defeat_keys(style):
    base = ready(style)
    arms = {"armR": {"hand": (0.20, 0.0, -0.50), "wpn": None if base["armR"]["wpn"] is None else (-40, 20)},
            "armL": {"hand": (0.22, 0.0, -0.50), "follow": 0.0, "shield": (0, -60) if base["armL"]["shield"] else None,
             "wpn": (20, 10) if base["armL"]["wpn"] else None}}
    knees = over(base, torso=(14.0, 0.0, 0.0), head=(12.0, 0.0, 0.0), hips=(0, -0.05, -0.34), ground=False,
                 legR=(-6, 10, 70, 0), legL=(10, 10, 82, 0), **arms)
    fall = over(base, pelvis=(-48.0, 0.0, 0.0), torso=(-12.0, 0.0, 0.0), head=(-18.0, 0.0, 0.0), hips=(0, -0.30, -0.56), ground=False,
                legR=(10, 12, 40, 0), legL=(22, 12, 30, 0), **arms)
    lie = over(base, pelvis=(-88.0, 0.0, 0.0), torso=(-4.0, 0.0, 0.0), head=(-6.0, 0.0, 8.0), hips=(0, -0.02, -0.80), ground=False,
               legR=(0, 14, 8, 20), legL=(0, 16, 14, 20), **arms)
    return [(0.0, base, "lin"), (0.22, knees, "in_out"), (0.55, fall, "in"), (0.78, lie, "out"), (1.0, lie, "lin")]


def ability_keys(style, cls, frames):
    base = ready(style)
    sp = _spread(style)
    if cls == "pawn":     # Last Stand: rallying roar, weapon raised
        peak = build_pose(style, base, A(hand=(0.12, 0.10, 0.30), wpn=(0, 96), torso=(-16, 0, 0), head=(-22, 0, 0),
                                         hips=(0, 0, -0.02), legs=(-8, 30, 18, 24)), power=False)
        return [(0.0, base, "lin"), (0.4, peak, "out"), (0.7, peak, "lin"), (1.0, base, "in_out")]
    if cls == "knight":   # Lunging Strike: coil, committed charge thrust, long recovery (72 ticks)
        coil = build_pose(style, base, A(hand=(0.10, 0.06, -0.16), wpn=(0, 6), torso=(10, 0, -22), hips=(0, -0.20, -0.10),
                                         legs=(-6, 28, 4, 40), armL={"hand": (0.0, 0.34, -0.10), "shield": (0, 0)}), power=False)
        thrust = build_pose(style, base, A(hand=(0.05, 0.54, -0.12), wpn=(0, 2), torso=(24, 0, 12), hips=(0, 0.55, -0.12),
                                           legs=(-30, 8, 40, 52)), power=False)
        end = over(thrust, hips=(0, 0.52, -0.12))
        se, ae = 0.45, 0.62
        return [(0.0, base, "lin"), (0.20, poses.blend(base, coil, 0.6), "in_out"), (0.30, coil, "out"),
                (0.42, thrust, "in"), (ae, end, "lin"), (0.82, poses.blend(end, base, 0.5), "in_out"), (1.0, base, "in_out")]
    if cls == "bishop":   # Blink: staff raised, arcane gesture, dip
        peak = build_pose(style, base, A(hand=(0.08, 0.14, 0.34), wpn=(0, 100), torso=(-10, 0, -10), head=(-16, 0, 0),
                                         hips=(0, 0, 0.0), legs=(-8, 26, 14, 24), armL={"follow": 0.0, "hand": (0.30, 0.26, 0.05)}), power=False)
        dip = build_pose(style, base, A(hand=(0.08, 0.20, -0.20), wpn=(0, 60), torso=(18, 0, 0), hips=(0, 0, -0.14),
                                        legs=(-8, 30, 60, 30), armL={"follow": 0.0, "hand": (0.10, 0.20, -0.30)}), power=False)
        return [(0.0, base, "lin"), (0.4, peak, "out"), (0.7, dip, "in_out"), (1.0, base, "in_out")]
    if cls == "rook":     # Fortress Guard: slam in, brace
        slam = build_pose(style, base, A(hand=(0.08, 0.50, -0.38), wpn=(0, -55), torso=(26, 0, 0), hips=(0, 0.16, -0.16),
                                         legs=(-12, 36, 50, 40), armL={"hand": (0.0, 0.46, -0.10), "shield": (0, 0)}), power=False)
        raise_ = build_pose(style, base, A(hand=(0.10, 0.02, 0.40), wpn=(0, 125), torso=(-14, 0, 0), hips=(0, -0.04, -0.04),
                                           legs=(-8, 34, 14, 36)), power=False)
        return [(0.0, base, "lin"), (0.28, raise_, "out"), (0.45, slam, "in"), (0.8, slam, "lin"), (1.0, base, "in_out")]
    if cls == "queen":    # Royal Fury: blades flourish and flare
        flare = build_pose(style, base, A(hand=(0.40, 0.10, 0.30), wpn=(-60, 80), armL={"hand": (0.40, 0.10, 0.30), "wpn": (60, 80)},
                                          torso=(-12, 0, 0), head=(-18, 0, 0), hips=(0, 0, -0.02), legs=(-6, 28, 14, 20)), power=False)
        cross = build_pose(style, base, A(hand=(-0.10, 0.42, 0.10), wpn=(30, 70), armL={"hand": (-0.10, 0.42, 0.10), "wpn": (-30, 70)},
                                          torso=(8, 0, 0), hips=(0, 0.04, -0.04), legs=(-10, 22, 24, 28)), power=False)
        return [(0.0, base, "lin"), (0.3, cross, "out"), (0.6, flare, "out"), (1.0, base, "in_out")]
    # king: Royal Counter (40 frames) - a readable COUNTER STANCE, then a precise riposte:
    #   0-15%   raise the guard: blade upright across the body, free hand forward, weight sunk back
    #   15-55%  hold the stance with a faint tremor (the window in which a blow is countered)
    #   55-72%  the riposte: step in, thrust
    guard = build_pose(style, base, A(hand=(0.10, 0.22, 0.02), wpn=(-12, 92), torso=(-6, 0, -12), head=(-4, 0, 0), hips=(0, -0.10, -0.10),
                                      legs=(-4, 32, 34, 44), armL={"hand": (0.28, 0.34, -0.06)}), power=False)
    tremor = over(guard, torso=(-5.0, 0.0, -11.0), hips=(0, -0.11, -0.10))
    rip = build_pose(style, base, A(hand=(0.04, 0.54, -0.12), wpn=(0, 10), torso=(20, 0, 12), hips=(0, 0.34, -0.08),
                                    legs=(-24, 12, 36, 46), armL={"hand": (0.30, 0.14, -0.14)}), power=False)
    return [(0.0, base, "lin"), (0.15, guard, "out"), (0.35, tremor, "in_out"), (0.55, guard, "in_out"), (0.64, rip, "in"),
            (0.76, rip, "lin"), (1.0, base, "in_out")]


# ------------------------------------------------------------------------------------------
# Hit reactions (cosmetic; they start and end on the ready pose so they crossfade into idle)
# ------------------------------------------------------------------------------------------
def recoil_pose(style, base, k):
    p = over(base, torso=(-9.0 * k, 0.0, -5.0 * k), head=(-8.0 * k, 0.0, 4.0 * k), hips=(0.0, -0.045 * k, -0.02 * k))
    for leg in ("legR", "legL"):
        sw, sp, kn, toe = p[leg]
        p[leg] = (sw - 4.0 * k, sp, kn + 7.0 * k, toe)
    for side in ("armR", "armL"):
        if p[side]["follow"] < 0.5:   # two-handed grips keep the off hand on the shaft via `follow`
            h = p[side]["hand"]
            p[side]["hand"] = (h[0] + 0.03 * k, h[1] - 0.09 * k, h[2] + 0.05 * k)
    return p


def hit_react_keys(style, heavy):
    base = ready(style)
    if not heavy:
        hit = recoil_pose(style, base, 1.0)
        return [(0.0, base, "lin"), (0.26, hit, "out"), (0.58, poses.blend(hit, base, 0.45), "in_out"), (1.0, base, "in_out")]
    hit = recoil_pose(style, base, 2.3)
    stumble = over(poses.blend(hit, base, 0.35), legR=(-2.0, _spread(style), 22.0, 0.0), legL=(12.0, _spread(style), 10.0, 0.0))
    return [(0.0, base, "lin"), (0.16, hit, "out"), (0.36, hit, "lin"), (0.62, stumble, "in_out"), (1.0, base, "in_out")]


# ------------------------------------------------------------------------------------------
# Victory (held end pose; each class has its own gesture)
# ------------------------------------------------------------------------------------------
def victory_keys(style, cls):
    base = ready(style)

    def P(**kw):
        return build_pose(style, base, A(**kw), power=False)

    if cls == "pawn":        # plant the spear, then thrust it overhead with a raised fist
        plant = P(hand=(0.26, 0.18, -0.16), wpn=(0, 88), armL={"follow": 0.0, "hand": (0.10, 0.10, -0.30)}, torso=(2, 0, -6), legs=(-6, 26, 10, 22))
        up = P(hand=(0.20, 0.10, 0.46), wpn=(0, 92), armL={"follow": 0.0, "hand": (0.34, 0.06, 0.46)}, torso=(-10, 0, 0),
               head=(-18, 0, 0), hips=(0, 0, 0.02), legs=(-6, 24, 8, 18))
        return [(0.0, base, "lin"), (0.26, plant, "out"), (0.52, up, "out"), (0.64, over(up, hips=(0, 0, 0.05)), "in_out"), (0.76, up, "in_out"), (1.0, up, "lin")]
    if cls == "knight":      # bow, then a formal sword salute
        bow = P(hand=(0.08, 0.30, -0.10), wpn=(0, 70), torso=(14, 0, 0), head=(14, 0, 0), hips=(0, 0.02, -0.04), legs=(-8, 22, 18, 26))
        salute = P(hand=(0.04, 0.26, 0.20), wpn=(6, 92), torso=(-4, 0, 0), head=(2, 0, 0), legs=(-4, 24, 8, 20))
        return [(0.0, base, "lin"), (0.34, bow, "in_out"), (0.60, salute, "out"), (1.0, salute, "lin")]
    if cls == "bishop":      # staff raised in benediction, free palm open, a slow hover
        up = P(hand=(0.12, 0.14, 0.42), wpn=(0, 96), armL={"follow": 0.0, "hand": (0.34, 0.12, 0.40)}, torso=(-10, 0, 0),
               head=(-20, 0, 0), hips=(0, 0, 0.02), legs=(-4, 18, 6, 14))
        return [(0.0, base, "lin"), (0.45, up, "out"), (0.72, over(up, hips=(0, 0, 0.06)), "in_out"), (1.0, up, "in_out")]
    if cls == "rook":        # hammer overhead, then slammed into the ground and left planted
        raise_ = P(hand=(0.10, 0.02, 0.46), wpn=(0, 112), torso=(-14, 0, 0), head=(-14, 0, 0), hips=(0, -0.02, 0), legs=(-8, 34, 16, 38))
        slam = P(hand=(0.08, 0.46, -0.36), wpn=(0, -58), torso=(28, 0, 0), hips=(0, 0.18, -0.18), legs=(-12, 38, 52, 42),
                 armL={"hand": (0.0, 0.46, -0.10), "shield": (0, 0)})
        planted = P(hand=(0.12, 0.40, -0.34), wpn=(0, -62), torso=(6, 0, 0), head=(-10, 0, 0), hips=(0, 0.06, -0.04), legs=(-8, 32, 14, 30))
        return [(0.0, base, "lin"), (0.30, raise_, "out"), (0.50, slam, "in"), (0.58, over(slam, hips=(0, 0.16, -0.16)), "out"),
                (0.76, planted, "in_out"), (1.0, planted, "lin")]
    if cls == "queen":       # blade flourish: cross, flare wide, hold
        cross = P(hand=(-0.10, 0.42, 0.10), wpn=(30, 70), armL={"hand": (-0.10, 0.42, 0.10), "wpn": (-30, 70)}, torso=(8, 0, 0),
                  hips=(0, 0.04, -0.04), legs=(-10, 22, 24, 28))
        flare = P(hand=(0.40, 0.10, 0.30), wpn=(-60, 80), armL={"hand": (0.40, 0.10, 0.30), "wpn": (60, 80)}, torso=(-12, 0, 0),
                  head=(-18, 0, 0), hips=(0, 0, -0.02), legs=(-6, 28, 14, 20))
        return [(0.0, base, "lin"), (0.22, cross, "in_out"), (0.46, flare, "out"), (0.62, cross, "in_out"), (0.84, flare, "out"), (1.0, flare, "lin")]
    # king: sword thrust skyward, crown held high, free hand to the chest
    sky = P(hand=(0.14, 0.10, 0.48), wpn=(0, 98), armL={"hand": (0.18, 0.30, 0.02)}, torso=(-12, 0, 0), head=(-12, 0, 0),
            hips=(0, 0, 0.02), legs=(-4, 28, 8, 22))
    low = P(hand=(0.10, 0.30, -0.10), wpn=(0, 70), armL={"hand": (0.18, 0.30, 0.02)}, torso=(4, 0, 0), legs=(-6, 28, 14, 26))
    return [(0.0, base, "lin"), (0.28, low, "in_out"), (0.56, sky, "out"), (1.0, sky, "lin")]


# ------------------------------------------------------------------------------------------
# Keying
# ------------------------------------------------------------------------------------------
def _frames(n):
    f = list(range(0, n + 1, STEP))
    if f[-1] != n:
        f.append(n)
    return f


def _key(arm, solver, frame, pose):
    rot, hips = solver.solve(pose)
    for bone, (p, r, y) in rot.items():
        skeleton.key_pose(arm, bone, frame, p, r, y, location=hips if bone == "Hips" else None)


def add_all(arm, cls, style, joints):
    solver = poses.Solver(joints, style)
    frames = spec.clip_frames(cls)

    def periodic(fn):
        def build(a):
            n = frames[build.name]
            for f in _frames(n):
                _key(a, solver, f, fn(f / n))
        return build

    def timeline(keys_fn):
        def build(a):
            n = frames[build.name]
            keys = keys_fn()
            for f in _frames(n):
                _key(a, solver, f, poses.sample(keys, f / n))
        return build

    makers = {
        "idle": periodic(lambda ph: idle_pose(style, ph)),
        "walk": periodic(lambda ph: loco_pose(style, "walk", ph)),
        "run": periodic(lambda ph: loco_pose(style, "run", ph)),
        "strafe_left": periodic(lambda ph: loco_pose(style, "strafe_left", ph)),
        "strafe_right": periodic(lambda ph: loco_pose(style, "strafe_right", ph)),
        "block": periodic(lambda ph: block_loop(style, ph)),
        "parry": timeline(lambda: parry_keys(style, cls, frames["parry"])),
        "dodge": timeline(lambda: dodge_keys(style)),
        "stagger": timeline(lambda: stagger_keys(style)),
        "ability": timeline(lambda: ability_keys(style, cls, frames["ability"])),
        "defeat": timeline(lambda: defeat_keys(style)),
        "victory": timeline(lambda: victory_keys(style, cls)),
        "hit_react_light": timeline(lambda: hit_react_keys(style, False)),
        "hit_react_heavy": timeline(lambda: hit_react_keys(style, True)),
    }
    for clip in ("light_1", "light_2", "light_3", "heavy"):
        makers[clip] = timeline(lambda clip=clip: attack_keys(style, cls, clip))
    for name in spec.CLIP_NAMES:
        fn = makers[name]
        fn.name = name
        export.add_clip(arm, name, fn, frames[name])
