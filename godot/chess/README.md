# Native Classic chess

`chess_engine.gd` is an original GDScript rules implementation; no third-party
engine source is vendored. Tests compare it against the repository's existing
BSD-2-Clause chess.js dependency and standard published perft positions.

- Board: indices 0=a1 through 63=h8, White uppercase; no scene dependencies.
- `load_fen(text)` validates transactionally. `fen()` exports the original FEN
  convention (the passed en passant square is recorded after every double pawn
  move, even without an adjacent capturer). Repetition keys include EP only if
  a legal EP capture exists. Imports validate position structure/king safety,
  not a retrograde proof that an arbitrary composed position is reachable.
- `legal_moves()`, `move(from,to,promotion)`, `undo()`, `in_check()`, `perft()`.
- SAN and PGN export. History includes source, target, promotion, SAN and FEN.
- Threefold/50 moves are claimable, including a declared intended legal move;
  fivefold/75 moves are automatic. Checkmate takes precedence over 75 moves.
- Standard insufficient-material detection handles bare kings, a lone minor,
  and bishops confined to one square color. No tablebase/retrograde solver for
  every possible blocked dead position is included.

`classic_match.gd` owns state, stable piece IDs, request admission, revisions,
clock checkpoints and local undo policy. Both board views read it and request
moves through it. It emits the existing v1 ChessGameState and MatchState and
accepts ChessMoveRequest with an independently authenticated seat ID. Its
`play()` convenience method is local-only. No client-provided FEN or result is
accepted as an ordinary move.

`clock_state()` is a local clock presentation API, **not** an addition to the
v1 wire schema. A production transport will need a versioned clock snapshot and
trusted clock synchronization. No native network adapter is introduced by this
Classic slice. In server mode local undo/pause/play conveniences are disabled;
server code must bind credentials before invoking submit_request.

## Computer opponent

`ai/` holds the computer opponent (alpha-beta search over this engine, six levels, Battle Chess duel model, worker thread). It uses
`legal_moves()` / `pseudo_moves()` / `_apply()` / `_restore()` as they are and plays through `ClassicMatch.play()`. See `ai/README.md` for the
design, the levels table, the Battle heuristic and the limits; run `npm run test:ai` for its suites.
