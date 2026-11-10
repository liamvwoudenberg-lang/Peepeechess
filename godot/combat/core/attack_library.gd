class_name AttackLibrary
extends RefCounted
## Per-role attack tables. These are *initial tuning values*, not measured balance.
## Timings scale off the FighterStats the authority supplies (lightTicks, heavyTicks); the
## relative shapes (windows, damage multipliers, costs) live here.

static var _cache: Dictionary = {}


static func supports_role(role: String) -> bool:
	return role == "p" or role == "n"


static func for_role(role: String) -> Dictionary:
	if not _cache.has(role):
		match role:
			"p":
				_cache[role] = _pawn()
			"n":
				_cache[role] = _knight()
			_:
				return {}
	return _cache[role]


## Light attack for the given 0-based chain index.
static func light(role: String, index: int) -> AttackDefinition:
	return for_role(role)["light"][clampi(index, 0, CombatConstants.COMBO_LENGTH - 1)]


static func heavy(role: String) -> AttackDefinition:
	return for_role(role)["heavy"]


## Attack executed by an attack-type ability, or null.
static func ability_attack(role: String, ability_id: String) -> AttackDefinition:
	return for_role(role)["abilities"].get(ability_id, null)


static func _atk(props: Dictionary) -> AttackDefinition:
	var def := AttackDefinition.new()
	for key in props:
		def.set(key, props[key])
	return def


static func _pawn() -> Dictionary:
	# Spear: long reach, narrow thrusts, a sweeping finisher. Fast and light.
	return {
		"light": [
			_atk({id = "pawn.light.1", kind = AttackDefinition.Kind.LIGHT, combo_index = 0, animation = "thrust",
				ticks_scale = 1.0, startup_end = 0.30, active_end = 0.50, cancel_from = 0.72,
				damage_mult = 1.0, arc_degrees = 36.0, stamina_cost = 10.0, poise_damage = 9.0,
				hitstun_ticks = 12, knockback_m = 0.25, forward_motion_m = 0.35, motion_start = 0.15, motion_end = 0.40}),
			_atk({id = "pawn.light.2", kind = AttackDefinition.Kind.LIGHT, combo_index = 1, animation = "thrust_low",
				ticks_scale = 0.95, startup_end = 0.30, active_end = 0.50, cancel_from = 0.72,
				damage_mult = 1.1, arc_degrees = 36.0, stamina_cost = 11.0, poise_damage = 9.0,
				hitstun_ticks = 12, knockback_m = 0.25, forward_motion_m = 0.35, motion_start = 0.15, motion_end = 0.40}),
			_atk({id = "pawn.light.3", kind = AttackDefinition.Kind.LIGHT, combo_index = 2, animation = "sweep",
				ticks_scale = 1.35, startup_end = 0.38, active_end = 0.58, cancel_from = 0.92,
				damage_mult = 1.45, arc_degrees = 100.0, stamina_cost = 16.0, poise_damage = 24.0,
				hitstun_ticks = 22, knockback_m = 0.7, forward_motion_m = 0.5, motion_start = 0.2, motion_end = 0.5}),
		],
		"heavy": _atk({id = "pawn.heavy", kind = AttackDefinition.Kind.HEAVY, combo_index = 0, animation = "lunge_thrust",
			ticks_scale = 1.0, startup_end = 0.50, active_end = 0.64, cancel_from = 0.95,
			damage_mult = 2.0, arc_degrees = 50.0, stamina_cost = 26.0, poise_damage = 32.0,
			hitstun_ticks = 30, guard_cost_mult = 1.8, knockback_m = 0.9,
			forward_motion_m = 0.9, motion_start = 0.35, motion_end = 0.55}),
		"abilities": {},
	}


static func _knight() -> Dictionary:
	# Longsword: wider arcs, heavier hits, armoured finisher/heavy, and the committed lunge.
	return {
		"light": [
			_atk({id = "knight.light.1", kind = AttackDefinition.Kind.LIGHT, combo_index = 0, animation = "slash_right",
				ticks_scale = 1.0, startup_end = 0.38, active_end = 0.58, cancel_from = 0.75,
				damage_mult = 1.0, arc_degrees = 100.0, stamina_cost = 14.0, poise_damage = 18.0,
				hitstun_ticks = 16, knockback_m = 0.35, forward_motion_m = 0.25, motion_start = 0.2, motion_end = 0.45}),
			_atk({id = "knight.light.2", kind = AttackDefinition.Kind.LIGHT, combo_index = 1, animation = "slash_left",
				ticks_scale = 0.95, startup_end = 0.38, active_end = 0.58, cancel_from = 0.75,
				damage_mult = 1.1, arc_degrees = 100.0, stamina_cost = 15.0, poise_damage = 18.0,
				hitstun_ticks = 16, knockback_m = 0.35, forward_motion_m = 0.25, motion_start = 0.2, motion_end = 0.45}),
			_atk({id = "knight.light.3", kind = AttackDefinition.Kind.LIGHT, combo_index = 2, animation = "overhead",
				ticks_scale = 1.3, startup_end = 0.45, active_end = 0.62, cancel_from = 0.92,
				damage_mult = 1.45, arc_degrees = 130.0, stamina_cost = 20.0, poise_damage = 34.0,
				hitstun_ticks = 26, knockback_m = 0.8, forward_motion_m = 0.45, motion_start = 0.25, motion_end = 0.55,
				armor_start = 0.35, armor_end = 0.62}),
		],
		"heavy": _atk({id = "knight.heavy", kind = AttackDefinition.Kind.HEAVY, combo_index = 0, animation = "overhead_smash",
			ticks_scale = 1.0, startup_end = 0.55, active_end = 0.67, cancel_from = 0.95,
			damage_mult = 2.0, arc_degrees = 90.0, stamina_cost = 32.0, poise_damage = 55.0,
			hitstun_ticks = 34, guard_cost_mult = 1.8, knockback_m = 1.0,
			forward_motion_m = 0.7, motion_start = 0.4, motion_end = 0.6, armor_start = 0.30, armor_end = 0.67}),
		"abilities": {
			"lunging-strike": _atk({id = "knight.lunging-strike", kind = AttackDefinition.Kind.ABILITY, combo_index = 0,
				animation = "lunge", absolute_ticks = 72, startup_end = 0.45, active_end = 0.62, cancel_from = 1.0,
				damage_mult = 2.2, reach_mult = 1.2, arc_degrees = 50.0, stamina_cost = 28.0, poise_damage = 60.0,
				hitstun_ticks = 40, guard_cost_mult = 2.0, knockback_m = 1.4,
				forward_motion_m = 4.2, motion_start = 0.30, motion_end = 0.55, armor_start = 0.0, armor_end = 0.62}),
		},
	}
