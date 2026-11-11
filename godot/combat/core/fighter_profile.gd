class_name FighterProfile
extends RefCounted
## Role tuning that the v1 FighterStats contract does not carry (poise, armour, guard, dodge,
## stamina economy). Values are authority-side constants keyed by role; the contract's stats
## (HP, stamina, damage, speed, reach, light/heavy/parry ticks, ability cooldown) always come
## from the BattleRequest, never from here.
##
## Pawn  - fast spear fighter: mobile and cheap to dodge, low poise/HP, no armour.
## Knight - armoured longsword fighter: high poise, damage reduction, strong parries and guard.
## Bishop - arcane spellblade: light armour and poise, evasive (Blink), decent parry riposte.
## Rook   - massive plate, warhammer and tower shield: huge poise, 25% armour, wide guard, weak parry, slow.
## Queen  - dual blades: lowest poise, fast cheap attacks, quick dodge, strong riposte.

static func supports_role(role: String) -> bool:
	return role == "p" or role == "n" or role == "b" or role == "r" or role == "q"


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
		"b":
			return {
				"display": "Bishop", "weapon": "spellblade", "radius": 0.40, "armor": 0.05,
				"poise": 35.0, "poise_regen_delay": 90, "poise_regen_per_tick": 0.25, "stagger_immunity_ticks": 36,
				"sprint_mult": 1.55, "sprint_drain_per_tick": 0.2,
				"stamina_regen_per_tick": 0.42, "stamina_regen_delay": 38,
				"block_arc_deg": 115.0, "block_cost_mult": 1.1, "block_move_mult": 0.5, "guardbreak_stun": 52,
				"parry_arc_deg": 125.0, "parry_cost": 10.0, "parry_recovery_ticks": 15, "parry_cooldown_ticks": 17,
				"parry_stagger_ticks": 40, "parry_refund": 9.0, "riposte_ticks": 50, "riposte_mult": 1.3,
				"dodge_cost": 20.0, "dodge_ticks": 24, "dodge_distance": 3.4, "dodge_iframe_start": 3, "dodge_iframe_end": 14,
				"dodge_cooldown_ticks": 9, "hit_react_ticks": 9,
			}
		"r":
			return {
				"display": "Rook", "weapon": "warhammer", "radius": 0.50, "armor": 0.25,
				"poise": 110.0, "poise_regen_delay": 110, "poise_regen_per_tick": 0.35, "stagger_immunity_ticks": 40,
				"sprint_mult": 1.3, "sprint_drain_per_tick": 0.26,
				"stamina_regen_per_tick": 0.35, "stamina_regen_delay": 44,
				"block_arc_deg": 150.0, "block_cost_mult": 0.55, "block_move_mult": 0.4, "guardbreak_stun": 60,
				"parry_arc_deg": 110.0, "parry_cost": 12.0, "parry_recovery_ticks": 18, "parry_cooldown_ticks": 20,
				"parry_stagger_ticks": 38, "parry_refund": 6.0, "riposte_ticks": 50, "riposte_mult": 1.3,
				"dodge_cost": 28.0, "dodge_ticks": 30, "dodge_distance": 2.4, "dodge_iframe_start": 5, "dodge_iframe_end": 14,
				"dodge_cooldown_ticks": 14, "hit_react_ticks": 6,
			}
		"q":
			return {
				"display": "Queen", "weapon": "dual blades", "radius": 0.40, "armor": 0.06,
				"poise": 28.0, "poise_regen_delay": 80, "poise_regen_per_tick": 0.25, "stagger_immunity_ticks": 30,
				"sprint_mult": 1.65, "sprint_drain_per_tick": 0.21,
				"stamina_regen_per_tick": 0.46, "stamina_regen_delay": 34,
				"block_arc_deg": 105.0, "block_cost_mult": 1.3, "block_move_mult": 0.5, "guardbreak_stun": 48,
				"parry_arc_deg": 125.0, "parry_cost": 10.0, "parry_recovery_ticks": 14, "parry_cooldown_ticks": 16,
				"parry_stagger_ticks": 42, "parry_refund": 9.0, "riposte_ticks": 52, "riposte_mult": 1.35,
				"dodge_cost": 16.0, "dodge_ticks": 20, "dodge_distance": 3.9, "dodge_iframe_start": 3, "dodge_iframe_end": 13,
				"dodge_cooldown_ticks": 7, "hit_react_ticks": 9,
			}
	return {}
