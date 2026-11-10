# Combat networking model (`godot/combat/net/`)

Status: **implemented and tested in-process only.** Codex has not published a transport, authenticated seats or a
hosted match service (no `godot/network/` exists on any branch), so nothing here talks to a socket. This module is
the combat side of that boundary: it is transport-agnostic and uses only the v1 wire types
(`CombatInput` client->server, `CombatSnapshot` server->client, `BattleResult` inside the final snapshot). No new
message types, no contract or docs changes, no Codex-owned file touched.

## Architecture

```
 device layer (keys/pad/touch)                              Codex-owned (not built yet)
        | intent                                      +-------------------------------+
        v                                             | authenticated transport (WSS) |
 +----------------+  CombatInput (1/tick)             |  seat auth, rate limits,      |
 | CombatNetClient| ---------------------------------> |  RTT pings, reconnect, results|
 |  predict local |                                   +---------------+---------------+
 |  reconcile     | <---------------------------------                |
 |  interpolate   |  CombatSnapshot (15 Hz, events    receive_input()   | snapshot_ready
 |  dedupe events |   repeated, result when final)                     v
 +-------+--------+                                   +-------------------------------+
         | view(): what to draw                       | CombatNetServer  (this module) |
         v                                            |  admission bookkeeping, RTT    |
   CombatArena (presentation)                         |  estimate -> hit grace, 15 Hz  |
                                                      |  snapshots, seat abandonment   |
                                                      +---------------+---------------+
                                                                      | step() @ 60 Hz
                                                                      v
                                                      +-------------------------------+
                                                      | CombatSimulation (authority)   |
                                                      |  fixed-tick, headless, owns    |
                                                      |  ALL damage / HP / results     |
                                                      +-------------------------------+
```

The simulation has no dependency on rendering or input devices; `CombatNetClient` has none on nodes or sockets either,
so the whole stack runs headless in tests (`net/net_harness.gd`: 1 server + 2 clients + 4 simulated one-way channels).

## Trust model

* **Only the server applies damage.** The client class has no method that changes HP, stamina, cooldowns or results
  (asserted by test, including after 4000 local ticks with no snapshots). HP/stamina/cooldown/result shown to the
  player are copied from schema-validated snapshots.
* Inputs are intent only; the schema rejects any extra field (damage/hp/result), and a forged-field client gets every
  packet refused (tested).
* Hit detection happens only in the simulation, from server-side geometry. The client never sends a hit claim and the
  server would not accept one (there is no field for it).
* `CombatInput.clientTick` is used for exactly one thing: a bounded round-trip estimate (below). It never grants a
  rewind and is never used to place an input in the past.

## What is predicted, reconciled, interpolated

| Concern | Behaviour |
| --- | --- |
| Local movement | Pure-math predictor mirroring `FighterMovement` for **Idle/Moving/Blocking only** (walk, strafe, sprint, block slow, accel/decel, turn rate, 24-sided wall, pillars, opponent separation). Starts with the fight (not one RTT later) using the known live tick + an ack-measured RTT. |
| Reconciliation | Each snapshot: restart from the authoritative position and replay every un-acked input; the visual error is blended out over ~6 ticks (100 ms); > 1.5 m snaps. Inputs the server ignored during the countdown are not replayed. |
| Local actions | When the server would accept a press (free state, enough stamina, ability off cooldown/condition met) `view()` shows a *predicted action* pose at once. It is confirmed by the next snapshot that shows an action state, cancelled if the press was acknowledged while still free, or expires after 8 ticks. It never changes HP or any result. |
| Remote fighters | Rendered `8 ticks` (~2 snapshot intervals, survives one lost snapshot) behind the client's estimated server tick, interpolated; state/stateTicks from the older sample; <= 6 ticks of extrapolation when the buffer runs dry; clamped inside the arena; jumps > 5 m are not interpolated. |
| Events | De-duplicated by `(battleId, eventId)` across the repeated event history, stale/reordered snapshots and reconnect (state can be exported/imported). Each cue fires exactly once. |
| Results | Only a validated snapshot's `result`, emitted once. |

## Latency compensation: hit-commit grace (the only one)

Without compensation a defender with round trip R must press parry R ticks earlier than a local player, so high-ping
defenders can never parry. The only compensation implemented is **bounded hit-commit grace**, in
`CombatSimulation.set_hit_grace(player, ticks)` (default 0 = original behaviour):

* A hit detected at tick T against a defender with grace g is held **pending** and resolved at T+g **against the
  defender's state at that moment**, so a parry/dodge whose input arrives late (up to g ticks after T) is honoured.
* The hit geometry is fixed at T on the server: stepping out of the way during the grace does not evade it. A hit
  resolves at most once. Already-defended hits (open parry window, i-frames, raised guard) and hits on staggered/defeated
  fighters resolve immediately. Pending hits are flushed before any knockout/timeout is evaluated (no free kills,
  no lost hits) and discarded when a battle stops; nothing leaks into the next battle.
