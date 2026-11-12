class_name HealthComponent
extends RefCounted
## Integer hit points. Integers keep the "higher HP percentage wins" timeout rule exact
## (cross-multiplication, CONTRACTS.md rule 7) and make results independent of float rounding.

signal changed(current: int, maximum: int)
signal depleted

var maximum: int = 1
var current: int = 1


func setup(max_hp: float) -> void:
	maximum = maxi(1, roundi(max_hp))
	current = maximum


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
