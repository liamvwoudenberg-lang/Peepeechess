# Rules configuration reference (generated)

Generated from `godot/config/chess_rules_meta.json` by `res://tools/config_docs.gd`. Do not edit by hand: change the metadata, then regenerate.
The values live in `godot/config/chess_rules.json`. `*` stands for a list position (`[*]`) or a name (a level number, a role, a boon id).

## All settings

Everything in chess_rules.json.

| Key | Type | Unit | Range | What it does |
|---|---|---|---|---|
| `battle_ai.fight_value.*` | int | centipawns | 0 .. 5000 | Value the chess computer gives a piece when it fights a Battle Chess duel. |
| `battle_ai.tier.*` | float | tier | 0 .. 10 | Strength tier used to estimate who wins a duel (higher = stronger). |
| `campaign.boon_offer_size` | int | boons | 1 .. 5 | How many boons are offered after a win. |
| `campaign.boons.*.cost` | float | multiplier | 0.1 .. 1 | Stamina cost multiplier (0.85 = 15% cheaper). |
| `campaign.boons.*.health` | float | fraction | 0 .. 1 | Extra health (0.15 = +15%). |
| `campaign.boons.*.regen` | float | multiplier | 1 .. 3 | Stamina regeneration multiplier (1.3 = 30% faster). |
| `campaign.boons.*.stamina` | float | fraction | 0 .. 1 | Extra stamina pool. |
| `campaign.boons.*.text` | string |  |  | Boon description shown to the player (keep it in line with the numbers). |
| `campaign.boons.*.title` | string |  |  | Boon name. |
| `campaign.level_by_encounter[*]` | string |  |  | AI level (easy, normal, hard, expert) of each of the 12 encounters, in order. |
| `campaign.max_boon_stack` | int | times | 1 .. 10 | How many times the same boon may be taken in one run. |
| `campaign.start_lives` | int | lives | 1 .. 20 | Lives at the start of a campaign run. |
| `computer_levels.*.attack_style` | string |  |  | Duel style when attacking. |
| `computer_levels.*.blunder` | float | probability | 0 .. 1 | Chance that the level deliberately plays a weaker move. |
| `computer_levels.*.margin` | int | centipawns | 0 .. 1000 | Moves within this score margin of the best may be picked instead. |
| `computer_levels.*.max_depth` | int | plies | 1 .. 40 | Deepest search the engine may reach (ply = one half-move). |
| `computer_levels.*.name` | string |  |  | Name of the computer level shown in the UI. |
| `computer_levels.*.node_limit` | int | positions | 50 .. 5000000 | Search stops after this many positions (makes the level deterministic). |
| `computer_levels.*.noise` | int | centipawns | 0 .. 1000 | Random noise added to move scores (weaker levels play looser). |
| `computer_levels.*.q_ply` | int | plies | 0 .. 40 | Extra plies of capture-only (quiescence) search. |
| `computer_levels.*.skill` | float | 0..1 | 0 .. 1 | Duel skill used when this level fights in Battle Chess. |
| `computer_levels.*.style` | string |  |  | Duel style for defence: balanced, defensive, aggressive or duelist. |
| `computer_levels.*.time_ms` | int | milliseconds | 10 .. 120000 | Wall-clock thinking budget per move (scaled on slow devices). |
| `duel_ai_levels.*.label` | string |  |  | Name of the duel AI level (Easy, Normal, Hard, Expert). |
| `duel_ai_levels.*.params.block_bias` | float | offset | -1 .. 1 | Preference for blocking. |
| `duel_ai_levels.*.params.cooldown_scale` | float | multiplier | 0.2 .. 4 | Scales the pause between the bot's actions (higher = slower). |
| `duel_ai_levels.*.params.defence_scale` | float | multiplier | 0 .. 2 | How often the bot defends (1 = baseline). |
| `duel_ai_levels.*.params.error_rate` | float | probability | 0 .. 1 | Chance of a mistimed or wrong action. |
| `duel_ai_levels.*.params.follow_chance` | float | probability | 0 .. 1 | Chance to follow up with the next hit of a combo. |
| `duel_ai_levels.*.params.follow_max` | int | hits | 0 .. 8 | Longest combo the bot will attempt. |
| `duel_ai_levels.*.params.heavy_chance` | float | probability | 0 .. 1 | Chance to use a heavy attack when an opening appears. |
| `duel_ai_levels.*.params.hold_extra` | float | seconds | 0 .. 2 | Extra time the bot holds a block or heavy charge. |
| `duel_ai_levels.*.params.parry_bias` | float | offset | -1 .. 1 | Preference for parrying (negative = avoids parries). |
| `duel_ai_levels.*.params.poke` | float | probability | 0 .. 1 | How often the bot pokes at range. |
| `duel_ai_levels.*.params.react_extra` | int | ticks (1 tick = 1/60 s) | 0 .. 120 | Extra reaction delay (higher = slower to react). |
| `duel_ai_levels.*.params.timing_jitter` | int | ticks (1 tick = 1/60 s) | 0 .. 30 | Random timing error on actions. |
| `duel_ai_levels.*.skill` | float | 0..1 | 0 .. 1 | Overall bot skill. |
| `duel_ai_levels.*.style` | string |  |  | Fighting style the bot uses. |
| `duel_ai_levels.*.summary` | string |  |  | One-line description shown to the player. |
| `royal.piece_values.*` | int | points | 0 .. 100 | Order value of a piece in King's last stand (smaller defends first). |
| `schema` | int |  | 1 .. 1 | File format version. Do not change. |
| `time_controls[*].increment_ms` | int | milliseconds | 0 .. 600000 | Time added after every move (Fischer increment). |
| `time_controls[*].initial_ms` | int | milliseconds | 1000 .. 21600000 | Starting clock time per side. |
| `time_controls[*].label` | string |  |  | Name shown in the time-control list. |
| `training.combo_window_ticks` | int | ticks (1 tick = 1/60 s) | 1 .. 600 | Time allowed between hits for them to count as a combo. |
| `training.default_counter_window_ticks` | int | ticks (1 tick = 1/60 s) | 1 .. 600 | Default time to counter-attack after a parry or block in a lesson. |
| `training.max_lesson_ticks` | int | ticks (1 tick = 1/60 s) | 600 .. 60000 | Hard time limit of any lesson. |
| `training.whiff_punish_window_ticks` | int | ticks (1 tick = 1/60 s) | 1 .. 600 | Time to punish an opponent's missed attack. |

