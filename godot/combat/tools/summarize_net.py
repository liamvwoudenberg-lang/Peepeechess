#!/usr/bin/env python3
"""Merge net_report.gd shard files and print the desync / completion table. Exit 1 if any desync or incomplete duel at a profile <= 150ms/2%.

  python3 godot/combat/tools/summarize_net.py /tmp/net-*.json [--md out.md]
"""
import json, sys, glob
args = [a for a in sys.argv[1:] if not a.startswith("--")]
md = sys.argv[sys.argv.index("--md") + 1] if "--md" in sys.argv else None
if md: args.remove(md)
rows = {}
tuning = None
for pattern in args:
    for f in sorted(glob.glob(pattern)):
        d = json.load(open(f)); tuning = d["tuning"]
        for name, r in d["profiles"].items():
            m = rows.setdefault(name, {k: 0 for k in r})
            for k, v in r.items():
                m[k] = max(m.get(k, 0), v) if k == "max_drift_cm" else (m.get(k, 0) + v if k != "mean_ticks" else m.get(k, 0) + v * r["duels"])
lines = [f"# Online duel report (tuning {tuning})", "", "| profile | duels | completed | both clients agree | desync: replay | applied | result | snapshots checked | terminal snapshot lost (reliable copy used) | replay position drift (duels / max cm) | mean duel (s) |", "|---|---|---|---|---|---|---|---|---|---|---|"]
bad = False
for name, m in rows.items():
    mean_s = (m["mean_ticks"] / max(1, m["duels"]) - 180) / 60.0
    lines.append(f"| {name} | {m['duels']} | {m['completed']} | {m['both_clients_got_result']} | {m['desync_replay']} | {m['desync_applied']} | {m['desync_result']} | {m['applied_checked']} | {m['terminal_lost']} | {m['drift_replay']} / {m['max_drift_cm']} | {mean_s:.1f} |")
    gate = not ("250ms" in name)
    if gate and (m["desync_replay"] or m["desync_applied"] or m["desync_result"] or m["completed"] != m["duels"]): bad = True
print("\n".join(lines))
if md: open(md, "w").write("\n".join(lines) + "\n")
sys.exit(1 if bad else 0)
