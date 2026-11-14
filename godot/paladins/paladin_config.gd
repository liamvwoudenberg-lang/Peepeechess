class_name PaladinConfig
extends RefCounted
## Reads godot/paladins/paladin_configs.json: per-role presentation data of the paladin models (height, measured body, arm and blade
## length, which animation groups are still procedural). One reusable loader; PaladinFighter takes its heights from here.
##   PaladinConfig.height("n")            standing height in metres
##   PaladinConfig.body_radius("n")       visible body radius (mean of half-width and half-depth), metres
##   PaladinConfig.visual_reach("n")      shoulder-to-sword-tip reach of the drawn character, metres (arm + blade)
##   PaladinConfig.audit("n")             {sim_radius, body_radius, radius_ratio, sim_reach, visual_reach, reach_gap}: how the
##                                         simulation's hurt circle and reach compare with what is drawn (balance data is unchanged)
const PATH := "res://paladins/paladin_configs.json"
const DEFAULTS := {"height": 1.7, "body": {"shoulder_half_width": 0.17, "waist_half_width": 0.15, "half_depth": 0.16}, "arm_length": 0.4, "blade_length": 0.86}

static var _data: Dictionary = {}


static func _roles() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = parsed if parsed is Dictionary else {"roles": {}}
	return _data.get("roles", {})


static func role(role_code: String) -> Dictionary:
	var merged: Dictionary = DEFAULTS.duplicate(true)
	merged.merge(_roles().get(role_code, {}), true)
	return merged


static func height(role_code: String) -> float:
	return float(role(role_code)["height"])


static func body_radius(role_code: String) -> float:
	var b: Dictionary = role(role_code)["body"]
	return 0.5 * (float(b["shoulder_half_width"]) + float(b["half_depth"]))


static func visual_reach(role_code: String) -> float:
	var r := role(role_code)
	return float(r["arm_length"]) + float(r["blade_length"])


## Roles that have a config entry.
static func roles() -> Array:
	return _roles().keys()


static func audit(role_code: String) -> Dictionary:
	var sim_radius := float(FighterProfile.for_role(role_code).get("radius", 0.4))
	var sim_reach := float(FighterRoster.stats_for(role_code).get("reachM", 1.5))
	var body := body_radius(role_code)
	var visual := visual_reach(role_code)
	return {"sim_radius": sim_radius, "body_radius": body, "radius_ratio": sim_radius / maxf(body, 0.01),
			"sim_reach": sim_reach, "visual_reach": visual, "reach_gap": sim_reach - visual}
