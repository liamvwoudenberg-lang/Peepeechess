# Shared contracts v1

The newer user-directed Battle king gauntlet is recorded in
[BATTLE_ROYAL_GAUNTLET.md](BATTLE_ROYAL_GAUNTLET.md). It requires a future ruleset
and contract version; it does not silently change these legacy v1 shapes. That
version now exists as the additive `godot/contracts/royal/v1` schema
(`battle-royal-v1`, see [BATTLE_ROYAL_V1.md](BATTLE_ROYAL_V1.md)); v1 stays unchanged.

Normative shape: [`godot/contracts/v1/schema.json`](../../godot/contracts/v1/schema.json),
JSON Schema 2020-12. Concrete valid and invalid payloads:
[`fixtures.json`](../../godot/contracts/v1/fixtures.json). Node types are in
`contracts/v1/types.ts`; Node tooling uses Ajv in `validate.ts`; Godot uses
`godot/contracts/codec.gd`. `npm run test:contracts` checks the same corpus in
both engines, then verifies Godot re-encoding in Node. These interfaces are
committed integration targets, not a claim that legacy transports already use them.
The native transport now consumes them through the additive
[ENet/DTLS session protocol](../network/PROTOCOL.md); legacy web transports keep
their existing protocols.

## Serialization and version policy

UTF-8 JSON objects, camelCase fields, exact case-sensitive enum strings. Wire
messages use `{ "type": "ChessMoveRequest", "payload": { ... } }`; the envelope
must contain exactly type and payload and its type must be one of the nine
public definitions below. Envelope admission/rate limiting is a future transport
adapter responsibility. Do not serialize engine Objects, NodePaths, Resources,
Vector3, Variant binary, or executable paths. Use plain `{x,y,z}` values.
All fields in each definition are required; absence differs from explicit null.
Unknown fields are rejected. All eight interfaces carry `schemaVersion: 1`.
No NaN/Infinity, duplicate object keys, integer overflow, or implicit string to
number coercion. Transport parsers must reject duplicate keys before schema
validation; the current codecs do not detect them after JSON parsing.

Integers are 0..2147483647, exactly representable in JS and Godot JSON. End a
session before counter exhaustion; never wrap. Finite floating-point fields are
bounded by the schema. Godot must use `JSON.stringify(value, "", true, true)`
(full precision); its default rounding can move pi outside the permitted range.
Never compare JSON text/hash by key order; compare decoded values. A simulation
is server-run, not deterministic cross-language lockstep.

Negotiate version and ruleset on authenticated connection. Reject unsupported
versions before a match starts; do not silently downgrade or mix v1 and legacy
snapshots. Unknown fields are a breaking v1 change: add a new version folder,
fixtures, adapters and migration note. Changes to balancing use a new statsId;
changes to outcomes use a new rulesetId. Codex coordinates and commits shared
contract changes before Claude updates consumers. `.godot-version` pins 4.6.3.

## Identity, coordinates and time

- `playerId`: opaque server-issued identity, bound to authenticated seat, never
  accepted merely because a payload names it. White/Black (`w`/`b`) are seats,
  not identity. Reconnect preserves player ID; UI names are not IDs. Opaque IDs
  use `[A-Za-z0-9][A-Za-z0-9_.:-]{0,95}` and contain no authentication secret.
- `pieceId`: stable within a match, allocated at initial setup (e.g. `w-p-d2`),
  follows movement, persists through promotion and is never reused after removal.
  The example name indicates original identity, not current position.
- `characterId`: `<faction>.<role>`, faction `royal|elves|skeletons`, role
  `p|n|b|r|q|k`. Examples: `royal.p`, `elves.n`, `skeletons.q`. Side colors are
  a presentation property; factions do not alter balance. Promotion keeps
  pieceId but changes role/characterId after successful resolution. ID-to-asset
  lookup is local data; missing art uses a visible placeholder, never arbitrary
  resource loading from payload text.
- Chess squares are algebraic `a1`..`h8`; internal file/rank coordinates are
  zero-based with a1=(0,0), h8=(7,7). White advances toward increasing rank.
  The canonical 3D board has square center
  `(x,y,z)=(file-3.5,0,3.5-rank)` meters, one-meter square pitch. Thus a1 is
  (-3.5,0,+3.5), h8 is (+3.5,0,-3.5). The 2D White view draws x=file,
  y=7-rank; rotate only presentation for Black.
