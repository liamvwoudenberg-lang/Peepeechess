"""GLB export + LOD helpers."""
from __future__ import annotations

from pathlib import Path

import bpy

from .runtime import make_active


def add_clip(armature, name: str, build_fn, frames: int) -> None:
    """Creates action `name` by calling build_fn(armature) (which keys poses on frames 0..frames),
    then parks it on its own NLA track so the glTF exporter writes it as a separate animation."""
    ad = armature.animation_data_create()
    action = bpy.data.actions.new(name)
    ad.action = action
    build_fn(armature)
    action.frame_range = (0, frames)
    ad.action = None
    track = ad.nla_tracks.new()
    track.name = name
    strip = track.strips.new(name, 0, action)
    strip.name = name


def export_glb(path: Path, objects, animations: bool = True) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True,
        export_apply=False, export_yup=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="AUTO", export_skins=True,
        export_animations=animations, export_animation_mode="NLA_TRACKS",
        export_force_sampling=True, export_optimize_animation_size=True, export_def_bones=False,
        export_cameras=False, export_lights=False)
    return path.stat().st_size


def make_lod(objects, ratio: float):
    """Decimated duplicates of mesh objects (vertex groups preserved). Returns the new objects."""
    out = []
    for obj in objects:
        copy = obj.copy()
        copy.data = obj.data.copy()
        copy.name = obj.name + "_LOD"
        bpy.context.scene.collection.objects.link(copy)
        copy.parent = obj.parent
        copy.parent_type = obj.parent_type
        copy.parent_bone = obj.parent_bone
        copy.matrix_parent_inverse = obj.matrix_parent_inverse.copy()
        mod = copy.modifiers.new("Decimate", "DECIMATE")
        mod.ratio = ratio
        make_active(copy)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        copy.data.validate(clean_customdata=True)  # decimation can leave duplicate/degenerate faces
        copy.data.update()
        out.append(copy)
    return out
