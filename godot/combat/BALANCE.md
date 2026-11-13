# Combat balance (six classes)

**Everything here is BOT-measured, not human-tested.** The numbers come from scripted opponents (`CombatAI` styles) playing
through the real `CombatInput` channel. They show that a winning plan exists for a scripted player that knows the published
frame data; they say nothing about how hard that plan is for a human, nor about feel. No human has played these fights.

## Attacker advantage (2026-11-13)

**The question:** are the six classes balanced, and does the attacker, like in real chess, have the advantage over the defender?
Measured first (`tools/attacker_matrix.gd`, 100 seeded duels per attacker/defender pairing, the same bot on both sides, seat colour
alternating): **no and no.** Before this change the attacker won **49.0%** of duels with the casual bot (`balanced` 0.6) and **47.8%**
with the skilled bot (`duelist` 0.9): a coin flip, slightly worse in mirror matchups (42-51%) because ties go to the defender. The roster
was far from balanced: as attacker the Queen won 74-78% and the Pawn 17-20%; **a Pawn attacking a Queen won 1 duel in 100**, a Queen attacking a
Pawn 95-98%.

**The rule now:** every pairing has two damage multipliers in `balance_v1.json` (`attacker_edge.pairs`, key = attacker role + defender
role, value = `[attacker x, defender x]`). Only the *weaker* side of a pairing is boosted and nobody is ever reduced, so a Pawn attacking a
Queen hits several times harder, and a Queen attacking a Pawn faces a defender that hits back harder. The multiplier is applied in
`CombatSimulation._apply_hit` before armour, so it also scales chip damage and the stamina cost of blocking the blow. The result and snapshot
shapes are unchanged (HP stays within the contract maximums). The pre-duel card states the advantage in words
(`Balance.describe_edge`), the tuning stamp changes with the table (a client and server with different tables can tell), the King is
neutral on either side (King's last stand keeps its own balance), and `CombatSimulation.start(request, {"attacker_edge": false})`
switches it off for tests of raw frame data (the shared test rigs do).

**Calibration** (`tools/edge_calibrate.gd`, merged into the data by `tools/merge_edge.py`): for each of the 25 pairings (Pawn, Knight, Bishop,
Rook, Queen) it bisects one scalar until the attacker wins about 62% of duels, averaged over the casual and the skilled bot, then the eight
weakest pairings were re-calibrated with twice the sample. Calibration seeds are never used to judge the result.

**Validation on independent seeds** (100 duels per pairing and bot, `tools/attacker_matrix.gd`): the attacker now wins **66.4%** (casual bot) and **59.2%** (skilled bot). Averaged over both bots, **every one of the 25 pairings favours the
attacker: overall 62.8%, lowest 56%, highest 72%, none below 55%** (table below, attacker = row). A Pawn attacking a Queen: **95% casual / 48%
skilled, mean 72%** (it was 1%). Timeouts: 0 of 2,500 casual duels, 166 of 2,500 skilled (it was 201). Average duel: 9.2 s casual, 25.7 s skilled
(it was 11.8 s and 28.2 s).

| attacker \ defender | Pawn | Knight | Bishop | Rook | Queen |
| --- | --- | --- | --- | --- | --- |
| **Pawn** | 60% | 62% | 64% | 70% | 72% |
| **Knight** | 57% | 61% | 72% | 56% | 64% |
| **Bishop** | 63% | 58% | 64% | 58% | 66% |
| **Rook** | 69% | 70% | 58% | 58% | 67% |
| **Queen** | 60% | 60% | 62% | 58% | 62% |

(mean of the casual and the skilled bot's attacker win rate, 100 duels each, seeds 9000+). The individual bots still disagree for a few pairings
(casual / skilled attacker win rate): Knight attacking Rook 15% / 97%, Rook attacking Knight 100% / 39%, Queen attacking Rook 28% / 89%, Bishop
attacking Rook 32% / 85%. The table is fitted to their mean; see the limits below.

**Why damage multipliers and not stamina.** The idea of an attacker with unlimited stamina and a defender with very limited stamina was built
and measured as a data-driven rule (`attacker_edge.stamina`: `attacker_cost`, `defender_cost`, `defender_regen`; it scales every stamina cost,
including sprinting and blocking, and the client's prediction mirrors it). Sweeps of four settings over all 25 pairings:

| rule (attacker cost / defender cost / defender regen) | casual bot: mean attacker win | skilled bot: mean attacker win |
| --- | --- | --- |
| none (baseline) | 49% | 48% |
| 0 / 1.25 / 0.9 | 77% | 44% |
| 0 / 1.5 / 0.8 | 84% | 48% |
| 0 / 1.75 / 0.7 | 89% | 52% |
| 0.5 / 1.5 / 0.8 | 84% | 48% |

A limited-stamina defender only hurts a fighter that blocks and dodges a lot; the skilled bot parries (10 stamina, 8 refunded on success), so its
stamina rarely binds. The rule therefore helps casual attackers enormously (mirror duels at 87-100% for the stronger settings, defending becomes
hopeless) and skilled attackers barely at all, and it widened the gap between the two skill levels from 34 to 41 points once damage was calibrated
on top. The attacker's own stamina almost never binds (the 0 and 0.5 rows are identical). So the shipped rule is the damage table, and the
stamina rule ships **neutral** (1.0 / 1.0 / 1.0): it is implemented, tested and one data edit away if a human playtest says defenders should
tire faster. If you enable it, recalibrate (`edge_calibrate.gd stamina=...`).

**Limits, honestly.**
* Everything is bot-measured. The two bots disagree sharply for some pairings (for example Knight attacking Rook: 15% casual, 97% skilled at one
  point of the calibration) because they play differently, not because of the numbers; the table is fitted to their mean. A person is neither
  bot. This needs human playtests before anyone trusts it.
* Two pairings (Pawn and Bishop attacking a Queen) reached the 6x search limit; their mean attacker rate is above 50% but below the target.
* The largest multipliers are large (up to x6); that is how far apart the classes are in raw stats. Narrowing the roster itself (Pawn HP and damage
  up, Queen down, as recommended further below) would make every multiplier smaller; that is a stats change outside this table.
* Duels are shorter and more decisive (casual bot: 11.8 s -> 9 s on average) and the skilled bot's timeouts fell, but "fun" is not something a
  bot can measure.
* Any later change to attacks, stats, stamina or the bots' behaviour moves these numbers; the `attacker_edge` test suite has a fixed-seed gate
  that fails when the attacker's advantage drifts, and the table must then be re-calibrated.

Reproduce: `godot --headless --path godot --script res://combat/tools/attacker_matrix.gd -- n=100 seed=9000 style=balanced skill=0.6 out=/tmp/a.json`
(add `edge=off` for the raw baseline, `stamina=0,1.25,0.9` for a stamina rule on its own; shard with `shard=0/4`);
calibrate with `edge_calibrate.gd target=0.62 n=32 iterations=8 shard=0/4 out=...`, merge with `python3 godot/combat/tools/merge_edge.py out-*.json --write`.

## Where the numbers live

* `godot/combat/data/balance_v1.json` (loader `data/balance_data.gd`, `preload` only): per-role profiles (poise, armour, guard,
  dodge, stamina economy, **movement profile**), ability definitions, every attack's frame data. `tuning_id` = `balance-v1`;
  `Balance.stamp()` = `balance-v1:<first 16 hex of the SHA-256 of the canonical data>` (currently `balance-v1:894711f5b35e3d38`, since the attacker advantage table was added; the win-rate matrices further down were measured against the previous data, `balance-v1:c8d3224861885f1d`).
* **Contract stats stay in the BattleRequest** (HP, stamina, base damage, speed, reach, light/heavy/parry ticks, cooldown, ability
  id; from `godot/chess/battle_stats.json`, owned by Codex, untouched). The data file contains none of them (tested).
* **Server and clients must run the same tuning**: compare `Balance.stamp()` before a fight. Proposal for Codex: add the stamp
  (string) to the match/battle handshake or to `BattleRequest` in the next contract revision and refuse mismatches.
  Overrides (`Balance.apply_override(patch)` / `clear_override()`) exist for tests and tooling only; they change the stamp
  (`balance-v1+override:...`), never leak into running fights, and are cleared by the suites that use them.

## What changed vs the previous hard-coded tables

| Item | Before | After |
| --- | --- | --- |
| Pawn, Knight, Bishop, Rook, Queen profile/ability/attack numbers | constants in GDScript | **identical values** from JSON (verified field by field and by type against a dump of the old tables) |
| Movement | global constants (`ACCEL 45`, `DECEL 70`, `TURN_FREE 0.30`, ...) | per-role keys; Pawn and Knight equal the old constants |
| Bishop | - | accel 55 / decel 85, turn 0.32/0.48, steer 0.38/0.14 |
| Rook | - | accel 30 / decel 52, turn 0.22/0.34, steer 0.28/0.08 (heavy, slow to turn) |
| Queen | - | accel 52 / decel 80, turn 0.34/0.50, steer 0.40/0.14 |
| King (new, experimental) | refused | armour 0.15, poise 85, parry arc 150, riposte x1.5, accel 36 / decel 60, turn 0.25/0.38; Royal Counter |

Pawn and Knight attack/profile numbers are deliberately **not retuned**: the existing suites assert them exactly
(damage, hitstun, poise, parry stagger, dodge, guard costs). A sensitivity sweep showed only `hit_react_ticks` and
`stagger_immunity_ticks` could move without breaking an existing test. No other class was retuned either: with the AI family below every
pairing is already winnable, so I changed nothing that was not needed.

### King and Royal Counter

`CombatSimulation.start(request)` stays strict (the v1 schema forbids `k` as a Combatant role; `supports_role("k")` is false).
`start(request, {"allow_experimental_roles": true})` validates a copy whose king combatants carry a placeholder role (schema check
only); every other rule is still enforced (tested). Royal Counter (data `abilities.royal-counter`): 56-tick cast, 22 stamina,
cooldown from the stats (600). Armoured from tick 0; **ticks 6..25 are the counter window**: a hit inside the 160-degree frontal
arc is negated (reported as a `parry` event: actor = attacker, target = King, because the v1 event enum has no `counter`), the
attacker is staggered 52 ticks, the King snaps to face them and ripostes (`king.royal-counter`, 30 ticks, first active tick 9,
damage x1.7 x riposte_mult 1.5) through the normal damage path. Ticks 26..55 are a whiff recovery: no armour, no actions. The stance moves at 20% speed and turns at 35% rate.
HUD string for the ability: **"Royal Counter"** (`FighterRoster.ability_name("k")`).

## Bot methodology

`CombatAI(builder, my_stats, opp_stats, seed, skill, style)`; styles: `balanced` (the original AI = the **default AI**,
skill 0.6), `aggressive`, `defensive`, `evasive`, `ability`, `duelist`, `patient`. `duelist`/`patient` model a skilled player:
they know the published frame data, identify the swing from the opponent's visible stamina drop and chain position, parry
on its first active tick (dodge the Knight's lunge), account for visible buffs, never swing into a Royal Counter stance, and punish
stagger and recovery; `patient` almost never pokes. Seats and attacker colour alternate with the seed.
"Winnable": some style/skill beats the default AI in >= 50% of N seeded fights. Fight outcomes are deterministic per seed.

## Win-rate matrix (N = 8 seeded fights per cell, `tools/balance_matrix.gd`, raw data `data/balance_matrix_v1.json`)

**Best style vs the default AI** (row = the class we play, column = the default AI of that class; wins of 8, `du` duelist,
`pa` patient). Every cell is >= 6/8: **no hopeless pairing, 36/36 winnable.**

| | p | n | b | r | q | k |
| --- | --- | --- | --- | --- | --- | --- |
| **p** | 8 du | 8 pa | 8 pa | 8 du | 7 pa | 6 pa |
| **n** | 8 du | 8 du | 8 du | 8 du | 8 pa | 8 du |
| **b** | 8 du | 8 du | 8 du | 8 du | 7 pa | 7 pa |
| **r** | 8 du | 8 du | 8 du | 8 du | 7 pa | 8 du |
| **q** | 8 du | 8 du | 8 du | 8 du | 8 du | 8 du |
| **k** | 8 du | 8 du | 8 du | 8 du | 8 du | 8 du |

**Default AI vs default AI** (row wins of 8; this is how the *unskilled* bot sees the roster):

| | p | n | b | r | q | k |
| --- | --- | --- | --- | --- | --- | --- |
| **p** | 5 | 0 | 0 | 2 | 0 | 0 |
| **n** | 8 | 2 | 8 | 3 | 2 | 2 |
| **b** | 5 | 0 | 4 | 2 | 0 | 0 |
| **r** | 5 | 3 | 6 | 4 | 1 | 4 |
| **q** | 8 | 6 | 8 | 6 | 4 | 4 |
| **k** | 8 | 3 | 8 | 5 | 4 | 3 |

**Skilled mirror** (duelist/0.9 vs duelist/0.9, row wins of 8; the closest thing here to an expert power ranking):

| | p | n | b | r | q | k |
| --- | --- | --- | --- | --- | --- | --- |
| **p** | 5 | 0 | 0 | 2 | 0 | 0 |
| **n** | 8 | 6 | 7 | 8 | 3 | 4 |
| **b** | 8 | 1 | 5 | 5 | 0 | 1 |
| **r** | 7 | 0 | 3 | 5 | 0 | 0 |
| **q** | 8 | 7 | 8 | 8 | 5 | 6 |
| **k** | 8 | 1 | 6 | 6 | 4 | 7 |

Mirror cells away from 4 reflect seat/attacker-colour asymmetry in the tiny sample, not class strength. Timeouts: 11 of 4032 fights.
The fast gate `tests/test_matchups.gd` (N = 6, first configuration reaching 3 wins) passed all 36 pairs with 0 timeouts.

## Honest reading, strengths, weaknesses, counters

* **Winnable everywhere, not equal.** Among skilled bots the Queen is strongest (cheap fast attacks, 135 HP, Royal Fury) and the
  Pawn weakest (80 HP, 12 damage; it only ever wins by parrying), with the Rook losing to the quick classes it cannot catch.
  I did **not** flatten this: contract stats are Codex's, and Pawn/Knight tables are frozen by existing tests.
  Recommendation for Codex (contract stats, not changed by me): Pawn HP/damage up, Rook damage or speed up, Queen light cost or damage down; re-run `tools/balance_matrix.gd`.
* **Pawn** - strength: reach 1.95, best dodge, fastest. Weakness: dies to ~4 hits. Plan: parry on the first active tick and punish the stagger; counters everything only through defence.
* **Knight** - strength: armoured heavy/finisher, strong parry, lunge. Weakness: slow lights, lunge is dodgeable. Counter: dodge the lunge, punish the 72-tick commit.
* **Bishop** - strength: Blink i-frames, wide arcs. Weakness: low HP/poise. Counter: close the gap, trade into the Blink cooldown.
* **Rook** - strength: 190 HP, 25% armour, Fortress Guard. Weakness: slow acceleration and turning, big stamina costs. Counter: circle it, bait heavies, parry the first active tick.
* **Queen** - strength: fast cheap chains, 5-link Royal Fury. Weakness: lowest poise, 28. Counter: parry to break the chain; a staggered Queen takes a full combo.
* **King** - strength: Royal Counter (negates and punishes a mistimed swing), armour. Weakness: the whiff recovery (30 vulnerable ticks) and a 10 s cooldown. Counter: do not swing into the stance; punish the recovery.

## Not covered / limits

Human play, controller feel, Android performance, and network play of the King (the v1 protocol cannot carry a King battle yet).
The client movement predictor (`net/movement_predictor.gd`) still uses the global Pawn/Knight constants: Bishop/Rook/Queen/King
free-movement prediction will drift slightly until it reads `accel/decel/turn_free/turn_locked` from `FighterProfile.for_role()`
(a 9-line diff is in the scratchpad `predictor_proposal.diff`; I did not touch `net/`).

## Reproduce

```sh
godot --headless --path godot --script res://combat/tests/test_runner.gd -- balance king matchups
godot --headless --path godot --script res://combat/tools/balance_matrix.gd -- n=8 seed=1000 out=/tmp/m.json   # ~15 min on 4 shards
```

## King's last stand (battle-royal-v1): sequence win rates

**BOT-measured, not human-tested.** `tools/royal_matrix.gd` (runner `tests/royal_runner.gd`) plays whole sequences exactly as
`BattleRoyalMatch` does: the King (attacker, colour alternating with the seed) fights the checking pieces in value/square order,
its HP/stamina/cooldown carried from duel to duel (`CombatSimulation.start(req, {"allow_experimental_roles": true, "initial_hp",
"initial_stamina", "initial_cooldown"})`), every checker fresh. Ties and double knockouts go to the checker. N = 24 seeded
sequences per cell. "fresh" repeats the same sequences with a full-HP King in every duel (the cost of attrition = wins(fresh) - wins).

**vs the default AI checkers (balanced 0.6)** - King wins of 24 (fresh-per-duel in brackets):

| checkers | King balanced 0.6 | King duelist 0.9 | King patient 0.9 |
| --- | --- | --- | --- |
| P | 24 | 24 | 24 |
| N | 15 | 23 | 24 |
| B | 22 | 24 | 24 |
| R | 18 | 24 | 24 |
| Q | 5 | 24 | 24 |
| P+B | 9 (22) | 24 | 24 |
| N+B | 0 (14) | 23 (23) | 24 |
| B+R | 1 (14) | 24 | 24 |
| N+R | 0 (10) | 23 (23) | 24 |
| N+Q | 0 (2) | 13 (24) | 22 (24) |
| R+Q | 0 (5) | 16 (24) | 22 (24) |

**vs skilled checkers (duelist 0.9)**, King duelist/patient: P 24/22, N 8/10, B 15/18, R 22/16, Q 6/11, P+B 17/17, N+B 3/5,
B+R 13/13, N+R 5/4, N+Q 0/0 (timeouts up to 14 of 48 duels for patient Kings: a patient King vs a patient-ish checker stalls).

Reading (honest): one checker is winnable for a skilled King and a coin flip to a loss for the default AI (Queen: 5/24); two
checkers are decided by attrition: the King finishes duel 1 with 14-60 HP on average against N/Q/R, so duel 2 is nearly a coin-flip
at best. Against skilled checkers a King without a rest is a clear underdog.

**Recommendations (none applied; contract stats are Codex's `battle_stats.json`, tuning is `balance_v1.json`):**
1. If the last stand should be a *real* last chance, give the King a **partial refresh between duels** (for example +25% of
   maxHp, full stamina; a rule in `BattleRoyalMatch`, not a stat) or raise King HP 160 -> ~210; the matrix says double checks
   by N/R/Q are otherwise ~unwinnable for non-expert Kings.
2. Keep the cooldown carry (600 ticks) as is; stamina carry is the harsher resource: the King usually enters duel 2 with < 30%.
3. Consider a single-checker timeout rule: 5400-tick fights between a patient King and a patient checker time out often.
4. Re-run `royal_matrix.gd` after any King/Queen/Knight retune; human playtests are still required.

Reproduce: `godot --headless --path godot --script res://combat/tools/royal_matrix.gd -- n=24 seed=7000 out=/tmp/royal.json
checkers=balanced:0.6 king=balanced:0.6,duelist:0.9,patient:0.9` (about 8 min; the skilled-checker variant about 15 min).

## Pacing and duel length (2026-11-13)

Why: with the attacker's advantage duels became very short (bot knockouts at 5-10 s; a boosted Pawn could end a Knight in two hits) and
played like button mashing. The goal is a slower, more readable fight where reading the opponent beats spamming.

What changed (all data, `balance_v1.json`; simulation numbers only through the data):
- **Pacing:** longer parry and dodge cooldowns, a wider parry window (`parry_window_bonus`), longer dodge invulnerability, a bigger parry
  stagger and refund and a stronger riposte, and higher stamina costs for swings (a heavy Pawn swing costs 44 instead of 26), so mashing runs dry
  and a well-timed parry or dodge opens the opponent.
- **Duel length:** `duel_length.pairs` holds one damage scale per pairing, calibrated (`length_calibrate.gd`) so a bot duel lasts about 28 s of
  active fight (casual bot 13-34 s, skilled bot 23-60 s). Misses: Rook vs Rook (68 s) and Rook vs Pawn (43 s) stay long because their damage
  scale cannot go above 1.0.
- **Attacker's edge recalibrated** for the new tuning (`edge_calibrate.gd`, n=20 per probe, n=60 refinement for Queen->Pawn, Queen->Bishop,
  Rook->Pawn, Bishop->Pawn). Every pairing lands at 55-68% for the mean of the casual and the skilled bot at calibration time. NOT validated on
  independent seeds yet (the first edge got that treatment); expect +-8 points of noise per pairing.
- Presentation of the new numbers (the HUD shows felt damage) is in the combat HUD.

Gates: the `attacker_edge` suite (the attacker wins more often than not on fixed seeds, duels last like a fight), the pacing suite
(`test_pacing.gd`, including a spam check: a constantly attacking style does not beat a reactive one) and the full harness.
Reproduce: `edge_calibrate.gd`, `length_calibrate.gd`, `merge_edge.py` and `merge_length.py` in `godot/combat/tools/`.

Limits: bot-measured only. The bots do not feel "Dark Souls": real people will find the timing windows and stamina pressure either right
or wrong. Playtest, then re-run the calibration tools.
