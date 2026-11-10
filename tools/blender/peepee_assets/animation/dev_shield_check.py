import sys, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from peepee_assets import runtime, skeleton
from peepee_assets.animation import kinematics as K, library, poses, clips
from mathutils import Vector
runtime.reset_scene()
arm, joints = skeleton.build_armature("T")
for cls in ("knight", "rook"):
    style = library.resolve_style(cls, {})
    solver = poses.Solver(joints, style)
    for name, pose in (("ready", clips.ready(style)), ("block", clips.block_pose(style))):
        rot, hips = solver.solve(pose)
        q = {b: K.from_pry(*v) for b, v in rot.items()}
        heads, rots = solver.kin.fk(q, hips)
        n = rots["LeftLowerArm"] @ solver.normal
        want = K.direction(*pose["armL"]["shield"])
        axis = (heads["LeftHand"] - heads["LeftLowerArm"]).normalized()
        print(f"{cls:6s} {name:5s} shield normal={tuple(round(x,2) for x in n)} want={tuple(round(x,2) for x in want)} "
              f"error={math.degrees(n.angle(want)):.1f} deg  forearm axis={tuple(round(x,2) for x in axis)}")
