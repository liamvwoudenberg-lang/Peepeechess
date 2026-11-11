# Combat module (`godot/combat/`)

Standalone third-person combat for Battle Chess. Owner: Claude Code (see
`docs/development/OWNERSHIP.md`). Baseline: shared contracts v1 (`c0dfe92`).

**Status: playable offline prototype with a headless authoritative simulation.
Multiplayer is NOT implemented.** Nothing here sends or receives network traffic.

## Run it

```sh
godot --path godot res://combat/scenes/test_arena.tscn      # menu: 1P vs AI / 2P split screen / AI demo
godot --headless --path godot --editor --import              # once, so global classes register
godot --headless --path godot --script res://combat/tests/test_runner.gd
```

Controls: see [CONTROLS.md](CONTROLS.md) (keyboard P1 / P2, DualShock 4 and Xbox pads, touch, menus, rebinding). Summary:
WASD + mouse (P1), arrows + JKL (P2), or one or two gamepads (left stick move, Square light, Triangle / R2 heavy, L1 block,
R1 parry, Cross dodge, Circle special, L2 sprint, L3 lock-on, right stick camera, Options pause). Bindings are rebindable
(Settings -> Controls & controllers) and the hints in the menu and HUD are generated from them. Project input maps are not touched.

## Layout

| Path | What |
| --- | --- |
| `core/` | Headless authority: `CombatSimulation`, `FighterController` (CharacterBody3D), `FighterMovement`, `CombatStateMachine`, `AttackDefinition`, `HitboxController`, `HealthComponent`, `StaminaComponent`, `AbilityComponent`, input state/builder, attack and profile tables |
| `ai/` | `CombatAI`: plays through the same `CombatInput` channel using only the public snapshot |
| `arenas/` | `StoneArena`: collision-only arena (`stone-v1`) |
| `presentation/` | Camera, local input, HUD, placeholder fighters, arena dressing. Read-only observers |
| `arena.tscn` / `arena.gd` | `CombatArena`: the mount point and adapter API |
| `scenes/` | Standalone test arena |
| `tests/` | Headless GDScript suite (see below) |

## Rules implemented (initial tuning, not measured balance)

* Fixed 60 Hz ticks; 180 countdown ticks then 5400 active ticks; times come from the request's `startTick`.
* **Light x3 combo** with rising stamina cost, chain/cancel point, 9-tick input buffer, 14-tick chain grace; **heavy** attacks.
* **Attack windows are data** (`AttackDefinition`: startup / active / recovery / cancel as fractions of the
  `FighterStats` tick lengths). The placeholder rig poses from the same numbers; imported clips must be
  authored to those markers. (A headless authority has no `AnimationPlayer`, so windows are not read from clips.)
