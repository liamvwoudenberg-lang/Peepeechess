extends RefCounted
## Per-fighter anti-mash bookkeeping (flag: duel rules on AND balance_v1.json `anti_mash.enabled`). Everything is counted in
## simulation ticks, so the state is a pure function of the input stream: deterministic, no clock, no randomness.
## Numbers live in balance_v1.json `anti_mash` (Balance.anti_mash()); BALANCE.md "Anti-mash" explains the rules.
##
##  * chain: consecutive actions (attack / parry / dodge) cost more stamina until the fighter has been free for `window_ticks`.
##  * staleness: the same attack landing again soon deals less (`step` per repeat among the last `memory` attacks, floored).
##  * dodge chain: a dodge begun soon after another loses i-frames and recovers more slowly.
##  * heavy hold / feint bookkeeping (used by CombatStateMachine).

const Balance := preload("res://combat/data/balance_data.gd")

var on := false
var cfg: Dictionary = {}

var chain := 0
var _free_ticks := 0
var dodge_chain := 0
var _dodge_free := 0
var history: Array[String] = []
var _since_hit := 0
var feint_cd := 0
var hold_used := 0


func setup(enabled: bool) -> void:
	on = enabled
	cfg = Balance.anti_mash() if enabled else {}
	chain = 0
	_free_ticks = 0
	dodge_chain = 0
	_dodge_free = 0
	history.clear()
	_since_hit = 0
	feint_cd = 0
	hold_used = 0



## Called once per tick by the state machine with whether the fighter is free (idle / moving / guarding) and not mid-dodge.
func tick(free: bool, dodging: bool) -> void:
	if not on:
		return
	if feint_cd > 0:
		feint_cd -= 1
	if free:
		_free_ticks += 1
		if _free_ticks > int(cfg["chain"]["window_ticks"]):
			chain = 0
	else:
		_free_ticks = 0
	if dodging:
		_dodge_free = 0
	else:
		_dodge_free += 1
		if _dodge_free > int(cfg["dodge"]["chain_window"]):
			dodge_chain = 0
	if not history.is_empty():
		_since_hit += 1
		if _since_hit > int(cfg["stale"]["decay_ticks"]):
			history.clear()


## Stamina multiplier for the next action; 1.0 when off.
func cost_mult() -> float:
	if not on:
		return 1.0
	var c: Dictionary = cfg["chain"]
	return minf(float(c["max_mult"]), 1.0 + float(c["step"]) * float(chain))


func note_action() -> void:
	if on:
		chain += 1
		_free_ticks = 0


## Chained dodges: how many i-frame ticks are trimmed and how many recovery ticks are added for the dodge about to start.
func dodge_trim() -> int:
	return 0 if not on else mini(int(cfg["dodge"]["max_trim"]), dodge_chain * int(cfg["dodge"]["iframe_trim"]))


func dodge_extra_recovery() -> int:
	return 0 if not on else mini(int(cfg["dodge"]["max_extra"]), dodge_chain * int(cfg["dodge"]["extra_recovery"]))


func note_dodge() -> void:
	if on:
		dodge_chain += 1
		_dodge_free = 0


## Damage multiplier for an attack with this id given the recent attack history (1.0 = fresh). Records the attack.
func stale_mult(attack_id: String) -> float:
	if not on:
		return 1.0
	var s: Dictionary = cfg["stale"]
	var repeats := 0
	for h in history:
		if h == attack_id:
			repeats += 1
	history.append(attack_id)
	while history.size() > int(s["memory"]):
		history.pop_front()
	_since_hit = 0
	return maxf(float(s["floor"]), 1.0 - float(s["step"]) * float(repeats))
