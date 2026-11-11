extends SceneTree
## Regenerates godot/contracts/royal/v1/fixtures.json from the real rules layer (valid payloads) plus targeted
## mutations (invalid payloads). Usage: godot --headless --path godot --script res://tests/royal/make_fixtures.gd
## Ids are rewritten to fixed strings so the committed file is stable. Review the diff before committing.
const Match = preload("res://chess/battle_royal_match.gd")
const MATE_BOTH = "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1" # double check by Re1 and Ra8; the king cannot move

class Auth extends RefCounted:
	var state = {"hp": 100, "stamina": 50.0, "cooldownTicks": 0}
	func fighter_state(_p): return state

var fixtures: Array = []
var ids: Dictionary = {}

func add(name: String, type: String, valid: bool, payload: Variant) -> void:
	fixtures.append({"name": name, "type": type, "valid": valid, "payload": payload})

func result_for(g, outcome: String, king_hp: int, other_hp: int, reason: String = "knockout") -> Dictionary:
	var p = g.pending_request()
	return {"schemaVersion": 1, "matchId": g.match_id, "battleId": p.battleId, "expectedRevision": g.revision, "resolvedTick": p.startTick + 181 + 600, "winnerPlayerId": p[outcome].playerId, "outcome": outcome, "reason": reason, "attackerHp": king_hp, "defenderHp": other_hp}

func finish_duel(g, a, outcome: String, end: Dictionary, other_hp: int) -> Dictionary:
	a.state = end
	var r = result_for(g, outcome, int(end.hp), other_hp)
	assert(g.accept_result(r, a).ok)
	return g.commit_battle()

func rename(value: Variant, from: String, to: String) -> Variant:
	return JSON.parse_string(JSON.stringify(value).replace(from, to))

