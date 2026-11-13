extends RefCounted
## Pacing (BALANCE.md "Pacing"): the shipped data makes fights slower and more readable so that reading the opponent beats mashing
## buttons: swings are 25% slower, cost 70% more stamina (a full bar pays for a handful of swings, not a dozen), the parry window
## is wider and a successful parry pays (longer stagger, bigger refund, stronger riposte). This suite pins those relations on the
## data AS SHIPPED, tests the parry window on a real fighter, and runs a deterministic bot check: a bot that attacks constantly
## ("aggressive": short gaps, long chains, rarely defends) must lose to bots that read and defend. The mechanics suites run on the
## documented frame data instead (test_runner.gd RAW_SUITES / raw_pacing.json). BOT-measured, not a human claim.
## Calibration of the spam check: tools/style_matchup.gd.

const Balance := preload("res://combat/data/balance_data.gd")
const Duel := preload("res://combat/tools/attacker_duel.gd")
const Support := preload("res://combat/tests/test_support.gd")
const ROLES := ["p", "n", "b", "r", "q"]
const SPAM_SEED := 36000
const SPAM_N_DEFENSIVE := 4   # per mirrored role: 20 duels against the defensive bot
const SPAM_N_DUELIST := 2     # 10 duels against the duelist
const SPAM_MAX_WIN_VS_DEFENSIVE := 0.5
const SPAM_MAX_WIN_VS_DUELIST := 0.2


static func run(h, tree: SceneTree) -> void:
	_data(h)
	await _parry_window(h, tree)
	await _spam(h, tree)


static func _data(h) -> void:
	h.begin("pacing data: slower swings, dearer swings, a wider parry window and a parry that pays (the five contract roles)")
	var raw := _raw_scales()
	for role in ROLES:
		var tables := Balance.attack_tables(role)
		var profile := Balance.profile(role)
		var stats := FighterRoster.stats_for(role)
		for def in tables["light"]:
			var factor: float = def.ticks_scale / float(raw[def.id])
			h.check(factor >= 1.2, "%s %s: swings are at least 20%% slower than the documented frame data (x%.2f)" % [role, def.id, factor])
			h.check(def.cancel_from >= 0.78, "%s %s: the next swing can start no earlier than 78%% of this one (%.2f)" % [role, def.id, def.cancel_from])
		var heavy: AttackDefinition = tables["heavy"]
		h.check(heavy.ticks_scale / float(raw[heavy.id]) >= 1.2, "%s heavy: at least 20%% slower (x%.2f)" % [role, heavy.ticks_scale / float(raw[heavy.id])])
		var light_cost: float = (tables["light"][0] as AttackDefinition).stamina_cost
		h.check(heavy.stamina_cost > light_cost, "%s: a heavy costs more than a light (%.1f > %.1f)" % [role, heavy.stamina_cost, light_cost])
		var swings := float(stats["maxStamina"]) / light_cost
		h.check(swings >= 2.5 and swings <= 9.0, "%s: a full stamina bar pays for %.1f light swings: mashing runs dry, fighting stays possible (2.5..9)" % [role, swings])
		h.check(int(profile["parry_window_bonus"]) >= 3, "%s: the parry window is %d ticks wider than the stats' parryTicks" % [role, int(profile["parry_window_bonus"])])
		h.check(int(profile["parry_stagger_ticks"]) >= 45, "%s: a parry staggers the attacker for %d ticks (>= 45)" % [role, int(profile["parry_stagger_ticks"])])
		h.check(float(profile["parry_refund"]) >= 12.0, "%s: a parry refunds %.0f stamina (>= 12)" % [role, float(profile["parry_refund"])])
		h.check(float(profile["riposte_mult"]) >= 1.35, "%s: the riposte after a parry hits x%.2f (>= 1.35)" % [role, float(profile["riposte_mult"])])
		h.check(int(profile["dodge_iframe_end"]) - int(profile["dodge_iframe_start"]) >= 10, "%s: the dodge's invulnerable window is %d ticks (>= 10)" % [role, int(profile["dodge_iframe_end"]) - int(profile["dodge_iframe_start"])])
	h.eq(int(Balance.profile("k")["parry_window_bonus"]), 0, "the King keeps the old pacing (King's last stand has its own balance)")

	h.begin("pacing data: the documented-frame-data override (raw_pacing.json) really restores the original numbers")
	var errors := Balance.apply_override(JSON.parse_string(FileAccess.get_file_as_string("res://combat/tests/raw_pacing.json")))
	h.check(errors.is_empty(), "the override is accepted (%s)" % str(errors))
	h.eq((Balance.attack_tables("p")["light"][0] as AttackDefinition).ticks_scale, 1.0, "Pawn light 1: x1.0 again")
	h.eq(int(Balance.profile("p")["parry_window_bonus"]), 0, "no parry window bonus")
	h.eq(int(Balance.profile("p")["parry_stagger_ticks"]), 34, "Pawn parry stagger 34 ticks again")
	Balance.clear_override()


