#!/usr/bin/env python3
"""Merge length_calibrate.gd shard files into balance_v1.json's "duel_length" section.

    python3 godot/combat/tools/merge_length.py OUT_DIR/len-*.json [--write] [--balance godot/combat/data/balance_v1.json]

Without --write it only prints the table. With --write it rewrites ONLY the "duel_length" block (a text edit: every other number stays
byte-identical; the block must sit before "attacker_edge" in the file, which merge_edge.py rewrites to the end of the file). Scales are
rounded to 3 decimals. Pairings that missed the target (or hit a scale limit) are listed so a human looks at them. Later files override
earlier ones, so a refinement run of a few pairings can be merged over the full run.
"""
import argparse, glob, json, sys

ROLES = "pnbrq"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--balance", default="godot/combat/data/balance_v1.json")
    args = parser.parse_args()
    pairs, target, tunings = {}, None, set()
    for pattern in args.files:
        for path in sorted(glob.glob(pattern)):
            data = json.load(open(path))
            pairs.update(data["pairs"])
            target = data["target"]
            tunings.add(data["tuning"])
    missing = [a + d for a in ROLES for d in ROLES if a + d not in pairs]
    if missing:
        print("MISSING pairings:", " ".join(missing), file=sys.stderr)
        return 1
    print(f"duel length scale per pairing (HP damage multiplier), calibrated for {target} s of fighting; tunings measured against: {sorted(tunings)}")
    print("pair   scale   length   casual/skilled median   timeouts c/s   evaluations")
    for a in ROLES:
        for d in ROLES:
            p = pairs[a + d]
            flag = "" if p["within_tolerance"] else "   <-- target missed " + p.get("note", "")
            print(f"{a}>{d}   {p['scale']:6.3f}  {p['score']:5.1f}   {p['median_casual']:5.1f}/{p['median_skilled']:5.1f}   {p['timeouts_casual']}/{p['timeouts_skilled']}   {p['evaluations']}{flag}")
    if not args.write:
        return 0

    lines = ['\t"duel_length": {', '\t\t"damage_scale": 1.0,', f'\t\t"target_seconds": {float(target)},', '\t\t"pairs": {']
    keys = [a + d for a in ROLES for d in ROLES]
    for i, key in enumerate(keys):
        value = min(1.0, max(0.05, pairs[key]["scale"]))
        lines.append(f'\t\t\t"{key}": {value:.3f}'.rstrip("0").rstrip(".") + ("," if i < len(keys) - 1 else ""))
    lines += ["\t\t}", "\t},"]
    block = "\n".join(lines)
    text = open(args.balance).read()
    start = text.index('\t"duel_length": {')
    end = text.index('\t"attacker_edge": {')
    assert start < end, '"duel_length" must come before "attacker_edge"'
    text = text[:start] + block + "\n" + text[end:]
    json.loads(text)  # must stay valid JSON
    open(args.balance, "w").write(text)
    print("wrote duel_length to", args.balance)
    return 0


if __name__ == "__main__":
    sys.exit(main())
