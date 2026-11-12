"""For every attack clip of every class: the frame of peak weapon-hand speed and of max forward reach,
compared with the sim's active window from spec.MARKERS."""
import sys, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from peepee_assets import runtime, skeleton
from peepee_assets.animation import kinematics as K, library, poses, clips, spec
from mathutils import Vector
runtime.reset_scene()
arm, joints = skeleton.build_armature("T")
bad = 0
for cls in spec.CLASSES:
    style = library.resolve_style(cls, {})
    solver = poses.Solver(joints, style)
    frames = spec.clip_frames(cls)
    for clip in ("light_1", "light_2", "light_3", "heavy"):
        n = frames[clip]; se, ae, _c = spec.MARKERS[cls][clip]
        keys = clips.attack_keys(style, cls, clip)
        side = "LeftHand" if (style["grip"] == "dual" and clip == "light_2") else "RightHand"
        pos = []
        for f in range(n + 1):
            rot, hips = solver.solve(poses.sample(keys, f / n))
            q = {b: K.from_pry(*v) for b, v in rot.items()}
            heads, _ = solver.kin.fk(q, hips)
            pos.append(heads[side])
        speed = [(pos[i + 1] - pos[i]).length for i in range(n)]
        peak = max(range(n), key=lambda i: speed[i])
        lo, hi = se * n, ae * n
        ok = lo - 1 <= peak <= hi + 1
        bad += 0 if ok else 1
        print(f"{cls:6s} {clip:8s} frames={n:2d} active=[{lo:5.1f},{hi:5.1f}] peak-speed frame={peak:2d} {'OK' if ok else 'OUTSIDE'}")
print("outside active window:", bad)
