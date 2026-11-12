# Combat networking model (`godot/combat/net/`)

Status: **implemented, wired into the real online path, tested in-process (lockstep harness) AND end-to-end over real ENet/DTLS sockets
on loopback through a latency/loss proxy.** Codex's transport (`godot/network/`) hosts `CombatNetServer` (dedicated server, seat RTT from
ENet, `inputResume`, abandonment) and the online client (`OnlineCombatView`) drives `CombatArena` through its network client
(`CombatNetClient`: prediction, reconciliation, interpolation). It uses only the v1 wire types (`CombatInput` client->server,
`CombatSnapshot` server->client, `BattleResult` inside the final snapshot): no new message types, no contract change.
**Not tested: real devices, real mobile/Wi-Fi/WAN networks, NAT, bandwidth limits, Windows/Android crossplay.** See
`docs/network/ONLINE_COMBAT.md` for the view interface and mixed-version notes, and "Real transport results" below.

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
| Local movement | Pure-math predictor mirroring `FighterMovement` for **Idle/Moving/Blocking only** (walk, strafe, sprint, block slow, per-role accel/decel/turn rates from `FighterProfile.for_role` incl. the experimental King, walking-speed buffs Last Stand / Royal Fury / Fortress Guard inferred from the snapshot's cooldown, 24-sided wall, pillars, opponent separation). Starts with the fight (not one RTT later) using the known live tick + an ack-measured RTT. The on-screen position is advanced by the sub-tick fraction (velocity extrapolation) for displays faster than 60 Hz. |
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

## Real transport results (end-to-end, loopback, `scripts/test-online-combat.mjs`)

What is real: the dedicated server process (ENet + DTLS, `DedicatedChessServer`, `CombatNetServer`, ENet-measured seat RTT), two separate
client processes each running `OnlineChessClient` + `OnlineCombatView` + `CombatArena` in its network-client mode, real 60 Hz physics clocks
in every process, real JSON/schema validation, real unreliable-fragment ENet packets. What is simulated: the network. Every client sits
behind a userspace UDP proxy (`scripts/lib/latency-proxy.mjs`) that adds fixed delay + uniform jitter and independent random loss.
It is loopback on a **shared, heavily loaded 4-core machine** (load average 9-13 during the runs): scheduling stalls inflate RTT and
starvation, so these are pessimistic for timing and say nothing about real WANs, mobile radios, NAT, bandwidth caps or bursty loss.
No device, Windows or Android client was involved.

Matrix (`--profile=full`, 31 fights, all passed): role pairs p-p, n-p, b-p, r-p, q-p, p-n, n-q, b-n and black-attacker p-p, each at
0 ms, 60 ms RTT + 2% loss (8 ms jitter) and 120 ms RTT + 2% loss (16 ms jitter), plus `reconnect` (seat w reconnects voluntarily
mid-fight, seat b's link is blacked out for 4 s), `parry` (both seats press light on the same server-tick estimate and react with parries;
60 and 120 ms) and `invalid` (replayed sequence, spoofed seat, other battle id, counter regression, out-of-range vector, injected
`damage`, client-sent `BattleResult`, `CombatInput` on the reliable channel). Every fight completed with a `BattleResult`; both clients' result
equalled the server's `COMBAT_BATTLE_DONE` result byte for byte, final chess state was identical, no battle was aborted, and for every
event id seen by both clients the two copies were identical (both clients saw all the same events in all fights).

| RTT config | fights | client mean correction (m) | worst p95 / worst max (m) | hard snaps | press -> on-screen (median) | press -> server-confirmed pose | server RTT feed (mean) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 0 ms | 9 | 0.021 | 0.30 / 0.30 | 0 | ~17 ms (one frame) | ~74 ms | 8-36 ms |
| 60 ms + 2% | 9 | 0.031 | 0.73 / 0.84 | 0 | ~15 ms | ~137 ms | 66-96 ms |
| 120 ms + 2% | 9 | 0.025 | 0.16 / 0.25 | 0 | ~16 ms | ~201 ms | 123-142 ms |

(Mean of per-client means over the plain `fight` scenarios; "corrections" are continuous predicted-vs-authoritative disagreements measured at
every snapshot, 10-148 per client per duel. Prediction resumption after an attack/dodge is reported separately as catch-ups: 4-13 per
client, typically 0.1-0.6 m, one 0.8 m, all blended over ~100 ms.) Lockstep suites for comparison (no jitter): walker error mean < 0.001 m;
melee mean 0.001-0.009 m (`net_roles`). The real-time numbers are 3-30x larger because two independent 60 Hz clocks drift in phase,
2% loss drops intents the server then repeats, and the machine stalls processes; the prediction replays one input per server tick.

Input latency: a press shows the predicted action pose on the proxy fighter within one frame (13-21 ms, the 60 Hz frame plus the physics
tick it waits for); without prediction the same press is visible only when a server snapshot confirms it, which here took 61-84 ms at 0 ms
RTT (snapshot cadence 66 ms + processing), 117-190 ms at 60 ms and 178-218 ms at 120 ms. Movement intents move the predicted fighter in the
same tick (asserted in `online_prediction_test`).

Dropped / late inputs (server side, per seat, live ticks only): a tick is "starved" when no new `CombatInput` was accepted for the seat
(the simulation reuses the last intent). Measured 4-45% (mean ~19-27%) on this loaded machine, longest gap 1-32 ticks in healthy fights
(0.5 s); stale (reordered/duplicated) inputs were 0 in all but the deliberate replay. Client-sent vs server-accepted inputs per seat: 0-6% fewer accepted at 0 ms (one outlier of 22%, not diagnosed; a stalled process on the shared
machine is the suspect), 2.6-16% at 60 ms + 2% loss and 2.7-14% at 120 ms + 2% loss (2% per direction from the proxy plus the sends that
cross the end of a duel). The reconnect scenario shows 122/203-tick
gaps (the blackout) and still ended with no forfeit, no invalid/forbidden input after the resume and a matching result. The server's RTT
feed tracks the configured RTT with ~10-20 ms of ENet/poll overhead (and more under load); the hit-commit grace therefore sat at its 6-tick
cap for most of the 60/120 ms fights.

Limits of this evidence: one machine, one OS, 31 duels (a handful per cell), Pawn..Queen only (the King is not hosted by the v1 server),
no clock-drift soak, nothing above 120 ms + 2% loss end-to-end, bots not humans (scripted fighters; presses are sparse), thresholds in the
script are loose on purpose (mean < 0.15 m, no snap, worst < 1.2 m unless the server had neutralised the seat).

## Tested limitations (what this does NOT prove)

* **Only in-process simulation.** No real sockets, TLS, NAT, MTU/fragmentation, congestion, or OS scheduling jitter.
  The harness steps client and server in lockstep with a perfectly synchronised tick clock: **clock skew and drift are not
  tested** (the clock estimator is a windowed offset; long-match drift is unverified).
* Latency above **150 ms RTT** and loss above 15% were not tested. Grace is capped at 100 ms, so compensation is partial
  above 100 ms RTT (see table).
* **Prediction covers free-state movement only.** During attacks, dodges, parries, stagger, abilities and knock-back the
  server position is shown (so a dodge's *motion* starts one RTT late; its *animation* starts at once via action
  prediction). Walking-speed buffs are modelled (tested exact on open floor); Blink is not. When prediction resumes after such a
  stretch the fighter catches up to where its inputs have taken it; this is reported as `catchups`, not as misprediction. The
  snapshot carries no "exhausted" or buff flag, so both are inferred (stamina 0..15%, buff time from `cooldownTicks`); stamina
  regeneration is not modelled in the replay window.
* **Wall contact is approximate**: the server collides capsules with 24 overlapping box colliders (engine), the predictor with 24
  half-planes. Errors appear only while grinding along the wall at sprint speed (<= 12 mm per tick, <= 9 cm over a 12-tick window in the
  worst case measured, buffed sprint at a polygon vertex). Open floor error equals the 0.0001 m snapshot quantisation.
* **Remote attack animation is inferred.** `FighterSnapshot` has no action id, so a remote client cannot know which combo
  link/heavy is playing (light vs heavy share the same early pose). Presentation must infer it; see proposals.
* Remote players are drawn ~133 ms (interpolation) plus one-way latency in the past; very short telegraphs (light
  startup 7 ticks) cannot be reacted to from the remote view at any latency.
* Snapshots at 15 Hz are not a rollback checkpoint (the contract says so): there is no full-state rollback netcode.
* Bishop **Blink** moves 4 m instantly; it is interpolated as a short fast slide (below the 5 m jump guard). Untested.
* A restarted client (new process) loses its **cumulative action counters**; no v1 CombatSnapshot carries them, so without help
  the server rejects its packets (tested). Codex's ENet protocol (`InputResume`, see below) supplies exactly the accepted
  sequence + counters, and `CombatNetClient.resume_input()` applies them: tested that a restarted client is rejected
  until it resumes, then continues with no rejected packet and no replayed press. Same-session reconnects (client object kept)
  always worked.
* Defender hit feedback is delayed by up to 6 ticks at high latency (inherent to the grace).
* The 1:1 input assumption: the predictor replays one input per server tick. Real transports break it (tick-phase jitter between two
  60 Hz clocks, loss, a stalled process): the server then reuses the last intent for a tick, which shows as extra correction in melee.
  There is no server-side jitter buffer. A seat silent for >= 15 ticks is neutralised by the server while the client keeps predicting
  (large correction / hard snap on return: intended).

## Proposals for Codex (item 1 is done, the rest are not)

1. ~~Feed the transport's measured RTT into `CombatNetServer.set_seat_rtt_ms()`~~ done: `DedicatedChessServer.step()` feeds ENet's
   `PEER_ROUND_TRIP_TIME` every tick (it includes both ends' poll intervals and retransmits, so it reads 11-18 ms on loopback).
2. Contract v2 candidates: `FighterSnapshot.actionId` (which attack/combo link is playing; remote animation currently
   infers it, see `presentation/remote_action_inference.gd`) and a `serverTimeMs`/tick-phase field.
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

### CombatArena (online presentation) is wired

`CombatArena.configure_network(local_player_id, send, builder = null, own_input = true)` + `start_battle(request)` in `PRESENTATION` mode creates a
`CombatNetClient`; `apply_snapshot()` feeds it; each 60 Hz physics tick the arena calls `net_step()` (one `CombatInput`
sent through your `send` Callable) and copies `client.view()` onto the proxy fighters: local fighter predicted, remote
fighter interpolated, HP/stamina/cooldown from snapshots only, events de-duplicated, the terminal `BattleResult` delivered
once via `battle_finished`. The input source forwards intent to the client (`LocalInputSource.net_client`). Remote attack
kind/combo link is inferred (`remote_action_inference.gd`) because snapshots carry no action id. Tested in `net_arena`
(arena + real `CombatNetServer` over a 100 ms RTT simulated link, incl. full presentation with models/HUD/camera).
Without `configure_network` PRESENTATION mode keeps its older ease-to-snapshot behaviour. The offline AUTHORITY mode that
Codex's battle adapter mounts is unchanged. The real online path (`godot/network/client/online_combat_view.gd`) passes the
transport's own `CombatInputBuilder` (one sequence/counter stream, restored from `inputResume` after a reconnect) and
`own_input = false` (the view owns the devices: keyboard/pad `LocalInputSource` and the touch adapter both feed
`arena.net_client.set_intent()/press()`); the arena runs at `process_priority` 100 so each tick sends the intent the devices set in
that same tick, and it stops sending once the result is known.

## Mapping to Codex's ENet session protocol v1

From `docs/network/PROTOCOL.md` and `godot/contracts/network/v1/schema.json`. Codex's dedicated server and client now implement
this and the end-to-end tests below exercise it over real ENet/DTLS sockets (on loopback).

| Codex message / rule | This layer |
| --- | --- |
| `CombatInput` on channel 1 (sequenced/unreliable), strictly increasing sequence + cumulative counters | `CombatNetClient.tick()` sends one per 60 Hz tick; `CombatNetServer.receive_input(seat, packet)`; stale/reordered/duplicated packets are harmless (tested) |
| `CombatSnapshot` 15 Hz on channel 1 | `CombatNetServer.snapshot_ready` signal; `CombatNetClient.on_snapshot()` / `CombatArena.apply_snapshot()` |
| `Ping` / `Pong` (nonce) | measure RTT in the transport and call `CombatNetServer.set_seat_rtt_ms(seat, ms)`; it replaces the claim-based estimate, so a lying client gains nothing |
| `ClockSync` (serverTick, 5 Hz) | `CombatNetClient.on_clock_sync(serverTick, localTick)` |
| `InputResume` (battleId, sequence, clientTick, 5 counters) | `CombatNetServer.input_resume(seat)` builds it (field names match the schema, tested); `CombatNetClient.resume_input()` applies it |
| Disconnect never pauses; 15-tick input neutralisation; 10 s to resume, forfeit unless both absent (then draw); forfeit bypasses `BattleResult` | same behaviour: `seat_abandoned`, `battle_aborted_draw`, `reconnect_seat()` (tested at exactly 600 server ticks) |
| Client-reported results / HP / damage forbidden | the client has no code path that sets them (tested) |

## Reproduce

```sh
godot --headless --path godot --editor --import
godot --headless --path godot --script res://combat/tests/test_runner.gd -- net net_latency net_arena net_roles   # ~2 min
godot --headless --path godot --script res://tests/network/online_prediction_test.gd                          # real ENet loopback, ~15 s
node scripts/test-online-combat.mjs                  # quick profile (6 duels); --profile=full for the 31-duel matrix; --only=<id>
npm run test:multiplayer                             # original ENet/DTLS suite + quick online combat profile
```
