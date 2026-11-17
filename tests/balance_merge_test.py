#!/usr/bin/env python3
"""merge_edge.py / merge_length.py must rewrite ONLY their own block of config/balance.json.

Regression for the 2026-11-16 pitfall where --write dropped every block that followed "attacker_edge" (hit_stun, pacing).
Run:  python3 -m unittest discover -s tests -p balance_merge_test.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BALANCE = os.path.join(ROOT, "godot", "config", "balance.json")
TOOLS = os.path.join(ROOT, "godot", "combat", "tools")
sys.path.insert(0, TOOLS)
from balance_file import find_block, replace_block, ROLES  # noqa: E402


def top_level_blocks(text: str) -> dict:
    """Raw text of every top-level `\t"key": ...` entry that is an object, by key."""
    out = {}
    for key in json.loads(text):
        found = find_block(text, key)
        if found:
            out[key] = text[found[0]:found[1]]
    return out


class MergeToolsKeepOtherBlocks(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.path = os.path.join(self.tmp, "balance.json")
        shutil.copy(BALANCE, self.path)
        self.before = open(self.path).read()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def _edge_shard(self, boost):
        pairs = {a + d: {"attacker_mult": boost, "defender_mult": 1.0, "rate_casual": 0.6, "rate_skilled": 0.6, "capped": ""} for a in ROLES for d in ROLES}
        path = os.path.join(self.tmp, "edge-0.json")
        json.dump({"pairs": pairs, "target": 0.62, "tuning": "balance-v1", "stamina": {"attacker_cost": 1.0, "defender_cost": 1.0, "defender_regen": 1.0}}, open(path, "w"))
        return path

    def _length_shard(self, scale):
        pairs = {a + d: {"scale": scale, "score": 28.0, "median_casual": 28.0, "median_skilled": 28.0, "timeouts_casual": 0, "timeouts_skilled": 0, "evaluations": 5, "within_tolerance": True}
                 for a in ROLES for d in ROLES}
        path = os.path.join(self.tmp, "len-0.json")
        json.dump({"pairs": pairs, "target": 28.0, "tuning": "balance-v1"}, open(path, "w"))
        return path

    def test_the_shipped_file_has_the_blocks_this_guards(self):
        blocks = top_level_blocks(self.before)
        for key in ("profiles", "abilities", "attacks", "duel_length", "pacing", "attacker_edge", "hit_stun"):
            self.assertIn(key, blocks)

    def test_merge_edge_rewrites_only_attacker_edge(self):
        shard = self._edge_shard(1.5)
        subprocess.run([sys.executable, os.path.join(TOOLS, "merge_edge.py"), shard, "--write", "--balance", self.path], check=True, capture_output=True)
        after = open(self.path).read()
        data = json.loads(after)   # still valid JSON
        before_blocks, after_blocks = top_level_blocks(self.before), top_level_blocks(after)
        for key in before_blocks:
            if key != "attacker_edge":
                self.assertEqual(before_blocks[key], after_blocks[key], f"block {key!r} must stay byte-identical")
        self.assertIn("hit_stun", data, "hit_stun must survive")
        self.assertIn("pacing", data, "pacing must survive")
        self.assertEqual(data["attacker_edge"]["matrix"]["p"]["q"], [1.5, 1.0])
        self.assertEqual(sum(len(row) for row in data["attacker_edge"]["matrix"].values()), 25)
        self.assertNotEqual(before_blocks["attacker_edge"], after_blocks["attacker_edge"])

    def test_merge_edge_twice_is_stable(self):
        shard = self._edge_shard(1.25)
        for _ in range(2):
            subprocess.run([sys.executable, os.path.join(TOOLS, "merge_edge.py"), shard, "--write", "--balance", self.path], check=True, capture_output=True)
        once = open(self.path).read()
        subprocess.run([sys.executable, os.path.join(TOOLS, "merge_edge.py"), shard, "--write", "--balance", self.path], check=True, capture_output=True)
        self.assertEqual(once, open(self.path).read())

    def test_merge_length_rewrites_only_duel_length(self):
        shard = self._length_shard(0.5)
        subprocess.run([sys.executable, os.path.join(TOOLS, "merge_length.py"), shard, "--write", "--balance", self.path], check=True, capture_output=True)
        after = open(self.path).read()
        data = json.loads(after)
        before_blocks, after_blocks = top_level_blocks(self.before), top_level_blocks(after)
        for key in before_blocks:
            if key != "duel_length":
                self.assertEqual(before_blocks[key], after_blocks[key], f"block {key!r} must stay byte-identical")
        self.assertEqual(data["duel_length"]["pairs"]["pp"], 0.5)

    def test_replace_block_ignores_braces_inside_strings(self):
        text = '{\n\t"a": {\n\t\t"s": "}{ \\" }"\n\t},\n\t"b": {\n\t\t"x": 1\n\t}\n}\n'
        out = replace_block(text, "a", '\t"a": {"s": "new"}')
        self.assertEqual(json.loads(out), {"a": {"s": "new"}, "b": {"x": 1}})

    def test_a_missing_block_is_appended_not_dropped(self):
        text = '{\n\t"b": {\n\t\t"x": 1\n\t}\n}\n'
        out = replace_block(text, "attacker_edge", '\t"attacker_edge": {\n\t\t"target": 0.5\n\t}')
        self.assertEqual(json.loads(out), {"b": {"x": 1}, "attacker_edge": {"target": 0.5}})


if __name__ == "__main__":
    unittest.main()
