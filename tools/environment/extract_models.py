#!/usr/bin/env python3
"""Unpack the Meshy packages in newmodels/ into godot/assets/environment/<name>/ (model.fbx + albedo/normal/roughness/metallic PNGs).

    python3 tools/environment/extract_models.py

The FBX files reference their textures by the original long names; the importer finds them next to the FBX, so the original names are kept
and a short alias list (below) tells the game which folder holds what. Idempotent.
"""
import shutil, sys, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "newmodels"
DST = ROOT / "godot/assets/environment"
NAMES = {
    "Weathered_Chessboard": "chessboard", "Ancient_Stone_Circle": "stone_circle", "Moss_Crowned_Pillar": "pillar",
    "Mossbound_Ancient_Archway": "archway", "Rustbound_Torch_Sconce": "torch_sconce", "Tattered_Heraldic_Banner": "banner",
    "Weathered_Ascent": "ascent", "castle_courtyard_fortress": "courtyard_fortress",
}


def short(name: str) -> str:
    for key, value in NAMES.items():
        if key in name:
            return value
    raise SystemExit("unknown package " + name)


def main() -> int:
    DST.mkdir(parents=True, exist_ok=True)
    for z in sorted(SRC.glob("*.zip")):
        out = DST / short(z.name)
        out.mkdir(exist_ok=True)
        with zipfile.ZipFile(z) as archive:
            for info in archive.infolist():
                if info.is_dir():
                    continue
                target = out / Path(info.filename).name
                target.write_bytes(archive.read(info))
    fortress_dir = next((p for p in SRC.iterdir() if p.is_dir()), None)
    if fortress_dir:
        out = DST / "courtyard_fortress"
        out.mkdir(exist_ok=True)
        for f in fortress_dir.rglob("*"):
            if f.is_file():
                shutil.copy2(f, out / f.name)
    for d in sorted(DST.iterdir()):
        print(d.name, sorted(p.suffix for p in d.iterdir() if p.is_file() and p.suffix in (".fbx", ".png")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
