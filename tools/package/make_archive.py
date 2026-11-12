#!/usr/bin/env python3
"""Byte-reproducible .zip / .tar.gz of one directory (sorted entries, fixed timestamp, fixed owner and modes).

usage: make_archive.py zip|tar.gz SRC_DIR OUT_FILE EPOCH
SRC_DIR's own name becomes the archive's single top-level folder. Files that are executable in SRC_DIR
(or end in .exe/.x86_64/.sh) get mode 0755, all others 0644.
"""
import gzip
import io
import os
import stat
import sys
import tarfile
import time
import zipfile


def entries(src):
    base = os.path.dirname(os.path.abspath(src))
    out = []
    for dp, dns, fns in os.walk(src):
        dns.sort()
        for n in sorted(fns):
            p = os.path.join(dp, n)
            out.append((os.path.relpath(p, base).replace(os.sep, "/"), p))
    return sorted(out)


def mode_of(path):
    exe = os.stat(path).st_mode & stat.S_IXUSR or path.endswith((".exe", ".x86_64", ".sh"))
    return 0o755 if exe else 0o644


def main():
    kind, src, out, epoch = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
    if kind == "zip":
        # ZIP cannot store years before 1980.
        dt = time.gmtime(max(epoch, 315532800))[:6]
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for arc, path in entries(src):
                zi = zipfile.ZipInfo(arc, dt)
                zi.compress_type = zipfile.ZIP_DEFLATED
                zi.create_system = 3
                zi.external_attr = (0o100000 | mode_of(path)) << 16
                with open(path, "rb") as f:
                    z.writestr(zi, f.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    elif kind == "tar.gz":
        raw = io.BytesIO()
        with tarfile.open(fileobj=raw, mode="w", format=tarfile.PAX_FORMAT) as t:
            for arc, path in entries(src):
                ti = tarfile.TarInfo(arc)
                ti.size = os.path.getsize(path)
                ti.mtime = epoch
                ti.mode = mode_of(path)
                ti.uid = ti.gid = 0
                ti.uname = ti.gname = ""
                with open(path, "rb") as f:
                    t.addfile(ti, f)
        with open(out, "wb") as f, gzip.GzipFile(filename="", mode="wb", fileobj=f, mtime=0, compresslevel=9) as g:
            g.write(raw.getvalue())
    else:
        sys.exit("kind must be zip or tar.gz")


main()
