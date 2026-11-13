#!/usr/bin/env python3
"""Merge edge_calibrate.gd shard files into balance_v1.json's "attacker_edge" section.

    python3 godot/combat/tools/merge_edge.py OUT_DIR/edge-*.json [--write] [--balance godot/combat/data/balance_v1.json]

Without --write it only prints the table. With --write it rewrites ONLY the "attacker_edge" block at the end of the data file
(text edit: every other number stays byte-identical). Multipliers are rounded to 2 decimals, never below 1.0, and at most one side
of a pairing is boosted (the loader validates this). Pairings that hit a search limit are listed so a human looks at them.
"""
import argparse, glob, json, sys

ROLES = "pnbrq"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--balance", default="godot/combat/data/balance_v1.json")
    parser.add_argument("--allow-mixed-tunings", action="store_true",
                        help="accept shards stamped with different balance data (fine here: calibration uses explicit multipliers, "
                             "so the attacker_edge table itself never influences it). Later files override earlier ones, so a "
                             "refinement run of a few pairings can be merged over the full run.")
    args = parser.parse_args()
    pairs, target, tunings, stamina_rules = {}, None, set(), set()
    for pattern in args.files:
        for path in sorted(glob.glob(pattern)):
            data = json.load(open(path))
            pairs.update(data["pairs"])
            target = data["target"]
            tunings.add(data["tuning"])
            rule = data.get("stamina", {"attacker_cost": 1.0, "defender_cost": 1.0, "defender_regen": 1.0})
            stamina_rules.add((rule["attacker_cost"], rule["defender_cost"], rule["defender_regen"]))
    missing = [a + d for a in ROLES for d in ROLES if a + d not in pairs]
    if missing:
        print("MISSING pairings:", " ".join(missing), file=sys.stderr)
        return 1
    if len(tunings) != 1 and not args.allow_mixed_tunings:
        print("shards were measured against different tunings:", tunings, "(pass --allow-mixed-tunings to merge anyway)", file=sys.stderr)
        return 1
    if len(stamina_rules) != 1:
        print("shards were calibrated under different stamina rules:", stamina_rules, file=sys.stderr)
        return 1
    stamina = next(iter(stamina_rules))
    print("stamina rule (attacker cost, defender cost, defender regeneration):", stamina)
    print("attacker advantage (attacker x / defender x) -> win rate casual/skilled/mean, calibrated for", target)
    print("       " + "".join(f"def {d}        " for d in ROLES))
    for a in ROLES:
        cells = []
        for d in ROLES:
            p = pairs[a + d]
            cells.append(f"{p['attacker_mult']:.2f}/{p['defender_mult']:.2f} {p['rate_casual']*100:3.0f}/{p['rate_skilled']*100:3.0f}%")
        print(f"atk {a}  " + "  ".join(cells))
    capped = [(k, v["capped"]) for k, v in sorted(pairs.items()) if v["capped"]]
    for key, why in capped:
        print(f"LIMIT {key}: {why}")
    if not args.write:
        return 0

    def num(v: float) -> str:
        return f"{v:.2f}".rstrip("0").rstrip(".") if v != 1 else "1.0"

    lines = ['\t"attacker_edge": {', f'\t\t"target": {target},',
             '\t\t"stamina": {', f'\t\t\t"attacker_cost": {num(stamina[0]) if stamina[0] else "0.0"},', f'\t\t\t"defender_cost": {num(stamina[1])},', f'\t\t\t"defender_regen": {num(stamina[2])}', '\t\t},',
             '\t\t"pairs": {']
    keys = [a + d for a in ROLES for d in ROLES]
    for i, key in enumerate(keys):
        p = pairs[key]
        a, d = max(1.0, p["attacker_mult"]), max(1.0, p["defender_mult"])
        if a > 1.0001 and d > 1.0001:
            a, d = (a, 1.0) if a >= d else (1.0, d)
        lines.append(f'\t\t\t"{key}": [{num(a)}, {num(d)}]' + ("," if i < len(keys) - 1 else ""))
    lines += ["\t\t}", "\t}"]
    block = "\n".join(lines)
    text = open(args.balance).read()
    marker = '\t"attacker_edge": {'
    if marker in text:
        head = text[: text.index(marker)].rstrip()
        head = head[:-1].rstrip() if head.endswith(",") else head
        text = head + ",\n" + block + "\n}\n"
    else:
        body = text.rstrip()
        assert body.endswith("}"), "unexpected end of file"
        text = body[:-1].rstrip() + ",\n" + block + "\n}\n"
    json.loads(text)  # must stay valid JSON
    open(args.balance, "w").write(text)
    print("wrote attacker_edge to", args.balance)
    return 0


if __name__ == "__main__":
    sys.exit(main())
