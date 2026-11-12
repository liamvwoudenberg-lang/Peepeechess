# ADR: `battle-royal-v1` - the King's last stand

Status: implemented, opt-in, 2026-11-11. Supersedes the "decisions still needed" list in
[`BATTLE_ROYAL_GAUNTLET.md`](BATTLE_ROYAL_GAUNTLET.md). The legacy `battle-checkmate-v1` / C0 rules
([`BATTLE_RULES.md`](BATTLE_RULES.md)), Classic, and every v1 contract/schema/fixture/type are unchanged.

Presentation model (final design): the circular arena (`stone-v1`) sits underneath the top-down board. A capture is a
trapdoor drop into the arena, a fight, and the winner climbs back. A last-stand duel uses exactly the same path; this
document only specifies the rules and data. (The abandoned on-board `board-v1` arena of `contracts/v2` is not used.)

## Why explicit decisions

Codex left these open on purpose because a live rules change must not be guessed. They are decided here, implemented as a
**new named ruleset** (`battle-royal-v1`, `BattleRoyalRules` + `BattleRoyalMatch`), and covered by tests. Nothing selects
it by default; Classic never starts a duel.

## Decisions

### D1. The mating group
The mating group is the mated side's opponent's pieces that **directly give check on the final checkmating position** (the
direct attackers of the King's square; both on a double check; three are possible only in constructed positions and are
handled). Pieces that only cover escape squares, block, or pin are *not* in the group. A piece that moved to *discover* a
check is not in it; the revealed attacker is. Pinned checkers still check and are included. Order, for determinism:
ascending material value (P 1, N 3, B 3, R 5, Q 9), then ascending square index (a1, b1 ... h1, a2 ... h8). A promoted piece
fights as its new role (promotion is irrelevant otherwise) under its stable piece id. If the group were ever empty at
checkmate (cannot happen) the rules fall back to ordinary C0 checkmate.

Justification: the direct checkers are the only pieces whose presence *is* the threat; the covering set is unbounded and
would turn one mate into a siege.

### D2. Who fights, who is attacker
The mated King is the **attacker** in every duel and the checker is the **defender**. `BattleRequest` semantics therefore give
ties (`timeout_tie`, `double_knockout`) to the *checker*: the King must win outright, and a double knockout is a King loss. The
King survives a duel iff `outcome == "attacker"` and its remaining HP is above zero. The checkers fight one after another in
the D1 order; the board is frozen for the whole sequence (same transaction as a capture duel: frozen FEN, revision and
identities; only the bound trusted authority can resolve it).

### D3. What persists
Within **one sequence**: the King's **HP, stamina and ability cooldown** carry from the end of a duel to the start of the next
(no reset, no heal, no regeneration in between). Every checker starts with full HP and stamina and a ready ability. Poise, buffs,
the regeneration delay, positions and facing are per-duel micro-state and reset. Stamina is carried on the 0.01 grid snapshots
use; a carried stamina of 0 starts exhausted. Carry-over comes only from the trusted simulation
(`CombatSimulation.fighter_state`), never from a client payload. **A new sequence later in the same game starts with a full,
rested King** (the King has no persistent HP in the ruleset; "HP does not reset" is a property of one sequence).

### D4. The King does not initiate ordinary duels
Unchanged from C0: kings never initiate or receive capture duels, king captures are rejected, mate uses Battle-legal moves.
The King fights only inside a sequence (and then as the attacker). Consequently a position that is Orthodox-escapable by a
King capture is still "mate" for sequence purposes, which is exactly when the King gets its capture chance.

### D5. Outcomes
* **The King loses any duel** (knockout, double knockout, tie, timeout on percentage): the match ends as **checkmate for the other
  side** (`1-0`/`0-1`, reason `Checkmate`). The board is untouched; remaining checkers never fight. No king is removed.
* **The King wins every duel**: the whole group is removed from the board and the position is re-evaluated by the ordinary Battle
  rules with **the same side to move** (the mated side). No ply is consumed, en passant is cleared, the halfmove counter resets,
  castling rights follow the rooks that remain, repetition history restarts (the removal is irreversible), the revision
  advances once. Verdicts:
  * the mated side is **still checkmated** (a hidden x-ray attacker was revealed and nothing escapes): **checkmate stands**
    immediately - a second sequence is never started from this call, so there are no infinite loops;
  * stalemate / insufficient material / other draw rules apply as usual;
  * **otherwise play continues** with the mated side to move, even if it is in check but has a legal reply.

  Deviation from the recommended wording ("resume only if not in check, else checkmate stands"): a King that won every duel and
  has a legal reply to a revealed check is not checkmated, and ending the match there would be an unforced loss on a legal
  position. The loop-freedom the recommendation wanted is kept by construction (D5 never recurses).
