class_name FighterProfile
extends RefCounted
## Role tuning that the v1 FighterStats contract does not carry (poise, armour, guard, dodge,
## stamina economy). Values are authority-side constants keyed by role; the contract's stats
## (HP, stamina, damage, speed, reach, light/heavy/parry ticks, ability cooldown) always come
## from the BattleRequest, never from here.
##
## Pawn  - fast spear fighter: mobile and cheap to dodge, low poise/HP, no armour.
## Knight - armoured longsword fighter: high poise, damage reduction, strong parries and guard.

static func supports_role(role: String) -> bool:
	return role == "p" or role == "n"


static func for_role(role: String) -> Dictionary:
	match role:
		"p":
			return {
				"display": "Pawn", "weapon": "spear", "radius": 0.38, "armor": 0.0,
				"poise": 30.0, "poise_regen_delay": 90, "poise_regen_per_tick": 0.25, "stagger_immunity_ticks": 36,
				"sprint_mult": 1.6, "sprint_drain_per_tick": 0.2,
				"stamina_regen_per_tick": 0.45, "stamina_regen_delay": 36,
				"block_arc_deg": 110.0, "block_cost_mult": 1.35, "block_move_mult": 0.5, "guardbreak_stun": 50,
				"parry_arc_deg": 120.0, "parry_cost": 10.0, "parry_recovery_ticks": 16, "parry_cooldown_ticks": 18,
				"parry_stagger_ticks": 34, "parry_refund": 8.0, "riposte_ticks": 48, "riposte_mult": 1.25,
				"dodge_cost": 18.0, "dodge_ticks": 22, "dodge_distance": 3.8, "dodge_iframe_start": 3, "dodge_iframe_end": 14,
				"dodge_cooldown_ticks": 8, "hit_react_ticks": 9,
			}
		"n":
			return {
				"display": "Knight", "weapon": "longsword", "radius": 0.45, "armor": 0.12,
				"poise": 70.0, "poise_regen_delay": 100, "poise_regen_per_tick": 0.3, "stagger_immunity_ticks": 36,
				"sprint_mult": 1.45, "sprint_drain_per_tick": 0.24,
				"stamina_regen_per_tick": 0.4, "stamina_regen_delay": 40,
				"block_arc_deg": 130.0, "block_cost_mult": 0.8, "block_move_mult": 0.45, "guardbreak_stun": 56,
				"parry_arc_deg": 140.0, "parry_cost": 10.0, "parry_recovery_ticks": 14, "parry_cooldown_ticks": 16,
				"parry_stagger_ticks": 60, "parry_refund": 14.0, "riposte_ticks": 60, "riposte_mult": 1.6,
				"dodge_cost": 24.0, "dodge_ticks": 26, "dodge_distance": 3.0, "dodge_iframe_start": 4, "dodge_iframe_end": 14,
				"dodge_cooldown_ticks": 10, "hit_react_ticks": 8,
			}
	return {}
