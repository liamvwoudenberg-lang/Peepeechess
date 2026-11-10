"""Forward/inverse kinematics on the shared skeleton, in pure mathutils (no depsgraph).

Rotation model (matches skeleton.set_pose): every bone has an "own" rotation Q (armature-axis
rotation about the bone's head). Totals compose down the chain: Qtot(child) = Qtot(parent) @ Q(child).
A bone's posed head = parent's rigid transform applied to the child's rest head.

Authoring helpers use a character frame: `cf(out, fwd, up)` etc. are converted to Blender
armature space (character faces -Y, left is +X).
"""
from __future__ import annotations

import math

from mathutils import Matrix, Vector

from .. import skeleton

I3 = Matrix.Identity(3)


def _parents():
    return {name: parent for name, parent, _h, _t in skeleton.bone_table()}


PARENT = _parents()
ORDER = [name for name, *_ in skeleton.bone_table()]          # parents precede children


def arc(a: Vector, b: Vector) -> Matrix:
    """Shortest rotation taking direction a to direction b."""
    return a.normalized().rotation_difference(b.normalized()).to_matrix()


def axis_angle(axis: Vector, degrees: float) -> Matrix:
    return Matrix.Rotation(math.radians(degrees), 3, axis.normalized())


def to_pry(m: Matrix):
    """3x3 rotation -> (pitch, roll, yaw) degrees such that Rz(yaw) @ Rx(pitch) @ Ry(roll) == m."""
    e = m.to_euler("YXZ")
    return (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z))


def from_pry(p, r, y) -> Matrix:
    return (Matrix.Rotation(math.radians(y), 3, "Z") @ Matrix.Rotation(math.radians(p), 3, "X")
            @ Matrix.Rotation(math.radians(r), 3, "Y"))


def cf(out: float, fwd: float, up: float, side: str = "R") -> Vector:
    """Character-frame offset -> armature space. `out` is outward from the body centre for the
    given side ("R": toward the character's right = -X, "L": toward the left = +X)."""
    sign = -1.0 if side == "R" else 1.0
    return Vector((sign * out, -fwd, up))


def direction(az: float, el: float) -> Vector:
    """Unit direction: azimuth 0 = forward, positive toward the character's LEFT; elevation above horizontal."""
    a, e = math.radians(az), math.radians(el)
    return Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))


class Kin:
    def __init__(self, joints):
        self.head = {n: Vector(h) for n, (h, _t) in joints.items()}
        self.tail = {n: Vector(t) for n, (_h, t) in joints.items()}
        self.rest_dir = {n: (self.tail[n] - self.head[n]).normalized() for n in joints}

    def length(self, a: str, b: str) -> float:
        return (self.head[b] - self.head[a]).length

    def fk(self, q: dict, hips_loc: Vector = Vector((0, 0, 0))):
        heads, rots = {}, {}
        for name in ORDER:
            p = PARENT[name]
            own = q.get(name, I3)
            if p is None:
                heads[name] = self.head[name].copy()
                rots[name] = own
            else:
                heads[name] = heads[p] + rots[p] @ (self.head[name] - self.head[p])
                rots[name] = rots[p] @ own
            if name == "Hips":
                heads[name] += hips_loc
        return heads, rots

    def two_bone(self, shoulder: Vector, target: Vector, l1: float, l2: float, pole: Vector):
        """Elbow/knee position for a two-bone chain reaching `target` (clamped to reach)."""
        to = target - shoulder
        dist = max(1e-4, min(to.length, (l1 + l2) * 0.995))
        n = to.normalized()
        a = (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        perp = pole - n * pole.dot(n)
        if perp.length < 1e-5:
            perp = Vector((0, 0, -1)) - n * Vector((0, 0, -1)).dot(n)
        perp.normalize()
        return shoulder + n * a + perp * h, shoulder + n * dist

    def solve_arm(self, side: str, q: dict, hips_loc: Vector, target: Vector, pole: Vector,
                  weapon_axis: Vector | None = None, weapon_dir: Vector | None = None,
                  weapon_roll: float = 0.0, normal_rest: Vector | None = None,
                  normal_dir: Vector | None = None):
        """Poses `<side>UpperArm/LowerArm/Hand` (side = 'Left'/'Right') into q so the wrist reaches
        `target`. Optional: align a prop axis (rest-frame `weapon_axis`) with `weapon_dir`, and
        twist the forearm so a shield normal faces `normal_dir`. Returns the wrist position reached."""
        up_n, lo_n, ha_n = f"{side}UpperArm", f"{side}LowerArm", f"{side}Hand"
        heads, rots = self.fk(q, hips_loc)
        shoulder = heads[up_n]
        l1, l2 = self.length(up_n, lo_n), self.length(lo_n, ha_n)
        elbow, wrist = self.two_bone(shoulder, target, l1, l2, pole)
        # upper arm
        qtot_u = arc(self.rest_dir[up_n], elbow - shoulder)
        parent_rot = rots[PARENT[up_n]]
        q[up_n] = parent_rot.inverted() @ qtot_u
        # forearm: minimal rotation relative to the upper arm (keeps twist continuous)
        d_l = wrist - elbow
        q_rel = arc(self.rest_dir[lo_n], qtot_u.inverted() @ d_l)
        qtot_l = qtot_u @ q_rel
        if normal_rest is not None and normal_dir is not None:
            axis = d_l.normalized()
            n_now = qtot_l @ normal_rest
            a = n_now - axis * n_now.dot(axis)
            b = normal_dir - axis * normal_dir.dot(axis)
            if a.length > 1e-4 and b.length > 1e-4:
                ang = a.angle(b)
                if a.cross(b).dot(axis) < 0:
                    ang = -ang
                qtot_l = axis_angle(axis, math.degrees(ang)) @ qtot_l
        q[lo_n] = qtot_u.inverted() @ qtot_l
        # hand / prop
        if weapon_axis is not None and weapon_dir is not None:
            align = arc(weapon_axis, weapon_dir)
            if weapon_roll:
                align = axis_angle(weapon_dir, weapon_roll) @ align
            q[ha_n] = qtot_l.inverted() @ align
        else:
            q[ha_n] = I3
        return wrist
