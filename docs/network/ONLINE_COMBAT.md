# Online combat: client view, prediction and mixed-version safety

Scope: how the online client mounts the combat arena and feeds it, what the server logs, and what a world presentation (the pit
`BattleWorld`) must provide to host it. The wire contract stays **v1** (`peepeechess-enet-v1`, arena `stone-v1`): nothing in
`godot/contracts/v1`, `godot/contracts/network/v1` or `contracts/*.ts` was changed. Measured numbers live in
`godot/combat/NETWORKING.md` ("Real transport results").

## Data flow

```
 keyboard/mouse/pad (LocalInputSource)  --\
 touch adapter (OnlineTouchCombatInput) ---+--> arena.net_client.set_intent()/press()      (OnlineCombatView.net_client())
                                           |
 CombatArena (PRESENTATION, process_priority 100: ticks after every device)
   _physics_process -> net_step(): CombatNetClient.tick() -> ONE CombatInput per 60 Hz tick
        built by OnlineChessClient.input_builder (the transport's single sequence/counter stream)
        -> OnlineChessClient.submit_combat_input -> ENet channel 1 (unreliable)
   CombatSnapshot (15 Hz, channel 1) -> OnlineCombatView.apply_snapshot -> CombatNetClient.on_snapshot
        reconcile local fighter (replay un-acked inputs), interpolate remote fighter 8 ticks behind, de-duplicate events
   ClockSync (5 Hz) -> CombatNetClient.on_clock_sync (extra clock sample; server tick == combat tick during a duel)
   _process -> view(): local fighter predicted (+ sub-tick extrapolation), remote interpolated, HP/stamina/cooldown/result from snapshots only
```

`OnlineCombatView` (godot/network/client/online_combat_view.gd):

* `setup(client: OnlineChessClient, host: Node)` once. `host` is any Node the arena instance is parented to (a `SubViewport` in the
  lobby, a `Node3D` mount in a world scene).
