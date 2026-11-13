class_name CombatStateMachine
extends RefCounted
## Per-fighter combat state machine. States are exactly the nine the CombatSnapshot schema names:
## Idle, Moving, Attacking, Blocking, Parrying, Dodging, Staggered, AbilityCasting, Defeated.
##
## Tick contract (called once per 60 Hz tick, before movement and hit resolution):
##   tick(intent) -> transitions, using the edges in `intent` plus a short input buffer.
##   end_tick()   -> state_ticks += 1 (after hits for this tick were resolved).
## `state_ticks` is 0 on the tick a state is entered, so an attack whose active window is
## [first, last) is hit-capable exactly on state_ticks in [first, last).
##
## Rules in one place:
##  * Free (Idle/Moving) -> may start ability, dodge, parry, heavy, light, or raise the guard.
##  * Attacking: committed until the attack's cancel point; from there a buffered light/heavy
##    chains (light chain of 3), or dodge/parry/ability cancels the recovery.
##  * Dodging: bounded invulnerability window, then recovery, then a short cooldown.
##  * Parrying: tight window (FighterStats.parryTicks) then committed recovery; no spam.
##  * Staggered: no actions; after it ends, brief stagger immunity stops stun locks.

const S := CombatConstants.State

enum Result { STARTED, DENIED_KEEP, DENIED_DROP }

var f: FighterController

var state: int = S.IDLE
var state_ticks: int = 0

var attack: AttackDefinition = null
var attack_total: int = 0
var combo_index: int = -1
var combo_timer: int = 0

var buffered: String = ""
var buffer_ticks: int = 0

var dodge_dir: Vector3 = Vector3.ZERO
var dodge_total: int = 0
var dodge_cooldown: int = 0

var parry_window: int = 0
var parry_total: int = 0
var parry_cooldown: int = 0
var parry_succeeded: bool = false

var stun_total: int = 0
var stun_kind: String = ""
var stagger_immunity: int = 0

var riposte_ticks: int = 0
var cast_total: int = 0
## "buff" / "blink" while casting a non-attack ability, "" otherwise.
var cast_kind: String = ""
var blink_dir: Vector3 = Vector3.ZERO

var last_denied: String = ""
var last_denied_tick: int = -1000

var _intent: FighterIntent = null


func bind(fighter: FighterController) -> void:
	f = fighter


# --------------------------------------------------------------------------------------------
# Queries used by hit resolution, movement and presentation
# --------------------------------------------------------------------------------------------
func is_free() -> bool:
	return state == S.IDLE or state == S.MOVING


func iframes_active() -> bool:
	if state == S.ABILITY_CASTING and cast_kind == "blink" and attack == null:
		return state_ticks < int(f.ability.definition["iframe_ticks"])  # Bishop: vanished
	return state == S.DODGING and state_ticks >= int(f.profile["dodge_iframe_start"]) \
			and state_ticks < int(f.profile["dodge_iframe_end"])


func parry_window_open() -> bool:
	return state == S.PARRYING and not parry_succeeded and state_ticks < parry_window


## Royal Counter stance (King): committed, armoured, slow. True for the whole stance (wind-up + counter window),
## false during the whiff recovery and once a counter has been triggered (the riposte is an ordinary attack).
func counter_stance() -> bool:
	return state == S.ABILITY_CASTING and attack == null and cast_kind == "counter" \
			and state_ticks < int(f.ability.definition["counter_end"])


## The frontal-hit-negating part of the stance: ticks [counter_start, counter_end) of the cast.
func counter_window_open() -> bool:
	return counter_stance() and state_ticks >= int(f.ability.definition["counter_start"])


func guard_up() -> bool:
	return state == S.BLOCKING and state_ticks >= CombatConstants.BLOCK_RAISE_TICKS


func attack_active() -> bool:
	return attack != null and (state == S.ATTACKING or state == S.ABILITY_CASTING) \
			and attack.phase_at(state_ticks, attack_total) == AttackDefinition.Phase.ACTIVE


func has_armor() -> bool:
	if state == S.ABILITY_CASTING and attack == null:
		if cast_kind == "counter":
			return counter_stance()  # armoured through wind-up and window; the whiff recovery is wide open
		return true  # Last Stand shout cannot be interrupted by ordinary hits
	return attack != null and attack.has_armor_at(state_ticks, attack_total)


func attack_phase() -> int:
	if attack == null:
		return -1
	return attack.phase_at(state_ticks, attack_total)


func attack_progress() -> float:
	if attack == null or attack_total <= 0:
		return 0.0
	return clampf(float(state_ticks) / float(attack_total), 0.0, 1.0)


# --------------------------------------------------------------------------------------------
# Per-tick update
# --------------------------------------------------------------------------------------------
func tick(intent: FighterIntent) -> void:
	_intent = intent
	_tick_timers()
	_buffer_edges(intent)
	match state:
		S.DEFEATED:
			return
		S.STAGGERED:
			_tick_staggered()
		S.ATTACKING, S.ABILITY_CASTING:
			if attack != null:
				_tick_attack()
			else:
				_tick_cast()
		S.DODGING:
			_tick_dodge()
		S.PARRYING:
			_tick_parry()
		S.BLOCKING:
			_tick_blocking()
		_:
			_tick_free()


