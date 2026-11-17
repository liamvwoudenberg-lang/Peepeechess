# Balance reference (generated)

Generated from `godot/config/balance_meta.json` by `res://tools/config_docs.gd`. Do not edit by hand: change the metadata, then regenerate.
The values live in `godot/config/balance.json`. A 'tick' is 1/60 s. Ranges are what the loader accepts, not recommendations.

## Role profiles (`profiles.<role>.*`)

Movement feel, health-independent defences and the stamina/poise economy of each role.

| Key | Type | Unit | Range | What it does |
|---|---|---|---|---|
| `accel` | float | metres/s^2 | 1 .. 200 | Movement acceleration (higher = snappier start). |
| `armor` | float | fraction | 0 .. 0.9 | Share of incoming damage that is ignored (0.25 = takes 25% less damage). |
| `attack_steer_other` | float | fraction | 0 .. 1 | How much movement input steers during the rest of an attack. |
| `attack_steer_startup` | float | fraction | 0 .. 1 | How much movement input steers during an attack wind-up. |
| `block_arc_deg` | float | degrees | 10 .. 360 | Width of the arc in front of the fighter in which blocking works. |
| `block_cost_mult` | float | multiplier | 0.1 .. 5 | Stamina cost multiplier when blocking a hit (lower = cheaper blocks). |
| `block_move_mult` | float | multiplier | 0 .. 1.5 | Move speed multiplier while holding block. |
| `decel` | float | metres/s^2 | 1 .. 300 | Movement deceleration when input stops. |
| `display` | string |  |  | Name shown in the UI for this role. |
| `dodge_cooldown_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Minimum time between dodges. |
| `dodge_cost` | float | stamina | 0 .. 100 | Stamina spent by a dodge roll. |
| `dodge_distance` | float | metres | 0.5 .. 10 | Distance covered by a dodge roll. |
| `dodge_iframe_end` | int | ticks (1 tick = 1/60 s) | 1 .. 90 | Tick of the dodge at which invulnerability ends. |
| `dodge_iframe_start` | int | ticks (1 tick = 1/60 s) | 0 .. 60 | Tick of the dodge at which invulnerability starts. |
| `dodge_ticks` | int | ticks (1 tick = 1/60 s) | 5 .. 120 | Total length of a dodge roll. |
| `guardbreak_stun` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Stun time when the guard is broken. |
| `hit_react_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 60 | Length of the flinch animation lock after a light hit that does not break poise. |
| `parry_arc_deg` | float | degrees | 10 .. 360 | Width of the arc in which a parry works. |
| `parry_cooldown_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Minimum time between parry attempts. |
| `parry_cost` | float | stamina | 0 .. 100 | Stamina spent to attempt a parry. |
| `parry_recovery_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 120 | Recovery time after a parry attempt. |
| `parry_refund` | float | stamina | 0 .. 100 | Stamina given back on a successful parry. |
| `parry_stagger_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | How long a successfully parried attacker is staggered. |
| `parry_steer` | float | fraction | 0 .. 1 | How much movement input steers during a parry. |
| `parry_window_bonus` | int | ticks (1 tick = 1/60 s) | 0 .. 30 | Extra ticks added to the parry timing window (bigger = more forgiving). |
| `poise` | float | poise points | 1 .. 400 | How much poise damage the fighter absorbs before it is staggered. Higher = harder to interrupt. |
| `poise_regen_delay` | int | ticks (1 tick = 1/60 s) | 0 .. 600 | Ticks after the last hit before poise starts to regenerate. |
| `poise_regen_per_tick` | float | poise per tick | 0 .. 5 | Poise regained each tick once the regen delay has passed. |
| `radius` | float | metres | 0.2 .. 1 | Body radius of the fighter; used for collisions and hit tests. |
| `riposte_mult` | float | multiplier | 1 .. 4 | Damage multiplier of the counter-attack right after a successful parry. |
| `riposte_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | How long the riposte bonus lasts. |
| `sprint_drain_per_tick` | float | stamina per tick | 0 .. 5 | Stamina spent each tick while sprinting. |
| `sprint_mult` | float | multiplier | 1 .. 3 | Move speed multiplier while sprinting. |
| `stagger_immunity_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Ticks of stagger immunity after recovering from a stagger (stops stun-locking). |
| `stamina_regen_delay` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Ticks after spending stamina before regeneration resumes. |
| `stamina_regen_per_tick` | float | stamina per tick | 0 .. 5 | Stamina regained each tick when not spending it. |
| `turn_attack_startup` | float | turn rate | 0 .. 1 | Turn speed during an attack's wind-up (free camera). |
| `turn_attack_startup_locked` | float | turn rate | 0 .. 1 | Turn speed during an attack's wind-up (locked on). |
| `turn_free` | float | turn rate | 0.01 .. 2 | Turn speed when not locked on and not attacking. |
| `turn_locked` | float | turn rate | 0.01 .. 2 | Turn speed while locked on to the opponent. |
| `weapon` | string |  |  | Weapon tag used by the presentation (sword model/clips). |

## Abilities (`abilities.<id>.*`)

One block per ability (buffs, blink, counter stance, the Queen's combo).

| Key | Type | Unit | Range | What it does |
|---|---|---|---|---|
| `attack_speed_mult` | float | multiplier | 0.5 .. 3 | Attack speed multiplier while buffed. |
| `blink_distance` | float | metres | 0.5 .. 12 | Distance of a blink (short teleport). |
| `blink_tick` | int | ticks (1 tick = 1/60 s) | 0 .. 120 | Tick of the cast at which the blink happens. |
| `buff_ticks` | int | ticks (1 tick = 1/60 s) | 1 .. 1800 | Duration of a buff. |
| `cast_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Cast time before the effect starts. |
| `combo_length` | int | hits | 1 .. 12 | Number of hits in an ability combo. |
| `counter_arc_deg` | float | degrees | 10 .. 360 | Arc of a counter stance. |
| `counter_end` | int | ticks (1 tick = 1/60 s) | 1 .. 240 | Tick at which a counter stance stops catching hits. |
| `counter_stagger_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 300 | Stagger applied to the attacker that hits a counter stance. |
| `counter_start` | int | ticks (1 tick = 1/60 s) | 0 .. 120 | Tick at which a counter stance starts to catch hits. |
| `damage_mult` | float | multiplier | 0.5 .. 4 | Damage multiplier while buffed. |
| `experimental` | bool |  |  | True = the ability is refused unless a caller opts in (the King). |
| `guard_cost_mult` | float | multiplier | 0 .. 5 | Guard stamina cost multiplier while the ability is active. |
| `guard_unbreakable` | bool |  |  | If true the guard cannot be broken while the ability is active. |
| `hp_threshold` | float | fraction of health | 0 .. 1 | Health fraction at or below which the ability is allowed (0 = always). |
| `iframe_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 120 | Invulnerability ticks granted by the ability. |
| `kind` | enum |  |  | What the ability does: buff, attack, blink or counter. |
| `move_mult` | float | multiplier | 0.1 .. 3 | Move speed multiplier while buffed. |
| `poise_mult` | float | multiplier | 0.5 .. 10 | Poise multiplier while the ability is active. |
| `regen_mult` | float | multiplier | 0 .. 5 | Stamina regeneration multiplier while buffed. |
| `role` | string |  |  | Role that owns the ability (must have a profile). |
| `stamina_cost` | float | stamina | 0 .. 200 | Stamina spent when the ability is used. |
| `stance_move_mult` | float | multiplier | 0 .. 1.5 | Move speed multiplier while in the stance. |
| `stance_turn_mult` | float | multiplier | 0 .. 1.5 | Turn speed multiplier while in the stance. |

