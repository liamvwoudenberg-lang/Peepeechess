"""PBR materials (glTF-compatible Principled BSDF: base-colour texture + metallic/roughness factors).

A material may carry a procedural texture (ensure_texture) or be a plain colour. Plain-colour
materials named `*_Accent` are the team-tint surfaces: Godot overrides their albedo at runtime
(White = ivory/gold, Black = crimson/violet) without touching the textured materials.
"""
from __future__ import annotations

import bpy

from .textures import ensure_texture


def get_material(name: str, color=(0.5, 0.5, 0.5), kind: str | None = None, tex_color=None,
                 metallic: float = 0.0, roughness: float = 0.8, emission=None,
                 emission_strength: float = 1.0, uv_m: float = 0.5, seed: int = 1, tex_size: int = 256):
    """Returns (creating if needed) the named material. `uv_m` = metres of surface per texture
    tile, used by modeling.MeshBuilder for the box-projected UVs."""
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = nodes["Principled BSDF"]
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if kind:
        path = ensure_texture(f"{name}", kind, tex_color or color, seed, tex_size)
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(str(path), check_existing=True)
        tex.image.colorspace_settings.name = "sRGB"
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color[:3], 1.0)
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission[:3], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emission_strength
    mat["uv_m"] = uv_m
    return mat
