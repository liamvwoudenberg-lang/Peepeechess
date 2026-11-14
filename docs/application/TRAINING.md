# Combat Training: framework, lessons and AI difficulty

Logic only (no UI yet). Everything runs on the SAME combat engine as a Battle Chess duel (`CombatSimulation` / `CombatArena`): same
frame data, stamina, parry window, dodge i-frames, hit stun and balance data. Nothing here changes a rule.

## API (all in `godot/training/` unless noted)

| Class | Purpose |
| --- | --- |
| `AIDifficulty` (`combat/ai/ai_difficulty.gd`) | Four presets (`easy normal hard expert`) as behaviour parameter sets for `CombatAI`; `make_ai(level, builder, my_stats, opp_stats, seed)`; fixed behaviours (`idle passive_block attack_only normal`). |
| `AdaptiveDifficulty` (`combat/ai/adaptive_difficulty.gd`) | Optional controller: `record_fight({won, hit_ratio, damage_taken, parries})` returns the next level; `AdaptiveDifficulty.fixed("hard")` never changes. |
| `LessonCatalog` | `load_all()` reads `res://training/lessons/*.json` (schema-validated, ordered), `in_category`, `playable`, `get_lesson`, `is_unlocked(id, progress)`, `next_after(id)`, `errors`. |
| `LessonSchema` | `validate(lesson) -> Array` of problems. |
| `TrainingSession` | Runs a lesson on the real engine. Headless: `await start(tree)`, `skip_countdown()`, set `player.move/block/sprint`, `player.press("light")`, `step()` (one 60 Hz tick), `finish(progress)`. UI: use `lesson_request()` for a normal `CombatArena`, `apply_handicaps(arena.sim)`, and attach an `ObjectiveTracker` yourself. |
| `ObjectiveTracker` | Detects objectives from `sim.event_emitted` + public fighter state. Signals: `objective_progress`, `objective_completed`, `combo_changed`, `combo_failed`, `feedback(kind, text)`, `lesson_completed(stats)`, `lesson_failed(reason, stats)`. Call `update()` after every `sim.step_tick()`. `rating()` / `ObjectiveTracker.rate(lesson, summary)`. |
| `TrainingOpponent` | The lesson opponent (`idle`, `passive_block`, `attack_only`, `normal` + level); sees only the public snapshot. |
| `ProgressStore` | `user://training_progress.json` (versioned JSON, atomic write, tolerant of missing/corrupt/foreign files): `record_attempt(id, completed, rating, seconds)`, `best_rating`, `is_completed`, `attempts`, `save()`. |
| `FreePractice` | `make({player_role, opponent_role, behaviour, difficulty})` returns an objective-free lesson dictionary (`free_practice: true`: nothing is rated or saved; the UI restarts the fight). |

Player seat id is `player-white`, the opponent is `player-black` (`TrainingSession.PLAYER_ID / OPPONENT_ID`).

## Lesson format (`godot/training/lessons/<id>.json`)

```json
{
 "id": "b08_first_combo", "category": "beginner", "order": 8,
 "title": "Your first combo", "summary": "Chain three light attacks without a gap.",
 "player_role": "p", "opponent_role": "p",            // p n b r q k
 "behaviour": "idle",                                   // idle | passive_block | attack_only | normal
 "difficulty": "easy",                                  // easy | normal | hard | expert (used by "normal" behaviour)
 "arena": "stone-v1", "attacker": "player",             // who counts as the capturing side ("player" | "opponent")
 "objectives": [{"id": "combo", "type": "combo", "text": "Land a 3-hit combo", "count": 3}],
 "fail": [{"type": "time_limit", "seconds": 88}],       // time_limit | hits_taken{count} | damage_fraction{fraction}
 "rating": {"silver": {"max_seconds": 25}, "gold": {"max_seconds": 15}},   // bronze = completed
 "constraints": {"player_hp_fraction": 0.5},            // optional handicap: start HP
 "requires": ["b06_dodge"],                             // unlock: all completed (any rating); none = first of its category
 "hints": ["..."], "available": true                    // available:false needs "unavailable_reason"
}
```

Rating thresholds: `max_seconds`, `max_hits_taken`, `min_combo`, `min_parries`, `max_damage_fraction` (all must hold for the tier).
A lesson completes as soon as every non-`optional` objective is done; it fails on any `fail` rule, on defeat, or when the fight ends first.

