#!/usr/bin/env python3
"""Authoring helper: writes godot/training/lessons/*.json. Edit a lesson here (or edit the JSON directly: both are valid sources) and run

    python3 tools/training/build_lessons.py

then `godot --headless --path godot --script res://combat/tests/test_runner.gd -- training` validates every file against LessonSchema.
Format: docs/application/TRAINING.md.
"""
import json
from pathlib import Path

OUT = Path(__file__).resolve().parents[2] / "godot/training/lessons"
L = []


def lesson(id, cat, order, title, summary, pr, orr, beh, diff, objs, fail=None, rating=None, hints=None, **kw):
    d = {"id": id, "category": cat, "order": order, "title": title, "summary": summary, "player_role": pr, "opponent_role": orr,
         "behaviour": beh, "difficulty": diff, "arena": "stone-v1", "attacker": kw.pop("attacker", "player"), "objectives": objs,
         "fail": fail or [], "rating": rating or {}, "hints": hints or []}
    d.update(kw)
    L.append(d)


def o(id, type, text, **p):
    x = {"id": id, "type": type, "text": text}
    x.update(p)
    return x


DMG = [{"type": "damage_fraction", "fraction": 0.9}]
T88 = [{"type": "time_limit", "seconds": 88}]

# ---- BEGINNER: combat fundamentals ----
lesson("b01_movement", "beginner", 1, "Movement", "Walk and sprint around the arena. Stay on the stone floor and keep your distance.", "p", "p", "idle", "easy",
       [o("walk", "move_distance", "Walk 8 metres", meters=8)], hints=["Move with the left stick / WASD. Sprinting costs stamina."],
       rating={"silver": {"max_seconds": 14}, "gold": {"max_seconds": 9}})
lesson("b02_camera", "beginner", 2, "Camera control", "Orbit the camera around the fighters.", "p", "p", "idle", "easy", [], available=False,
       unavailable_reason="Camera control is a presentation feature: the combat simulation reports nothing about it, so it cannot be verified. It is covered in the movement lesson's hints.")
lesson("b03_first_strike", "beginner", 3, "Basic attacks", "Land three clean light attacks on the training dummy.", "p", "p", "idle", "easy",
       [o("hits", "hit_count", "Hit the dummy 3 times", count=3)], hints=["Stand inside the sword's reach and press the light attack."],
       rating={"silver": {"max_seconds": 20}, "gold": {"max_seconds": 12}})
lesson("b04_range", "beginner", 4, "Attack range", "Reach matters: hit the dummy from the far edge of your reach.", "n", "p", "idle", "easy",
       [o("far", "hit_at_range", "Land 2 hits from at least 1.2 m", count=2, min_distance=1.2)],
       hints=["Step back until the dummy is just inside your weapon's reach, then strike."])
lesson("b05_block", "beginner", 5, "Blocking", "Hold block while the opponent attacks and absorb 3 blows.", "p", "p", "attack_only", "easy",
       [o("blocks", "block_n", "Block 3 attacks", count=3)], fail=DMG, hints=["Hold the block button facing the attacker. Blocking costs stamina."])
lesson("b06_dodge", "beginner", 6, "Dodging", "Dodge through 3 attacks. The first frames of a dodge are invulnerable.", "p", "p", "attack_only", "easy",
       [o("dodges", "dodge_n", "Dodge 3 attacks", count=3)], fail=DMG, hints=["Press dodge just before the blow lands, with a direction held."])
lesson("b07_stamina", "beginner", 7, "Stamina and recovery", "Empty your stamina with attacks, then back off and let it recover.", "p", "p", "idle", "easy",
       [o("cycle", "stamina_cycle", "Drop below 30% stamina, then recover to 90%", drain_below=0.3, recover_above=0.9)],
       hints=["Stamina does not recover while you act. Stop attacking and wait."])
lesson("b08_first_combo", "beginner", 8, "Your first combo", "Chain three light attacks without a gap.", "p", "p", "idle", "easy",
       [o("combo", "combo", "Land a 3-hit combo", count=3)], hints=["Press light again just as the swing ends: the chain window is short."],
       rating={"silver": {"max_seconds": 25}, "gold": {"max_seconds": 15}})

