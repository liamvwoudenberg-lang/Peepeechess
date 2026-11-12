# Battle Chess: battle-checkmate-v1

This codifies the **existing** `src/battle/rules.ts`/`BATTLE-CHESS.md` variant.
Classic remains ordinary chess. Victory remains checkmate, not king capture.
Mate uses Battle-legal moves; it is not an assertion that every Orthodox chess
escape remains available. In particular kings cannot initiate capture duels.
This preserves the working implementation rather than silently changing it.

## Safety before combat

Start with ordinary chess-legal moves, including usual king attack maps. Kings
attack adjacent squares for safety even though they never initiate captures;
pinned enemy pieces still attack squares as in chess. Reject king captures and
all king-initiated capture attempts. Quiet king moves and castling remain legal
when ordinary chess permits them. Kings stay on the board and never lose HP.

Before accepting any other capture, compute **both** complete successor boards:

- Attacker win: ordinary legal capture from origin to destination, including EP
  victim removal and any selected promotion.
- Defender win: attacker disappears from its original square; defender stays
  on its original square, including for EP. Switch turn, clear EP, reset the
  halfmove counter to 0, update rook castling rights and increment fullmove after
  Black's attempt. This consumes exactly one turn/ply, never a null/quiet move.

Both successors must leave the moving player's king safe. Otherwise the attempt
is unavailable and no battle starts. Never resolve an unsafe losing outcome by
leaving a checked king behind, rerolling combat, forcing attacker victory or
silently substituting a different chess move. The remaining player's king may
be in check if it is now that player's turn; that is an ordinary legal check.

The board stays frozen during the duel. No second chess move, promotion change,
view change or client-sent result can alter its pending identities/FEN. A result
from the trusted simulation resolves that exact pending capture once.

## Special moves and terminal states

| Situation | Rule |
| --- | --- |
| In check | Only moves satisfying both ordinary legality and the two-outcome safety test can be played. Capturing a checking piece is often unavailable because it would remain on a defender win. A capture that wins by interposing an attacker is likewise unavailable if losing removes that interposition. A quiet block/king escape remains possible when safe. |
| Pinned attacker | A move along a pin may be Orthodox-legal after capture but is forbidden if removal of the attacker exposes its king on defeat. A pinned defender is not moved on defender victory. |
| En passant | BattleRequest.defender.square is the actual pawn square, not the empty destination. Attacker win removes that pawn and lands on destination; defender win removes the attacker and leaves that pawn. Test discovered attacks for both outcomes. EP expires either way. |
| Promotion | Choose q/r/b/n before starting. Capturing pawn fights with pawn stats; it promotes only after attacker victory. Defender victory creates no promotion. Quiet promotion is immediate. Stable pieceId persists; role/characterId changes only on committed promotion. |
| Castling | Quiet compound king/rook move, no duel; both pieces move atomically and normal through-check/attacked-square rules apply. Rights never resurrect. An attacking original rook loses rights if it moves or dies; a defending original rook that stays and wins keeps its rights. Captured original rooks lose rights normally. |
| Mate | Side to move is in ordinary geometric check and has zero Battle-legal moves: it loses. This can be mate when an Orthodox king capture would escape, because king duels are excluded. Disclose that restriction in UI. |
| Stalemate | Zero Battle-legal moves without check: draw. |
| Draw accounting | Keep the existing automatic insufficient-material, 100-halfmove and threefold conventions. Count failed captures as captures for the halfmove reset. Repetition key includes side/rights and EP only when a Battle-legal EP capture exists. Do not claim these draw defaults match every FIDE claim procedure. |
| Duel ties | KO wins; at 5400 active ticks compare remaining/max HP percentages by cross multiplication. Exact tie or double KO favors defender. No random winner. Fresh stats/resources each duel, 180 countdown ticks. Chess is untimed in this Battle ruleset. |
| Abandonment | Resignation completes the match. Online inputs neutralize after 15 missing-input ticks; missing seat forfeits after 10 seconds, both missing draws. No synthetic king capture. Local play can explicitly pause. |

Example: `1r5k/8/8/8/8/8/r7/K7 w - - 0 1` has an Orthodox Kxa2
escape. It is checkmate under this variant: the king cannot duel and b1/b2 are
attacked. This is a documented difference in legal moves, **not a changed victory
condition**. Supporting all Orthodox king captures while allowing a defender to
kill every attacker would require another rule exception/version. That change
is outside this preservation task.

History stores intended from/to/promotion, outcome and final FEN. Failed
captures cannot be replayed as ordinary SAN/PGN. Existing `[defended]` chronicle
notation is descriptive only. Authoritative replays use custom events. The
initial automated tests exercise check/pins, EP, all promotions, rook rights,
move counters, repetition, terminal positions and one-time capture settlement.