func _init() -> void:
	var a = Auth.new()
	var g = Match.new()
	g.bind_combat_authority(a)
	g.new_game(0, 0, MATE_BOTH)
	var mid = g.match_id
	var seq = g.royal_request()
	var duel0 = g.royal_duel_request()
	add("valid RoyalSequenceRequest (double check)", "RoyalSequenceRequest", true, seq)
	add("valid RoyalBattleRequest (king attacker)", "RoyalBattleRequest", true, duel0.battle)
	add("valid RoyalDuelRequest (first duel)", "RoyalDuelRequest", true, duel0)
	add("valid RoyalMatchState (first duel pending)", "RoyalMatchState", true, g.match_state())
	var end0 = {"hp": 112, "stamina": 61.5, "cooldownTicks": 340}
	var r0 = result_for(g, "attacker", 112, 0)
	a.state = end0
	g.accept_result(r0, a)
	add("valid BattleResult of a royal duel", "BattleResult", true, r0)
	g.commit_battle()
	var duel1 = g.royal_duel_request()
	add("valid RoyalDuelRequest (carried king state)", "RoyalDuelRequest", true, duel1)
	var progress = g.royal_progress()
	add("valid RoyalSequenceProgress (second duel)", "RoyalSequenceProgress", true, progress)
	finish_duel(g, a, "defender", {"hp": 0, "stamina": 12.25, "cooldownTicks": 120}, 41)
	var fell = g.royal_log[0]
	add("valid RoyalDuelResult (king survives)", "RoyalDuelResult", true, fell.duels[0])
	add("valid RoyalDuelResult (king falls)", "RoyalDuelResult", true, fell.duels[1])
	add("valid RoyalSequenceResult (king fell: checkmate)", "RoyalSequenceResult", true, fell)
	# A second game: the king wins both duels.
	var h = Match.new()
	h.bind_combat_authority(a)
	h.new_game(0, 0, MATE_BOTH)
	var mid2 = h.match_id
	finish_duel(h, a, "attacker", {"hp": 112, "stamina": 61.5, "cooldownTicks": 340}, 0)
	finish_duel(h, a, "attacker", {"hp": 31, "stamina": 0.0, "cooldownTicks": 20}, 0)
	var won = h.royal_log[0]
	add("valid RoyalSequenceResult (king survived)", "RoyalSequenceResult", true, won)
	var aborted = Match.new()
	aborted.bind_combat_authority(a)
	aborted.new_game(0, 0, MATE_BOTH)
	var mid3 = aborted.match_id
	aborted.abandon_pending()
	add("valid RoyalSequenceResult (abandoned)", "RoyalSequenceResult", true, aborted.royal_log[0])
	add("valid RoyalMatchState (complete, no duel)", "RoyalMatchState", true, g.match_state())
	# Invalid cases: each breaks exactly one rule.
	var bad = func(name, type, base, edit: Callable):
		var copy = JSON.parse_string(JSON.stringify(base))
		edit.call(copy)
		add(name, type, false, copy)
	bad.call("wrong ruleset id", "RoyalSequenceRequest", seq, func(v): v.rulesetId = "battle-checkmate-v1")
	bad.call("wrong schema version", "RoyalSequenceRequest", seq, func(v): v.schemaVersion = 2)
	bad.call("no attackers", "RoyalSequenceRequest", seq, func(v): v.attackers = [])
	bad.call("too many attackers", "RoyalSequenceRequest", seq, func(v): v.attackers = range(17).map(func(_i): return seq.attackers[0]))
	bad.call("king combatant is not a king", "RoyalSequenceRequest", seq, func(v): v.king.role = "q")
	bad.call("king start hp missing", "RoyalSequenceRequest", seq, func(v): v.king.erase("startHp"))
	bad.call("king start hp zero", "RoyalSequenceRequest", seq, func(v): v.king.startHp = 0)
	bad.call("king start stamina negative", "RoyalSequenceRequest", seq, func(v): v.king.startStamina = -1)
	bad.call("unknown field", "RoyalSequenceRequest", seq, func(v): v.hp = 160)
	bad.call("attacker role invalid", "RoyalSequenceRequest", seq, func(v): v.attackers[0].role = "x")
	bad.call("unknown mated colour", "RoyalSequenceRequest", seq, func(v): v.mated = "r")
	bad.call("duel index out of range", "RoyalDuelRequest", duel1, func(v): v.duelIndex = 16)
	bad.call("duel without king start", "RoyalDuelRequest", duel1, func(v): v.erase("kingStart"))
	bad.call("king start fractional cooldown", "RoyalDuelRequest", duel1, func(v): v.kingStart.cooldownTicks = 1.5)
	bad.call("king start hp negative", "RoyalDuelRequest", duel1, func(v): v.kingStart.hp = -1)
	bad.call("duel arena is not the stone arena", "RoyalDuelRequest", duel1, func(v): v.battle.arenaId = "board-v1")
	bad.call("duel battle with an unknown field", "RoyalDuelRequest", duel1, func(v): v.battle.result = null)
	bad.call("duel result with a string flag", "RoyalDuelResult", fell.duels[0], func(v): v.kingSurvived = "yes")
	bad.call("duel result with an unknown reason", "RoyalDuelResult", fell.duels[0], func(v): v.result.reason = "forfeit")
	bad.call("sequence outcome unknown", "RoyalSequenceResult", won, func(v): v.outcome = "king_won")
	bad.call("sequence match result invalid", "RoyalSequenceResult", won, func(v): v.matchResult = "2-0")
	bad.call("sequence result without fen", "RoyalSequenceResult", won, func(v): v.erase("fenAfter"))
	bad.call("progress status not active", "RoyalSequenceProgress", progress, func(v): v.status = "won")
	bad.call("progress remaining is not a list", "RoyalSequenceProgress", progress, func(v): v.remaining = "w-r-a1")
	bad.call("match state with the legacy ruleset id", "RoyalMatchState", fixtures[3].payload, func(v): v.rulesetId = "battle-checkmate-v1")
	bad.call("match state without royal progress", "RoyalMatchState", fixtures[3].payload, func(v): v.erase("royal"))
	bad.call("match state classic mode", "RoyalMatchState", fixtures[3].payload, func(v): v.mode = "classic")
	bad.call("king start hp above bound", "RoyalDuelRequest", duel1, func(v): v.kingStart.hp = 10001)
	# Stable ids and a stable, readable match id.
	var text = JSON.stringify(fixtures, "  ", false, true)
	for pair in [[mid, "royal-fixture-1"], [mid2, "royal-fixture-2"], [mid3, "royal-fixture-3"]]:
		text = text.replace(pair[0], pair[1])
	var file = FileAccess.open("res://contracts/royal/v1/fixtures.json", FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	print("wrote %d royal fixtures" % fixtures.size())
	quit(0)
