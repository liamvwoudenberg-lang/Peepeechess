#!/usr/bin/env python3
"""Fairness report from duel_report.gd JSON shards: piece-vs-piece, white-vs-black, attacker-vs-defender, with flags.

  python3 godot/combat/tools/summarize_duels.py /tmp/dr-*.json [--md out.md]

Flags every cell whose win rate is outside 35..65%. The Pawn<->Queen pairing is expected to be lopsided on purpose (the Pawn should win
about 15..25%): it is flagged only when the underdog is outside that range.
"""
import json, sys, collections
args = [a for a in sys.argv[1:] if not a.startswith("--")]
md_out = sys.argv[sys.argv.index("--md") + 1] if "--md" in sys.argv else None
if md_out: args.remove(md_out)
recs, meta = [], None
for f in args:
    d = json.load(open(f)); meta = meta or d; recs += d["records"]
R = "pnbrq"; NAME = {"p": "Pawn", "n": "Knight", "b": "Bishop", "r": "Rook", "q": "Queen"}
cell = collections.defaultdict(lambda: [0, 0])
col = collections.defaultdict(lambda: [0, 0])
for r in recs:
    k = (r["a"], r["d"]); cell[k][1] += 1; cell[k][0] += r["outcome"] == "attacker"
    c = "white" if r["attacker_white"] else "black"; col[c][1] += 1; col[c][0] += r["outcome"] == "attacker"
lines = []
def out(s=""): lines.append(s); print(s)
n_per = meta["n"]
out(f"# Duel fairness report  (tuning {meta['tuning']}, bots: {meta['cfg']['style']} {meta['cfg']['skill']} on both seats, ~{n_per} duels per pairing)")
out("\n## Attacker win % (row = attacker, column = defender)\n")
out("| | " + " | ".join(NAME[d] for d in R) + " |"); out("|---|" + "---|" * len(R))
flags = []
def intended_pawn_queen(a, d, w):
    # the underdog (Pawn) should win ~15..25%: attacker pawn -> 15..25, attacker queen -> 75..85
    if (a, d) == ("p", "q"): return 0.12 <= w <= 0.28
    if (a, d) == ("q", "p"): return 0.72 <= w <= 0.88
    return None
for a in R:
    row = []
    for d in R:
        w, n = cell[(a, d)]
        if n == 0: row.append("-"); continue
        rate = w / n; ok = intended_pawn_queen(a, d, rate)
        bad = (not ok) if ok is not None else not (0.35 <= rate <= 0.65)
        if bad: flags.append((NAME[a] + " attacks " + NAME[d], rate, n))
        row.append(f"{100*rate:.0f}%" + (" ⚠" if bad else (" ◎" if ok else "")))
    out(f"| **{NAME[a]}** | " + " | ".join(row) + " |")
out("\n◎ = Pawn↔Queen pairing inside the intended 15–25% underdog window; ⚠ = outside the target.")
out("\n## Piece strength (win % over all duels, attacking and defending)\n")
for r_ in R:
    w = sum(cell[(r_, d)][0] for d in R) + sum(cell[(a, r_)][1] - cell[(a, r_)][0] for a in R)
    n = sum(cell[(r_, d)][1] for d in R) + sum(cell[(a, r_)][1] for a in R)
    out(f"- {NAME[r_]}: {100*w/n:.0f}%" + ("  ⚠" if not 0.35 <= w / n <= 0.65 else ""))
tw = sum(c[0] for c in cell.values()); tn = sum(c[1] for c in cell.values())
out(f"\n## Attacker vs defender\n\nAttacker wins {100*tw/tn:.1f}% of {tn} duels (target: slightly below 50%, i.e. the defender holds a small edge).")
out("\n## White vs black (attacking seat colour)\n")
for c in ("white", "black"):
    w, n = col[c]; out(f"- attacker is {c}: {100*w/n:.1f}% ({n} duels)")
ticks = sorted(r["fight_ticks"] / 60 for r in recs)
out(f"\n## Duel length\n\nmedian {ticks[len(ticks)//2]:.1f}s, p10 {ticks[len(ticks)//10]:.1f}s, p90 {ticks[9*len(ticks)//10]:.1f}s; timeouts {100*sum(r['reason'].startswith('timeout') for r in recs)/len(recs):.1f}%")
out("\n## Flags (outside 35–65%, Pawn↔Queen excepted)\n")
out("\n".join(f"- {f}: {100*r:.0f}% (n={n})" for f, r, n in flags) or "none")
if md_out: open(md_out, "w").write("\n".join(lines) + "\n")