func end_tick() -> void:
	state_ticks += 1


func _tick_timers() -> void:
	if dodge_cooldown > 0:
		dodge_cooldown -= 1
	if parry_cooldown > 0:
		parry_cooldown -= 1
	if riposte_ticks > 0:
		riposte_ticks -= 1
	if stagger_immunity > 0 and state != S.STAGGERED:
		stagger_immunity -= 1
	if combo_timer > 0 and state != S.ATTACKING:
		combo_timer -= 1
		if combo_timer == 0:
			combo_index = -1


func _buffer_edges(intent: FighterIntent) -> void:
	if state == S.STAGGERED or state == S.DEFEATED:
		buffered = ""
		buffer_ticks = 0
		return
	var action := intent.edge_action()
	if action != "":
		buffered = action
		buffer_ticks = CombatConstants.INPUT_BUFFER_TICKS
	elif buffer_ticks > 0:
		buffer_ticks -= 1
		if buffer_ticks == 0:
			buffered = ""


# --------------------------------------------------------------------------------------------
# State handlers
# --------------------------------------------------------------------------------------------
func _tick_free() -> void:
	if _consume_buffer(["ability", "dodge", "parry", "heavy", "light"]):
		return
	if _intent.block_held and not f.stamina.exhausted:
		_enter(S.BLOCKING)
		return
	var target: int = S.MOVING if _intent.has_move() else S.IDLE
	if state != target:
		_enter(target)


func _tick_blocking() -> void:
	if not _intent.block_held or f.stamina.exhausted:
		_enter(S.IDLE)
		_tick_free()
		return
	_consume_buffer(["ability", "dodge", "parry", "heavy", "light"])


func _tick_attack() -> void:
	if state_ticks >= attack_total:
		_finish_attack()
		return
	if state_ticks >= attack.cancel_tick(attack_total):
		if _consume_buffer(["ability", "dodge", "parry", "heavy", "light"]):
			return
		if _intent.block_held and not f.stamina.exhausted:
			_close_swing()
			_enter(S.BLOCKING)


func _finish_attack() -> void:
	var was_light := attack.kind == AttackDefinition.Kind.LIGHT
	_close_swing()
	if was_light and combo_index < f.combo_limit() - 1:
		combo_timer = CombatConstants.COMBO_GRACE_TICKS
	else:
		combo_index = -1
	_enter(S.IDLE)
	_tick_free()


func _tick_cast() -> void:
	if cast_kind == "counter" and state_ticks == int(f.ability.definition["counter_end"]):
		f.queue_event("whiff")  # the window closed with nothing to counter: the King is now recovering
	if state_ticks >= cast_total:
		_enter(S.IDLE)
		_tick_free()


func _tick_dodge() -> void:
	if state_ticks >= dodge_total:
		_enter(S.IDLE)
		_tick_free()
		return
	if state_ticks >= dodge_total - 6:
		_consume_buffer(["heavy", "light"])


func _tick_parry() -> void:
	if parry_succeeded and _consume_buffer(["ability", "dodge", "heavy", "light"]):
		return
	if state_ticks >= parry_total:
		_enter(S.IDLE)
		_tick_free()


func _tick_staggered() -> void:
	if state_ticks >= stun_total:
		stagger_immunity = int(f.profile["stagger_immunity_ticks"])
		_enter(S.IDLE)
		_tick_free()


# --------------------------------------------------------------------------------------------
# Action starts
# --------------------------------------------------------------------------------------------
func _consume_buffer(allowed: Array) -> bool:
	if buffered == "" or not (buffered in allowed):
		return false
	var outcome: int = _attempt(buffered)
	if outcome == Result.STARTED:
		buffered = ""
		buffer_ticks = 0
		return true
	if outcome == Result.DENIED_DROP:
		buffered = ""
		buffer_ticks = 0
	return false


func _attempt(action: String) -> int:
	match action:
		"light":
			return _start_light()
		"heavy":
			return _begin_attack(AttackLibrary.heavy(f.role), -1)
		"dodge":
			return _start_dodge()
		"parry":
			return _start_parry()
		"ability":
			return _start_ability()
	return Result.DENIED_DROP


func _start_light() -> int:
	var index := 0
	if state == S.ATTACKING and attack != null and attack.kind == AttackDefinition.Kind.LIGHT:
		index = combo_index + 1
	elif combo_timer > 0 and combo_index >= 0:
		index = combo_index + 1
	if index >= f.combo_limit():
		index = 0  # chain exhausted: a new press begins a fresh chain
	return _begin_attack(AttackLibrary.light(f.role, index), index)


