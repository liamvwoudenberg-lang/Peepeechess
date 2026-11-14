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


## Radius of the circle that attacks test against: the drawn body (the wider of shoulder half-width and half-depth) plus 5 cm for the
## armour's silhouette. An explicit "hit_radius" in the JSON wins. `fallback` is returned when the role has no entry or "hit": false.
static func hit_radius(role_code: String, fallback: float) -> float:
	var entry: Dictionary = _roles().get(role_code, {})
	if entry.is_empty() or not bool(entry.get("hit", true)):
		return fallback
	if entry.has("hit_radius"):
		return float(entry["hit_radius"])
	var b: Dictionary = role(role_code)["body"]
	return maxf(float(b["shoulder_half_width"]), float(b["half_depth"])) + 0.05


## Sword-tip reach (m, forward of the fighter's origin) at the strike pose of the light / heavy clips, measured by
## combat/tools/paladin_reach.gd with the blade at BLADE_SCALE times a plain sword.
const BLADE_SCALE := 1.25
const MAX_LUNGE := 0.95


static func tip_forward(role_code: String, heavy: bool) -> float:
	var tips: Dictionary = _roles().get(role_code, {}).get("tip_forward", {})
	return float(tips.get("heavy" if heavy else "light", 1.4))


## Presentation-only forward step of the model during a strike so that the DRAWN sword tip reaches the nearest point of a body standing
## at the simulation's maximum hit range: reach + (separation - hit radius) - tip reach - the forward motion the attack already has.
static func lunge(role_code: String, heavy: bool) -> float:
	var sep := float(FighterProfile.for_role(role_code).get("radius", 0.4))
	var front := float(FighterRoster.stats_for(role_code).get("reachM", 1.5)) + (sep - hit_radius(role_code, sep))
	var attack: AttackDefinition = AttackLibrary.heavy(role_code) if heavy else AttackLibrary.light(role_code, 0)
	var forward_motion := attack.forward_motion_m if attack != null else 0.0
	return clampf(front - tip_forward(role_code, heavy) - forward_motion, 0.0, MAX_LUNGE)


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