## Attack frame data (`attacks.<role>.light[i] / heavy / abilities.<id>`)

The same keys apply to every light attack in the chain, the heavy and the ability swings.

| Key | Type | Unit | Range | What it does |
|---|---|---|---|---|
| `absolute_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 400 | Fixed total length in ticks (0 = derive from the role's contract light/heavy ticks and ticks_scale). |
| `active_end` | float | fraction of the attack | 0 .. 1 | Where the active (damaging) frames end. |
| `animation` | string |  |  | Animation tag the presentation plays for this attack. |
| `arc_degrees` | float | degrees | 1 .. 360 | Width of the hit arc (narrower = needs more aim). |
| `armor_end` | float | fraction of the attack | -1 .. 1 | Where super armour ends (-1 = never). |
| `armor_start` | float | fraction of the attack | -1 .. 1 | Where super armour starts (-1 = never). |
| `cancel_from` | float | fraction of the attack | 0 .. 1 | From here the attack can be cancelled into the next action. |
| `combo_index` | int | index | 0 .. 8 | Position in the light-attack chain (0 = first). |
| `damage_mult` | float | multiplier | 0 .. 8 | Multiplier on the contract base damage. |
| `far_m` | float | metres | 0 .. 20 | Distance above which far_mult applies (Bishop beam is stronger at range). |
| `far_mult` | float | multiplier | 0 .. 4 | Damage multiplier at long range. |
| `forward_motion_m` | float | metres | 0 .. 10 | Distance the fighter lunges forward during the attack. |
| `guard_break` | int | 0/1 | 0 .. 1 | 1 = this attack always breaks a raised guard. |
| `guard_cost_mult` | float | multiplier | 0 .. 8 | Multiplier on the blocker's stamina cost. |
| `hitstun_ticks` | int | ticks (1 tick = 1/60 s) | 0 .. 200 | Base hit stun the victim suffers; multiplied by hit_stun.*_mult. |
| `id` | string |  |  | Identifier of the attack (used in logs and tests). |
| `kind` | enum |  |  | LIGHT, HEAVY or ABILITY. |
| `knockback_m` | float | metres | 0 .. 6 | Knockback distance on a hit. |
| `motion_end` | float | fraction of the attack | 0 .. 1 | Where the forward lunge ends. |
| `motion_start` | float | fraction of the attack | 0 .. 1 | Where the forward lunge starts. |
| `near_m` | float | metres | 0 .. 10 | Distance below which near_mult applies (Bishop beam is weaker up close). |
| `near_mult` | float | multiplier | 0 .. 4 | Damage multiplier at close range. |
| `poise_damage` | float | poise points | 0 .. 400 | Poise damage dealt to the victim. |
| `reach_mult` | float | multiplier | 0.2 .. 5 | Multiplier on the contract reach. |
| `stamina_cost` | float | stamina | 0 .. 200 | Stamina spent to swing. |
| `startup_end` | float | fraction of the attack | 0 .. 1 | Where the wind-up ends and the active frames begin. |
| `ticks_scale` | float | multiplier | 0.3 .. 4 | Scales the attack's length relative to the contract ticks (higher = slower). |

## Global blocks

Hit stun, pacing, duel length and the attacker table.

| Key | Type | Unit | Range | What it does |
|---|---|---|---|---|
| `attacker_edge.pairs.*` | pair | multipliers | 1 .. 8 | [attacker damage x, defender damage x] for one pairing; at most one side may be above 1. Edit it in the matrix form (attacker_edge.matrix[attacker][defender]). |
| `attacker_edge.stamina.attacker_cost` | float | multiplier | 0 .. 1 | Attacker's stamina cost multiplier (1 = neutral, lower = cheaper). |
| `attacker_edge.stamina.defender_cost` | float | multiplier | 1 .. 4 | Defender's stamina cost multiplier (1 = neutral, higher = costlier). |
| `attacker_edge.stamina.defender_regen` | float | multiplier | 0.1 .. 1 | Defender's stamina regeneration multiplier (1 = neutral, lower = slower). |
| `attacker_edge.target` | float | win rate | 0 .. 1 | Win rate the table was calibrated for (informational, bots only). |
| `duel_length.damage_scale` | float | multiplier | 0.05 .. 2 | Global HP-damage scale used for every pairing without its own entry. |
| `duel_length.pairs.*` | float | multiplier | 0.05 .. 1 | Per pairing (attacker role + defender role) damage scale that brings a duel to the target length. |
| `duel_length.target_seconds` | float | seconds | 5 .. 600 | Target duel length the per-pair scales were calibrated for (informational). |
| `hit_stun.ability_mult` | float | multiplier | 0 .. 5 | Hit stun multiplier for an ability hit. |
| `hit_stun.heavy_mult` | float | multiplier | 0 .. 5 | Hit stun multiplier for a heavy (charged) hit; keep above light_mult. |
| `hit_stun.light_mult` | float | multiplier | 0 .. 5 | Hit stun multiplier for a clean light hit. |
| `pacing.comeback.damage_mult` | float | multiplier | 1 .. 2 | Damage multiplier of the comeback bonus. |
| `pacing.comeback.hp_gap` | float | fraction of health | 0.05 .. 1 | A fighter this far behind on health gets the comeback damage bonus. |
| `pacing.sudden_death.ramp_per_s` | float | fraction per second | 0 .. 1 | Damage growth per second once sudden death has started. |
| `pacing.sudden_death.start_s` | float | seconds | 5 .. 600 | Seconds of fighting after which every blow starts to grow. |
| `schema` | int |  | 1 .. 1 | File format version. Do not change. |
| `tuning_id` | string |  |  | Name of this tuning. It is part of the stamp: client and server must match. |

