#!/usr/bin/env python3
"""Static check of an exported Godot Windows executable (PE32+ with an embedded PCK). Never runs the file.

usage: inspect_exe.py EXE [--godot 4.6] [--require packed/path ...]

What it verifies (exit status 1 and a "FAILED" line if any of it is not true):
  * a valid PE32+ x86_64 image whose Authenticode certificate table is reported (unsigned builds are allowed, just named);
  * the embedded PCK ("pck" section) is consistent with the trailer at the end of the file, was written by the expected
    Godot version, and the MD5 of EVERY packed file matches its directory entry (so the pack is complete and uncorrupted);
  * the project settings inside the pack name a main scene, and the files that the game reads at run time exist
    (see DEFAULT_REQUIRED below, mirrored from tools/package/smoke/package_smoke.gd; add more with --require);
  * no unit-test folders or Markdown files were shipped.
It also prints the Windows version resource (product / description / version) so an export without resource
metadata is noticed. This proves the file is a well-formed Windows build of the project; it does NOT prove that it
starts on Windows (nothing here can run a Windows program).
"""
import argparse
import hashlib
import re
import struct
import sys

DEFAULT_REQUIRED = [
    "project.binary",
    "chess/battle_stats.json",
    "combat/data/balance_v1.json",
    "assets/combat/audio/manifest.json",
    "assets/combat/arena/stone_arena_lights.json",
    "assets/combat/manifest/asset_manifest.json",
    "assets/world/manifest/world_manifest.json",
    "contracts/v2/schema.json",
]
PE_MACHINES = {0x8664: "x86_64", 0xAA64: "arm64", 0x14C: "x86"}
SUBSYSTEMS = {2: "GUI", 3: "console"}
errors = []


def check(ok, label):
    print(("ok    " if ok else "FAIL  ") + label)
    if not ok:
        errors.append(label)


def parse_pe(f, size):
    f.seek(0)
    head = f.read(4096)
    if head[:2] != b"MZ":
        sys.exit("FAILED: not a PE file (no MZ header)")
    pe = struct.unpack_from("<I", head, 0x3C)[0]
    f.seek(pe)
    h = f.read(24 + 240 + 40 * 96)
    if h[:4] != b"PE\0\0":
        sys.exit("FAILED: no PE signature")
    machine, nsec, _ts, _sp, _ns, optsz, _ch = struct.unpack_from("<HHIIIHH", h, 4)
    opt = 24
    magic = struct.unpack_from("<H", h, opt)[0]
    info = {"machine": machine, "pe32plus": magic == 0x20B, "sections": {}}
    info["subsystem"] = struct.unpack_from("<H", h, opt + 68)[0]
    if magic == 0x20B:  # data directory 4 = certificate table (file offset, size)
        info["cert_offset"], info["cert_size"] = struct.unpack_from("<II", h, opt + 112 + 4 * 8)
    sec = opt + optsz
    for i in range(nsec):
        name, vsize, _va, rsize, rptr = struct.unpack_from("<8sIIII", h, sec + 40 * i)
        info["sections"][name.rstrip(b"\0").decode("latin-1")] = (rptr, rsize, vsize)
    return info


def parse_ecfg(blob):
    """project.binary: 'ECFG', count, then (key, variant) pairs. Only string values are decoded."""
    out = {}
    if blob[:4] != b"ECFG":
        return out
    count = struct.unpack_from("<I", blob, 4)[0]
    pos = 8
    for _ in range(count):
        klen = struct.unpack_from("<I", blob, pos)[0]
        key = blob[pos + 4:pos + 4 + klen].decode("utf-8", "replace")
        pos += 4 + klen
        vlen = struct.unpack_from("<I", blob, pos)[0]
        val = blob[pos + 4:pos + 4 + vlen]
        pos += 4 + vlen
        if len(val) >= 8 and struct.unpack_from("<I", val, 0)[0] == 4:  # Variant::STRING
            slen = struct.unpack_from("<I", val, 4)[0]
            out[key] = val[8:8 + slen].decode("utf-8", "replace")
    return out


