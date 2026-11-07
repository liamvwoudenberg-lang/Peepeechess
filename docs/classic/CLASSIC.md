# Play native Classic Chess

From the repository root with Godot 4.6.3:

```sh
godot --path godot
```

This is a playable **local two-player** native Classic game. The existing web
application and its online modes remain unchanged. Native matchmaking/network
transport, AI play, platform exports and combat integration are separate work.

Choose **New game** for untimed, 1+0, 3+2, 5+0, 10+0, 15+10 or 30+0. New game
starts White's clock; the initial demonstration board waits for Start clock or
the first move. Fischer increments apply after a legal move. Pause/resume and
undo are allowed only for local practice. Undo restores the pre-move clocks,
registry, castling/EP/draw state and history; it invalidates old revisions.
Switching views or perspective never pauses or restarts the match.

## Controls

| View | Mouse / keyboard | Touch |
| --- | --- | --- |
| 2D | Select piece and destination, or drag/drop. Focus the board and use arrows plus Enter/Space; Escape clears selection. | Tap piece then target, or drag a piece. |
| 3D | Click piece and target, or drag/drop. Right/middle drag orbits, wheel zooms. | Tap piece and target; swipe orbits; pinch zooms. |

Both views highlight legal destinations, selection, check and the last move.
All four promotion choices are available in a touch-sized dialog; the pawn does
not move until a choice is made. The clock continues during promotion/dialogs.
2D uses the existing illustrated royal pieces; 3D uses role-specific primitive
meshes with ivory/obsidian materials and lighting. Animation can be disabled.
Flip board and camera orientation are client-local state, absent from the wire
snapshots. A narrow window stacks the board above the match panel and scrolls
vertically; the square board itself remains fully visible.

**FEN / PGN** copies the current FEN or PGN to the clipboard. Loading a FEN is an
explicit new local match with reset clocks/history, not an in-game move. Invalid
FEN leaves the old match intact. A position that changed while the dialog was
open must be reopened before import. PGN export includes SetUp/FEN headers for
nonstandard initial positions; PGN import is not part of this slice.

**Draw options** lets the side to move claim threefold repetition or fifty moves
in the current position, or declare an intended legal move such as `g1f3` or
`a7a8q`. A valid claim ends the game without playing that declared move. An
agreed draw requires confirmation passed to the opponent on the shared device.
Fivefold repetition and 75 moves are automatic; mate takes priority. Resignation
requires confirmation. Timeout is a draw when the opponent has no mating
material; otherwise the opponent wins. Standard material dead-position cases
are detected; there is no exhaustive tablebase for arbitrary blocked positions.

## Architecture and integration

- `godot/chess/chess_engine.gd`: pure native legal moves, FEN, SAN, PGN, draw
  accounting, adjudication, undo and perft.
- `godot/chess/classic_match.gd`: local authority, monotonic clock accounting,
  stable identities, idempotent move requests, stale/seat rejection and v1 states.
- `godot/boards/board_interaction.gd`: common selection/move intent.
- `godot/boards/board_2d.gd`, `board_3d.gd`, `piece_meshes.gd`: projections only.
- `godot/app/main.gd`: responsive UI, promotion, clock and position dialogs.

No Claude combat-owned path is changed. The pure engine has no combat logic.
The user's new Battle king-gauntlet direction is recorded in
`docs/architecture/BATTLE_ROYAL_GAUNTLET.md` for a separate versioned integration.

Use `npm run test:classic` for the native tests and `npm run test:contracts` for
shared v1 compatibility. The CI PR check runs both alongside existing web checks.
See VALIDATION.md for actual results and limits of this PR.
