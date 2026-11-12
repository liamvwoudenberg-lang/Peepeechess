class_name BattleRoyalMatch
extends "res://chess/battle_match.gd"
## battle-royal-v1 ("the king's last stand"), opt-in beside the preserved battle-checkmate-v1 / C0 match.
##
## All Battle behaviour (frozen capture transactions, trusted-authority results, safety of both outcomes) is inherited.
## When a move leaves the side to move checkmated, the match does NOT end: it freezes that position and runs a
## SEQUENCE of duels, the mated King (attacker) against each piece of the mating group in turn, through the very same
## pending/combat/aftermath transaction that ordinary captures use (so BattleFlow, the adapter, the server session and
## the presentation layer treat each duel as a normal fight). Decisions and edge cases: docs/architecture/BATTLE_ROYAL_V1.md.
##
##   * the King's HP, stamina and ability cooldown carry from one duel to the next (poise/buffs/positions do not);
##     every checker starts with full resources;
##   * the King losing ANY duel (including a double knockout, a tie or a timeout loss) ends the match as checkmate;
##   * winning EVERY duel removes the whole group from the board and the position is re-evaluated by the ordinary
##     Battle rules with the same side to move (no ply is consumed; never a second sequence from the same position);
##   * the trusted combat authority supplies the King's end resources (`fighter_state`); a client never does.
signal sequence_started(info: Dictionary)
signal duel_started(index: int, total: int, king_hp: int)
signal duel_finished(index: int, total: int, summary: Dictionary)
signal sequence_finished(summary: Dictionary)
const RoyalRules = preload("res://chess/battle_royal_rules.gd")
const RoyalCodec = preload("res://contracts/royal/v1/codec.gd")
const RULESET_ID = "battle-royal-v1"
## A duel that could not even be started (scene failed to load, authority did not answer) is retried from its
## unchanged start state this many times before the sequence is declared unplayable and checkmate stands.
const MAX_RETRIES = 2
var royal_codec = RoyalCodec.new()
## One RoyalSequenceResult per finished sequence of this game, oldest first (the custom replay/chronicle record).
var royal_log: Array = []
var _royal: Dictionary = {}
var _royal_serial = 0

func _new_engine():
	return RoyalRules.new()

func new_game(base_ms: int = 0, increment: int = 0, fen: String = RoyalRules.START_FEN) -> Dictionary:
	var started = super.new_game(base_ms, increment, fen)
	_royal.clear()
	_royal_serial = 0
	royal_log.clear()
	if started.ok and not engine.mate_pending.is_empty():
		_begin_sequence() # a loaded position that is already checkmate fights its last stand immediately
	return started

# ---- sequence lifecycle -------------------------------------------------------------------------------------------

func royal_active() -> bool:
	return not _royal.is_empty()

func submit_request(request: Dictionary, authenticated_player_id: String, now: int = -1) -> Dictionary:
	var response = super.submit_request(request, authenticated_player_id, now)
	if response.ok and _royal.is_empty() and phase == "board" and not engine.mate_pending.is_empty():
		_begin_sequence() # a quiet move created checkmate
	return response

