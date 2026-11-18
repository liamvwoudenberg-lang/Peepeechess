# Fairness pass — changelog, tuning values and measurements (2026-11-18)

Target engine: the **Godot** client (`godot/`). The legacy TypeScript game (`src/battle/`) was **not** changed.
Goal: chess skill and fighting skill count about equally; neither lets a player ignore the other.
**Everything measured below comes from bots, not humans.** No person has played these changes (see "Limits").

## What changed and why

| Pillar | Change | Where (all numbers in `godot/combat/data/balance_v1.json`) |
| --- | --- | --- |
| Capture = gamble | **Defender's edge:** the attacker cannot start an action for the first 24 ticks (0.4 s), the defender takes x0.92 damage and recovers stamina x1.15 faster. | `duel_rules.defender` |
| | **A failed attack costs the attacker:** a whiff, a blocked or a dodged swing drains stamina (x1.5 for the seat that started the duel). Parried swings already cost a stagger. | `duel_rules.failed_attack` |
| Skill over stats | **Stat-gap compression table recalibrated.** The per-pairing damage multipliers (`attacker_edge.pairs`) no longer give the attacker the initiative; they are fitted so equal-skill duels hit `duel_rules.targets`: Pawn vs Queen about 15–25 %, every other pairing 35–65 %, defender +3 points. | `attacker_edge.pairs`, `duel_rules.targets` |
| Fast pace | Sudden death starts at 30 s (was 40) and ramps 6 %/s (was 4 %), so passive duels end: timeouts 4.4 % -> 3.1 %, p90 duel 68 s -> 60 s. The duel timer was already separate from the chess clock (Battle chess is untimed; a duel is 3 s countdown + 90 s). | `pacing.sudden_death` |
| Persistent damage | A piece keeps its HP fraction after a duel (floor 25 %, so it is never useless) and heals 4 % per own turn, +10 % more on its two home ranks ("rest squares"). | `meta.persistence`, `meta.healing` |
| Support / position | Defended piece takes x0.90, isolated x1.10, flanked x1.05; holding 3+ centre squares (and more than the opponent) gives x1.10 stamina regen. | `meta.support`, `meta.key_squares` |
| Resolve | Earned on the board (protecting pieces, centre control, giving check, holding the line as defender, winning a capture) and refunded by duel performance (parry, dodge, hits). Spent **in the duel on the ability button**: wounded + ability on cooldown = **Second Wind** (vulnerable 0.8 s heal cast, 22 % HP); healthy = **Overcharge** (ability ready again). An exhausted fighter's dodge is paid with Resolve (**extra dodge**). | `duel_rules.resolve`, `meta.resolve` |
| Tempo bonus | A **decisive** win (winner keeps 60 %+ HP) heals the winner 12 % and grants 15 Resolve. *Not a free move:* see "Not done". | `meta.decisive` |
| Anti-snowball | The side behind by 3+ material gets x1.6 Resolve gains and takes x0.93 damage. | `meta.comeback` |
| King | Unchanged: kings never duel in this ruleset, checkmate decides the game; King pairings are neutral in every new rule. | |
| Debug | `F3` / `--combat-debug` overlay now shows per-seat HP, damage dealt/taken, Resolve (+gained -spent), damage multiplier and the last 8 log lines; `--duel-log` or `PEEPEECHESS_DUEL_LOG=1` prints the same lines to the console. The chess layer keeps `meta.notes` (heals, Resolve, support tags per duel). | `combat_debug.gd`, `CombatSimulation.debug_lines` |

New code: `chess/battle_meta.gd` (rules), `chess/battle_meta_match.gd` (the local Battle match now uses it; chess rules are still `battle-checkmate-v1`), the duel rules in `combat/core/combat_simulation.gd`, `fighter_controller.gd`, `combat_state_machine.gd`; the bots use Second Wind through `CombatAI.use_resolve` (own Resolve is handed over locally because it is not in the v1 snapshot; no wire/contract change).
Raw frame data (`attacker_edge:false`), King pairings, practice mode (`training_session.gd`) and the net test rigs run with `duel_rules:false`, so every older mechanic test still measures raw numbers.

## Tuning values to try first (all in `balance_v1.json`)

1. `duel_rules.defender.take_mult` 0.92 -> 0.90 and `head_start_ticks` 24 -> 30 if attackers still win more than ~50 % (measured 51.6 %, target ~47 %).
2. `duel_rules.failed_attack.whiff_stamina` 9 -> 12 if players spam swings; down to 6 if attacking feels too punished.
3. `meta.support.*` and `meta.persistence.min_start_hp_frac` (0.25 -> 0.15) / `meta.healing.per_turn_frac` (0.04 -> 0.02) to make the board matter more. Measured: these moved the chess-vs-fight result by less than the noise (6/24 vs 7/24 wins), so do not expect them to fix a fight-skill imbalance.
4. `duel_rules.resolve.second_wind.heal_frac` (0.22) and `cost` (40) for how much a comeback heal is worth.
5. After any change to attacks, stats or AI: re-fit with `edge_calibrate.gd rule=skill` (below) and `python3 godot/combat/tools/summarize_duels.py`.

## Harness (headless, no window)

