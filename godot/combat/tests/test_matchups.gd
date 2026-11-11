extends RefCounted
## Every class can beat every other class: all 36 ordered pairs (incl. mirrors) of the six-class roster.
##
## "Winnable" = SOME style/skill of the AI family (duelist, patient, aggressive, defensive, evasive, ability, balanced at
## skill 0.6 / 0.9) beats the DEFAULT AI (balanced, skill 0.6) of the opposing class in at least half of N deterministic
## seeded fights. The search stops at the first configuration that gets there, so this gate stays fast; the exhaustive
## win-rate matrix comes from tools/balance_matrix.gd and is documented in BALANCE.md.
##
## BOT-MEASURED, NOT HUMAN-TESTED: it proves a winning plan exists for a scripted skilled player with perfect frame
## knowledge (the "duelist" style parries on the published first-active tick); it says nothing about how hard that plan
## is for a human. A timeout counts as no win for the side that did not win on HP; their share is reported.

const Runner := preload("res://combat/tests/matchup_runner.gd")
const N := 6
const BASE_SEED := 3000


static func run(h, tree: SceneTree) -> void:
	var roles: Array = FighterRoster.ALL_ROLES
	h.begin("matchups: all 36 ordered pairs are winnable (some style beats the default AI in >= %d of %d seeded fights)" % [(N + 1) / 2, N])
	var hopeless: Array = []
	var played := 0
	var timeouts := 0
	var rows := {}
	var pairs := 0
	for a in roles:
		var line := ""
		for b in roles:
			pairs += 1
			var found: Dictionary = await Runner.winnable(tree, a, b, N, BASE_SEED)
			for entry in found["tried"]:
				played += int(entry["played"])
				timeouts += int(entry["timeouts"])
			var best: Dictionary = found["best"]
			if not found["ok"]:
				hopeless.append("%s>%s (best %s/%.1f %d/%d)" % [a, b, best["style"], best["skill"], best["wins"], N])
			line += " %s%s:%s/%.1f %d" % [a, b, String(best["style"]).substr(0, 4), best["skill"], best["wins"]]
		rows[a] = line
	for a in roles:
		print("  %s" % rows[a])
	h.eq(pairs, 36, "all 36 ordered pairs were examined")
	h.eq(hopeless, [], "no hopeless pairing")
	h.check(timeouts * 10 <= played, "timeouts are rare in the searched fights (%d of %d)" % [timeouts, played])
	print("  matchups: %d fights, %d timeouts (bot-measured; see BALANCE.md for the full matrix)" % [played, timeouts])