- Arena coordinates are independent of board coordinates: meters, +Y up,
  +X right, +Z forward at yaw=0. Gameplay heading is
  `(sin(yaw),0,cos(yaw))`, radians in [-pi,pi]. A Godot visual looking toward
  local -Z needs an explicit visual rotation; do not invert gameplay input.
  White spawns at (0,0,-2.6) facing 0; Black at (0,0,+2.6) facing pi, regardless
  of which seat attacks. moveX/moveZ are world-space intent, not screen-space;
  clients convert camera-relative input before submission. Clamp/normalize the
  combined vector to length <=1 on authority. Schema bounds each axis separately.
- `serverTick`: match-relative monotonic 60 Hz tick, 0 at match creation;
  increments in board and combat phases while online, never wall-clock time.
  A battle uses startTick; 180 countdown ticks, then 5400 active ticks.
  `clientTick` is an untrusted diagnostic/prediction hint, not permission to
  rewind/hit. Snapshots target 15 Hz; ticks are independent of display FPS.
- `revision`: chess commit counter, increments exactly once per resolved ply.
  The native Classic local-only undo operation also increments revision to
  invalidate abandoned-line requests; ply may decrease on that operation.
  Online undo remains forbidden. Pending combat keeps the previous FEN, ply and
  revision. State phase changes
  are ordered by serverTick; one pending battle per match. Completion without
  a move does not invent a chess ply. `expectedRevision` identifies the frozen
  board. Requests must also pass phase/seat checks, not revision alone.

## Public interfaces and event ownership

| Interface | Producer → consumer | Meaning |
| --- | --- | --- |
| ChessGameState | Chess authority → clients/persistence | initialFen, current fen, board revision, ply, stable on-board pieces and custom history. Both views read it. No arbitrary client FEN. |
| ChessMoveRequest | Authenticated seat → chess authority | requestId, expectedRevision, from/to and explicit promotion or null. Null defaults to queen only when a promotion is required; servers record the chosen role. |
| BattleRequest | Chess authority → trusted combat authority and clients | frozen beforeFen/revision, stable attacker/defender identities, actual victim square, destination, promotion choice, immutable stats, arena, seed and start tick. Kings never participate. |
| BattleResult | Trusted combat authority → chess authority | final HP, resolved tick, winning player, outcome and reason. No FEN; the chess authority derives the board. Never admitted from a client. |
| FighterStats | Server-approved balance registry → combat | statsId and role, base HP/stamina/damage, actual movement speed m/s and reach m, action/cooldown durations in ticks. Frozen for a duel. Never trusted client loadout data. |
| CombatInput | Authenticated fighter seat → combat authority | match/battle/player, monotonic packet sequence, axes/heading, held booleans and action counters. Cannot contain HP/damage. |
| CombatSnapshot | Combat authority → clients | tick, remaining timers, exactly two fighters, acknowledged input sequences, bounded event list and optional trusted terminal result. Presentation only, not a server checkpoint of all hidden simulation state. |
| MatchState | Match authority → clients | mode/ruleset/phase, seat IDs, chess state, pending battle/combat or null, match result/reason. Complete reconnect presentation snapshot; full authority recovery also requires private history/draw and simulation state. |
| ProtocolError | Authority → requester | fixed code, bounded display message, optional requestId/currentRevision and retryable hint. No stack traces or credentials. |

`FighterStats` values should be converted deliberately from legacy config:
base walk speed is `1.05 + speed*0.29` m/s (pawn/queen=3.66), not the old speed
rating of 9 m/s. Convert durations to ticks using ceiling(seconds*60), keeping
at least one tick for a nonzero duration. The examples are initial balance
values, not proof of parity of a new Godot simulation.

## Admission, ordering and cross-field invariants

Schema validation checks shape, not authorization or all game semantics. The
future adapter must also enforce the following; the foundation tests verify
example consistency and existing engine outcomes, not a live adapter:

1. Verify credentials, match membership and side-to-move. Allow only move/input
   request types from clients. Apply a 1 MiB snapshot/frame ceiling, 64 KiB
   client frame ceiling and per-seat rate limits before parsing/schema work.
