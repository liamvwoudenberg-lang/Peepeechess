extends RefCounted
## The configuration layer (godot/config/): balance.json + chess_rules.json, their metadata, strict validation with readable
## errors, comment keys, the compact attacker matrix, the debug-only override (and its release/online refusal), the
## typed rule getters (equal to the constants they replaced) and the generated reference documents.

const Balance := preload("res://combat/data/balance_data.gd")
const ChessRules := preload("res://config/chess_rules.gd")
const Reference := preload("res://config/config_reference.gd")
const Tools := preload("res://config/config_tools.gd")

const TEMP_OVERRIDE := "user://config_test_override.json"


static func run(h, _tree: SceneTree) -> void:
	_balance_file(h)
	_balance_errors(h)
	_comments_and_matrix(h)
	_override(h)
	_rules_file(h)
	_rules_errors(h)
	_rules_override(h)
	_docs(h)
	_tools(h)
	_panel(h)


static func _balance_file(h) -> void:
	h.begin("config/balance.json: lives in config/, validates against its metadata, stamp unchanged by the move")
	h.check(FileAccess.file_exists("res://config/balance.json"), "the balance data is godot/config/balance.json")
	h.check(not FileAccess.file_exists("res://combat/data/balance_v1.json"), "the old location is gone (one source of truth)")
	var raw: Dictionary = Tools.read_json("res://config/balance.json")
	h.check(Balance.validate(raw).is_empty(), "the shipped file has no validation errors (types, ranges, unknown keys): %s" % str(Balance.validate(raw)))
	h.eq(Balance.stamp_of(raw), Balance.stamp(), "stamp_of(file) equals the loaded stamp")
	h.eq(Balance.stamp(), "balance-v1:7a1e47e27f4d0966", "the stamp is byte-for-byte the one before the config migration (pure refactor)")


static func _balance_errors(h) -> void:
	h.begin("config/balance.json: errors name the file, the key path, the value, the range and the unit")
	var data: Dictionary = Tools.read_json("res://config/balance.json")
	var bad := data.duplicate(true)
	bad["profiles"]["n"]["armor"] = -0.3
	var errors: Array = Balance.validate(bad)
	h.check(errors.has("config/balance.json: profiles.n.armor = -0.3 is below the minimum 0 (unit: fraction)"), "below-minimum message: %s" % str(errors))
	bad = data.duplicate(true)
	bad["profiles"]["q"]["poise"] = 99999.0
	errors = Balance.validate(bad)
	h.check(errors.has("config/balance.json: profiles.q.poise = 99999 is above the maximum 400 (unit: poise points)"), "above-maximum message: %s" % str(errors))
	bad = data.duplicate(true)
	var armour: float = bad["profiles"]["p"]["armor"]
	bad["profiles"]["p"].erase("armor")
	bad["profiles"]["p"]["armour"] = armour
	errors = Balance.validate(bad)
	var typo_found := false
	for message in errors:
		if String(message).contains("profiles.p.armour is not a known setting") and String(message).contains("did you mean armor?"):
			typo_found = true
	h.check(typo_found, "a typo'd key is refused with a suggestion: %s" % str(errors))
	bad = data.duplicate(true)
	bad["attacks"]["n"]["heavy"]["hitstun_ticks"] = 12.5
	errors = Balance.validate(bad)
	var whole := false
	for message in errors:
		if String(message).contains("attacks.n.heavy.hitstun_ticks = 12.5 must be a whole number"):
			whole = true
	h.check(whole, "a tick count must be a whole number: %s" % str(errors))
	bad = data.duplicate(true)
	bad["hit_stun"]["heavy_mult"] = 9.0
	errors = Balance.validate(bad)
	var stun := false
	for message in errors:
		if String(message).contains("hit_stun.heavy_mult"):
			stun = true
	h.check(stun, "global blocks are range-checked too")


