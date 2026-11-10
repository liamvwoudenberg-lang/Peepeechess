"""Deterministic procedural textures (numpy, no external files). 256x256 tileable PNGs,
written with a tiny pure-Python PNG encoder so output bytes are reproducible.

ensure_texture(name, kind, color) -> Path  (writes godot/assets/combat/textures/<name>.png if
missing; same inputs always give the same bytes).
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

import numpy as np

from .runtime import ASSET_ROOT

TEXTURE_DIR = ASSET_ROOT / "textures"
SIZE = 256
KINDS = ("steel", "leather", "cloth", "wood", "stone_floor", "stone_wall", "rust")


def write_png(path: Path, rgb: np.ndarray) -> None:
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag: bytes, data: bytes) -> bytes:
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


def _smooth(t):
    return t * t * (3 - 2 * t)


def value_noise(rng, cells_x: int, cells_y: int, size: int = SIZE) -> np.ndarray:
    """Tileable value noise in [0,1], `cells_x` x `cells_y` lattice."""
    grid = rng.random((cells_y, cells_x))
    xs = np.linspace(0, cells_x, size, endpoint=False)
    ys = np.linspace(0, cells_y, size, endpoint=False)
    x0 = np.floor(xs).astype(int) % cells_x
    y0 = np.floor(ys).astype(int) % cells_y
    x1, y1 = (x0 + 1) % cells_x, (y0 + 1) % cells_y
    tx = _smooth(xs - np.floor(xs))[None, :]
    ty = _smooth(ys - np.floor(ys))[:, None]
    a = grid[y0][:, x0]
    b = grid[y0][:, x1]
    c = grid[y1][:, x0]
    d = grid[y1][:, x1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(rng, base: int = 4, octaves: int = 4, size: int = SIZE, stretch: float = 1.0) -> np.ndarray:
    total, amp, norm = np.zeros((size, size)), 1.0, 0.0
    for o in range(octaves):
        cx = base * 2 ** o
        cy = max(1, int(round(cx * stretch)))
        total += amp * value_noise(rng, cx, cy, size)
        norm += amp
        amp *= 0.5
    return total / norm


def _scratches(rng, count: int, size: int = SIZE) -> np.ndarray:
    img = np.zeros((size, size))
    for _ in range(count):
        x, y = rng.integers(0, size, 2)
        length = int(rng.integers(12, 70))
        dx, dy = rng.normal(0, 1, 2)
        n = max(abs(dx), abs(dy), 1e-3)
        dx, dy = dx / n, dy / n
        for i in range(length):
            img[int(y + dy * i) % size, int(x + dx * i) % size] = rng.uniform(0.3, 1.0)
    return img


def _voronoi(rng, points: int, size: int = SIZE) -> np.ndarray:
    pts = rng.random((points, 2)) * size
    ys, xs = np.mgrid[0:size, 0:size]
    best = np.full((size, size), 1e9)
    for px, py in pts:
        for ox in (-size, 0, size):
            for oy in (-size, 0, size):
                d = (xs - (px + ox)) ** 2 + (ys - (py + oy)) ** 2
                best = np.minimum(best, d)
    best = np.sqrt(best)
    return best / best.max()


def generate(kind: str, color, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    base = np.array(color[:3], dtype=float)
    n = fbm(rng, 4, 4)
    if kind == "steel":
        streak = fbm(rng, 2, 3, stretch=24.0)
        value = 0.78 + 0.22 * n + 0.12 * (streak - 0.5) + 0.25 * _scratches(rng, 160)
    elif kind == "leather":
        cells = _voronoi(rng, 90)
        value = 0.7 + 0.3 * cells + 0.18 * (n - 0.5)
    elif kind == "cloth":
        xs = np.arange(SIZE)
        weave = 0.5 + 0.5 * np.sin(xs[None, :] * 2 * np.pi / 4) * np.sin(xs[:, None] * 2 * np.pi / 4)
        value = 0.78 + 0.14 * weave + 0.2 * (n - 0.5)
    elif kind == "wood":
        grain = fbm(rng, 3, 4, stretch=14.0)
        value = 0.7 + 0.3 * grain + 0.08 * (n - 0.5)
    elif kind in ("stone_floor", "stone_wall"):
        tiles_x, tiles_y = (4, 4) if kind == "stone_floor" else (4, 8)
        value = np.zeros((SIZE, SIZE))
        tw, th = SIZE // tiles_x, SIZE // tiles_y
        for ty in range(tiles_y):
            for tx in range(tiles_x):
                shift = (th // 2 if (kind == "stone_wall" and ty % 2) else 0)
                tone = rng.uniform(0.78, 1.08)
                ys = (np.arange(th) + ty * th) % SIZE
                xs_ = (np.arange(tw) + tx * tw + shift) % SIZE
                value[np.ix_(ys, xs_)] = tone
        yy, xx = np.mgrid[0:SIZE, 0:SIZE]
        ex = np.minimum((xx % tw), tw - 1 - (xx % tw))
        ey = np.minimum((yy % th), th - 1 - (yy % th))
        grout = np.where(np.minimum(ex, ey) < 2, 0.45, 1.0)
        value = value * grout * (0.82 + 0.3 * n) + 0.1 * _scratches(rng, 60)
    elif kind == "rust":
        value = 0.55 + 0.45 * n + 0.2 * (fbm(rng, 8, 3) - 0.5)
        value = value * (0.7 + 0.5 * fbm(rng, 3, 2))
    else:
        raise ValueError(f"unknown texture kind {kind}")
    rgb = np.clip(base[None, None, :] * np.asarray(value)[..., None], 0.0, 1.0)
    return (rgb * 255.0 + 0.5).astype(np.uint8)


def ensure_texture(name: str, kind: str, color, seed: int = 1) -> Path:
    """Writes <textures>/<name>.png when absent and returns its path."""
    path = TEXTURE_DIR / f"{name}.png"
    if not path.exists():
        write_png(path, generate(kind, color, seed))
    return path
