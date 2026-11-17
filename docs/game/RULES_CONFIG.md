# Chess rules configuration

[`godot/config/chess_rules.json`](../../godot/config/chess_rules.json) holds every tunable rule switch and number outside combat
balance. Meaning, unit and allowed range of every key: the generated table [RULES_REFERENCE.md](RULES_REFERENCE.md). Keys starting
with an underscore are comments. Combat numbers are in [`balance.json`](BALANCE_GUIDE.md).

| Section | What it controls | Read by |
|---|---|---|
| `time_controls` | The clock presets (label, starting time, increment) in the Play page and the friends challenge | `ui/application.gd` (`TIMES`) |
| `computer_levels` | The six chess computer levels: search depth, node/time budget, noise, deliberate blunders, and the duel skill/style the level uses in Battle Chess | `chess/ai/chess_ai.gd` |
| `duel_ai_levels` | Easy / Normal / Hard / Expert duel bots: reaction delay, error rate, combo following, defence | `combat/ai/ai_difficulty.gd` |
| `battle_ai` | How the chess computer values a capture in Battle Chess (piece fight value and strength tier) | `chess/ai/battle_model.gd` |
| `royal` | Piece order values used by King's last stand | `chess/battle_royal_rules.gd` |
| `campaign` | Lives, boon stacking and offer size, the AI level of each of the 12 encounters, the five boons | `campaign/*` |
| `training` | Combo, counter and whiff-punish windows and the lesson time limit | `training/*` |

## What is deliberately not configurable

Move legality, castling, en passant, promotion, check, checkmate, stalemate, insufficient material, the fifty-move rule claim
(100 half-moves) and automatic draw (150), threefold-repetition claim and fivefold automatic draw. These are FIDE rules shared by
every client and by the online contract, so a local file must never change them. The file carries a `_fixed_rules` note with the
same list.

## Validation and the override

* Loading checks every value (type, range, unit, unknown key) and names the problem, for example
  `config/chess_rules.json: computer_levels.3.max_depth = 0 is below the minimum 1 (unit: plies)`.
  The 12 campaign levels must be `easy`, `normal`, `hard` or `expert`; computer levels must be numbered 1..N without gaps.
* Debug builds can override single keys with `user://config_override/chess_rules.json` (or `--config-dir=<folder>`): objects merge
  key by key, lists are replaced whole. Release builds and online/ranked matches ignore it.
* `godot --headless --path godot --script res://tools/config_check.gd` validates both files; `config_diff.gd chess_rules` shows
  what you changed against git HEAD.

Time controls are a local UI choice and are not part of the combat tuning stamp.
