#!/usr/bin/env python3
"""Extract each paladin GLB's base-colour texture and write white and black variants (gold trim is kept).

    python3 tools/paladins/build_textures.py

Input:  godot/assets/paladins/<role>.glb (Meshy / Mixamo rigged, one material, baseColor texture embedded)
Output: godot/assets/paladins/textures/<role>_w.jpg  (ivory/silver: slightly brighter and warmer)
        godot/assets/paladins/textures/<role>_b.jpg  (dark gunmetal: silver/white recoloured dark, gold and dark leather kept)
The mesh UVs are untouched, so the variants are applied at run time as an albedo override (PaladinModel).
"""
import json, struct, io, sys
from pathlib import Path
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2] / "godot/assets/paladins"
ROLES = ["pawn", "knight", "bishop", "rook", "king"]


def base_color_image(glb: Path) -> Image.Image:
    d = glb.read_bytes()
    jl = struct.unpack("<I", d[12:16])[0]
    j = json.loads(d[20:20 + jl])
    binoff = 20 + jl + 8
    mat = j["materials"][0]["pbrMetallicRoughness"]
    tex = j["textures"][mat["baseColorTexture"]["index"]]
    view = j["bufferViews"][j["images"][tex["source"]]["bufferView"]]
    start = binoff + view.get("byteOffset", 0)
    return Image.open(io.BytesIO(d[start:start + view["byteLength"]])).convert("RGB")


def hsv_arrays(img: Image.Image):
    hsv = np.asarray(img.convert("HSV")).astype(np.float32) / 255.0
    return hsv[..., 0], hsv[..., 1], hsv[..., 2]


def recolor(img: Image.Image, side: str) -> Image.Image:
    rgb = np.asarray(img).astype(np.float32) / 255.0
    h, s, v = hsv_arrays(img)
    # gold = warm hue (about 30-60 degrees) with real saturation; everything else is steel / cloth / leather
    gold = ((h > 0.08) & (h < 0.18) & (s > 0.35)).astype(np.float32)
    # soften the mask so the gold edge does not get a halo
    gold = np.asarray(Image.fromarray((gold * 255).astype(np.uint8)).filter(__import__("PIL.ImageFilter", fromlist=["x"]).GaussianBlur(1.2))).astype(np.float32) / 255.0
    lum = (0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2])[..., None]
    if side == "b":
        # dark gunmetal with a cool tint; keep some of the original shading so the relief still reads
        dark = np.clip(lum * 0.30 + 0.025, 0, 1) * np.array([0.92, 0.97, 1.08], dtype=np.float32)
        out = rgb * gold[..., None] + dark * (1 - gold[..., None])
    else:
        # ivory / bright silver: lift the greys, warm them slightly, leave gold alone
        light = np.clip(lum * 1.18 + 0.06, 0, 1) * np.array([1.03, 1.0, 0.94], dtype=np.float32)
        out = rgb * gold[..., None] + np.clip(light, 0, 1) * (1 - gold[..., None])
    return Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8))


def main() -> int:
    (ROOT / "textures").mkdir(parents=True, exist_ok=True)
    for role in ROLES:
        glb = ROOT / f"{role}.glb"
        if not glb.exists():
            print("missing", glb, file=sys.stderr)
            continue
        base = base_color_image(glb)
        for side in ("w", "b"):
            out = ROOT / "textures" / f"{role}_{side}.jpg"
            recolor(base, side).save(out, quality=90)
            print("wrote", out.relative_to(ROOT.parents[2]), out.stat().st_size // 1024, "KB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