* `sync(frame)` on every `MatchFrame`: mounts the arena when `frame.state.battle` appears in `combat`/`aftermath`, tears it down otherwise.
* `net_client()` returns the arena's `CombatNetClient` (or `null`): **all** input devices talk to it (`set_intent(move_x, move_z, yaw,
  lock, sprint, block)` once per frame/tick, `press("light"|"heavy"|"dodge"|"parry"|"ability")` per button edge). Intent is world space;
  the device converts from camera space exactly as offline.
* signals `arena_mounted(arena)` (after `start_battle`, arena already in the tree) and `arena_unmounted` (just before it is freed).
* Properties: `arena`, `source` (keyboard/pad `LocalInputSource`, disabled in touch mode), `input_scheme`, `touch_enabled`, `battle_id`.

Behaviour worth knowing:

* One input stream: the arena's client uses `OnlineChessClient.input_builder`, which the client restores from the server's
  `inputResume` (MatchFrame) after a reconnect, so sequence numbers and cumulative press counters never go backwards and no press is replayed.
* A lost connection sets the intent to neutral (the server neutralises a silent seat after 15 ticks; the prediction must agree) and the
  client stops sending for a battle once its result is known.
* Benign `STALE_INPUT` errors (an unreliable `CombatInput` that arrived duplicated/out of order) are not forwarded as error banners.
* The prediction model covers free-state movement for all roles (per-role movement profile incl. the experimental King) and the
  walking-speed buffs; attacks, dodges, parries, stagger, knock-back and Blink show server state (their *animation* is predicted).

## Mounting in the pit `BattleWorld` (what to rely on)

`godot/world/README.md` ("Online path") lists what is missing on the world side. The combat side now offers:

1. `OnlineCombatView.setup(client, world.chamber.arena_mount)`: `host` is typed `Node`; the arena is a `Node3D` at the origin, unscaled
   (same requirement as `BattleCombatAdapter`). Call `pit.begin(frame.state.battle)` when `phase` becomes `combat`, connect
   `arena_mounted` to `pit.attach_arena(arena)` and call `pit.present_result(frame.state.combat.result)` in `aftermath`.
2. The arena is mounted by `sync()` the moment the server frame says `combat`, and starts sending inputs immediately (the server ignores
   inputs during its 180-tick countdown, so this is harmless). The server's countdown does **not** wait for the pit pre-roll: if the camera
   arrives after tick 180 the fight is already live. Either keep the pre-roll below 3 s, or accept that the player fights while the camera
   arrives (prediction is already running). A server-granted presentation delay would need a new message (contract v2).
3. The server returns the board to `board` about 120 ticks (2 s) after the result. The world must fast-forward its return sequence;
   `arena_unmounted` fires before the arena is freed so the pit can detach it first.
4. The arena builds its own `ThirdPersonCamera` for the local fighter (`arena.cameras[0]`, used by the keyboard/pad source for the heading).
   The world's `CameraRig` should keep the rig camera current (the arena does not call `make_current`).
5. Input must keep living in the application's viewport (the view creates the source as its own child), not under the arena in a `SubViewport`.

## Server-side behaviour (verified)

* `DedicatedChessServer.step()` feeds `PEER_ROUND_TRIP_TIME` of each seat's ENet peer into `CombatNetServer.set_seat_rtt_ms()` every
  physics tick (the hit-commit grace is therefore driven by the transport measurement, not by client claims). Caveat: ENet's RTT
  includes both ends' poll intervals (loopback shows 11-18 ms) and rises with reliable-packet retransmissions under loss; the grace
  is capped at 6 ticks anyway.
* `inputResume` travels in every `MatchFrame` (including the one sent right after a resume) and is applied by `OnlineChessClient`.
* Abandonment/forfeit/draw: the combat host forfeits a seat after 600 server ticks without input (or after a transport disconnect), the
  session also applies the 10 s wall-clock disconnect rule; neither produces a `BattleResult`. Tested in-process (`network_test.gd`) and
  end-to-end with a 4 s link blackout (`reconnect` scenario).
* Events are de-duplicated by `(battleId, eventId)` on the client; both clients observed identical events in every end-to-end fight.
* Per-duel stdout lines (JSON): `COMBAT_BATTLE_START`, `COMBAT_BATTLE_DONE` (result + per-seat accepted/stale inputs, starved ticks, max gap,
  mean grace, RTT feed) and `COMBAT_BATTLE_ABORT`; `SERVER_READY ... tuning=balance-v1:<hash>`.

## Mixed-version / tuning safety within v1

The server and the client are built from the same repository, so they share the combat code and `balance_v1.json`. If they were
ever different builds, a client would still be *correct* (the server alone is authoritative; the client's prediction is cosmetic) but would
mispredict and show wrong cooldown/ability assumptions. v1 messages have `additionalProperties: false`, so nothing can be added to
`Hello`/`Welcome` without a new contract version. Within v1 this change adds only:

* the tuning stamp `Balance.stamp()` (`balance-v1:<16 hex of the canonical-data SHA-256>`) in the server's `SERVER_READY` line and in every
  `COMBAT_BATTLE_*` log line, so operators and tests can see exactly what a process simulates;
* this document.

Proposed handshake for the next contract version (not implemented, needs a Codex-owned contract change):

1. `Hello.clientBuild = {protocolRevision, tuningStamp, appVersion}` (all required in v2, informational in v1-compat mode).
2. `Welcome.serverBuild = {protocolRevision, tuningStamp}` and `Welcome.combat = {arenaIds:["stone-v1"], roles:[...], snapshotHz:15, inputHz:60}`
   (replacing the free-standing `combatRoles`).
3. Server policy: different `protocolRevision` -> `ProtocolError UNSUPPORTED_VERSION` and close; different `tuningStamp` -> accept but
   mark the session `prediction: "off"`; the server then also stops trusting client-estimated timing (it already does).
   The client, on mismatch, runs `CombatArena` without `configure_network` prediction (the old ease-to-snapshot presentation) and shows
   a non-blocking "update the app for smoother combat" notice. Ranked play should refuse a mismatch outright.
4. Add `CombatSnapshot.tuningStamp` hash (optional) so a hot-swapped server balance is detected mid-session, and `FighterSnapshot.actionId`
   plus a buff-remaining field so the predictor stops inferring buffs from `cooldownTicks`.

## Tests

| Command | What it proves |
| --- | --- |
| `godot --headless --path godot --script res://tests/network/online_prediction_test.gd` | real ENet loopback, real server, two clients with real views: shared input builder, keyboard source and touch intents predicted, press shown at once, reconnect keeps one stream, result stops sending |
| `godot ... res://combat/tests/test_runner.gd -- net_roles` | predictor vs authority for six roles (open floor 0.00012 m), buffs, networked error 0/50/100/150 ms with/without loss for every v1 role, melee table |
| `node scripts/test-online-combat.mjs [--profile=full] [--only=<id>]` | complete duels through the UDP latency/loss proxy; convergence to the server result; reconnect + blackout; simultaneous attack/parry; invalid inputs |
| `npm run test:multiplayer` | the original ENet/DTLS suite plus the quick online-combat profile |

Not covered: real devices, real mobile/Wi-Fi networks, NAT rebinding, bandwidth limits, Windows/Android crossplay, clock drift over long
matches, more than 150 ms RTT in the lockstep suites (120 ms + 2% loss end-to-end).
