#!/usr/bin/env python3
"""Read-only: report broken references in Markdown docs.

    python3 tools/dev/check_doc_links.py [paths...]      # default: *.md at the root and docs/**/*.md

Checks (1) relative Markdown links [text](path#anchor) and (2) backticked repository paths such as `godot/combat/core/x.gd`, `docs/foo.md`,
`scripts/test-x.mjs`, `tools/...` (only paths that start with a known top-level directory and contain a file extension or end with '/').
Paths containing wildcards, '<', '{', '...' or placeholders are skipped. Anchors are not validated. Nothing is modified.
"""
import os, re, sys
from pathlib import Path

ROOTS = ("godot/", "docs/", "scripts/", "tools/", "src/", "server/", "api/", "contracts/", "tests/", "android/", ".github/", "public/", "downloads/", "newmodels/")
LINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
TICK = re.compile(r"`([^`\n]+)`")
SKIP = {".git", "node_modules", ".claude", ".godot"}


def md_files(args):
    if args:
        for a in args:
            p = Path(a)
            if p.is_dir():
                yield from p.rglob("*.md")
            else:
                yield p
        return
    for p in Path(".").glob("*.md"):
        yield p
    for dp, dn, fn in os.walk("docs"):
        dn[:] = [d for d in dn if d not in SKIP]
        for f in fn:
            if f.endswith(".md"):
                yield Path(dp) / f


def skip_path(s: str) -> bool:
    return any(c in s for c in "*<>{}$|") or "..." in s or s.startswith(("http", "mailto", "#")) or " " in s


def main() -> int:
    missing = []
    checked = 0
    for md in sorted(set(md_files(sys.argv[1:]))):
        text = md.read_text(encoding="utf-8", errors="ignore")
        for m in LINK.finditer(text):
            tgt = m.group(1).split("#")[0]
            if not tgt or skip_path(m.group(1)):
                continue
            checked += 1
            if not (md.parent / tgt).exists() and not Path(tgt).exists():
                missing.append((md.as_posix(), "link", tgt))
        for m in TICK.finditer(text):
            s = m.group(1).strip().rstrip(".,:;")
            if skip_path(s) or not s.startswith(ROOTS):
                continue
            if not (re.search(r"\.[A-Za-z0-9]{1,6}$", s) or s.endswith("/")):
                continue
            checked += 1
            if not Path(s).exists():
                missing.append((md.as_posix(), "path", s))
    print(f"checked {checked} references in {len(set(md_files(sys.argv[1:])))} markdown files; broken: {len(missing)}")
    by_doc = {}
    for doc, kind, tgt in missing:
        by_doc.setdefault(doc, []).append((kind, tgt))
    for doc in sorted(by_doc):
        print(doc)
        for kind, tgt in sorted(set(by_doc[doc])):
            print(f"   {kind}: {tgt}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
