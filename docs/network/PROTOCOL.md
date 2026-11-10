# ENet session protocol v1

This additive transport contract leaves `contracts/v1` chess/combat shapes
unchanged. Schema: `godot/contracts/network/v1/schema.json`; TypeScript tooling:
`contracts/network/v1/types.ts`. Frame envelopes contain exactly `type` and
`payload`, serialized as bounded UTF-8 JSON with full float precision. Reject
duplicate object keys (including escaped aliases), unknown fields/types,
nonfinite numbers, invalid UTF-8 and excessive nesting before admission.

Use Godot ENet's DTLS extension, validating server hostname and certificate.
No Godot RPC, Variant object decoding, client paths, client-provided FEN,
HP/damage or results are admitted. This native protocol is identical on Windows
and Android; it does not make legacy web/WebSocket clients wire compatible.

| Direction | Type | Channel |
| --- | --- | --- |
| Client → server | Hello, CreateMatch, JoinMatch, MatchCommand, Ping, ChessMoveRequest | 0 reliable |
| Client → server | CombatInput | 1 sequenced/unreliable |
| Server → client | Welcome, Ack, ProtocolError, MatchFrame, Pong | 0 reliable |
| Server → client | CombatSnapshot, ClockSync | 1 sequenced/unreliable |

Hello negotiates `schemaVersion:1` and `protocol:peepeechess-enet-v1` before
commands. A null resumeToken creates an anonymous identity; a 256-bit
server-issued bearer sessionToken resumes that exact identity. The server
stores a digest, binds it to one transport peer and never logs it. Tokens are
not an account login or a portable match checkpoint. DTLS is required outside
explicit loopback development mode. Sessions expire after at most 24 hours and
are process-local; server restart invalidates tokens and aborts lost matches.

CreateMatch starts standard initial chess, reserving White for its creator.
JoinMatch claims the single empty Black seat; opaque match IDs serve as private
invite codes. Both seats must send ready before clocks/gameplay start. A peer
may belong to one live match. No client can pick another player ID, starting
FEN, balance registry, tick rate or combat configuration. C0 chess is untimed.
MatchCommand supports ready, own-seat resignation, two-seat draw agreement and
standard draw claims. Draw claims use the existing engine's exact kind strings.

Command IDs and chess request IDs are idempotent per session/match: exact
retries return their original acknowledgment; reuse with changed intent is
rejected. Combat inputs require strictly increasing sequence and cumulative
press counters per battle/seat, across reconnect. Gaps never replay attacks.
InputResume conveys the authenticated seat's accepted sequence/counters; a
client resumes above those values. All axes, movement, costs, cooldowns,
collisions, damage, HP and winners are computed by the server combat module.

MatchFrame embeds the existing v1 MatchState plus authoritative clocks, lobby
readiness, presence, draw offer and own-seat input acknowledgment. Its
frameSequence is monotonic per room. Full frames are reliable on structural
changes and periodically for recovery. CombatSnapshot targets 15 Hz and clocks
5 Hz; discard stale snapshots by match/battle/tick and never let an unreliable
snapshot replace a newer reliable board state. Rendering preferences never
appear in the protocol. Clients keep their own 2D/3D choice and camera.

The server uses fixed 60 Hz combat ticks and its own monotonic wall clock for
chess clocks, heartbeat deadlines and abandonment. Disconnect never pauses a
duel. A disconnected seat has ten seconds to resume; if both are absent when a
deadline expires the match draws, otherwise the missing seat forfeits. Inputs
neutralize after the existing simulation's 15-tick threshold. The server commits
validated combat results once after a bounded aftermath interval, regardless
of client presentation. Client-reported BattleResult is forbidden.

Admission applies packet/byte/control/input rate budgets before schema work,
bounded unauthenticated handshakes, room/session/request caches and frame sizes.
The existing ProtocolError codes identify failures. Neither a rejected command
nor a stale/invalid input can change the chess board or inject combat state.