2. A requestId is unique per player/match. Store its payload and result with the
   authoritative commit. An exact retry returns the original response; reuse
   with different intent is rejected. Process moves serially per match.
3. FEN must pass chess validation plus king-safety/import checks. On-board
   pieceIds/squares are unique, agree with FEN roles/colors and character roles;
   history.length=ply. Replay custom history from initialFen for authoritative
   recovery; failed captures are not legal SAN/PGN moves. Match IDs agree across
   nested payloads, seat IDs differ, battle participants match registry/FEN,
   stats.role matches combatant.role, and arenaId is an approved registry entry.
4. mode=classic requires rulesetId=classic-v1 and null battle/combat. Battle
   uses battle-checkmate-v1. Board phase has null battle/combat; combat/aftermath
   require matching pending battle and snapshot, unchanged FEN/revision and no
   match result. Complete has a non-null result/reason and null battle/combat.
   A final CombatSnapshot may carry its BattleResult before match completion.
5. Input sequence strictly increases per battle/seat across reconnect. Action
   fields are cumulative press counters starting at 0 per battle, **not** held
   buttons; increases produce at most one edge per accepted packet/action and
   do not bypass simulation stamina/cooldowns. Counters never decrease, reset
   or wrap within a battle. Gaps do not replay missed attacks. A stale packet
   is ignored/rejected. After 15 ticks without input, neutralize held controls;
   retain seen action counters so replay cannot retrigger an action.
6. HP/stamina cannot exceed each fighter's immutable stats maxima; durations and
   event IDs/ticks must agree with the battle. eventId is monotonic per battle;
   clients deduplicate by battleId/eventId and discard older snapshots. The
   server retains/repeats recent events within the 256-event bound; events are
   cosmetic notifications, not a second source of damage or state changes.
   actorPlayerId identifies the initiating attacker/ability user and
   targetPlayerId the other fighter. For a parry/block event the actor is the
   incoming attack's initiator, and the target is the defending fighter.
7. Result winnerPlayerId equals the declared outcome's participant. Check battle
   ID, expectedRevision, frozen FEN, phase and trusted source; atomically resolve
   once. A duplicate result never removes another piece or increments ply twice.
   HP percentage comparisons use cross multiplication; exact timeout ties and
   double KOs favor defender. Match forfeits/resignation bypass BattleResult.
8. On reconnect request a current MatchState, keep stable IDs/counters and
   discard prediction. Online disconnect does not pause combat; after ten
   seconds forfeit the missing seat, or draw if both disappear. Server schedules
   abandonment from its own clock; it is not client-reported elapsed time.
   Offline explicit pause may freeze local ticks. An infrastructure restart
   aborts the match with an explicit service error until durable recovery exists;
   never fabricate a winning combat result.

Errors: malformed/oversized shape → INVALID_PAYLOAD; incompatible version →
UNSUPPORTED_VERSION; missing/invalid credentials → UNAUTHENTICATED; wrong seat
or client-sent trusted state → FORBIDDEN; changed board → STALE_REVISION;
geometry/turn legality → ILLEGAL_MOVE; unsafe defender outcome → UNSAFE_OUTCOME;
combat/match phase mismatch → WRONG_PHASE; replayed input → STALE_INPUT;
excessive requests → RATE_LIMITED; private server fault → INTERNAL. Refresh on
STALE_REVISION/WRONG_PHASE; never retry an illegal move automatically. Messages
are display text, codes drive behavior. No errors mutate board state.

## Example capture

The full corpus includes all interfaces. This abbreviated flow uses the exact
IDs in it; read the corpus for complete payloads with all required fields:

```json
{"type":"ChessMoveRequest","payload":{"schemaVersion":1,"matchId":"match-demo","requestId":"move-1","playerId":"player-white","expectedRevision":6,"from":"d4","to":"e5","promotion":null}}
```

The source position is `7k/8/8/4q3/3P4/8/8/7K w - - 0 1`. The pawn attempts
d4xe5 against the queen; the FEN remains unchanged throughout battle-demo-1.
An exact timeout HP-percentage tie resolves for player-black, removing the pawn
at d4, keeping the queen on e5, passing the turn to Black and committing once.
Revision 6 here is a server commit counter from a loaded position; ply 0 counts
moves since initialFen, so revision and ply need not be equal after loading.
