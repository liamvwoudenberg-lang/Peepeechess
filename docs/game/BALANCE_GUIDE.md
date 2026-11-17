# Balance guide: how to tune the fights

All combat numbers live in **one file you can edit by hand**: [`godot/config/balance.json`](../../godot/config/balance.json).
Chess rules and the other designer numbers (time controls, computer levels, campaign boons ...) live in
[`godot/config/chess_rules.json`](../../godot/config/chess_rules.json) (see [RULES_CONFIG.md](RULES_CONFIG.md)).

Every key is documented (meaning, unit, allowed range) in the generated table [BALANCE_REFERENCE.md](BALANCE_REFERENCE.md).
Keys that start with an underscore are comments: write your reasoning next to a number (`"_why": "..."`) and the game ignores it
(it is not part of the tuning stamp either).

## Tune a number and test it: three commands

```sh
# 1. edit godot/config/balance.json (e.g. profiles.n.armor), then validate it and see the new stamp
godot --headless --path godot --script res://tools/config_check.gd

# 2. see exactly what you changed against git HEAD
godot --headless --path godot --script res://tools/config_diff.gd

# 3. play the pairings you touched with the bots (attacker letter + defender letter: p n b r q)
godot --headless --path godot --script res://tools/config_quicksim.gd -- nq,qn n=16
```

`config_check` fails (exit code 1) with messages like
`config/balance.json: profiles.n.armor = -0.3 is below the minimum 0 (unit: fraction)` or
`profiles.p.armour is not a known setting (did you mean armor?)`, so a typo can never silently do nothing.

`config_quicksim` prints the attacker's win rate (casual bot / skilled bot) and the mean fight length. It is **bot-measured**:
a quick signal while tuning, never a human playtest.

## Try a number without touching the shipped file (debug builds)

* **Debug panel**: press **F6** in a debug build. Pick a role, use the **+ / −** steppers, then start the next fight (a fight
  that is already running keeps its copy). **Copy JSON diff** puts the changes on the clipboard (paste them into `balance.json`),
  **Save override** keeps them for the next debug launch, **Reset** drops them.
* **Override file**: `user://config_override/balance.json` (or `--config-dir=<folder containing balance.json>`) holding just the
  keys to change, e.g. `{"profiles": {"n": {"armor": 0.3}}}`. Dictionaries merge key by key, arrays are replaced whole.

Safety rules, enforced in code and tested (`config` suite):

* Overrides exist **only in debug builds**. A release build ignores the folder, the file and the panel.
* An override changes the **tuning stamp** (`balance-v1+override:...`). Starting an **online or ranked match clears the
  override** and locks it out until the match ends, so a client and a server can never run different numbers.

## Where each knob lives

| You want to change | Look at |
|---|---|
| A role's toughness, stamina and poise, defence timing, dodge, movement feel | `profiles.<role>.*` |
| Swing speed, damage, reach, arc (aim), knockback, super armour, lunge | `attacks.<role>.light[i] / heavy / abilities.<id>` |
| Ability behaviour (buffs, blink, counter stance, Queen combo) | `abilities.<id>.*` |
| How long stun lasts after a hit (heavier blows stun longer) | `hit_stun.*` |
| Comeback bonus and the sudden-death ramp that end long duels | `pacing.*` |
| Fight length per pairing | `duel_length.*` |
| Who has the advantage when attacking | `attacker_edge.matrix[attacker][defender] = [attacker x, defender x]`, `attacker_edge.stamina.*` |

Contract stats (health, base damage, move speed, reach, light/heavy/parry ticks, ability cooldowns) come from the BattleRequest
(`godot/chess/battle_stats.json`, Codex-owned), not from this file.

## The tuning stamp

`balance-v1:<16 hex>` is a hash of the *values* (not of formatting or comments). A server and its clients must show the same stamp.
After an intended change update `SHIPPED_STAMP` in `godot/combat/tests/test_balance.gd` and say why in the comment. The `config`
suite pins the stamp too, so an accidental edit fails loudly.

## Recalibrating the attacker table (after changing frame data, stun, pacing or roles)

1. Run the calibration in 4 shards (about 25 to 30 minutes), e.g. for shard `i` in 0..3:
   `godot --headless --path godot --script res://combat/tools/edge_calibrate.gd -- rule=initiative n=24 iterations=6 seed=31000 shard=$i/4 out=<dir>/edge-$i.json`
   (give every shard its own `XDG_*` folders when running them in parallel).
2. Merge: `python3 godot/combat/tools/merge_edge.py <dir>/edge-*.json --write` (preview without `--write`).
   Duel length uses `length_calibrate.gd` and `merge_length.py` the same way.
3. The tools rewrite **only their own block** (`attacker_edge`, resp. `duel_length`) and leave every other block, `hit_stun` and `pacing`
   included, byte for byte as it was (guarded by `tests/balance_merge_test.py`; the 2026-11-16 pitfall where blocks after
   `attacker_edge` were dropped is fixed). Check `git diff` anyway.
4. Update `SHIPPED_STAMP`, run the suites below, and note the new table in `godot/combat/BALANCE.md`.

## Checks before you commit a balance change

```sh
godot --headless --path godot --script res://tools/config_check.gd
godot --headless --path godot --script res://tests/run_combat_tests.gd -- config balance attacker_edge piece_identity pacing roles net_arena
python3 -m unittest discover -s tests -p balance_merge_test.py      # npm run test:config
npm run test:battle && npm run test:multiplayer
```

After editing `godot/config/*_meta.json` regenerate the reference tables:
`godot --headless --path godot --script res://tools/config_docs.gd` (the `config` suite fails while they are stale).

## What the numbers do not tell you

Bots measure balance, humans feel it. Every table in this repository is bot-measured; a human playtest of each pairing is still open
(see `TODO.md`).