```sh
godot --headless --path godot --editor --import        # once, and after adding scripts
# piece vs piece, white vs black, attacker vs defender, with flags outside 35-65 %:
godot --headless --path godot --script res://combat/tools/duel_report.gd -- n=40 seed=90000 style=duelist skill=0.9 shard=0/4 out=/tmp/dr-0.json   # shards 0..3
python3 godot/combat/tools/summarize_duels.py /tmp/dr-*.json --md /tmp/report.md
# chess skill vs fighting skill, full games through BattleMetaMatch (persistence, support, Resolve, comeback):
godot --headless --path godot --script res://combat/tools/chess_vs_fight.gd -- games=32 seed=300 chess_a=5 fight_a=0.45 style_a=duelist chess_b=2 fight_b=0.90 shard=0/4 out=/tmp/cvf-0.json [patch='{"meta":{...}}']
# re-fit the compression table to the targets (about 10 min on 4 cores), then write it into the data:
godot --headless --path godot --script res://combat/tools/edge_calibrate.gd -- rule=skill skilled_weight=1.0 n=40 iterations=6 shard=0/4 out=/tmp/cal-0.json
```

## Results (bots; seeds never used for calibration)

**Equal-skill duels** (duelist 0.9 on both seats, 1000 duels, +-1.6 points on aggregates, +-8 on a single cell):

| attacker \ defender | Pawn | Knight | Bishop | Rook | Queen |
| --- | --- | --- | --- | --- | --- |
| Pawn | 32 | 30 | 25 | 45 | **18** |
| Knight | 35 | 45 | 65 | 65 | 52 |
| Bishop | 75 | 40 | 55 | 52 | 45 |
| Rook | 70 | 55 | 40 | 62 | 60 |
| Queen | **85** | 48 | 70 | 60 | 60 |

Piece strength (all duels): Pawn 35 %, Knight 54 %, Bishop 51 %, Rook 50 %, Queen 59 % (all inside 35–65). Attacker wins 51.6 %; attacker white 54.8 % / black 48.4 %; median duel 32.9 s (p10 18.6 s, p90 60.2 s); 3.1 % timeouts. The underdog Pawn beats the Queen 15–18 % of the time attacking and 15 % defending (the 15–25 % target).
**Flagged outside 35–65 %** (the Pawn<->Queen pairing is the intended exception): Pawn attacks Pawn 32 %, Pawn attacks Knight 30 %, Pawn attacks Bishop 25 %, Bishop attacks Pawn 75 %, Rook attacks Pawn 70 %, Queen attacks Bishop 70 %. All of them are Pawn pairings or the Queen; most are within two standard errors of the band, none is a hopeless matchup, but the Pawn is the weakest piece for a skilled fighter.

**Chess skill vs fight skill** (32 games per row, checkmate or draw; A = chess level 5 "Expert", B = chess level 2 "Casual" and a duelist 0.90 fighter):

| A's fighter | A wins | B wins | draws |
| --- | --- | --- | --- |
| button-masher (balanced 0.30) | 7 | 16 | 1 (24 games) |
| balanced 0.55 | 5 | 27 | 0 |
| duelist 0.40 | 13 | 16 | 3 |
| duelist 0.55 | 14 | 17 | 1 |
| duelist 0.70 | 21 | 10 | 1 |

So the two skills reach parity where a strong chess player is a moderate (not hopeless) fighter. A pure button-masher cannot be rescued by chess in these games: fighting skill still outweighs chess skill at that extreme, and the chess bot does not know it is a weak fighter, so it keeps capturing. Resolve flow in the 24-game run: 11,067 gained, 1,480 spent, 12 second winds, 40 Resolve dodges, 79 decisive wins in 172 duels; defenders won 74 % of duels in these games because the chess-strong side attacks more often than it can win.

## Limits (read before trusting any of this)

* **Bot-measured only.** The casual bot (balanced 0.6) sees a very different roster from the duelist bot, because the damage table was fitted to the duelist: Pawn 73 %, Knight 21 % (24 duels per pairing, before the final sudden-death tweak). A human is neither bot. The big multipliers (up to x3.75) are the honest cost of the Pawn's 80 HP / 12 damage; a real fix is to compress the contract stats themselves (`godot/chess/battle_stats.json`, with `src/battle/config.ts` and `scripts/export-battle-stats.mjs`) and then re-fit; that was not done here.
* The chess AI's capture evaluation (`chess/ai/battle_model.gd`) still reads the old `balance_matrix_v1.json` win table; it was not regenerated.
* **Not done:** a *free reposition* (changing whose turn it is needs a contract and UI change; decisive wins give heal + Resolve instead); rock-paper-scissors counters beyond the existing Knight lunge / Bishop beam / Rook guard-break (not measured as a cycle); Resolve and persistent HP are **not** used by the online server/`match_session` or the TypeScript game; the net client does not predict the defender's head start (an attacker's early swing is rejected by the server); the Royal ruleset (`battle-royal-v1`) is unchanged.
* Pre-existing, unrelated: the `anim_integrity` suite fails the same 6 high findings on the untouched baseline commit (Knight lunge / Rook heavy / Bishop heavy animation timing).