# ---- INTERMEDIATE: combat techniques ----
lesson("i01_long_combo", "intermediate", 1, "Multi-hit combos", "The Queen chains a longer light combo.", "q", "p", "idle", "normal",
       [o("combo", "combo", "Land a 4-hit combo", count=4)], hints=["Keep pressing light on the beat; the Queen's chain is longer than the others."],
       requires=["b08_first_combo"])
lesson("i02_dodge_counter", "intermediate", 2, "Dodge and counter", "Dodge an attack and strike back before they recover.", "n", "p", "attack_only", "normal",
       [o("dodge", "dodge_n", "Dodge 2 attacks", count=2),
        o("counter", "counter_after", "Counter within 1.5 s of a dodge", after="dodge", count=2, window_ticks=90)],
       fail=DMG, requires=["b06_dodge", "b08_first_combo"])
lesson("i03_punish_recovery", "intermediate", 3, "Punish the recovery", "Attack the opponent while they recover from a swing.", "b", "n", "attack_only", "normal",
       [o("punish", "punish", "Punish 2 recoveries", count=2)], fail=DMG, hints=["After they swing, there is a gap: step in and hit it."],
       requires=["b05_block"])
lesson("i04_block_punish", "intermediate", 4, "Block and punish", "Block the attack, then hit back.", "r", "p", "attack_only", "normal",
       [o("block", "block_n", "Block 2 attacks", count=2),
        o("counter", "counter_after", "Hit back within 1.5 s of a block", after="block", count=2, window_ticks=90)], fail=DMG, requires=["b05_block"])
lesson("i05_distance", "intermediate", 5, "Managing distance", "Hold a safe gap to the Rook for 6 seconds without being hit more than twice.", "b", "r", "attack_only", "normal",
       [o("gap", "hold_distance", "Stay 2.2-3.6 m away for 6 s", min=2.2, max=3.6, seconds=6)], fail=[{"type": "hits_taken", "count": 2}],
       hints=["The Rook is slow: circle and keep out of reach."], requires=["b01_movement"])
lesson("i06_moving_opponent", "intermediate", 6, "Moving opponents", "Land 4 hits on an opponent who fights back.", "n", "b", "normal", "easy",
       [o("hits", "hit_count", "Land 4 hits", count=4)], fail=[{"type": "time_limit", "seconds": 80}], requires=["i02_dodge_counter"])

# ---- ADVANCED: character mastery ----
lesson("a01_knight_vs_pawn", "advanced", 1, "Knight vs Pawn: reach and lunge", "Use the Knight's reach, its Lunging Strike and a combo to win.", "n", "p", "normal", "normal",
       [o("lunge", "ability_use", "Use Lunging Strike", count=1), o("combo", "combo", "Land a 2-hit combo", count=2), o("win", "win", "Win the duel")],
       fail=T88, rating={"silver": {"max_hits_taken": 2}, "gold": {"max_hits_taken": 0}}, requires=["i06_moving_opponent"])
lesson("a02_rook_vs_knight", "advanced", 2, "Rook vs Knight: defensive timing", "Parry or block the fast Knight and punish its recovery.", "r", "n", "normal", "normal",
       [o("parry", "parry_n", "Parry 2 attacks", count=2), o("punish", "punish", "Punish 2 recoveries", count=2), o("win", "win", "Win the duel")],
       fail=T88, requires=["i04_block_punish"])
lesson("a03_bishop_vs_rook", "advanced", 3, "Bishop vs Rook: spacing and counters", "Keep your distance, counter, and win.", "b", "r", "normal", "normal",
       [o("gap", "hold_distance", "Hold 2.2-3.6 m for 5 s", min=2.2, max=3.6, seconds=5),
        o("counter", "counter_after", "Strike within 1.5 s of a parry", after="parry", count=1, window_ticks=90), o("win", "win", "Win the duel")],
       fail=T88, requires=["i05_distance"])
lesson("a04_queen_vs_king", "advanced", 4, "Queen vs King: combo mastery", "Chain Royal Fury combos against the King and win.", "q", "k", "normal", "hard",
       [o("fury", "ability_use", "Use Royal Fury", count=1), o("combo", "combo", "Land a 3-hit combo", count=3), o("win", "win", "Win the duel")],
       fail=T88, requires=["i01_long_combo"])
