"""Dev check: python3 dev_compare_clips.py  (from the repository root)
Compares the animation data (per clip, per channel: sampler input + output bytes) of every character GLB in the working tree against
`git show <ref>:<same path>` (ref = first argument, default HEAD) and reports clips that were removed/changed or added. Used to prove that adding clips left the existing
clips bit-identical. Plain python3 (no Blender needed)."""
import json, struct, sys, subprocess, hashlib
def parse(d):
    jl = struct.unpack('<I', d[12:16])[0]
    j = json.loads(d[20:20+jl]); off = 20+jl
    bl = struct.unpack('<I', d[off:off+4])[0]; b = d[off+8:off+8+bl]
    return j, b
def acc(j,b,i):
    a=j["accessors"][i]; v=j["bufferViews"][a["bufferView"]]; o=v.get("byteOffset",0)+a.get("byteOffset",0)
    n={"SCALAR":1,"VEC3":3,"VEC4":4}[a["type"]]*a["count"]*4
    return b[o:o+n]
def anims(d):
    j,b=parse(d); out={}
    for an in j["animations"]:
        m={}
        for ch in an["channels"]:
            s=an["samplers"][ch["sampler"]]
            m[(j["nodes"][ch["target"]["node"]]["name"],ch["target"]["path"])]=hashlib.md5(acc(j,b,s["input"])+acc(j,b,s["output"])).hexdigest()
        out[an["name"]]=m
    return out, [n["name"] for n in j["nodes"]], [s["name"] for s in j.get("skins",[])], [x.get("name") for x in j["materials"]]
bad=0
for cls in ["pawn","knight","bishop","rook","queen","king"]:
    for suf in ["","_lod1"]:
        p=f"godot/assets/combat/characters/{cls}/{cls}{suf}.glb"
        old=subprocess.check_output(["git","show",(sys.argv[1] if len(sys.argv)>1 else "HEAD")+":"+p]); new=open(p,"rb").read()
        a,an,asn,am=anims(old); b,bn,bsn,bm=anims(new)
        same=[k for k in a if a[k]==b.get(k)]
        diff=[k for k in a if a[k]!=b.get(k)]
        newc=[k for k in b if k not in a]
        print(cls+suf, "unchanged clips", len(same), "changed", diff, "new", newc, "nodes equal", sorted(an)==sorted(bn), "materials equal", am==bm)
        bad+=len(diff)
print("changed existing clips total:", bad)
