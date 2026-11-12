class_name PadMath
extends RefCounted
## Pure, side-effect-free gamepad maths (no Input singleton access), so every number is unit-testable.
##
## Stick: a radial (circular) dead zone with rescaling. The raw vector is read as a whole (never per axis, which
## would make a diagonal "stick" to one axis). Inside `inner` the result is zero; between `inner` and `outer` the
## length ramps 0..1; beyond `outer` it is 1. `outer` < 1 matters because real sticks (DualShock 4 included)
## often cannot reach |v| = 1 on the diagonals. The ramp is shaped with `exponent` (1 = linear, 2 = precise at
## low deflection). The direction is preserved exactly.
##
## Trigger: Schmitt trigger. Engages above `press`, releases below `release` (release < press), so a trigger that
## hovers around the threshold does not chatter.

const DEFAULT_INNER := 0.18  # the constant LocalInputSource has always used (STICK_DEADZONE)
const DEFAULT_OUTER := 0.96
const DEFAULT_TRIGGER_PRESS := 0.5  # the old "sprint when LT > 0.5"
const DEFAULT_TRIGGER_RELEASE := 0.35


static func radial(v: Vector2, inner: float = DEFAULT_INNER, outer: float = DEFAULT_OUTER, exponent: float = 1.0) -> Vector2:
	inner = clampf(inner, 0.0, 0.9)
	outer = clampf(outer, inner + 0.05, 1.0)
	var length := v.length()
	if length <= inner + 0.00001:  # epsilon: a float32 0.18 must still count as 'on the edge'
		return Vector2.ZERO
	var t := clampf((length - inner) / (outer - inner), 0.0, 1.0)
	if exponent != 1.0:
		t = pow(t, clampf(exponent, 0.25, 4.0))
	return v / length * t


## Raw trigger axis -> 0..1. Some drivers rest at -1 (range -1..1), some at 0; negatives are "not pressed".
static func trigger_value(raw: float) -> float:
	return clampf(raw, 0.0, 1.0)


## Stateful press/release detector with hysteresis. `update` returns the new held state.
class Schmitt:
	extends RefCounted
	var press: float
	var release: float
	var held: bool = false

	func _init(p_press: float = DEFAULT_TRIGGER_PRESS, p_release: float = DEFAULT_TRIGGER_RELEASE) -> void:
		set_thresholds(p_press, p_release)

	func set_thresholds(p_press: float, p_release: float) -> void:
		press = clampf(p_press, 0.1, 0.95)
		release = clampf(minf(p_release, press - 0.05), 0.0, press - 0.05)

	## Returns true only on the tick the state flipped from released to held (the "press" edge).
	func update(value: float) -> bool:
		var was := held
		if held:
			if value < release:
				held = false
		elif value > press:
			held = true
		return held and not was

	func reset() -> void:
		held = false