def version_resource(blob):
    """Read StringFileInfo values from the .rsrc section (UTF-16 key, 4-byte aligned, UTF-16 value)."""
    out = {}
    for key in ("CompanyName", "FileDescription", "FileVersion", "ProductName", "ProductVersion"):
        needle = key.encode("utf-16le") + b"\0\0"
        i = blob.find(needle)
        if i < 0:
            continue
        pos = (i + len(needle) + 3) & ~3
        end = pos
        while end + 1 < len(blob) and blob[end:end + 2] != b"\0\0":
            end += 2
        out[key] = blob[pos:end].decode("utf-16le", "replace")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("exe")
    ap.add_argument("--godot", default="4.6", help="expected Godot major.minor[.patch] prefix recorded in the pack (default 4.6)")
    ap.add_argument("--require", action="append", default=[], help="additional packed path that must exist (repeatable)")
    args = ap.parse_args()

    with open(args.exe, "rb") as f:
        size = f.seek(0, 2)
        sha = hashlib.sha256()
        f.seek(0)
        for block in iter(lambda: f.read(1 << 20), b""):
            sha.update(block)
        print(f"file:     {args.exe}")
        print(f"size:     {size} bytes")
        print(f"sha256:   {sha.hexdigest()}")
        pe = parse_pe(f, size)
        check(pe["machine"] == 0x8664 and pe["pe32plus"], "Windows x86_64 image (PE32+, machine 0x8664; this file: %s)" % PE_MACHINES.get(pe["machine"], hex(pe["machine"])))
        print("subsystem: %s" % SUBSYSTEMS.get(pe["subsystem"], pe["subsystem"]))
        signed = pe.get("cert_size", 0) > 0
        print("signature: %s" % ("Authenticode certificate table present (not validated here)" if signed else "none (unsigned; Windows SmartScreen will warn)"))

        # ---- embedded PCK -------------------------------------------------------------------------------------
        check("pck" in pe["sections"], "PE has an embedded 'pck' section (binary_format/embed_pck=true)")
        if "pck" not in pe["sections"]:
            sys.exit("FAILED: no embedded pack, the exe would need a separate .pck file")
        f.seek(size - 12)
        pck_size, trailer = struct.unpack("<Q4s", f.read(12))
        check(trailer == b"GDPC", "pack trailer magic GDPC at the end of the file")
        start = size - 12 - pck_size
        check(start == pe["sections"]["pck"][0], "pack start from the trailer equals the 'pck' section offset (%d)" % start)
        f.seek(start)
        hdr = f.read(104)
        magic, fmt, vmaj, vmin, vpat, flags, file_base, dir_offset = struct.unpack_from("<6IQQ", hdr, 0)
        check(magic == 0x43504447, "pack header magic GDPC")
        check(fmt == 3, "pack format version 3 (parsed here), got %d" % fmt)
        check(not flags & 1, "pack directory is not encrypted")
        godot = "%d.%d.%d" % (vmaj, vmin, vpat)
        check(godot.startswith(args.godot), "pack written by Godot %s (expected %s*)" % (godot, args.godot))
        rel = start if flags & 2 else 0
        f.seek(rel + dir_offset)
        count = struct.unpack("<I", f.read(4))[0]
        entries = []
        for _ in range(count):
            plen = struct.unpack("<I", f.read(4))[0]
            path = f.read(plen).rstrip(b"\0").decode("utf-8", "replace")
            off, length = struct.unpack("<QQ", f.read(16))
            md5 = f.read(16)
            eflags = struct.unpack("<I", f.read(4))[0]
            entries.append((path, off, length, md5, eflags))
        bad = []
        total = 0
        files = {}
        settings = {}
        for path, off, length, md5, eflags in entries:
            f.seek(rel + file_base + off)
            data = f.read(length)
            total += length
            files[path] = length
            if not eflags & 1 and hashlib.md5(data).digest() != md5:
                bad.append(path)
            if path == "project.binary":
                settings = parse_ecfg(data)
        check(not bad, "MD5 of all %d packed files matches the pack directory%s" % (count, "" if not bad else " (mismatches: %s)" % ", ".join(bad[:5])))
        print("pack:     Godot %s, format v%d, %d files, %.1f MiB of data, %.1f MiB pack in a %.1f MiB exe" % (
            godot, fmt, count, total / 1048576, pck_size / 1048576, size / 1048576))

        # ---- project settings and content ---------------------------------------------------------------------
        main_scene = settings.get("application/run/main_scene", "")
        check(bool(main_scene), "project settings name a main scene: %s" % (main_scene or "(none)"))
        if main_scene.startswith("res://"):
            rel_scene = main_scene[6:]
            check(rel_scene + ".remap" in files or rel_scene in files, "main scene file is packed (%s)" % rel_scene)
        print("project:  %s" % settings.get("application/config/name", "?"))
        for needed in DEFAULT_REQUIRED + args.require:
            check(needed in files, "packed: " + needed)
        for pattern, label in ((r"(^|/)tests?/", "unit-test folders"), (r"\.md$", "Markdown files")):
            leaked = [p for p in files if re.search(pattern, p)]
            check(not leaked, "no %s packed%s" % (label, "" if not leaked else " (%d, e.g. %s)" % (len(leaked), leaked[0])))
        kinds = {"compiled scripts (.gdc)": 0, "plain scripts (.gd)": 0, "scenes (.scn/.tscn/.remap)": 0, "audio (.sample/.ogg*/.mp3)": 0,
                 "textures (.ctex)": 0, "JSON": 0}
        for p in files:
            if p.endswith(".gdc"):
                kinds["compiled scripts (.gdc)"] += 1
            elif p.endswith(".gd"):
                kinds["plain scripts (.gd)"] += 1
            elif p.endswith((".scn", ".tscn")) or (p.endswith(".remap") and ".tscn" in p):
                kinds["scenes (.scn/.tscn/.remap)"] += 1
            elif p.endswith((".sample", ".oggvorbisstr", ".mp3str")):
                kinds["audio (.sample/.ogg*/.mp3)"] += 1
            elif p.endswith(".ctex"):
                kinds["textures (.ctex)"] += 1
            elif p.endswith(".json"):
                kinds["JSON"] += 1
        print("contents: " + ", ".join("%d %s" % (n, k) for k, n in kinds.items()))

        # ---- Windows version resource -------------------------------------------------------------------------
        rptr, rsize, _ = pe["sections"].get(".rsrc", (0, 0, 0))
        f.seek(rptr)
        meta = version_resource(f.read(rsize)) if rsize else {}
        check(bool(meta.get("ProductName")), "Windows version resource written: " + (", ".join("%s=%s" % kv for kv in meta.items()) or "(none)"))

    if errors:
        print("FAILED: %d check(s) failed" % len(errors))
        sys.exit(1)
    print("RESULT: ok (static checks only; the file was not run)")


main()
