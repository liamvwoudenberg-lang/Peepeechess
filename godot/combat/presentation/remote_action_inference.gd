extends RefCounted
## Presentation-only inference for a REMOTE fighter. CombatSnapshot carries the state name and
## stateTicks but no action id (a known v1 limitation, see NETWORKING.md), so the proxy fighter that
## CharacterModel / FighterVisual animate needs its attack kind guessed from what the snapshots show:
##   * entering Attacking                         -> light link 1
##   * stateTicks goes BACKWARDS while Attacking  -> the chain continued: next link
##   * stateTicks passes a light's length         -> it was a heavy (only knowable late, so the
##                                                   first ~light-length ticks of a heavy play the light clip)
## Buff attack-speed changes are not visible remotely, so totals assume no buff. None of this feeds
## back into combat: it only fills the cosmetic fields of the local proxy FighterController.

const S := CombatConstants.State

var combo_index: int = -1
var heavy: bool = false
var _prev_state: int = -1
var _prev_ticks: int = 0


func apply(f: FighterController, state: int, ticks: int) -> void:
	var sm := f.sm
	if state == S.ATTACKING:
		if _prev_state != S.ATTACKING:
			combo_index = 0
			heavy = false
		elif ticks < _prev_ticks:
			combo_index = (combo_index + 1) % maxi(1, f.combo_limit())
			heavy = false
		var light_def := AttackLibrary.light(f.role, combo_index)
		if not heavy and ticks >= light_def.total_ticks(f.stats):
			heavy = true
		var def := AttackLibrary.heavy(f.role) if heavy else light_def
		sm.attack = def
		sm.attack_total = def.total_ticks(f.stats)
		sm.combo_index = -1 if heavy else combo_index
	elif state == S.ABILITY_CASTING:
		if f.ability.is_attack_ability():
			sm.attack = AttackLibrary.ability_attack(f.role, f.ability.ability_id)
			sm.attack_total = sm.attack.total_ticks(f.stats)
		else:
			sm.attack = null
			sm.cast_total = int(f.ability.definition.get("cast_ticks", 12))
	else:
		sm.attack = null
		if state == S.PARRYING:
			sm.parry_total = int(f.stats["parryTicks"]) + int(f.profile["parry_recovery_ticks"])
		elif state == S.DODGING:
			sm.dodge_total = int(f.profile["dodge_ticks"])
		elif state == S.STAGGERED:
			sm.stun_total = 30  # unknown remotely; the clip is paced to this assumption
		combo_index = -1 if state != S.IDLE and state != S.MOVING else combo_index
	sm.state = state
	sm.state_ticks = ticks
	_prev_state = state
	_prev_ticks = ticks
