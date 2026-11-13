# Paladin pieces on the 3D board

The rigged paladin models (`godot/assets/paladins/`, loader `godot/paladins/paladin_model.gd`) are the default 3D piece set ("Paladins
(animated characters)" in Board settings; the procedural and carved sets stay selectable and are the fallback when the models are missing).

- `godot/boards/paladin_piece.gd`: wraps a `PaladinModel` under the usual piece root. The root keeps the contract BattleWorld / PitSequence rely on
  (position, `rotation.y` 0 white / PI black, scale, visible); the model sits under `facer`, which turns to the walking direction and back.
- `ChessBoard3D.sync_state` (`godot/boards/board_3d.gd`): for ONE new ply forward (and animation on) the moved piece walks (a step up to
  1.6 m) or runs (longer) along a straight line; a knight walks an L (long leg first); castling moves both pieces; a captured piece stays until the
  mover has arrived, then shrinks away; a promoted pawn walks, then becomes the new piece on arrival. Undo, new game, FEN load, flip, theme change and
  "Animate moves" off snap instantly. The chess state is applied at once: the animation never gates input or rules.
- Speeds 1.5 m/s walking, 3 m/s running, never slower than 2.5 s for a whole move (BoardTheme animation speed scales it).
- Heights (m): pawn 1.10, knight 1.30, bishop 1.36, rook 1.24, queen 1.44, king 1.52 (tile = 1 m), so they read from the top-down view too.
- Resting pose is the first frame of the Walking clip (paused, so idle pieces cost no animation time) until the model owner adds a real idle.
- The model template cache is never in the tree; `PaladinPiece.release_cache()` frees it at engine shutdown (and when a board leaves the tree).

Tests: combat suite `paladin_board` (`godot --headless --fixed-fps 60 --path godot --script res://tests/run_combat_tests.gd -- paladin_board`).
Screenshots (software GL): `docs/ui/paladins/`, made with `godot/combat/tools/paladin_board_shot.gd`.

Limits: the Battle Chess pit still shows the old character models for the fighters until the combat conversion lands; the attacker walks to the
tile inside the existing pit sequence (not on the board first); castling's rook and king can pass through each other; sliding pieces cross
squares in a straight line over other pieces' heads is not prevented; nothing was seen on a real GPU.
