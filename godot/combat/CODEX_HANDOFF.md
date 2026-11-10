# Combat -> Codex handoff (roles + network compatibility)

Author: Claude Code (combat owner). Branch `feature/combat-core` -> `ccr-a4637d6e-lypbb4` (PR #4).
Consumed baselines: `origin/codex/battle-loop` (67101fe, fast-forwarded) and `origin/codex/native-multiplayer`
(7552f8c, protocol docs/schemas only; merged, no conflicts). No Codex-owned file was changed.

## 1. What is new

| Area | Result |
| --- | --- |
| Bishop, Rook, Queen simulation | `FighterProfile.supports_role()` / `AttackLibrary.supports_role()` are true for p n b r q (false for k). Blink, Fortress Guard, Royal Fury; stats come from the BattleRequest (tests read `godot/chess/battle_stats.json` read-only). |
| Network layer | `godot/combat/net/` (server host, client prediction/reconciliation/interpolation, simulated link, harness) + `NETWORKING.md`. Transport-agnostic; no sockets. |
| Hit-commit grace | `CombatSimulation.set_hit_grace()`, default 0 (offline behaviour unchanged), capped at 6 ticks: the only lag compensation. |
| Online presentation | `CombatArena.configure_network(local_player_id, send)` then `start_battle(request)` in `PRESENTATION` mode; `apply_snapshot()` feeds the client. Offline `AUTHORITY` mode (what your battle adapter mounts) is unchanged. |
| Assets | GLBs rebuilt: clip lengths now equal your approved `c0-balance-v1` ticks (Rook light 42, Queen 29, King 33) and the simulation's ability cast ticks. |

## 2. ONE change needed in a Codex-owned test

`godot/tests/battle/real_combat_test.gd:137-138` asserts a Queen capture is *refused* ("missing fighter mechanics disclosed").
That is now false by design. Replace it with e.g.

```gdscript
expect(unsupported.ok, "Queen capture is supported by the combat module")
```

(or loop `check_request` over p/n/b/r/q; kings can never be defended/attackers, so there is no real unsupported role left to test).
Verified: with only that assertion changed, `npm run test:battle` passes completely (exit 0); I restored the file afterwards
and did not commit the edit. Your plan to "extend the real input-driven cases to every role" is now possible.

## 3. Mapping to your ENet protocol v1 (`docs/network/PROTOCOL.md`)

| Your message / rule | Hook in `godot/combat/net/` |
| --- | --- |
| `CombatInput` (ch. 1) | `CombatNetServer.receive_input(authenticated_seat, packet)`; client sends one per 60 Hz tick |
| `CombatSnapshot` 15 Hz (ch. 1) | `CombatNetServer.snapshot_ready(snapshot)`; client `on_snapshot(snapshot, local_tick)` |
| `Ping`/`Pong` | measure RTT in the transport -> `CombatNetServer.set_seat_rtt_ms(seat, ms)` (otherwise a bounded, client-claim based estimate is used) |
| `ClockSync` | `CombatNetClient.on_clock_sync(serverTick, local_tick)` |
| `InputResume` | `CombatNetServer.input_resume(seat)` returns exactly your schema's fields; `CombatNetClient.resume_input(dict)` applies it (tested: restart -> rejected until resumed -> continues, no replayed press) |
| Disconnect/abandonment | `seat_abandoned(player_id)` after 600 server ticks, `battle_aborted_draw` if both absent, `reconnect_seat(player_id)`; none produce a `BattleResult` (forfeit bypasses it, per CONTRACTS.md) |
| Result | `CombatSimulation.finished(result)` / `CombatNetServer.battle_finished(result)`, exactly once; clients cannot supply results (tested) |

Hosting sketch (also in `NETWORKING.md`):

```gdscript
var sim := CombatSimulation.new(); add_child(sim)
var host := preload("res://combat/net/combat_net_server.gd").new(sim)
host.start(battle_request)                 # validated; c0 stats come from YOUR registry
host.snapshot_ready.connect(send_snapshot_to_both_seats)
host.battle_finished.connect(settle_once)
host.seat_abandoned.connect(forfeit); host.battle_aborted_draw.connect(draw)
# per authenticated CombatInput:  host.receive_input(seat, packet)
# every 60 Hz tick:               host.step()
```

## 4. Checks actually run (Godot 4.6.3, Node v22.23.4, Linux)

| Check | Result |
| --- | --- |
| Combat suite (`godot/combat/tests`) | **3327 checks / 202 tests pass**, no engine diagnostics (incl. `roles`, `net`, `net_latency`, `net_arena`, `assets`) |
| `npm run lint` | pass |
| `npm test` | 74/74 (includes `tests/combat/combat.test.ts`) |
| `npm run build` | pass |
| `npm run test:contracts` | pass (21 shared cases, 9 round trips) |
| `npm run test:classic` | pass |
| `npm run test:battle` | **1 failure**: the stale Queen assertion in section 2; passes entirely with that assertion updated |

Not run: any real transport, real GPU/mobile rendering, Windows/Android exports, human playtesting. Node 24 (the version your docs
specify) was not available; Node 22.23 was used.

## 5. Measured network behaviour and limits (full detail in `NETWORKING.md`)

In-process simulated link, Pawn/Knight: prediction error mean <= 0.0008 m at 0/50/100/150 ms RTT; authority replay
byte-identical at every latency, also with loss and reordering; 5%/15% loss tolerated; simultaneous attacks trade
symmetrically; forfeit fires at exactly 600 server ticks. Limits: grace is partial at 150 ms RTT (cap 6 ticks vs RTT 9);
a client lying about its RTT can gain the cap unless you supply measured RTT (1 above); prediction covers free-state movement
only (no buff/Blink modelling); remote attack kind/combo link is inferred because snapshots have no action id (propose
`FighterSnapshot.actionId` in a v2 contract); roles other than Pawn/Knight were not run through the network suites; nothing
beyond 150 ms RTT or 15% loss was tested; no real sockets, NAT or clock drift.

## 6. Remaining / needs a decision from you

1. Update the stale test (section 2).
2. Build the transport adapter using section 3; feed measured RTT.
3. Decide on contract v2 additions (`actionId`, tick-phase/time field).
4. Balance: role tuning is initial. The AI soak favours Knight/Queen over Pawn; not a balance claim.
5. King combat remains the separately versioned v2 gauntlet; the combat module refuses it.
