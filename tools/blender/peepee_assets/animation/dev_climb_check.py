"""Dev check: python dev_climb_check.py  -> contact accuracy / slide of the climb clip for all six classes.
Hands = the Hand joint (wrist), feet = the Toes joint (ball). A limb is 'holding' while its relative height falls; in the world it
must not move (world = body-relative + body rise 2*RUNG per cycle)."""
import importlib
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
import bpy  # noqa: F401  (registers mathutils)
from mathutils import Vector

from peepee_assets import runtime, skeleton
from peepee_assets.animation import kinematics as K, library, poses, spec
from peepee_assets.animation import world_clips as W
from peepee_assets.animation.clips import ready

runtime.reset_scene()
for cls in spec.CLASSES:
    mod = importlib.import_module(f"peepee_assets.characters.{cls}")
    arm, joints = skeleton.build_armature(cls.capitalize(), **mod.PROPORTIONS)
    style = library.resolve_style(cls, mod.STYLE)
    solver = poses.Solver(joints, style)
    cl = W.Climber(solver, style)
    base = ready(style)
    n = spec.CLIMB_TICKS
    tracks = {k: [] for k in ("RightHand", "LeftHand", "RightToes", "LeftToes")}
    knee_f = []
    for f in range(n + 1):
        u = f / n
        rot, hips = solver.solve(cl.pose(u, base))
        q = {b: K.from_pry(*v) for b, v in rot.items()}
        heads, rots = solver.kin.fk(q, hips)
        rise = 2 * spec.RUNG_SPACING * u
        for k in tracks:
            h = heads[k] if k.endswith("Hand") else heads[k.replace("Toes", "Foot")] + rots[k.replace("Toes", "Foot")] @ (solver.kin.tail[k.replace("Toes", "Foot")] - solver.kin.head[k.replace("Toes", "Foot")])
            tracks[k].append(Vector((h.x, h.y, h.z + rise)))
        knee_f.append(max(-heads["RightLowerLeg"].y, -heads["LeftLowerLeg"].y))
    out = [f"{cls:7s}"]
    for k, pts in tracks.items():
        # holding window: group A (RightHand, LeftToes) holds for u in [0.5,1]; group B for u in [0,0.5]
        hold = range(n // 2, n + 1) if k in ("RightHand", "LeftToes") else range(0, n // 2 + 1)
        ys = [pts[i] for i in hold]
        dev = max((p - ys[0]).length for p in ys)
        out.append(f"{k} slide {dev*100:4.1f}cm y={-ys[0].y:.2f} z0={ys[0].z:.2f}")
    def grid_err(k, off):
        hold = list(range(n // 2, n + 1)) if k in ("RightHand", "LeftToes") else list(range(0, n // 2 + 1))
        zc = tracks[k][hold[0]].z - off
        return (zc / spec.RUNG_SPACING - 0.5 - round(zc / spec.RUNG_SPACING - 0.5)) * spec.RUNG_SPACING
    out.append("grid err hand %.1f/%.1fcm foot %.1f/%.1fcm" % tuple(100 * grid_err(k, o) for k, o in (("RightHand", W.GRIP_BELOW_WRIST), ("LeftHand", W.GRIP_BELOW_WRIST), ("RightToes", W.BALL_ABOVE_RUNG), ("LeftToes", W.BALL_ABOVE_RUNG))))
    out.append(f"shift h{cl.hand_shift*100:+.1f} f{cl.foot_shift*100:+.1f}cm")
    out.append(f"knee max fwd {max(knee_f):.2f}")
    # loop closure
    out.append("loop err " + f"{max((tracks[k][0] - (tracks[k][-1] - Vector((0,0,2*spec.RUNG_SPACING)))).length for k in tracks)*100:.2f}cm")
    print(" | ".join(out))
if "--dump" in sys.argv:
    for f in range(0, n + 1, 4):
        print(f, [f"{p.y:+.3f},{p.z:.3f}" for p in (tracks["LeftToes"][f], tracks["RightToes"][f])])