lesson("a05_king_vs_queen", "advanced", 5, "King vs Queen: survive with the counter", "Answer the Queen's chain with Royal Counter and win by timing.", "k", "q", "normal", "hard",
       [o("counter", "ability_use", "Use Royal Counter 2 times", count=2), o("parry", "parry_n", "Counter / parry 2 attacks", count=2), o("win", "win", "Win the duel")],
       fail=T88, hints=["Plant the stance a moment before her swing lands: a late counter leaves you open."], requires=["a04_queen_vs_king"])
lesson("a06_cancel", "advanced", 6, "Animation cancelling", "Cancel an attack's recovery with a dodge.", "p", "p", "normal", "easy",
       [o("cancel", "cancel", "Cancel 3 attacks into a dodge", count=3), o("hits", "hit_count", "Land 2 hits", count=2)],
       fail=[{"type": "time_limit", "seconds": 80}],
       hints=["After the swing's cancel point you can dodge, parry or use your ability instead of waiting."], requires=["b08_first_combo", "b06_dodge"])
lesson("a07_read_attacks", "advanced", 7, "Reading attacks", "Parry 3 of the Knight's swings by watching its wind-up.", "q", "n", "attack_only", "normal",
       [o("parry", "parry_n", "Parry 3 attacks", count=3)], fail=DMG, requires=["i04_block_punish"])
lesson("a08_punish_whiff", "advanced", 8, "Punishing misses", "Make the Bishop miss, then punish 3 times.", "r", "b", "attack_only", "hard",
       [o("punish", "punish", "Punish 3 openings", count=3)], fail=DMG, requires=["i03_punish_recovery"])

# ---- EXPERT: combat challenges ----
lesson("e01_hard_duel", "expert", 1, "Hard duel", "Beat a Hard Knight with a Pawn.", "p", "n", "normal", "hard",
       [o("win", "win", "Win the duel")], fail=T88, rating={"silver": {"max_damage_fraction": 0.6}, "gold": {"max_damage_fraction": 0.3}},
       requires=["a01_knight_vs_pawn"])
lesson("e02_limited_health", "expert", 2, "Limited health", "Win while starting with only half your health.", "p", "p", "normal", "normal",
       [o("win", "win", "Win with half health")], constraints={"player_hp_fraction": 0.5}, fail=T88, requires=["a06_cancel"])
lesson("e03_combo_pressure", "expert", 3, "Combos under pressure", "Land a 3-hit combo against a Hard Rook, then win.", "q", "r", "normal", "hard",
       [o("combo", "combo", "Land a 3-hit combo", count=3), o("win", "win", "Win the duel")], fail=T88, requires=["a04_queen_vs_king"])
lesson("e04_stronger_opponent", "expert", 4, "Beat a stronger fighter", "A Pawn against a Hard Queen: use every defence.", "p", "q", "normal", "hard",
       [o("win", "win", "Win the duel")], fail=T88, requires=["e01_hard_duel"])
lesson("e05_survive", "expert", 5, "Survive the onslaught", "Survive 30 seconds against an Expert Queen who strikes first.", "p", "q", "normal", "expert",
       [o("survive", "survive", "Survive 30 seconds", seconds=30)], fail=[], requires=["a07_read_attacks"], attacker="opponent")
lesson("e06_gauntlet", "expert", 6, "Difficult matchup", "King against an Expert Queen: win with the counter.", "k", "q", "normal", "expert",
       [o("win", "win", "Win the duel")], fail=T88, requires=["a05_king_vs_queen"])
lesson("e07_faster_opponent", "expert", 7, "Faster opponent", "Rook against a Hard Bishop: win through defence.", "r", "b", "normal", "hard",
       [o("win", "win", "Win the duel")], fail=T88, requires=["a08_punish_whiff"])

if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("*.json"):
        old.unlink()
    for l in L:
        (OUT / f"{l['id']}.json").write_text(json.dumps(l, indent=1) + "\n")
    print(len(L), "lessons written to", OUT)
