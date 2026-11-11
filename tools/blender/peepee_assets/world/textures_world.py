"""Deterministic tileable marble / basalt textures for the board tiles and the chess pieces (numpy only).

`generate(kind, color, seed, size)` -> uint8 RGB array. All kinds are seamless (every noise lattice is periodic and the vein
phase uses integer frequencies), so the same PNG can tile across a surface or be re-offset per tile.
"""
from __future__ import annotations

import numpy as np

from ..textures import fbm, value_noise

KINDS = ("marble_light", "marble_dark", "basalt")


def _veins(rng, size, freq_a, freq_b, warp, sharp):
    """1 on a vein line, 0 away from it (periodic)."""
    yy, xx = np.mgrid[0:size, 0:size] / float(size)
    n = fbm(rng, 3, 4, size)
    phase = 2.0 * np.pi * (freq_a * xx + freq_b * yy) + warp * (n - 0.5) * 2.0 * np.pi
    t = np.abs(np.sin(phase * 0.5))
    return np.clip(1.0 - t * sharp, 0.0, 1.0) ** 2


def generate(kind: str, color, seed: int, size: int = 256) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = np.array(color[:3], dtype=float)
    cloud = fbm(rng, 3, 5, size)
    fine = fbm(rng, 16, 3, size)
    if kind == "marble_light":      # warm ivory marble: soft clouds, thin grey-brown veins
        v1 = _veins(rng, size, 2, 1, 1.6, 9.0)
        v2 = _veins(rng, size, 1, 3, 2.4, 14.0)
        value = 0.90 + 0.16 * (cloud - 0.5) + 0.05 * (fine - 0.5) - 0.20 * v1 - 0.12 * v2
        rgb = base[None, None, :] * value[..., None]
        rgb = rgb * (1.0 + 0.04 * (cloud - 0.5)[..., None] * np.array([1.0, 0.2, -1.0])[None, None, :])
    elif kind == "marble_dark":     # blue-green slate marble: darker clouds, pale veins
        v1 = _veins(rng, size, 1, 2, 1.8, 10.0)
        v2 = _veins(rng, size, 3, 1, 2.2, 16.0)
        value = 0.92 + 0.30 * (cloud - 0.5) + 0.07 * (fine - 0.5)
        rgb = base[None, None, :] * value[..., None] + (0.07 * v1 + 0.04 * v2)[..., None] * np.array([0.8, 0.9, 1.0])[None, None, :]
    elif kind == "basalt":          # near-black fine-grained stone with faint mineral flecks
        flecks = (value_noise(rng, 64, 64, size) > 0.86).astype(float)
        value = 0.88 + 0.35 * (cloud - 0.5) + 0.12 * (fine - 0.5)
        rgb = base[None, None, :] * value[..., None] + 0.05 * flecks[..., None] * np.array([1.0, 0.95, 0.9])[None, None, :]
    else:
        raise ValueError(kind)
    return (np.clip(rgb, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