* A later, separate mate in the same game opens a new sequence (D3).

### D6. Abandonment, timeouts, resignation
Chess is untimed in Battle, so there is no clock inside a sequence. A disconnect/forfeit uses the existing abandonment rules:
the disconnecting seat loses (`Disconnect timeout`), both gone draws, an absent-input seat forfeits via the combat host, a
resignation by the mated side (which is the acting side) is its loss. The sequence is dropped (`outcome: "abandoned"`, no invented
result). If a duel cannot even be started (scene fails to load, authority silent) it is **retried from its unchanged start
state** up to two times (new `battleId` suffix `:retryN`); after that the sequence is `unplayable` and **checkmate stands**
(`Checkmate (last stand could not be fought)`). A validated result is never discarded by an interruption.

### D7. Draws and Classic
Draw rules are unaffected (agree-draw, pause and undo are refused during a sequence). Classic and legacy Battle end at
checkmate exactly as before and never construct a sequence. Stalemate is not mate. A loaded position that is already
checkmate fights its last stand when the game starts.

## Edge cases (all covered by `godot/tests/royal/rules_test.gd`)

| Case | Rule |
| --- | --- |
| Double / triple check | All direct checkers fight in D1 order; the first King loss ends the sequence. |
| Same value | Knight/bishop (3) and rook/rook (5) are ordered by square; a1..h8. |
| Discovered check | Only the revealed attacker(s) are in the group, not the moved piece. |
| Checker is the opponent's king | Impossible (kings cannot be adjacent). |
| En passant / promotion | Irrelevant to the sequence; the position after the committed move is what freezes. A promoted checker fights as its promoted role under the pawn's stable id. |
| The mating move was a capture duel | The duel settles normally first (attacker victory); the sequence starts after that commit. |
| X-ray piece behind a checker | Not in the group; if revealed and still mating, checkmate stands (D5). |
| Removed rook held a castling right | The right is removed. |
| Stalemate | A draw, never a sequence. |
| Game starts in a mated position | The sequence starts immediately. |

## Contract (additive; `godot/contracts/royal/v1`)

`schema.json` is *generated* by `scripts/build-royal-schema.mjs` from the immutable v1 schema (shared definitions copied
verbatim, enforced by `tests/contracts/royal.test.ts`); `fixtures.json` (13 valid, 28 invalid) is regenerated by
`godot/tests/royal/make_fixtures.gd` from the real rules layer; TS types live in `contracts/royal/v1`. The only v1 rule the King
breaks is `Combatant.role`, so the duel payload is a *BattleRequest-compatible* `RoyalBattleRequest` (king role allowed) that
CombatSimulation validates with its existing experimental relaxation. Results and snapshots stay plain v1 shapes.

| Type | Purpose |
| --- | --- |
| `RoyalSequenceRequest` | frozen mating position: `battleId` (sequence id), `matchId`, `beforeFen`, `mated`, `king` (combatant + `startHp/startStamina/startCooldown`), ordered `attackers` with stats |
| `RoyalDuelRequest` | one duel: `duelIndex/duelCount`, `kingStart {hp,stamina,cooldownTicks}`, `battle` (RoyalBattleRequest, King = attacker) |
| `RoyalDuelResult` | a v1 `BattleResult` plus `kingEnd` (from the trusted authority) and `kingSurvived` |
| `RoyalSequenceProgress` | active sequence: current duel, carried King, `defeated`, `remaining` |
| `RoyalSequenceResult` | `outcome` `king_survived\|king_fell\|unplayable\|abandoned`, every duel, `fenAfter`, `matchResult` |
| `RoyalMatchState` | `MatchState` with `rulesetId: battle-royal-v1`, king-capable `battle`, and `royal` progress |

`v1 MatchState` cannot carry a king duel (rulesetId enum, Combatant role): that is intentional and tested.

## Integration

* `BattleRoyalMatch` signals: `sequence_started(info)`, `duel_started(index,total,king_hp)`, `duel_finished(index,total,summary)`,
  `sequence_finished(summary)`; `BattleFlow` re-emits the same four for the presentation layer (the duel itself is an ordinary
  fight; the flow shows the banner for 1.5 s, starts it by itself, forbids cancelling it, and does not play the board-return
  animation between duels).
* Combat hosts pass `game.combat_options()` to `CombatSimulation.start(request, options)`; the adapter relaxes only the king
  role (`check_request(request, options)`); `CombatArena.start_battle(request, options)` and `combat_net_server.start` accept it.
