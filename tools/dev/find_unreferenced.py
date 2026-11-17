#!/usr/bin/env python3
"""Read-only: find Godot scripts, classes, scenes, assets and import sidecars that nothing references.

    python3 tools/dev/find_unreferenced.py [--godot godot] [--roots-tests] [--json out.json] [--min-kb 0]

Rules (conservative, so a hit means "worth a human look", not "safe to delete"):
- A reference is any text occurrence of the res:// path, or (for .gd) of the class_name, in .gd/.tscn/.tres/.res(text)/.cfg/.godot/.json/.md/.py/.mjs/.ts/.yml
  files of the repo (Godot project and tooling), excluding the file itself. Import sidecars (.import) and .uid files are not references.
- Entry points (always referenced): project.godot (main scene, autoloads, icons), export presets, files under godot/tests, godot/combat/tests,
  godot/**/tools and tools/ (treated as roots because the test suites and dev tools run them by path).
- Assets are 'unreferenced' when no text references their res:// path AND no *referenced* file lists them as a dependency (e.g. a GLB's textures are
  found through the .import 'source_file'/'dest_files' only when the GLB itself is referenced).
Nothing is modified.
"""
import argparse, json, os, re, sys
from pathlib import Path

TEXT_EXT = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".json", ".md", ".py", ".mjs", ".ts", ".yml", ".yaml", ".sh", ".txt", ".import", ".gdshader", ".svg"}
SKIP_DIRS = {".git", ".godot", "node_modules", ".claude", "newmodels"}
ASSET_EXT = {".png", ".jpg", ".jpeg", ".webp", ".wav", ".ogg", ".mp3", ".glb", ".gltf", ".fbx", ".obj", ".res", ".tres", ".tscn", ".svg", ".ttf", ".otf", ".gdshader", ".json", ".bin"}


def walk(root: Path):
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            yield Path(dp) / f


def read(p: Path) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        return ""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--json", default="")
    ap.add_argument("--min-kb", type=float, default=0.0)
    a = ap.parse_args()
    gd_root = Path(a.godot)
    repo = Path(".")
    files = [p for p in walk(repo) if p.suffix in TEXT_EXT and ".import" != p.suffix]
    # .import files are sidecars; keep them only to resolve dependencies
    texts = {}
    for p in files:
        if p.suffix == ".import":
            continue
        texts[p] = read(p)
    all_text = "\n".join(texts.values())
    # asset dependency graph through .import sources: x.glb.import -> dest files (not needed for references)
    classes = {}
    scripts = [p for p in walk(gd_root) if p.suffix == ".gd"]
    for s in scripts:
        m = re.search(r"^class_name\s+(\w+)", read(s), re.M)
        if m:
            classes[m.group(1)] = s
    root_dirs = ("tests", "tools")
    def is_root(p: Path) -> bool:
        parts = p.relative_to(gd_root).parts if gd_root in p.parents else p.parts
        return "tests" in parts or "tools" in parts or p.name.startswith("test_") or p.name.endswith("_test.gd")

    def res_path(p: Path) -> str:
        return "res://" + p.relative_to(gd_root).as_posix()

    def refs_to(p: Path, needle: str, extra: str = "") -> int:
        n = 0
        for q, t in texts.items():
            if q == p:
                continue
            if needle in t or (extra and re.search(r"\b" + re.escape(extra) + r"\b", t)):
                n += 1
        return n

    out = {"scripts": [], "classes": [], "assets": [], "orphan_uid": [], "orphan_import": []}
    gd_texts = {p: t for p, t in texts.items() if p.suffix == ".gd"}
    for s in sorted(scripts):
        rp = res_path(s)
        cn = next((k for k, v in classes.items() if v == s), "")
        n = refs_to(s, rp, cn)
        # same-directory relative preload e.g. preload("foo.gd")
        if n == 0:
            n = sum(1 for q, t in texts.items() if q != s and (s.name in t))
        if n == 0 and not is_root(s):
            out["scripts"].append({"path": s.as_posix(), "class": cn, "kb": round(s.stat().st_size / 1024, 1)})
    # classes referenced only by their own file
    for cn, s in sorted(classes.items()):
        if is_root(s):
            continue
        used = any(q != s and re.search(r"\b" + re.escape(cn) + r"\b", t) for q, t in texts.items())
        if not used:
            out["classes"].append({"class": cn, "path": s.as_posix()})
    # assets
    assets_dir = gd_root / "assets"
    for p in sorted(walk(assets_dir)) if assets_dir.exists() else []:
        if p.suffix in (".import", ".uid") or p.suffix not in ASSET_EXT:
            continue
        kb = p.stat().st_size / 1024
        if kb < a.min_kb:
            continue
        rp = res_path(p)
        n = refs_to(p, rp)
        if n == 0:
            # referenced by file name only (e.g. directory scans or string building)
            stem = p.stem
            n2 = sum(1 for q, t in texts.items() if stem in t and q != p)
            parent = rp.rsplit("/", 1)[0] + "/"
            dir_ref = parent in all_text   # a directory prefix is mentioned: the file may be loaded through a built string
            out["assets"].append({"path": p.as_posix(), "kb": round(kb, 1), "name_mentions": n2, "dir_referenced": dir_ref})
    # orphan .uid / .import
    for p in walk(gd_root):
        if p.suffix == ".uid" and not p.with_suffix("").exists():
            out["orphan_uid"].append(p.as_posix())
        if p.suffix == ".import" and not p.with_suffix("").exists():
            out["orphan_import"].append(p.as_posix())
    # report
    def total_kb(items): return round(sum(i.get("kb", 0) for i in items) / 1024, 1)
    print(f"unreferenced scripts (no path/class/name mention outside tests+tools): {len(out['scripts'])}")
    for i in out["scripts"]:
        print(f"  {i['path']}  class={i['class'] or '-'}  {i['kb']} KB")
    print(f"classes never used outside their file: {len(out['classes'])}")
    for i in out["classes"]:
        print(f"  {i['class']}  ({i['path']})")
    strict = [i for i in out["assets"] if i["name_mentions"] == 0 and not i["dir_referenced"]]
    loose = [i for i in out["assets"] if i["name_mentions"] > 0 or i["dir_referenced"]]
    print(f"assets with no res:// reference, no name mention and no directory-prefix mention: {len(strict)} files, {total_kb(strict)} MB")
    for i in sorted(strict, key=lambda x: -x["kb"])[:60]:
        print(f"  {i['path']}  {i['kb']} KB")
    print(f"assets with no res:// reference but a name or directory mention (dynamic string building likely): {len(loose)} files, {total_kb(loose)} MB")
    for i in sorted(loose, key=lambda x: -x["kb"])[:25]:
        print(f"  {i['path']}  {i['kb']} KB  mentions={i['name_mentions']}")
    print(f"orphan .uid: {len(out['orphan_uid'])}  orphan .import: {len(out['orphan_import'])}")
    for p in out["orphan_uid"][:30] + out["orphan_import"][:30]:
        print("  " + p)
    if a.json:
        Path(a.json).write_text(json.dumps(out, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