func _begin_attack(def: AttackDefinition, light_index: int) -> int:
	if not f.stamina.spend(def.stamina_cost):
		return _deny("stamina")
	_close_swing()
	attack = def
	attack_total = def.total_ticks(f.stats, f.ability.attack_speed_mult())
	combo_index = light_index
	combo_timer = 0
	_enter(S.ATTACKING)
	f.hitbox.begin_swing()
	return Result.STARTED


func _start_dodge() -> int:
	if dodge_cooldown > 0:
		return Result.DENIED_KEEP
	if not f.stamina.spend(float(f.profile["dodge_cost"])):
		return _deny("stamina")
	_close_swing()
	if _intent.has_move():
		dodge_dir = _intent.move_vector().normalized()
	else:
		dodge_dir = -CombatConstants.heading(f.yaw)
	dodge_total = int(f.profile["dodge_ticks"])
	dodge_cooldown = dodge_total + int(f.profile["dodge_cooldown_ticks"])
	_enter(S.DODGING)
	return Result.STARTED


func _start_parry() -> int:
	if parry_cooldown > 0:
		return Result.DENIED_KEEP
	if not f.stamina.spend(float(f.profile["parry_cost"])):
		return _deny("stamina")
	_close_swing()
	parry_window = int(f.stats["parryTicks"]) + int(f.profile.get("parry_window_bonus", 0))   # data: a wider, more readable window (BALANCE.md "Pacing")
	parry_total = parry_window + int(f.profile["parry_recovery_ticks"])
	parry_cooldown = parry_total + int(f.profile["parry_cooldown_ticks"])
	parry_succeeded = false
	_enter(S.PARRYING)
	return Result.STARTED


func _start_ability() -> int:
	var check: Dictionary = f.ability.check(f.health, f.stamina)
	if not check["ok"]:
		return _deny(String(check["reason"]))
	var cost: float = f.ability.stamina_cost()
	if cost > 0.0 and not f.stamina.spend(cost):
		return _deny("stamina")
	_close_swing()
	f.ability.commit()
	if f.ability.is_attack_ability():
		attack = AttackLibrary.ability_attack(f.role, f.ability.ability_id)
		attack_total = attack.total_ticks(f.stats, f.ability.attack_speed_mult())
		combo_index = -1
		cast_kind = "attack"
		_enter(S.ABILITY_CASTING)
		f.hitbox.begin_swing()
	else:
		attack = null
		cast_total = int(f.ability.definition["cast_ticks"])
		cast_kind = String(f.ability.definition["kind"])
		if cast_kind == "blink":
			# Direction is fixed when the cast starts: held move direction, else straight ahead.
			blink_dir = _intent.move_vector().normalized() if _intent.has_move() else CombatConstants.heading(f.yaw)
		_enter(S.ABILITY_CASTING)
	f.queue_event("ability")
	return Result.STARTED


func _deny(reason: String) -> int:
	last_denied = reason
	last_denied_tick = f.local_tick
	return Result.DENIED_DROP


# --------------------------------------------------------------------------------------------
# Externally triggered transitions (called by hit resolution)
# --------------------------------------------------------------------------------------------
func enter_staggered(ticks: int, kind: String) -> void:
	if state == S.DEFEATED:
		return
	_close_swing()
	combo_index = -1
	combo_timer = 0
	buffered = ""
	buffer_ticks = 0
	stun_total = maxi(1, ticks)
	stun_kind = kind
	_enter(S.STAGGERED)


func enter_defeated() -> void:
	_close_swing()
	combo_index = -1
	combo_timer = 0
	buffered = ""
	buffer_ticks = 0
	_enter(S.DEFEATED)


func on_parry_success() -> void:
	parry_succeeded = true
	parry_total = mini(parry_total, state_ticks + 10)
	riposte_ticks = int(f.profile["riposte_ticks"])


## Royal Counter triggered by `attacker`: the King snaps to face them and ripostes with the ability attack
## (an ordinary AttackDefinition resolved through the normal hit path, boosted by the profile's riposte_mult).
func on_counter_success(attacker: FighterController) -> void:
	var def := AttackLibrary.ability_attack(f.role, f.ability.ability_id)
	if def == null:
		return
	var to := CombatConstants.flat(attacker.global_position - f.global_position)
	if to.length_squared() > 0.000001:
		f.yaw = CombatConstants.yaw_of(to)
	attack = def
	attack_total = def.total_ticks(f.stats, f.ability.attack_speed_mult())
	combo_index = -1
	cast_kind = "attack"
	riposte_ticks = attack_total + 2
	_enter(S.ABILITY_CASTING)
	f.hitbox.begin_swing()


# --------------------------------------------------------------------------------------------
func _enter(new_state: int) -> void:
	state = new_state
	state_ticks = 0


## Leaves the current swing. A swing that reached its active window without touching anyone
## is reported as a whiff (cosmetic event only).
func _close_swing() -> void:
	if attack != null:
		if not f.hitbox.hit_anything and state_ticks >= attack.active_window(attack_total).x:
			f.queue_event("whiff")
		f.hitbox.end_swing()
	attack = null
	attack_total = 0
