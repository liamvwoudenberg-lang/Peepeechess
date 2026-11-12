# Battle C0 validation — updated 2026-11-10

The capture loop from `67101fe` is now integrated with Claude's complete C0
roster and latest handoff `6cc2ea7` in `codex/native-multiplayer`. Pawn, Knight,
Bishop, Rook and Queen simulation, abilities, generated models and clips are
available. The earlier Pawn/Knight-only dependency is resolved. King duels remain
the separate v2 gauntlet; C0 retains its documented king-safety/checkmate rules.

| Actual check | Result |
| --- | --- |
| `npm run test:battle` | 250 authority/rules, 50 flow, 9 protocol-adapter, 31 fixture-UI and 137 real-combat checks passed (477 total) |
| Differential rules corpus | 106 seeded/special positions / 747 outcomes matched the existing C0 authority |
| Full-roster network host | 86 checks: ten real knockouts, both outcomes with all five roles, Bishop/Rook/Queen ability events, exactly-once settlement and retired-input rejection |
| Online UI | 30 checks: two client views, independent 2D/3D/flip preferences, authority-free presentation, touch-driven real network duel and matching survivor registries |
| Real ENet/DTLS processes | Four successive capture battles, a defender victory, en passant, reconnect/result receipt recovery and final resignation; both clients agreed on all 13 board revisions under delay/10% packet loss |
| Classic preservation | 83 engine, 53 match/clock, 345 view/UI checks; 72 positions / 1,962 legal moves matched chess.js |

The authority tests cover check, pins, both-outcome safety, EP discovered check
and actual victim square, promotion, castling rights, counters, draws,
mate/stalemate, stable IDs and replay protection. They reject invalid sources,
IDs, revisions, timing, HP/causes, nonfinite values, altered frozen boards and
conflicting results. Accepted results survive presentation interruption and
cannot overwrite already terminal mate. Fixture transitions exercise loading/
start failure, late callbacks, cancellation, timeouts, invalid and duplicate
results, interrupted aftermath/return and new-match invalidation.

Real-combat tests mount Claude's unchanged components and use legitimate
CombatInput. No HP, placement, attack state or winning result is injected.
Attacker wins remove the victim and move/promote the attacker; defender wins
remove the attacker at origin and preserve the defender. Both consume the turn.
The board stays frozen through combat, commits once and returns to the selected
view. Local play and native online play use the same chess rules and registry.

The prior rendered Linux run verified real Pawn controls/damage, attacker and
defender victories and return to the continuing board with generated models.
The new full-roster/online acceptance is automated on Linux. Physical Windows/
Android crossplay, exports, device controls/performance and king-gauntlet v2
remain unverified. See [multiplayer validation](../network/VALIDATION.md) for
exact environment, test counts, network impairment data and remaining limits.