* Local: `BattleFlow` + `BattleCombatAdapter` (thin, options only when non-empty, so legacy calls are byte-identical).
* Server: `OnlineMatchSession.configure(..., ruleset)` with `"battle-royal-v1"` runs the sequence authoritatively (the server
  starts each duel's simulation, owns the carry-over, awards forfeits). It is **in-process only**: the v1 network schemas
  (`mode` enum, `MatchState`) cannot carry the sequence, so `dedicated_server` never selects it. Exposing it online needs a
  `network/royal` frame variant (see Remaining).

## Balance (bot-measured, not human-tested)

See `godot/combat/BALANCE.md` ("King's last stand"). Summary: against the *default* AI a duelist/patient King beats single
checkers 22-24 of 24 but a double check from two non-pawn pieces is lost ~always by the default-AI King and by attrition
even for a skilled King against skilled checkers. Recommendations are listed there; no stat was changed.

## Implementation status (local play, 2026-11-12)

Playable for LOCAL Battle Chess (two players or the computer opponent); verified by headless suites and software-GL screenshots only.

* **Choice**: "King's last stand" toggle (default OFF, one-paragraph explanation, last choice persisted in `user://royal_options.cfg`) in the New game dialog
  (Battle games) and on the Play page (local Battle / Computer; never shown for Classic or Online). `RoyalOption` (`godot/ui/royal_option.gd`);
  `main.gd` creates `BattleRoyalMatch` instead of `BattleMatch` (`_switch_mode(1, royal)`).
* **Who fights**: the mated King is always the attacker. Against the computer, the colour the computer plays is fought by CombatAI (the level's `attack_style`
  when its King attacks, its defending style for a checker); the human always uses seat 1's controls. Two humans: each side keeps its own scheme. A human resigning
  against the computer mid-sequence forfeits (not the mated side by default).
* **Presentation** (`godot/world/README.md`, "King's last stand"): one descent, an INTERLUDE per extra duel (arena restarted in place, no scene reload, no black
  screen), one climb; interruption at any point recovers a consistent top-down board. Banner "KING'S LAST STAND - duel i of n" with the carried HP / stamina /
  cooldown (read from the match, fed by the trusted simulation), HUD context line "LAST STAND / DUEL i/n", King HP bar starting at the carried fraction, a result-screen
  note when the sequence ended in checkmate.
* **Tests**: `npm run test:royal` runs suite `royal_flow` (899 checks) besides rules / flow / session / `royal`.
* **Not done / known**: the online wire variant (below); human playtests; the chess AI searches with C0 semantics (it treats a mate as a win and does not know the
  King may survive); a reactive-style computer King (defensive/duelist) never attacks, and a tie goes to the checker, so low-level computer Kings are weak;
  Skip animation during a non-final duel re-descends for the next duel; two-human split-screen cameras were not screenshotted.

## Remaining

* **Online wire variant: contract DONE, server/client NOT wired.** `godot/contracts/royal/network/v1/{schema,fixtures}.json` (generated by
  `scripts/build-royal-network-schema.mjs`, TS types `contracts/royal/network/v1/types.ts`, test `tests/contracts/royal-network.test.ts`, run by `npm run test:contracts`)
  define the additive family for protocol id **`peepeechess-enet-royal-v1`**: `RoyalHello` (client opt-in, carries `rulesetId`), `RoyalWelcome`, `RoyalCreateMatch`
  (battle, untimed), `RoyalMatchFrame` (a v1 frame whose `state` is `RoyalMatchState`), and `RoyalSequenceNotice` (`progress` | `duel_result` | `sequence_result`, wrapping
  the existing `RoyalSequenceProgress` / `RoyalDuelResult` / `RoyalSequenceResult`). `JoinMatch`, `MatchCommand`, `Ping`/`Pong`, `Ack`, `ClockSync`, `ChessMoveRequest`,
  `CombatInput`, `CombatSnapshot`, `ProtocolError` are reused unchanged. No v1 message was edited; a v1 peer rejects every royal message (tested) and vice versa.
  Documented handshake: the client connects and sends `RoyalHello` instead of `Hello`; the server answers `RoyalWelcome` (or `UNSUPPORTED_VERSION` if it does not host royal);
  `RoyalCreateMatch` creates a royal room; `JoinMatch` into a room of the other ruleset is `FORBIDDEN`; the server pushes `RoyalMatchFrame` instead of `MatchFrame`, and a
  `RoyalSequenceNotice` after every duel start/commit and at the end (`OnlineMatchSession` already owns all of this data: `royal_progress()`, per-duel `fighter_state`, `royal_log`).
  **Missing**: a `RoyalWireCodec` (godot/network), per-connection codec selection + `RoyalHello`/`RoyalCreateMatch` handling and notice broadcast in `dedicated_server.gd`, an optional
  `ruleset` field in the backend allocation, `OnlineChessClient`/lobby handling and presentation of the notices, and a two-client loopback test.
* Human playtests of the last stand; stat recommendations in BALANCE.md are unapplied.
