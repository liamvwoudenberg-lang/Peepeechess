class_name NetworkRateBudget
extends RefCounted
var rate: float
var capacity: float
var tokens: float
var updated: int
func _init(per_second: float, burst: float, now: int) -> void:
	rate = per_second
	capacity = burst
	tokens = burst
	updated = now
func take(now: int, cost: float = 1.0) -> bool:
	tokens = minf(capacity, tokens + maxf(0, now - updated) * rate / 1000.0)
	updated = now
	if cost > tokens:
		return false
	tokens -= cost
	return true