### Objective types (detected only from real simulation events)

`move_distance{meters}` `hit_count{count}` `hit_at_range{count,min_distance}` `combo{count}` (consecutive connected hits within 78 ticks, broken
by being hit, blocked, parried or dodged) `block_n` `parry_n` `dodge_n` `counter_after{after:block|parry|dodge,count,window_ticks}`
`punish{count}` (a hit while the opponent recovers from a swing, is staggered, or whiffed in the last 70 ticks) `ability_use{count}`
`cancel{count}` (an attack cut short by a dodge, parry or ability) `stamina_cycle{drain_below,recover_above}` `hold_distance{min,max,seconds}`
`survive{seconds}` `stun{count}` (a hit that leaves the opponent staggered: hit stun) `stun_followup{count}` (another hit while that stun runs)
`win{}` `win_clean{max_hits_taken}`.

Pressing a button counts for nothing: the combo test suite shows 67 attack presses in the air complete nothing, while chained connected hits do.

## Lessons

30 lessons (29 playable, 1 unavailable) in four categories; the list is generated by `tools/training/build_lessons.py` (edit it, or edit the JSON
directly, then run the `training` suite which validates every file).

- Beginner: movement, camera control (**unavailable**: camera is presentation, the simulation reports nothing about it), basic attacks, range, blocking,
  dodging, stamina and recovery, first combo.
- Intermediate: multi-hit combo (Queen), dodge and counter, punish the recovery, block and punish, distance (Bishop vs Rook), hit stun and follow-ups,
  moving opponents.
- Advanced: Knight vs Pawn (reach + Lunging Strike), Rook vs Knight (parry + punish), Bishop vs Rook (spacing + counters), Queen vs King (Royal Fury
  combos), King vs Queen (Royal Counter), animation cancelling, reading attacks, punishing misses.
- Expert: hard duel, limited health (start at half HP), combos under pressure, beating a stronger fighter, surviving an Expert Queen for 30 s, difficult
  matchups (King vs Expert Queen, Rook vs Hard Bishop).

## AI difficulty

A preset is `{style, skill, params}`; `params` are `CombatAI` behaviour keys (`react_extra` ticks, `error_rate`, `follow_chance`, `timing_jitter`,
`defence_scale`, `parry_bias`, `block_bias`, `heavy_chance`, `follow_max`, `cooldown_scale`, `poke`, `hold_extra`, ...). No preset touches damage or health.
The AI plays through `CombatInputBuilder` packets and reads only the public `CombatSnapshot` taken BEFORE the current tick's inputs: it cannot see the
human's packet of the same tick (tested by submitting the human's packet before / after the AI decides: identical fights).

| Level | Style / skill | Behaviour |
| --- | --- | --- |
| Easy | balanced 0.1 | +16 ticks reaction delay, 30% hesitation, 35% defence rate, no parry bias, mostly single swings |
| Normal | balanced 0.5 | +4 ticks, 10% hesitation, simple 2-3 hit chains |
| Hard | duelist 0.78 | frame-data parries with +-3 ticks of error, punishes recovery, full chains |
| Expert | duelist 1.0 | exact frame-data timing, no hesitation, faster pokes, heavy finishers |

Measured win rate against the fixed reference bot (balanced, skill 0.6) with `combat/tools/ai_levels.gd`: see the table in the report below (bot-measured).

Adaptive mode: an exponential moving average of per-fight performance (win 0.5 + hit ratio + damage avoided + parries) must stay above 0.72 / below
0.32 for two fights before the level moves one step; a fixed level never moves.

## Adding things

- **A lesson:** add it to `build_lessons.py` (or drop a JSON file in `godot/training/lessons/`) and run the `training` suite.
- **A character:** add its role to `FighterRoster` (stats + attack tables in `balance_v1.json`); lessons may then use its role letter.
- **A combo or objective type:** add the type to `LessonSchema.OBJECTIVE_TYPES` / `REQUIRED_PARAM`, detect it in `ObjectiveTracker` from an event or fighter state, and
  add a scripted-fight test to `combat/tests/test_training.gd`.
- **An AI parameter:** add the key with a NEUTRAL value to `CombatAI.NEUTRAL` (neutral must draw no extra random numbers) and use it in a preset.

## Tests

`godot --headless --fixed-fps 60 --path godot --script res://tests/run_combat_tests.gd -- training ai_difficulty`