* g = `ceil(estimated RTT ticks)` capped at **6 ticks (100 ms)**, per defender, symmetric rule for both seats. RTT comes from
  `set_seat_rtt_ms()` (the transport's own ping measurement; recommended, not client-influenceable) or, failing that, from
  the median of `arrival tick - clientTick` over the last 9 inputs (monotone claims, clamped to the arrival tick,
  samples > 30 ticks ignored).
* No rewind, no re-simulation, no trust in client hit claims. Attacks get **no** compensation (the attacker's swing is
  server-timed), only defensive timing.

Costs (real, measured or inherent): the defender's hit feedback is delayed by up to 6 ticks at high latency; a client
that lies about its RTT gains at most the cap unless the transport RTT is fed in; partial compensation above 100 ms RTT.

## Measured results (`godot --headless --path godot --script res://combat/tests/test_runner.gd -- net net_latency`)

Convention: **"N ms latency" = round trip N ms** (one-way ~N/2). Channels are integer ticks (1 tick = 16.667 ms),
up/down split so sums are exact: 0 ms = 0/0, 50 ms = 1/2, 100 ms = 3/3, 150 ms = 4/5 ticks. All runs are seeded and
reproducible; the server's RTT estimate equalled the configured RTT exactly (0/3/6/9 ticks, asserted).

Prediction error of the local fighter (reconciliation correction in metres; walker bot incl. sprint and wall/pillar
contact; 900 live ticks; thresholds asserted: mean < 0.01, p95 < 0.03, max < 0.25, no hard snaps):

| RTT | corrections | mean | p95 | max | hard snaps |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 226 | 0.0004 | 0.0031 | 0.0099 | 0 |
| 50 ms | 225 | 0.0007 | 0.0040 | 0.0428 | 0 |
| 100 ms | 226 | 0.0006 | 0.0041 | 0.0151 | 0 |
| 150 ms | 226 | 0.0008 | 0.0035 | 0.0344 | 0 |

Reconciliation: an injected 0.6 m server-side displacement appears as a 0.6 m correction one RTT later, decays by 1/6 per
tick to zero without overshoot and is never snapped; a 2.2 m displacement hard-snaps.

Remote interpolation (observer's view of a sprinting opponent, per-frame step; sprint is 0.0976 m/tick): max step
0.0976 at 0/50/100/150 ms (0 teleports), 0.0976 with 5% loss (14 extrapolated frames, all <= 6 ticks), 0.1188 with jitter 2.

Parry fairness (scripted heavy, hit on tick 27; reactor presses parry R ticks after **its own view** first shows the
attack; successful R, R scanned 0..38 step 2):

| RTT | grace OFF | grace ON |
| --- | --- | --- |
| 0 ms | [6..16] (6 values) | [6..16] (6) |
| 50 ms | [4..14] (6) | [4..16] (7) |
| 100 ms | [4..12] (5) | [4..18] (8) |
| 150 ms | [0..6] (4) | [0..12] (7) |

At 150 ms the reaction that is ideal at 0 ms (R=12) fails without grace and works with it, but only at the edge of the
window (the cap is 6 ticks, the RTT is 9). Presses 4 ticks outside the 0 ms window fail (no free parries). A client at
0 ms claiming a 6-tick RTT extends its window to [6..22], exactly the cap.

Other scenarios (all asserted):

* **Authority independence** (0/50/100/150 ms, and 100 ms + 10% loss + reorder + duplicates): replaying the server's
  accepted inputs through a bare simulation reproduces the final state byte-for-byte.
* **Simultaneous attacks** (0 ms vs 150 ms seats): both presses applied on the same server tick, both hits land (68/68 HP
  as at 0 ms); the slower seat's incoming hit commits 6 ticks later (208 vs 214); a double knockout resolves identically
  (same outcome, same `resolvedTick`).
* **Packet loss** (50 ms RTT, both directions): 5% / 15% -> counters stay in sync (lost packets are healed by the next
  one because action counters are cumulative), actions applied 1.06 / 1.15 ticks late on average (max 2), no corrupt
  admission, no hard snaps, worst correction 0.25 m; a 15%-loss fight finishes with a valid `BattleResult` that both clients receive.
* **Reordering / duplication / jitter** (jitter 3, 30% reorder, 10% duplicates, 100 ms): ~1000 stale arrivals rejected, no
  corruption, no lost or double-fired action, strictly increasing accepted sequences.
* **Disconnect**: a silent seat is neutralised after 15 ticks (stops, no phantom block) while the other keeps fighting;
  forfeit fires at **exactly 600 server ticks** after its last accepted input (or after a transport disconnect notice),
  with **no `BattleResult`**, and the aborted battle stops ticking; both seats gone -> one draw signal; reconnecting at 5 s
  resumes (sequence continues, nothing stale); reconnecting after the window is refused.
* **Forgery**: damage/hp/result fields rejected on every packet; lying about RTT is bounded by the cap and overridden by
  transport RTT.

## Tested limitations (what this does NOT prove)

* **Only in-process simulation.** No real sockets, TLS, NAT, MTU/fragmentation, congestion, or OS scheduling jitter.
  The harness steps client and server in lockstep with a perfectly synchronised tick clock: **clock skew and drift are not
  tested** (the clock estimator is a windowed offset; long-match drift is unverified).
* Latency above **150 ms RTT** and loss above 15% were not tested. Grace is capped at 100 ms, so compensation is partial
  above 100 ms RTT (see table).
* **Prediction covers free-state movement only.** During attacks, dodges, parries, stagger, abilities and knock-back the
  server position is shown (so a dodge's *motion* starts one RTT late; its *animation* starts at once via action
  prediction). Buff speed multipliers (Last Stand, Fury, Fortress Guard) and Blink are not modelled and were not tested
  for prediction error; expect larger corrections while buffed.
* **Remote attack animation is inferred.** `FighterSnapshot` has no action id, so a remote client cannot know which combo
  link/heavy is playing (light vs heavy share the same early pose). Presentation must infer it; see proposals.
* Remote players are drawn ~133 ms (interpolation) plus one-way latency in the past; very short telegraphs (light
  startup 7 ticks) cannot be reacted to from the remote view at any latency.
* Snapshots at 15 Hz are not a rollback checkpoint (the contract says so): there is no full-state rollback netcode.
* Bishop **Blink** moves 4 m instantly; it is interpolated as a short fast slide (below the 5 m jump guard). Untested.
* A restarted client (new process) can continue its **sequence** (from `lastInputSequence`) but not its **cumulative action
  counters**, which no v1 message carries: if it had pressed any action earlier the server rejects its packets as decreasing
  counters (tested). Same-session reconnects (client object kept) work.
* Defender hit feedback is delayed by up to 6 ticks at high latency (inherent to the grace).
* Tests use Pawn/Knight fighters; other roles share the same code paths but were not run through the network suites.

## Proposals for Codex (not implemented here)

1. Feed the transport's measured RTT into `CombatNetServer.set_seat_rtt_ms()` every few seconds (removes the lying-client
   bonus entirely).
2. Contract v2 candidates: `FighterSnapshot.actionId` (which attack/combo link is playing), a `serverTimeMs`/tick-phase
   field, and returning each seat's action counters in the reconnect snapshot (or accepting a counter reset on reconnect).
3. Treat `seat_abandoned(player_id)` / `battle_aborted_draw` as match-level forfeit/draw (they bypass `BattleResult`).
4. Clients should send one `CombatInput` per 60 Hz tick (`CombatNetClient.tick()` does) and the transport should not batch
   or reorder them across seats.

## Integration steps for a hosted match

```gdscript
# --- server process (trusted) ---
var sim := CombatSimulation.new(); add_child(sim)
var net := preload("res://combat/net/combat_net_server.gd").new(sim)
net.snapshot_ready.connect(func(s): broadcast_to_both_seats(s))          # CombatSnapshot, ~15 Hz + final
net.battle_finished.connect(func(r): chess_authority.settle(r))          # BattleResult, exactly once
net.seat_abandoned.connect(func(id): match.forfeit(id))                  # no BattleResult
net.battle_aborted_draw.connect(func(): match.draw())
net.start(battle_request)                                                # BattleRequest built by the chess authority
await get_tree().physics_frame                                           # let static colliders register
# per packet (after authenticating the sender to a seat):
net.receive_input(authenticated_player_id, packet)                       # -> {ok, code?}
# once per 60 Hz tick:
net.step()
# transport hooks:
net.set_seat_rtt_ms(id, measured_rtt_ms); net.set_seat_connected(id, false/true)
send_to_client(net.reconnect_seat(id))                                   # fresh snapshot on reconnect

# --- client ---
var client := preload("res://combat/net/combat_net_client.gd").new(battle_request, my_player_id, func(p): transport.send(p))
client.event_confirmed.connect(play_cue)          # once per event
# every 60 Hz tick:   client.set_intent(world_move_x, world_move_z, yaw, lock, sprint, block); client.press("light"); client.tick(local_tick)
# on each snapshot:   client.on_snapshot(snapshot, local_tick)
# every frame:        draw client.view(player_id, local_tick_float)   # position/yaw/state/hp/... per fighter
```

`CombatArena` (PRESENTATION mode) is not yet wired to `CombatNetClient`; its current `apply_snapshot()` path eases to the
latest snapshot. Wiring is the next step (presentation-owned, not required for the authority).

## Reproduce

```sh
godot --headless --path godot --editor --import
godot --headless --path godot --script res://combat/tests/test_runner.gd -- net net_latency   # ~45 s
```
