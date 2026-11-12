"""Per-character pipeline. Each class module (pawn.py ...) defines:

    NAME        "pawn"
    PROPORTIONS dict(scale=, shoulder_width=, hip_width=)   -> skeleton.build_armature
    STYLE       dict consumed by animation.library (weapon style, stance); see that module
    def build(arm, joints) -> {"body": <skinned mesh obj>, "props": [prop objs attached to sockets]}

`make_character` runs the whole chain and writes the GLBs + a stats dict for the manifest.
"""
from __future__ import annotations

import importlib
from pathlib import Path

import bmesh
import bpy

from .. import export, modeling, runtime, skeleton
from ..animation import library, spec

LOD1_RATIO = 0.4           # mobile variant: ~40% of the triangles
BUDGET_TRIS = {"lod0": 9000, "lod1": 4000}


def collision_hull(body, name):
    """Convex hull of the body (weapons excluded) as a tiny mesh for physics proxies."""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    res = bmesh.ops.convex_hull(bm, input=bm.verts)
    bmesh.ops.delete(bm, geom=res["geom_unused"] + res["geom_interior"], context="VERTS")
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    runtime.link(obj)
    return obj


def make_character(cls: str, out_dir: Path, lods: bool = True) -> dict:
    mod = importlib.import_module(f"peepee_assets.characters.{cls}")
    runtime.reset_scene()
    arm, joints = skeleton.build_armature(cls.capitalize(), **mod.PROPORTIONS)
    built = mod.build(arm, joints)
    body, props = built["body"], built["props"]
    library.add_all_clips(arm, cls, mod.STYLE, joints)
    out_dir.mkdir(parents=True, exist_ok=True)
    stats = {"class": cls, "role": spec.ROLE[cls], "proportions": mod.PROPORTIONS,
             "tris_lod0": modeling.triangles(body), "props": {p.name: modeling.triangles(p) for p in props}}
    stats["bytes_lod0"] = export.export_glb(out_dir / f"{cls}.glb", [arm, body] + props)
    if lods:
        lod = export.make_lod([body], LOD1_RATIO)[0]
        stats["tris_lod1"] = modeling.triangles(lod)
        stats["bytes_lod1"] = export.export_glb(out_dir / f"{cls}_lod1.glb", [arm, lod] + props)
        hull = collision_hull(body, f"{cls}_collision")
        stats["collision_verts"] = len(hull.data.vertices)
        stats["bytes_collision"] = export.export_glb(out_dir / f"{cls}_collision.glb", [hull], animations=False)
    xs = [v.co.x for v in body.data.vertices]
    ys = [v.co.y for v in body.data.vertices]
    zs = [v.co.z for v in body.data.vertices]
    stats["bounds_body"] = {"x": [min(xs), max(xs)], "y": [min(ys), max(ys)], "z": [min(zs), max(zs)]}
    stats["clips"] = spec.clip_frames(cls)
    # contracts the Godot side checks (test_anim_integrity): the locomotion ground speeds the clips are foot-locked at, the attack markers
    # (startup_end, active_end, cancel_from as fractions) the strikes are authored to, and the King's counter layout.
    stats["nominal_speed_mps"] = dict(spec.NOMINAL_SPEED_MPS)
    stats["markers"] = {clip: list(v) for clip, v in spec.MARKERS[cls].items()}
    if cls == "king":
        stats["counter"] = {"start": spec.COUNTER_START, "end": spec.COUNTER_END, "riposte_start_frame": spec.COUNTER_RIPOSTE_START,
                            "riposte_ticks": spec.COUNTER_RIPOSTE_TICKS}
    return stats