static func _comments_and_matrix(h) -> void:
	h.begin("config/balance.json: comment keys (underscore) and the compact attacker matrix do not change the tuning")
	var data: Dictionary = Tools.read_json("res://config/balance.json")
	var commented := data.duplicate(true)
	commented["_note"] = "a designer's remark"
	commented["profiles"]["p"]["_why"] = "Pawn is scrappy"
	commented["attacks"]["n"]["heavy"]["_why"] = "telegraphed lunge"
	h.check(Balance.validate(commented).is_empty(), "comments are accepted anywhere")
	h.eq(Balance.stamp_of(commented), Balance.stamp(), "comments do not change the tuning stamp")
	var matrix: Dictionary = data["attacker_edge"]["matrix"]
	var mismatches := 0
	for attacker in matrix:
		for defender in matrix[attacker]:
			var pair: Array = Balance.attacker_edge(attacker, defender)
			var cell: Array = matrix[attacker][defender]
			if absf(pair[0] - float(cell[0])) > 0.00001 or absf(pair[1] - float(cell[1])) > 0.00001:
				mismatches += 1
	h.eq(mismatches, 0, "every matrix cell [attacker][defender] equals Balance.attacker_edge(attacker, defender)")
	h.eq(matrix.size(), 5, "five attacker rows")
	var legacy := data.duplicate(true)
	var pairs := {}
	for attacker in matrix:
		for defender in matrix[attacker]:
			pairs[attacker + defender] = matrix[attacker][defender]
	legacy["attacker_edge"].erase("matrix")
	legacy["attacker_edge"]["pairs"] = pairs
	h.eq(Balance.stamp_of(legacy), Balance.stamp(), "the older flat `pairs` form is still accepted and hashes identically")


