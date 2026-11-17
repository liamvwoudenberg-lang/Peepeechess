#!/usr/bin/env python3
"""Read-only: list every reference to a file or class before moving or deleting it.

    python3 tools/dev/res_refs.py godot/combat/core/combat_simulation.gd
    python3 tools/dev/res_refs.py res://ui/application.gd
    python3 tools/dev/res_refs.py CombatSimulation          # a class_name or any text

Prints file:line for: the res:// path, the repo-relative path, the basename (marked 'name') and, for scripts with a class_name, the class name.
Use it to update references with a script after a `git mv`. Nothing is modified.
"""
import os, re, sys
from pathlib import Path

SKIP = {".git", ".godot", "node_modules", ".claude"}
TEXT = {".gd", ".tscn", ".tres", ".cfg", ".godot", ".json", ".md", ".py", ".mjs", ".ts", ".tsx", ".yml", ".yaml", ".sh", ".txt", ".gdshader", ".html", ".bat", ".ps1"}


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    target = sys.argv[1]
    needles = {target}
    cls = ""
    p = Path(target.replace("res://", "godot/", 1) if target.startswith("res://") else target)
    if p.exists() and p.is_file():
        rel = p.as_posix()
        needles |= {rel, p.name}
        if rel.startswith("godot/"):
            needles.add("res://" + rel[len("godot/"):])
        if p.suffix == ".gd":
            m = re.search(r"^class_name\s+(\w+)", p.read_text(encoding="utf-8", errors="ignore"), re.M)
            if m:
                cls = m.group(1)
                needles.add(cls)
    hits = 0
    for dp, dn, fn in os.walk("."):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            q = Path(dp) / f
            if q.suffix not in TEXT or q.resolve() == p.resolve():
                continue
            try:
                lines = q.read_text(encoding="utf-8", errors="ignore").splitlines()
            except Exception:
                continue
            for i, line in enumerate(lines, 1):
                for n in needles:
                    if n in line and (n != cls or re.search(r"\b" + re.escape(n) + r"\b", line)):
                        kind = "class" if n == cls else ("name" if n == p.name else "path")
                        print(f"{q.as_posix()[2:]}:{i}: [{kind}] {line.strip()[:140]}")
                        hits += 1
                        break
    print(f"-- {hits} reference lines for {sorted(needles)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
