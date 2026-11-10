# Native multiplayer validation — 2026-11-10

Executed on Linux, Godot **4.6.3 stable**, Node **24.22.1**, OpenSSL **3.5.7**.
Integration base: develop `b4c6dab`, Battle integration `67101fe`, latest consumed
Claude handoff `6cc2ea7` (including role mechanics `0c522d4` and net host
`c2110ea`). All combat-owned source, assets, Blender scripts and tests match the
published owner handoff. No physical Windows or Android device/export was run.

| Actual check | Result |
| --- | --- |
| `npm run lint` | Passed |
| `npm test` | 71 Node tests passed; unchanged Claude Godot suite: 3,327 checks / 202 tests passed; standalone arena passed |
| `npm run build` | Passed; existing web chunk-size warning remains |
| `npm run test:contracts` | 23 Node tests, 21 shared Godot cases and 9 exact cross-engine round trips passed |
| `npm run test:classic` | 83 engine, 53 match/clock, 345 view/UI checks; 72 positions / 1,962 legal moves matched chess.js; main import/smoke passed |
| `npm run test:battle` | 477 checks passed, including 137 through the real arena; 106 C0 positions / 747 outcomes matched the reference authority |
| `npm run test:multiplayer` | 62 server/protocol checks, 86 full-roster host checks and 30 online UI checks passed; three real ENet/DTLS two-client scenarios and certificate probes passed |

The multiplayer runner launched one separate headless dedicated server and two
separate Godot client processes per scenario. These use the production client
and server, real ENet sockets and DTLS, not a transport mock. Synthetic test
clients submit intent only: no HP edits, teleports, forced attacks or fabricated
successful results drive the matches.

| Real-process scenario | Observed result |
| --- | --- |
| Classic | Four plies to Fool's Mate; both clients observed five matching board revisions and server result `0-1` / Checkmate |
| Clock | Both ready, no move; server expired White's one-second clock; both received `0-1` / Time expired |
| Battle | Twelve plies, four real knockouts (three attacker wins, one defender win), en passant, a session reconnect and final own-seat resignation; both clients received four identical result receipts and 13 matching board revisions |
| Certificate trust | Incorrect CA never authenticated (expected TLS-handshake error); a subsequent client with the correct CA authenticated successfully against the same server |

The Battle case passed through seeded raw UDP proxies (seeds 173 and 941):
40–59 ms one-way delay and a configured 10% packet loss in each direction.
In the successful run, proxy A received 4,080 datagrams, dropped 434 and forwarded
3,646; proxy B received 4,477, dropped 440 and forwarded 4,037. Packet counts and resolved ticks
vary with OS scheduling. The proxy preserves a distinct upstream endpoint for
each new client UDP socket, including reconnects, instead of conflating DTLS
sessions on one port. Both clients must still agree on every observed board,
recovered history prefix, final stable piece registry and authoritative result.
No claim of cross-platform lockstep or internet-scale capacity follows.

Server/protocol checks cover authentication, invalid/active token reuse,
identity spoofing, illegal/stale moves, exact retry/idempotency, request-ID
collisions, client-sent winners/damage, duplicate keys/escaped aliases,
nonfinite/malformed/deep/oversized JSON, invalid UTF-8, control/input rate limits,
clocks, both-ready admission, draw consent, mate, combat startup, sequence replay,
reconnect counter continuity, disconnect forfeits/draws, silent-input abandonment,
RTT authority and simultaneous-match collision-world isolation.

The full-roster suite runs ten input-driven knockouts through Claude's actual
CombatNetServer using approved C0 stats. Both outcomes are exercised with all
five fighter roles, including real Blink, Fortress Guard and Royal Fury events.
Settlement and in-flight retired-battle inputs are checked independently of
visual presentation. The UI suite mounts two real online scenes, keeps different
2D/3D and flipped preferences, verifies PRESENTATION mode cannot tick authority,
and drives a complete duel through injected multi-touch movement/attack events
and real network input. Both views agree on the 31 surviving pieces and next turn.

A bounded 32-result receipt journal repairs missed aftermath displays after
reconnect without reapplying a move. Graceful ENet disconnect precedes DTLS
shutdown; dead peers are locally reset. Forged unreliable damage packets are
retried by the adversarial test until a rejection is observed, rather than
assuming an unreliable datagram arrived. All gameplay runs reject script/parse/
resource diagnostics. Only the intentional incorrect-CA probe permits its
specific TLS-handshake diagnostic. The test harness uses real time for sockets,
clocks, loss and latency; only the combat-only animation suite uses a fixed
60 Hz presentation clock. No combat-owned assertion was removed or relaxed.

Reproduce with `npm run test:multiplayer`. Set `MULTIPLAYER_REPORT_DIR` to keep
synthetic state/packet counters; successful runs delete temporary credentials.
See README.md for server startup and two-client instructions.

Still unverified: Windows-to-Android physical crossplay, exported/signed native
builds, touch/gamepad feel, NAT/firewall deployment, real GPU/mobile performance,
long-running clock drift, persistent crash recovery and account/rating service
integration. King-gauntlet v2 is not part of C0. GitHub CI is a separate check;
local success must not be represented as hosted CI success until it reports one.