func _begin_sequence() -> void:
	var pending: Dictionary = engine.mate_pending
	var mated: String = pending.mated
	var group: Array = []
	var attackers: Array = []
	for entry in pending.group:
		var combatant = _combatant(entry.square)
		group.append({"pieceId": combatant.pieceId, "square": combatant.square, "index": entry.square, "role": entry.role, "color": entry.color, "playerId": combatant.playerId})
		attackers.append(combatant)
	var king_at: int = pending.kingSquare
	var king: Dictionary = _combatant(king_at)
	var start = {"hp": int(king.stats.maxHp), "stamina": float(king.stats.maxStamina), "cooldownTicks": 0}
	_royal_serial += 1
	var sequence_id = "%s:royal:%d" % [match_id, _royal_serial]
	var king_combatant = king.duplicate(true)
	king_combatant["startHp"] = start.hp
	king_combatant["startStamina"] = start.stamina
	king_combatant["startCooldown"] = start.cooldownTicks
	var request = {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": sequence_id, "matchId": match_id, "expectedRevision": revision, "beforeFen": engine.fen(), "mated": mated, "king": king_combatant, "attackers": attackers, "arenaId": "stone-v1", "startTick": server_tick}
	_royal = {"battleId": sequence_id, "mated": mated, "kingIndex": king_at, "kingPieceId": king.pieceId, "kingPlayerId": king.playerId, "group": group, "index": 0, "defeated": [], "duels": [], "king": start, "retries": 0, "request": request, "duel": {}, "end": {}, "startRevision": revision}
	if not royal_codec.valid("RoyalSequenceRequest", request):
		_abort_sequence("unplayable", "Checkmate (last stand could not be constructed)")
		return
	sequence_started.emit(request.duplicate(true))
	_prepare_duel()

func _prepare_duel() -> void:
	var index: int = _royal.index
	var checker: Dictionary = _royal.group[index]
	var retry = "" if _royal.retries == 0 else ":retry%d" % _royal.retries
	var battle_id = "%s:duel:%d%s" % [_royal.battleId, index, retry]
	var prepared = {"schemaVersion": 1, "matchId": match_id, "battleId": battle_id, "expectedRevision": revision, "beforeFen": engine.fen(), "from": BattleRules.square(_royal.kingIndex), "to": checker.square, "promotion": null, "attacker": _combatant(_royal.kingIndex), "defender": _combatant(checker.index), "arenaId": "stone-v1", "startTick": server_tick, "countdownTicks": 180, "durationTicks": 5400, "seed": absi(battle_id.hash()) % 2147483647}
	var envelope = {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": _royal.battleId, "duelIndex": index, "duelCount": _royal.group.size(), "kingStart": _royal.king.duplicate(), "battle": prepared}
	if not royal_codec.valid("RoyalDuelRequest", envelope) or prepared.defender.pieceId != checker.pieceId:
		_abort_sequence("unplayable", "Checkmate (last stand could not be constructed)")
		return
	_royal.duel = envelope
	_royal.end = {}
	_frozen = chess_state().duplicate(true)
	_pending = prepared
	_intent = {}
	_combat = _initial_snapshot(prepared)
	_terminal = {}
	phase = "combat"
	changed.emit()
	battle_prepared.emit(_pending.duplicate(true))
	duel_started.emit(index, _royal.group.size(), int(_royal.king.hp))

func _start_hp(participant: Dictionary):
	if not _royal.is_empty() and participant.role == "k":
		return _royal.king.hp
	return super._start_hp(participant)

func _start_stamina(participant: Dictionary):
	if not _royal.is_empty() and participant.role == "k":
		return _royal.king.stamina
	return super._start_stamina(participant)

func _start_cooldown(participant: Dictionary) -> int:
	if not _royal.is_empty() and participant.role == "k":
		return int(_royal.king.cooldownTicks)
	return super._start_cooldown(participant)

## The options the combat host passes to CombatSimulation.start for the pending battle (King's carried resources).
func combat_options() -> Dictionary:
	if _royal.is_empty() or _pending.is_empty():
		return {}
	return {"allow_experimental_roles": true, "initial_hp": int(_royal.king.hp), "initial_stamina": float(_royal.king.stamina), "initial_cooldown": int(_royal.king.cooldownTicks)}

## RoyalDuelRequest of the pending duel ({} when none): the BattleRequest-compatible payload plus the King's start state.
func royal_duel_request() -> Dictionary:
	return _royal.duel.duplicate(true) if not _royal.is_empty() and not _pending.is_empty() else {}

## RoyalSequenceRequest of the running sequence ({} when none).
func royal_request() -> Dictionary:
	return _royal.request.duplicate(true) if not _royal.is_empty() else {}

## RoyalSequenceProgress of the running sequence ({} when none).
func royal_progress() -> Dictionary:
	if _royal.is_empty():
		return {}
	var remaining: Array = []
	for i in range(_royal.index, _royal.group.size()):
		remaining.append(_royal.group[i].pieceId)
	return {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": _royal.battleId, "matchId": match_id, "status": "active", "duelIndex": _royal.index, "duelCount": _royal.group.size(), "currentBattleId": _pending.battleId if not _pending.is_empty() else null, "king": _royal.king.duplicate(), "defeated": _royal.defeated.duplicate(), "remaining": remaining}

# ---- authority boundary --------------------------------------------------------------------------------------------

func accept_result(value: Dictionary, source: Object) -> Dictionary:
	if _royal.is_empty() or _pending.is_empty():
		return super.accept_result(value, source)
	if not _trusted(source):
		return {"ok": false, "error": "Combat result did not come from the bound authority."}
	# The King's end resources come from the trusted simulation only, never from a payload a client could send.
	var end: Dictionary = source.call("fighter_state", _royal.kingPlayerId) if source.has_method("fighter_state") else {}
	var max_hp: float = _pending.attacker.stats.maxHp
	var max_stamina: float = _pending.attacker.stats.maxStamina
	var max_cooldown: int = int(_pending.attacker.stats.cooldownTicks)
	var valid_end = end.has_all(["hp", "stamina", "cooldownTicks"]) and (end.hp is int or end.hp is float) and (end.stamina is int or end.stamina is float) and (end.cooldownTicks is int or end.cooldownTicks is float)
	if valid_end:
		valid_end = end.hp >= 0 and end.hp <= max_hp and end.stamina >= 0 and end.stamina <= max_stamina and end.cooldownTicks >= 0 and end.cooldownTicks <= max_cooldown and end.hp == value.get("attackerHp", -1)
	if not valid_end:
		return {"ok": false, "error": "The combat authority did not report a consistent King state."}
	var accepted = super.accept_result(value, source)
	if accepted.ok and not accepted.get("duplicate", false):
		_royal.end = {"hp": int(end.hp), "stamina": float(end.stamina), "cooldownTicks": int(end.cooldownTicks)}
	return accepted

func commit_battle() -> Dictionary:
	if _royal.is_empty():
		var committed = super.commit_battle()
		if committed.ok and _royal.is_empty() and phase == "board" and not engine.mate_pending.is_empty():
			_begin_sequence() # the capture that was just settled created checkmate
		return committed
	if phase != "aftermath" or _terminal.is_empty() or _royal.end.is_empty() or not _still_frozen():
		return {"ok": false, "error": "No validated battle can be committed."}
	var index: int = _royal.index
	var total: int = _royal.group.size()
	var survived: bool = _terminal.outcome == "attacker" and int(_royal.end.hp) > 0
	var duel = {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": _royal.battleId, "duelIndex": index, "duelCount": total, "result": _terminal.duplicate(true), "kingEnd": _royal.end.duplicate(), "kingSurvived": survived}
	_royal.duels.append(duel)
	_royal.king = _royal.end.duplicate()
	_royal.retries = 0
	duel_finished.emit(index, total, duel.duplicate(true))
	if not survived:
		return _finish_sequence("king_fell")
	_royal.defeated.append(_royal.group[index].pieceId)
	if index + 1 >= total:
		return _finish_sequence("king_survived")
	_royal.index += 1
	_clear_pending()
	_prepare_duel()
	return {"ok": true, "revision": revision, "outcome": "attacker", "sequence": "active"}

func _finish_sequence(outcome: String, why: String = "Checkmate") -> Dictionary:
	var removed: Array = []
	for entry in _royal.group:
		removed.append(entry.index)
	if outcome == "king_survived":
		engine.resolve_king_survived(removed)
		for at in removed:
			registry.erase(at)
	else:
		engine.resolve_king_fell(why)
	var summary = {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": _royal.battleId, "matchId": match_id, "expectedRevision": _royal.startRevision, "outcome": outcome, "duels": _royal.duels.duplicate(true), "defeated": _royal.defeated.duplicate(), "kingEnd": _royal.king.duplicate(), "resolvedTick": server_tick, "matchResult": engine.result if not engine.result.is_empty() else null, "reason": engine.reason if not engine.reason.is_empty() else null, "fenAfter": engine.fen()}
	var after = revision + 1
	_royal.clear()
	_clear_pending()
	revision = after
	engine.last_stands.append(summary.duplicate(true))
	royal_log.append(summary.duplicate(true))
	changed.emit()
	sequence_finished.emit(summary.duplicate(true))
	return {"ok": true, "revision": revision, "outcome": outcome, "sequence": "finished", "summary": summary}

func _abort_sequence(outcome: String, why: String) -> void:
	if _royal.is_empty():
		return
	_finish_sequence(outcome, why)

# ---- interruption, abandonment, resignation -----------------------------------------------------------------------

## An interrupted duel (scene failed to load, authority silent) is retried from its unchanged start state; a validated
## result is never discarded. After MAX_RETRIES failures the sequence is unplayable and checkmate stands.
func cancel_pending() -> void:
	if _royal.is_empty():
		super.cancel_pending()
		return
	if phase == "aftermath":
		commit_battle()
		return
	_royal.retries += 1
	if _royal.retries > MAX_RETRIES:
		_abort_sequence("unplayable", "Checkmate (last stand could not be fought)")
		return
	_clear_pending()
	_prepare_duel()

## Forfeit/abort path (the server session finishes the match another way): drop the sequence without an outcome.
func abandon_pending() -> void:
	if _royal.is_empty():
		super.abandon_pending()
		return
	var summary = {"schemaVersion": 1, "rulesetId": RULESET_ID, "battleId": _royal.battleId, "matchId": match_id, "expectedRevision": _royal.startRevision, "outcome": "abandoned", "duels": _royal.duels.duplicate(true), "defeated": _royal.defeated.duplicate(), "kingEnd": _royal.king.duplicate(), "resolvedTick": server_tick, "matchResult": null, "reason": null, "fenAfter": engine.fen()}
	_royal.clear()
	_clear_pending()
	engine.mate_pending = {}
	royal_log.append(summary.duplicate(true))
	changed.emit()
	sequence_finished.emit(summary.duplicate(true))

func resign() -> void:
	if _royal.is_empty():
		super.resign()
		return
	poll_clock()
	var resigning_color = engine.turn # the mated side is on move during its last stand
	abandon_pending()
	if engine.result.is_empty():
		engine.result = "0-1" if resigning_color == "w" else "1-0"
		engine.reason = "Resignation"
	changed.emit()

func set_paused(value: bool) -> bool:
	return super.set_paused(value) if _royal.is_empty() else false

# ---- wire state ----------------------------------------------------------------------------------------------------

## RoyalMatchState: MatchState with rulesetId battle-royal-v1, the King-capable BattleRequest and `royal` progress.
func match_state() -> Dictionary:
	var state = super.match_state()
	state.rulesetId = RULESET_ID
	state.royal = royal_progress() if not _royal.is_empty() else null
	return state
