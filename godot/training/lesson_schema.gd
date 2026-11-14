class_name LessonSchema
extends RefCounted
## Validation of one lesson dictionary (the JSON files in res://training/lessons/). `validate()` returns human-readable problems; an
## empty array means the lesson is valid. Format documentation: docs/application/TRAINING.md.

const CATEGORIES := ["beginner", "intermediate", "advanced", "expert"]
const OBJECTIVE_TYPES := ["move_distance", "hit_count", "hit_at_range", "combo", "block_n", "parry_n", "dodge_n", "counter_after", "punish",
		"ability_use", "cancel", "stamina_cycle", "hold_distance", "survive", "win", "win_clean", "stun", "stun_followup"]
const FAIL_TYPES := ["time_limit", "hits_taken", "damage_fraction"]
const RATING_KEYS := ["max_seconds", "max_hits_taken", "min_combo", "min_parries", "max_damage_fraction"]
## Objective type -> the parameter that must be present.
const REQUIRED_PARAM := {"move_distance": "meters", "hit_count": "count", "hit_at_range": "count", "combo": "count", "block_n": "count",
		"parry_n": "count", "dodge_n": "count", "counter_after": "count", "punish": "count", "ability_use": "count", "cancel": "count",
		"hold_distance": "seconds", "survive": "seconds", "stun": "count", "stun_followup": "count"}


static func validate(lesson: Dictionary) -> Array:
	var problems: Array = []
	var id := String(lesson.get("id", ""))
	if id == "" or not id.is_valid_identifier():
		problems.append("id must be a non-empty identifier (letters, digits, underscore): '%s'" % id)
	for key in ["title", "summary"]:
		if String(lesson.get(key, "")) == "":
			problems.append("%s: missing %s" % [id, key])
	if not (String(lesson.get("category", "")) in CATEGORIES):
		problems.append("%s: category must be one of %s" % [id, str(CATEGORIES)])
	for key in ["player_role", "opponent_role"]:
		if not (String(lesson.get(key, "")) in FighterRoster.ALL_ROLES):
			problems.append("%s: %s must be one of %s" % [id, key, str(FighterRoster.ALL_ROLES)])
	if not (String(lesson.get("behaviour", "")) in AIDifficulty.BEHAVIOURS):
		problems.append("%s: behaviour must be one of %s" % [id, str(AIDifficulty.BEHAVIOURS)])
	if not (String(lesson.get("difficulty", "normal")) in AIDifficulty.LEVELS):
		problems.append("%s: difficulty must be one of %s" % [id, str(AIDifficulty.LEVELS)])
	if not (String(lesson.get("attacker", "player")) in ["player", "opponent"]):
		problems.append("%s: attacker must be 'player' or 'opponent'" % id)
	if not lesson.has("order") or typeof(lesson["order"]) not in [TYPE_INT, TYPE_FLOAT]:
		problems.append("%s: order (number) is required" % id)
	if lesson.has("available") and not bool(lesson["available"]) and String(lesson.get("unavailable_reason", "")) == "":
		problems.append("%s: an unavailable lesson needs an unavailable_reason" % id)
	var available := bool(lesson.get("available", true))
	var objectives: Array = lesson.get("objectives", [])
	if available and objectives.is_empty():
		problems.append("%s: an available lesson needs objectives" % id)
	var seen := {}
	for o in objectives:
		if not (o is Dictionary):
			problems.append("%s: objective is not an object" % id)
			continue
		var oid := String(o.get("id", ""))
		var type := String(o.get("type", ""))
		if oid == "" or seen.has(oid):
			problems.append("%s: objective id missing or duplicate: '%s'" % [id, oid])
		seen[oid] = true
		if not (type in OBJECTIVE_TYPES):
			problems.append("%s/%s: unknown objective type '%s'" % [id, oid, type])
			continue
		if REQUIRED_PARAM.has(type) and float(o.get(REQUIRED_PARAM[type], 0)) <= 0.0:
			problems.append("%s/%s: %s needs a positive '%s'" % [id, oid, type, REQUIRED_PARAM[type]])
		if type == "counter_after" and not (String(o.get("after", "")) in ["block", "parry", "dodge"]):
			problems.append("%s/%s: counter_after needs after = block|parry|dodge" % [id, oid])
		if type == "hold_distance" and float(o.get("max", 0.0)) <= float(o.get("min", 0.0)):
			problems.append("%s/%s: hold_distance needs max > min" % [id, oid])
		if String(o.get("text", "")) == "":
			problems.append("%s/%s: objective needs display text" % [id, oid])
	for rule in lesson.get("fail", []):
		if not (String(rule.get("type", "")) in FAIL_TYPES):
			problems.append("%s: unknown fail rule '%s'" % [id, String(rule.get("type", ""))])
	var rating: Dictionary = lesson.get("rating", {})
	for tier in rating:
		if not (String(tier) in ["silver", "gold"]):
			problems.append("%s: rating tiers are silver and gold (bronze = completed)" % id)
		for key in rating[tier]:
			if not (String(key) in RATING_KEYS):
				problems.append("%s: unknown rating threshold '%s'" % [id, String(key)])
	var constraints: Dictionary = lesson.get("constraints", {})
	if constraints.has("player_hp_fraction") and not (float(constraints["player_hp_fraction"]) > 0.0 and float(constraints["player_hp_fraction"]) <= 1.0):
		problems.append("%s: constraints.player_hp_fraction must be in (0, 1]" % id)
	if lesson.has("requires") and not (lesson["requires"] is Array):
		problems.append("%s: requires must be a list of lesson ids" % id)
	return problems