## attack id -> ticks_scale of the documented frame data (raw_pacing.json)
static func _raw_scales() -> Dictionary:
	var patch: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://combat/tests/raw_pacing.json"))
	var scales := {}
	for role in patch["attacks"]:
		for light in patch["attacks"][role]["light"]:
			scales[String(light["id"])] = float(light["ticks_scale"])
		scales[String(patch["attacks"][role]["heavy"]["id"])] = float(patch["attacks"][role]["heavy"]["ticks_scale"])
	return scales


static func _parry_window(h, tree: SceneTree) -> void:
	h.begin("pacing parry window: the window on a real fighter is parryTicks plus the data's bonus")
	for role in ["p", "n", "r"]:
		var rig = await Support.make_rig(tree, role, role)
		rig.face_off()
		rig.to_live()
		rig.b.press("parry")
		rig.tick()
		var expected := int(rig.black().stats["parryTicks"]) + int(Balance.profile(role)["parry_window_bonus"])
		h.eq(rig.black().sm.parry_window, expected, "%s: the parry window is %d ticks (stats %d + bonus %d)" % [role, expected, int(rig.black().stats["parryTicks"]), int(Balance.profile(role)["parry_window_bonus"])])
		rig.dispose()


## A's win rate against B over mirrored roles; A and B swap the attacker's seat with the seed so the attacker's advantage cancels.
static func _win_rate(tree: SceneTree, a_cfg: Dictionary, b_cfg: Dictionary, n_per_role: int) -> Dictionary:
	var wins := 0
	var total := 0
	for role in ROLES:
		for i in n_per_role:
			var swap := i % 2 == 1
			var r: Dictionary = await Duel.duel(tree, role, role, b_cfg if swap else a_cfg, SPAM_SEED + i, {}, a_cfg if swap else b_cfg)
			var attacker_won: bool = r["outcome"] == "attacker"
			if attacker_won != swap:
				wins += 1
			total += 1
	return {"wins": wins, "n": total}


static func _spam(h, tree: SceneTree) -> void:
	h.begin("pacing spam check: a bot that attacks constantly loses to bots that read and defend (fixed seeds, mirrored roles)")
	var spammer := {"style": "aggressive", "skill": 0.9}
	var vs_defensive: Dictionary = await _win_rate(tree, spammer, {"style": "defensive", "skill": 0.9}, SPAM_N_DEFENSIVE)
	var rate_defensive := float(vs_defensive["wins"]) / float(vs_defensive["n"])
	h.check(rate_defensive <= SPAM_MAX_WIN_VS_DEFENSIVE, "the spammer wins %d of %d against the defensive bot (%.0f%%, needs <= %.0f%%)" % [vs_defensive["wins"], vs_defensive["n"], 100.0 * rate_defensive, 100.0 * SPAM_MAX_WIN_VS_DEFENSIVE])
	var vs_duelist: Dictionary = await _win_rate(tree, spammer, {"style": "duelist", "skill": 0.9}, SPAM_N_DUELIST)
	var rate_duelist := float(vs_duelist["wins"]) / float(vs_duelist["n"])
	h.check(rate_duelist <= SPAM_MAX_WIN_VS_DUELIST, "the spammer wins %d of %d against the duelist (%.0f%%, needs <= %.0f%%)" % [vs_duelist["wins"], vs_duelist["n"], 100.0 * rate_duelist, 100.0 * SPAM_MAX_WIN_VS_DUELIST])