* **Block** (3-tick raise, frontal arc, stamina per hit, guard break), **perfect parry** (window = `FighterStats.parryTicks`,
  frontal, stagger + stamina refund + riposte multiplier; Knight's is longer/stronger), **directional dodge** with i-frames,
  poise-based **stagger** with post-stagger immunity (no stun-locks), flinch reactions, armour frames, **Defeated**.
* **Stamina**: atomic spends, regen delay, paused while guarding/sprinting, exhaustion lock-out.
* **Abilities**: Pawn *Last Stand* (<=35% HP, 5 s buff, free), Knight *Lunging Strike* (armoured 4.2 m charge, breaks a Pawn's guard). Cooldowns from `FighterStats.cooldownTicks`.
* Results: knockout; at the limit the higher remaining-HP percentage wins (exact integer cross-multiplication);
  exact tie and double knockout go to the **defender**; no randomness.

Supported fighters: Pawn, Knight, Bishop (Blink), Rook (Fortress Guard), Queen (Royal Fury). The King is **refused** with
`INVALID_PAYLOAD` (the v1 schema also forbids it; king combat belongs to the v2 gauntlet). Unknown roles/abilities are refused,
never faked. Role tuning beyond the contract's stats is initial and unmeasured.

## Integration with `BattleRequest` / `BattleResult`

The chess authority owns the board and builds the request; combat never touches chess state.

```gdscript
# Server (trusted): host the headless authority. No camera/audio/mesh needed.
var sim := CombatSimulation.new()
add_child(sim)
var reply := sim.start(battle_request)          # validates against the v1 schema + semantics
if not reply.ok: ...                            # reply.code is a ProtocolError code
await get_tree().physics_frame                   # let static colliders register before the first live tick
# every 1/60 s:
sim.submit_input(combat_input)                   # per authenticated seat; INVALID_PAYLOAD / STALE_INPUT / FORBIDDEN on bad packets
sim.step_tick()                                  # or let CombatArena._physics_process do it
var snapshot := sim.snapshot()                   # send ~15 Hz to clients (CombatSnapshot)
sim.finished.connect(func(result): chess_authority.settle(result))   # BattleResult, exactly once
```

* `BattleResult` is produced only by `CombatSimulation`; a client must never be able to submit one.
  `resolvedTick = startTick + 180 + elapsed active ticks`, e.g. a timeout tie at `startTick 300` resolves at `5880` (matches the shared fixture).
* The simulation reads **every** number from `BattleRequest` (stats, ability id, arena). `FighterRoster`
  (`combat-proto-v1.*`) exists only for the test arena and tests and is *not* the balance registry.
* Client (presentation): `CombatArena` with `mode = PRESENTATION`, `start_battle(request)`, then `apply_snapshot(snapshot)`;
  it discards older snapshots, rejects schema-invalid ones, de-duplicates events by `eventId`. Inputs are sent to the server, not the arena.
* Offline/hot-seat: `CombatArena` in `AUTHORITY` mode, `configure_seats({...})`, `start_battle(request)`,
  connect `battle_finished(result)` and feed it to the local chess authority. This is a local authority, not a secure one.

`CombatArena` API: `start_battle(request)`, `submit_input(input)`, `apply_snapshot(snapshot)`, `stop_battle()`;
signals `combat_snapshot`, `battle_finished`, `battle_started` (matches ARCHITECTURE.md). The chess adapter is Codex's.

### Contract notes / requests for Codex (not changed by me)

1. `CombatEvent.actor` is always the **initiator** (attacker / ability user), `target` the other seat, for every event type
   (including `parry`/`dodge`/`block`). Please document this in CONTRACTS.md.
2. `FighterSnapshot` has no attack/animation id, so a remote client cannot tell which combo link is playing. A future v2 field
   (e.g. `actionId`) would fix it; the presentation currently infers it from state.
3. CONTRACTS.md says "+X right"; in a right-handed Y-up system a character facing +Z has its right at **-X**. The code follows the stated
   heading formula `(sin yaw, 0, cos yaw)` and treats "+X right" as a presentation note.
4. `parryTicks` in the contract's examples is 10 for the pawn (`round(0.17*60)`) while the text says `ceil`; the prototype roster uses 11.
5. Add `tests/combat/*.test.ts` to the root `test` script (root config is Codex-owned). The wrapper greps for engine diagnostics.

## Networking

`godot/combat/net/` + `NETWORKING.md`: server host, client prediction/reconciliation/interpolation, hit-commit grace (the only lag compensation), event de-duplication, disconnect handling, a simulated-link test harness, and the mapping to Codex's ENet protocol v1. `CombatArena.configure_network()` enables the online presentation path.

## Tests

`godot/combat/tests/` (runner `test_runner.gd`): components, contracts/admission, input, pads (controls: bindings, two-pad fight, hot-plug, board cursor, menu focus), movement, attacks, defense,
abilities, endings, adapter, assets, roles, AI soak (incl. determinism), net, net_latency, net_arena. Every check goes through the real `CombatInput` channel.
`tests/combat/combat.test.ts` runs import + suite + a headless arena run and fails on any `SCRIPT ERROR`/`Parse Error`/`ERROR:`.

## Known limitations (honest list)

* **Not human-playtested.** I verified behaviour by tests, headless runs, and software-GL screenshots under Xvfb; I did not
  play it with a real keyboard/mouse/gamepad, so input feel, camera comfort and balance are unvalidated. The AI soak is not a balance claim
  (the Knight beat the Pawn in all mixed AI matches; Pawn is untuned).
* No audio, no Android/Windows export or device testing. **No real network transport**: `net/` is a transport-agnostic client/server model tested over an in-process simulated link (see `NETWORKING.md` for what is and is not proven); no rollback netcode.
* Fighters use the Blender-generated models when their GLBs exist (`godot/assets/combat/`, pipeline in `tools/blender/`), otherwise primitive placeholders. The art is stylized low-poly; animation was reviewed as still frames, not in motion, on software GL only.
* Fighter-vs-fighter contact is analytic (not engine physics) on purpose; line-of-sight is not modelled for hits (pillars do not block).
* Engine-collision world geometry needs one physics frame to register before the first tick.
* The King has a model and clips but no simulation (v2 gauntlet). Pawn/Knight/Bishop/Rook/Queen fight; their balance is untuned (in the AI soak the Pawn is weak, Knight/Queen strong - not a balance claim).
* Snapshot-driven presentation (`apply_snapshot`) is basic (eases position; infers animation) and untested against a live server.
