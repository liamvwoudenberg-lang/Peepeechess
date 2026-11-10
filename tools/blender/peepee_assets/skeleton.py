"""The shared humanoid skeleton.

One bone hierarchy and one set of bone names for all six classes, so every clip and every
Godot-side attachment works on every character. Names follow Godot's SkeletonProfileHumanoid
(Hips, Spine, Chest, UpperChest, Neck, Head, LeftShoulder, LeftUpperArm, ...) so Godot's
humanoid retargeting recognises the rig. No fingers (mobile budget). Extra NON-deforming socket
bones carry weapons and props.

Per-class proportions only move joint positions (bone lengths); topology and names never change.

Pose authoring convention (see set_pose): rotations are given as (pitch, roll, yaw) in degrees
about the ARMATURE axes, regardless of each bone's own rest orientation:
  pitch = about +X (character's left axis).  Positive tips the top of a part FORWARD (-Y); a
          hanging arm/leg therefore swings BACKWARD for positive pitch, FORWARD for negative.
  roll  = about +Y (the forward/back axis). For an arm hanging down, positive roll swings it
          toward -X (the character's right).
  yaw   = about +Z. Positive turns the front toward +X (the character's left).
Rotations compose down the chain as armature-axis rotations (child = parent_rot * own_rot * rest).
"""
from __future__ import annotations

import math

import bpy
from mathutils import Euler, Matrix, Vector

from .runtime import link, make_active

# (name, parent, head, tail) for the LEFT/centre bones, base proportions, height 1.8 m,
# character faces -Y, left is +X. Right-side bones are mirrored automatically.
_CENTRE = [
    ("Root", None, (0, 0, 0), (0, 0, 0.12)),
    ("Hips", "Root", (0, 0, 0.95), (0, 0, 1.05)),
    ("Spine", "Hips", (0, 0, 1.05), (0, 0, 1.20)),
    ("Chest", "Spine", (0, 0, 1.20), (0, 0, 1.36)),
    ("UpperChest", "Chest", (0, 0, 1.36), (0, 0, 1.52)),
    ("Neck", "UpperChest", (0, 0, 1.52), (0, 0, 1.62)),
    ("Head", "Neck", (0, 0, 1.62), (0, 0, 1.82)),
]
_LEFT = [
    ("LeftShoulder", "UpperChest", (0.04, 0, 1.47), (0.17, 0, 1.48)),
    ("LeftUpperArm", "LeftShoulder", (0.17, 0, 1.48), (0.21, 0, 1.19)),
    ("LeftLowerArm", "LeftUpperArm", (0.21, 0, 1.19), (0.235, 0, 0.93)),
    ("LeftHand", "LeftLowerArm", (0.235, 0, 0.93), (0.25, 0, 0.80)),
    ("LeftUpperLeg", "Hips", (0.10, 0, 0.95), (0.11, 0, 0.52)),
    ("LeftLowerLeg", "LeftUpperLeg", (0.11, 0, 0.52), (0.11, 0, 0.10)),
    ("LeftFoot", "LeftLowerLeg", (0.11, 0, 0.10), (0.11, -0.13, 0.04)),
    ("LeftToes", "LeftFoot", (0.11, -0.13, 0.04), (0.11, -0.23, 0.02)),
]
# Non-deforming sockets. head/tail in base proportions.
_SOCKETS = [
    ("WeaponSocket_R", "RightHand", (-0.2425, 0, 0.87), (-0.2425, 0, 0.79)),
    ("WeaponSocket_L", "LeftHand", (0.2425, 0, 0.87), (0.2425, 0, 0.79)),
    ("ShieldSocket_L", "LeftLowerArm", (0.28, -0.02, 1.06), (0.28, -0.08, 1.06)),
    ("BackSocket", "UpperChest", (0.0, 0.14, 1.42), (0.0, 0.22, 1.42)),
    ("HeadTop", "Head", (0, 0, 1.82), (0, 0, 1.90)),
]

DEFORM_BONES = [b[0] for b in _CENTRE] + [n for (n, *_rest) in _LEFT] + [
    n.replace("Left", "Right") for (n, *_rest) in _LEFT]
SOCKET_BONES = [s[0] for s in _SOCKETS]
ALL_BONES = DEFORM_BONES + SOCKET_BONES