static func _override(h) -> void:
	h.begin("balance override: debug builds only, changes the stamp, refused in release builds and online/ranked matches")
	var shipped := Balance.stamp()
	_write_temp({"profiles": {"n": {"armor": 0.3}}})
	h.check(not Balance.load_override_from(TEMP_OVERRIDE, false), "a release build ignores the override file")
	h.check(not Balance.is_overridden() and Balance.stamp() == shipped, "...and nothing changed (stamp %s)" % Balance.stamp())
	h.check(Balance.load_override_from(TEMP_OVERRIDE, true), "a debug build applies it")
	h.check(Balance.is_overridden(), "the override is active")
	h.check(Balance.stamp() != shipped, "an override changes the tuning stamp (so a server/client mismatch is visible): %s" % Balance.stamp())
	h.check(Balance.stamp().contains("+override"), "the stamp says +override")
	h.near(float(Balance.profile("n")["armor"]), 0.3, 0.00001, "the changed number is served")
	Balance.lock_for_online()
	h.check(not Balance.is_overridden() and Balance.stamp() == shipped, "starting an online/ranked match clears the override: back to the shipped stamp")
	h.check(not Balance.dev_overrides_allowed(true), "while locked even a debug build refuses overrides")
	h.check(not Balance.load_override_from(TEMP_OVERRIDE, true), "...so the file is not applied during an online match")
	Balance.unlock_online()
	_write_temp({"profiles": {"n": {"armor": -5.0}}})
	h.check(not Balance.load_override_from(TEMP_OVERRIDE, true), "an invalid override is not applied")
	h.check(not Balance.dev_override_errors().is_empty() and String(Balance.dev_override_errors()[0]).contains("profiles.n.armor"), "its errors are kept: %s" % str(Balance.dev_override_errors()))
	h.check(not Balance.is_overridden(), "nothing leaked from the invalid file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_OVERRIDE))
	Balance.clear_override()
	h.eq(Balance.stamp(), shipped, "cleared: shipped stamp again")


static func _write_temp(patch: Dictionary) -> void:
	var file := FileAccess.open(TEMP_OVERRIDE, FileAccess.WRITE)
	file.store_string(JSON.stringify(patch))
	file.close()


static func _rules_file(h) -> void:
	h.begin("config/chess_rules.json: validates; the typed getters equal the constants they replaced")
	var raw: Dictionary = Tools.read_json(ChessRules.DATA_PATH)
	h.check(ChessRules.validate(raw).is_empty(), "the shipped rules file has no validation errors: %s" % str(ChessRules.validate(raw)))
	var times := ChessRules.time_controls()
	h.eq(times.size(), 5, "five time controls")
	h.eq(times[0], ["3 + 2 · Blitz", 180000, 2000], "3 + 2 Blitz")
	h.eq(times[3], ["15 + 10 · Rapid", 900000, 10000], "15 + 10 Rapid")
	h.eq(times[4], ["30 + 0 · Classical", 1800000, 0], "30 + 0 Classical")
	var levels := ChessRules.computer_levels()
	h.eq(levels.keys(), [1, 2, 3, 4, 5, 6], "computer levels are numbered 1..6 (integer keys)")
	h.eq(levels[3], {"name": "Club", "max_depth": 3, "q_ply": 4, "node_limit": 4000, "time_ms": 1000, "noise": 25, "margin": 110, "blunder": 0.04, "skill": 0.55, "style": "balanced", "attack_style": "balanced"}, "level 3 (Club) is unchanged")
	h.eq(levels[6]["max_depth"], 12, "level 6 searches 12 plies")
	h.eq(ChessRules.min_computer_level(), 1, "min level")
	h.eq(ChessRules.max_computer_level(), 6, "max level")
	var duel := ChessRules.duel_ai_levels()
	h.eq(duel.keys(), ["easy", "normal", "hard", "expert"], "four duel AI levels")
	h.eq(duel["easy"]["params"]["react_extra"], 16, "easy reacts 16 ticks late (int)")
	h.near(float(duel["hard"]["params"]["error_rate"]), 0.06, 0.00001, "hard error rate")
	h.eq(ChessRules.battle_fight_value()["q"], 900, "queen fight value")
	h.near(float(ChessRules.battle_tier()["n"]), 2.0, 0.00001, "knight tier")
	h.eq(ChessRules.royal_piece_values(), {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9}, "royal piece order values")
	h.eq(ChessRules.campaign_start_lives(), 3, "three lives")
	h.eq(ChessRules.campaign_max_boon_stack(), 2, "boons stack twice")
	h.eq(ChessRules.campaign_boon_offer_size(), 3, "three boons offered")
	h.eq(ChessRules.campaign_level_by_encounter().size(), 12, "twelve encounters")
	h.eq(ChessRules.campaign_boons().size(), 5, "five boons")
	h.near(float(ChessRules.campaign_boons()["efficiency"]["cost"]), 0.85, 0.00001, "efficiency boon cost")
	h.eq(ChessRules.training_combo_window_ticks(), 78, "combo window")
	h.eq(ChessRules.training_default_counter_window_ticks(), 90, "counter window")
	h.eq(ChessRules.training_whiff_punish_window_ticks(), 70, "whiff-punish window")
	h.eq(ChessRules.training_max_lesson_ticks(), 6000, "lesson time limit")
	var consumer_levels = load("res://chess/ai/chess_ai.gd").LEVELS
	h.eq(consumer_levels[2]["name"], "Casual", "the chess AI reads its levels from the config")
	h.eq(load("res://campaign/campaign_run.gd").START_LIVES, 3, "the campaign reads its lives from the config")


static func _rules_errors(h) -> void:
	h.begin("config/chess_rules.json: errors name the file, the key path, the value, the range and the unit")
	var data: Dictionary = Tools.read_json(ChessRules.DATA_PATH)
	var bad := data.duplicate(true)
	bad["computer_levels"]["3"]["max_depth"] = 0
	var errors: Array = ChessRules.validate(bad)
	h.check(errors.has("config/chess_rules.json: computer_levels.3.max_depth = 0 is below the minimum 1 (unit: plies)"), "below-minimum message: %s" % str(errors))
	bad = data.duplicate(true)
	bad["time_controls"][0]["initial_ms"] = 5
	errors = ChessRules.validate(bad)
	h.check(errors.has("config/chess_rules.json: time_controls[0].initial_ms = 5 is below the minimum 1000 (unit: milliseconds)"), "time control message: %s" % str(errors))
	bad = data.duplicate(true)
	bad["campaign"]["level_by_encounter"][4] = "godlike"
	errors = ChessRules.validate(bad)
	var level_error := false
	for message in errors:
		if String(message).contains("campaign.level_by_encounter[4] = godlike must be one of"):
			level_error = true
	h.check(level_error, "an unknown AI level in the campaign is refused: %s" % str(errors))
	bad = data.duplicate(true)
	bad["training"]["combo_windw_ticks"] = 78
	errors = ChessRules.validate(bad)
	var typo := false
	for message in errors:
		if String(message).contains("training.combo_windw_ticks is not a known setting"):
			typo = true
	h.check(typo, "a typo'd rule key is refused: %s" % str(errors))
	bad = data.duplicate(true)
	bad["computer_levels"].erase("4")
	errors = ChessRules.validate(bad)
	h.check(not errors.is_empty(), "computer levels must be numbered without gaps")


static func _rules_override(h) -> void:
	h.begin("chess rules override: patch applies, invalid patch refused, clear restores")
	var errors := ChessRules.apply_override({"time_controls": [{"label": "1 + 0 · Bullet", "initial_ms": 60000, "increment_ms": 0}]})
	h.check(errors.is_empty(), "a valid patch applies: %s" % str(errors))
	h.eq(ChessRules.time_controls().size(), 1, "the time-control list was replaced whole")
	h.check(ChessRules.is_overridden(), "override active")
	ChessRules.clear_override()
	h.eq(ChessRules.time_controls().size(), 5, "cleared: five time controls again")
	errors = ChessRules.apply_override({"campaign": {"start_lives": 0}})
	h.check(not errors.is_empty() and not ChessRules.is_overridden(), "an invalid patch is refused and nothing leaks: %s" % str(errors))
	h.eq(ChessRules.campaign_start_lives(), 3, "lives unchanged")


static func _docs(h) -> void:
	h.begin("generated reference documents are current")
	var stale: Array = Reference.docs_current()
	h.check(stale.is_empty(), "docs/game/*_REFERENCE.md match the metadata (regenerate: godot --headless --path godot --script res://tools/config_docs.gd) stale: %s" % str(stale))
	var text: String = Reference.balance_markdown()
	h.check(text.contains("| `armor` |"), "the balance reference lists the armor key")
	var meta: Dictionary = load("res://config/config_meta.gd").meta("res://config/balance_meta.json")
	var data: Dictionary = Tools.read_json("res://config/balance.json")
	var missing: Array = []
	for role in data["profiles"]:
		for key in data["profiles"][role]:
			if not (meta["profiles"] as Dictionary).has(key):
				missing.append("profiles.%s.%s" % [role, key])
	h.check(missing.is_empty(), "every profile key in the file is documented in the metadata: %s" % str(missing))


static func _tools(h) -> void:
	h.begin("config tools: flatten and diff")
	var a := {"x": {"y": 1.0, "_c": "ignored"}, "list": [{"v": 1}, {"v": 2}], "pair": [1.0, 2.0]}
	var b := {"x": {"y": 2.0}, "list": [{"v": 1}, {"v": 3}], "pair": [1.0, 2.0]}
	var rows: Array = Tools.diff(Tools.flatten(a), Tools.flatten(b))
	h.eq(rows.size(), 2, "two differences")
	h.eq(rows[0]["path"], "list[1].v", "list entries get an index in the path")
	h.eq(rows[1]["path"], "x.y", "nested keys are dotted")
	h.check(Tools.format_diff(rows).contains("x.y: 1 -> 2"), "readable lines: %s" % Tools.format_diff(rows))
	h.eq(Tools.diff(Tools.flatten(a), Tools.flatten(a)).size(), 0, "identical data has no differences")


static func _panel(h) -> void:
	h.begin("debug balance panel: steppers write an override, reset clears it, online lock refuses")
	var Panel = load("res://ui/debug/balance_panel.gd")
	var panel = Panel.new()
	panel._meta = load("res://config/config_meta.gd").meta(Balance.META_PATH)
	var shipped := Balance.stamp()
	var before := float(Balance.profile("n")["armor"])
	var errors: Array = panel.step(["profiles", "n", "armor"], 1)
	h.check(errors.is_empty(), "a + step applies: %s" % str(errors))
	h.check(float(Balance.profile("n")["armor"]) > before, "the armor went up (%s -> %s)" % [before, Balance.profile("n")["armor"]])
	h.check(Balance.stamp() != shipped, "the stamp shows the override")
	h.check(panel.diff_json().contains("armor"), "the diff names the changed key")
	var ticks_before := int(Balance.profile("n")["dodge_ticks"])
	panel.step(["profiles", "n", "dodge_ticks"], 1)
	h.check(int(Balance.profile("n")["dodge_ticks"]) > ticks_before, "integer (tick) settings step by whole ticks")
	for i in 400:
		panel.step(["profiles", "n", "armor"], 1)
	h.check(float(Balance.profile("n")["armor"]) <= 0.9, "a stepper never leaves the metadata range (armor <= 0.9, is %s)" % Balance.profile("n")["armor"])
	panel.reset()
	h.check(not Balance.is_overridden() and Balance.stamp() == shipped, "reset restores the shipped tuning")
	Balance.lock_for_online()
	var locked: Array = panel.step(["profiles", "n", "armor"], 1)
	h.check(not locked.is_empty() and not Balance.is_overridden(), "an online/ranked lock refuses changes: %s" % str(locked))
	Balance.unlock_online()
	h.check(not panel.step(["profiles", "n", "nosuchkey"], 1).is_empty(), "an unknown setting is refused")
	panel.free()
	Balance.clear_override()
