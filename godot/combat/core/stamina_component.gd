class_name StaminaComponent
extends RefCounted
## Stamina pool shared by attacks, dodges, parries, abilities, sprinting and guarding.
##
## Rules (all in ticks / per-tick units, 60 Hz):
##  * Discrete actions use spend(); it succeeds only if the full cost is available and the
##    fighter is not exhausted. A failed spend changes nothing.
##  * Continuous costs (sprint) use drain(); forced losses (blocking a hit) use lose().
##  * Any spend resets the regeneration delay; regeneration is paused while guarding.
##  * Reaching zero marks the fighter exhausted: nothing can be spent and regeneration waits
##    twice as long, until stamina climbs back above RECOVER_FRACTION of the maximum.

const RECOVER_FRACTION := 0.15

var maximum: float = 100.0
var current: float = 100.0
var regen_per_tick: float = 0.4
var regen_delay_ticks: int = 36
var regen_multiplier: float = 1.0
## The attacker's/defender's stamina rule for this duel (BALANCE.md "Attacker advantage"). `cost_multiplier` scales EVERY cost
## (actions, sprinting, blocking): 0 = free, i.e. unlimited stamina; > 1 = the pool empties faster. `seat_regen` scales regeneration.
## Separate from `regen_multiplier`, which an ability resets every tick.
var cost_multiplier: float = 1.0
var seat_regen: float = 1.0
var exhausted: bool = false
var _delay: int = 0


func setup(max_stamina: float, regen: float, delay_ticks: int) -> void:
	maximum = max_stamina
	current = max_stamina
	regen_per_tick = regen
	regen_delay_ticks = delay_ticks
	regen_multiplier = 1.0
	cost_multiplier = 1.0
	seat_regen = 1.0
	exhausted = false
	_delay = 0


func can_afford(cost: float) -> bool:
	return not exhausted and current >= cost * cost_multiplier


func spend(cost: float) -> bool:
	if not can_afford(cost):
		return false
	current -= cost * cost_multiplier
	_after_loss()
	return true


## Continuous drain. Returns false once the pool is empty.
func drain(amount: float) -> bool:
	if exhausted:
		return false
	current = maxf(0.0, current - amount * cost_multiplier)
	_after_loss()
	return current > 0.0


## Forced loss (for example absorbing a blow). Returns the shortfall that could not be paid.
func lose(amount: float) -> float:
	amount *= cost_multiplier
	var shortfall := maxf(0.0, amount - current)
	current = maxf(0.0, current - amount)
	_after_loss()
	return shortfall


func refund(amount: float) -> void:
	current = minf(maximum, current + amount)
	if exhausted and current >= maximum * RECOVER_FRACTION:
		exhausted = false


func ratio() -> float:
	return current / maximum


func tick(regen_allowed: bool) -> void:
	if _delay > 0:
		_delay -= 1
		return
	if not regen_allowed:
		return
	current = minf(maximum, current + regen_per_tick * regen_multiplier * seat_regen)
	if exhausted and current >= maximum * RECOVER_FRACTION:
		exhausted = false


func _after_loss() -> void:
	_delay = regen_delay_ticks
	if current <= 0.0:
		current = 0.0
		exhausted = true
		_delay = regen_delay_ticks * 2
