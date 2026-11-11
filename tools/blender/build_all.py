"""Regenerates every combat asset.

  blender --background --python tools/blender/build_all.py -- [--only pawn,knight|arena] [--no-lods]
  (or, with the bpy wheel)  python tools/blender/build_all.py [--only ...]

Writes godot/assets/combat/{characters/<class>/*.glb, arena/stone_arena.glb, textures/*.png,
manifest/asset_manifest.json}. Deterministic: no randomness except fixed seeds in textures.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from peepee_assets import runtime
from peepee_assets.animation import spec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--no-lods", action="store_true")
    ap.add_argument("--out", default="", help="asset root to write into instead of godot/assets/combat (scratch builds)")
    args = ap.parse_args(runtime.script_args())
    if args.out:
        # Redirect EVERYTHING (GLBs, textures, manifest) so a scratch build never touches the live assets.
        from pathlib import Path as _P
        from peepee_assets import textures
        runtime.ASSET_ROOT = _P(args.out).resolve()
        textures.TEXTURE_DIR = runtime.ASSET_ROOT / "textures"
    wanted = [w for w in args.only.split(",") if w] or spec.CLASSES + ["arena"]
    manifest_path = runtime.ASSET_ROOT / "manifest" / "asset_manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"characters": {}}
    from peepee_assets.characters import base
    for cls in spec.CLASSES:
        if cls in wanted:
            runtime.log(f"building {cls}")
            manifest["characters"][cls] = base.make_character(cls, runtime.ASSET_ROOT / "characters" / cls, not args.no_lods)
    if "arena" in wanted:
        from peepee_assets import arena
        runtime.log("building arena")
        manifest["arena"] = arena.build(runtime.ASSET_ROOT / "arena")
    manifest["generator"] = {"blender": __import__("bpy").app.version_string, "script": "tools/blender/build_all.py"}
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    runtime.log("done")


main()
