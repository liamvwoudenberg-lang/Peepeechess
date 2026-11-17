extends SceneTree
## Validates the tuning files and prints the stamp.
##
##   godot --headless --path godot --script res://tools/config_check.gd
##
## Prints: the tuning stamp (what online play compares), whether a development override is active, the per-role summary, the
## attacker matrix and any problem (errors name the file, key path, value, range and unit). Exit code 1 on any error, so it can
## run in CI and as a pre-commit check.
const Balance := preload("res://combat/data/balance_data.gd")
const Tools := preload("res://config/config_tools.gd")


func _initialize() -> void:
	await process_frame
	var failures := 0
	var raw: Dictionary = Tools.read_json(Balance.DATA_PATH)
	if raw.is_empty():
		print("FAIL %s is missing or not valid JSON" % Balance.SOURCE_LABEL)
		quit(1)
		return
	var errors: Array = Balance.validate(raw)
	if errors.is_empty():
		print("OK   %s is valid" % Balance.SOURCE_LABEL)
	else:
		failures += errors.size()
		for message in errors:
			print("FAIL " + String(message))
	print("tuning id:    %s" % Balance.tuning_id())
	print("tuning stamp: %s   (client and server must show the same stamp)" % Balance.stamp())
	print("override:     %s" % ("ACTIVE (development only; online play is refused)" if Balance.is_overridden() else "none"))
	var override_path := Balance.dev_override_file()
	if FileAccess.file_exists(override_path):
		print("override file: %s (%s)" % [override_path, "applied" if Balance.is_overridden() else "NOT applied: " + "; ".join(Balance.dev_override_errors())])
		if not Balance.dev_override_errors().is_empty():
			failures += Balance.dev_override_errors().size()
	for role in Balance.roles():
		var p := Balance.profile(role)
		var tables := Balance.attack_tables(role)
		print("  role %s (%s): poise %s, armor %s, light chain %d, abilities %d" % [role, p.get("display", "?"), p.get("poise"), p.get("armor"), (tables["light"] as Array).size(), (tables["abilities"] as Dictionary).size()])
	var pace := Balance.pacing()
	print("pacing:       comeback x%s below %s%% health gap, sudden death after %s s (+%s%%/s)" % [pace["comeback"]["damage_mult"], int(float(pace["comeback"]["hp_gap"]) * 100.0), pace["sudden_death"]["start_s"], int(float(pace["sudden_death"]["ramp_per_s"]) * 100.0)])
	var stun := Balance.hit_stun()
	print("hit stun:     light x%s, heavy x%s, ability x%s" % [stun["light_mult"], stun["heavy_mult"], stun["ability_mult"]])
	print("attacker edge (attacker x / defender x), rows attack, columns defend:")
	var header := "       "
	for d in "pnbrq":
		header += "   %s      " % d
	print(header)
	for a in "pnbrq":
		var line := "  %s    " % a
		for d in "pnbrq":
			var pair := Balance.attacker_edge(a, d)
			line += " %4.2f/%4.2f" % [pair[0], pair[1]]
		print(line)
	var rules_errors := _check_chess_rules()
	failures += rules_errors
	print("RESULT: %s" % ("PASS" if failures == 0 else "FAIL (%d problem(s))" % failures))
	quit(0 if failures == 0 else 1)


func _check_chess_rules() -> int:
	var Rules = load("res://config/chess_rules.gd")
	if Rules == null:
		return 0
	var errors: Array = Rules.validate(Tools.read_json(Rules.DATA_PATH))
	if errors.is_empty():
		print("OK   %s is valid (%d time controls, %d computer levels, %d campaign boons)" % [Rules.SOURCE_LABEL, Rules.time_controls().size(), Rules.computer_levels().size(), Rules.campaign_boons().size()])
	else:
		for message in errors:
			print("FAIL " + String(message))
	return errors.size()