def mirror_name(name: str) -> str:
    if name.startswith("Left"):
        return "Right" + name[4:]
    if name.startswith("Right"):
        return "Left" + name[5:]
    if name.endswith("_L"):
        return name[:-2] + "_R"
    if name.endswith("_R"):
        return name[:-2] + "_L"
    return name


def _scaled(p, scale, width):
    x, y, z = p
    return Vector((x * width * scale, y * scale, z * scale))


def bone_table(scale: float = 1.0, shoulder_width: float = 1.0, hip_width: float = 1.0):
    """Full bone list with proportions applied: [(name, parent, head, tail), ...]."""
    rows = []
    for name, parent, head, tail in _CENTRE:
        rows.append((name, parent, _scaled(head, scale, 1.0), _scaled(tail, scale, 1.0)))
    for name, parent, head, tail in _LEFT:
        width = hip_width if "Leg" in name or "Foot" in name or "Toes" in name else shoulder_width
        h = _scaled(head, scale, width)
        t = _scaled(tail, scale, width)
        rows.append((name, parent, h, t))
        mh, mt = Vector((-h.x, h.y, h.z)), Vector((-t.x, t.y, t.z))
        rows.append((mirror_name(name), mirror_name(parent) if parent and parent.startswith("Left") else parent, mh, mt))
    for name, parent, head, tail in _SOCKETS:
        width = shoulder_width
        rows.append((name, parent, _scaled(head, scale, width), _scaled(tail, scale, width)))
    # parents must precede children (Left rows were appended with their mirrored twin right after)
    order = {}
    for i, row in enumerate(rows):
        order[row[0]] = i
    rows.sort(key=lambda r: _depth(r[0], {x[0]: x[1] for x in rows}))
    return rows


def _depth(name, parents):
    d = 0
    while parents.get(name):
        name = parents[name]
        d += 1
    return d


def build_armature(name: str, scale: float = 1.0, shoulder_width: float = 1.0, hip_width: float = 1.0):
    """Creates the armature object. Returns (armature_object, joints) where joints maps bone name ->
    (head Vector, tail Vector) in armature space (== world space; the object sits at the origin)."""
    data = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, data)
    link(obj)
    make_active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    joints = {}
    created = {}
    for bone_name, parent, head, tail in bone_table(scale, shoulder_width, hip_width):
        eb = data.edit_bones.new(bone_name)
        eb.head = head
        eb.tail = tail
        eb.roll = 0.0
        eb.use_deform = bone_name in DEFORM_BONES
        if parent:
            eb.parent = created[parent]
        created[bone_name] = eb
        joints[bone_name] = (Vector(head), Vector(tail))
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in obj.pose.bones:
        pb.rotation_mode = "QUATERNION"
    data.display_type = "STICK"
    return obj, joints


def rest_rotation(armature, bone_name: str) -> Matrix:
    """3x3 rest orientation of a bone in armature space."""
    return armature.data.bones[bone_name].matrix_local.to_3x3()


def set_pose(armature, bone_name: str, pitch=0.0, roll=0.0, yaw=0.0, location=None):
    """Poses `bone_name` with an armature-axis rotation (degrees) and optional armature-space
    translation (metres, mainly for Hips/Root). Does not insert keyframes."""
    pb = armature.pose.bones[bone_name]
    r = rest_rotation(armature, bone_name)
    q = (Matrix.Rotation(math.radians(yaw), 3, "Z")
         @ Matrix.Rotation(math.radians(pitch), 3, "X")
         @ Matrix.Rotation(math.radians(roll), 3, "Y"))
    pb.rotation_mode = "QUATERNION"
    pb.rotation_quaternion = (r.inverted() @ q @ r).to_quaternion()
    if location is not None:
        pb.location = r.inverted() @ Vector(location)
    else:
        pb.location = (0.0, 0.0, 0.0)


def key_pose(armature, bone_name: str, frame: float, pitch=0.0, roll=0.0, yaw=0.0, location=None):
    set_pose(armature, bone_name, pitch, roll, yaw, location)
    pb = armature.pose.bones[bone_name]
    pb.keyframe_insert("rotation_quaternion", frame=frame)
    if location is not None or bone_name in ("Hips", "Root"):
        pb.keyframe_insert("location", frame=frame)


def clear_pose(armature):
    for pb in armature.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0)
        pb.location = (0, 0, 0)
        pb.scale = (1, 1, 1)
