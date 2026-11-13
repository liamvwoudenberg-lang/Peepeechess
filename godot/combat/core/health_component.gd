class_name HealthComponent
extends RefCounted
## Integer hit points. Integers keep the "higher HP percentage wins" timeout rule exact
## (cross-multiplication, CONTRACTS.md rule 7) and make results independent of float rounding.

signal changed(current: int, maximum: int)
signal depleted

var maximum: int = 1
var current: int = 1
## Fractional damage not yet taken off (see apply_scaled).
var _carry: float = 0.0


func setup(max_hp: float) -> void:
	maximum = maxi(1, roundi(max_hp))
	current = maximum
	_carry = 0.0


## Applies damage that is not a whole number of hit points (the duel-length scale, BALANCE.md "Duel length"): the fraction is carried
## to the next blow, so the total over a fight is exact and HP stays an integer in the contract's units. Returns the whole HP removed
## by THIS blow (0 for a graze that only builds up the carry).
func apply_scaled(amount: float) -> int:
	if current <= 0 or amount <= 0.0:
		return 0
	_carry += amount
	var whole := int(floor(_carry + 0.000001))
	_carry = maxf(0.0, _carry - float(whole))
	return apply_damage(whole)


## Applies already-calculated damage; returns the HP actually removed.
func apply_damage(amount: int) -> int:
	if current <= 0 or amount <= 0:
		return 0
	var dealt: int = mini(amount, current)
	current -= dealt
	changed.emit(current, maximum)
	if current == 0:
		depleted.emit()
	return dealt


func heal(amount: int) -> int:
	if current <= 0 or amount <= 0:
		return 0
	var healed: int = mini(amount, maximum - current)
	current += healed
	if healed > 0:
		changed.emit(current, maximum)
	return healed


func is_alive() -> bool:
	return current > 0


func ratio() -> float:
	return float(current) / float(maximum)


## True when current HP is at or below the given fraction of maximum.
func at_or_below(fraction: float) -> bool:
	return float(current) <= float(maximum) * fraction
