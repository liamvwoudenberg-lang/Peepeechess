import sys, math
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from peepee_assets import runtime, skeleton
from peepee_assets.animation import kinematics as K, library, poses, clips
from mathutils import Vector
runtime.reset_scene()
arm, joints = skeleton.build_armature("T")
style = library.resolve_style("knight", {})
solver = poses.Solver(joints, style)
pose = clips.ready(style)
pose = poses.over(pose, torso=(20, 0, 25), pelvis=(0, 0, 10), hips=(0.02, 0.05, 0.03))
rot, hips = solver.solve(pose)
for b, (p, r, y) in rot.items():
    skeleton.set_pose(arm, b, p, r, y, location=hips if b == "Hips" else None)
import bpy
bpy.context.view_layer.update()
# my FK
q = {b: K.from_pry(*v) for b, v in rot.items()}
heads, rots = solver.kin.fk(q, hips)
worst = 0
for b in ("Head", "RightUpperArm", "LeftLowerArm", "RightHand", "LeftFoot", "RightToes", "WeaponSocket_R"):
    blender = arm.pose.bones[b].head
    d = (blender - heads[b]).length
    worst = max(worst, d)
    print(f"{b:16s} blender={tuple(round(x,3) for x in blender)} mine={tuple(round(x,3) for x in heads[b])} err={d:.5f}")
print("WORST ERR (m):", worst)
