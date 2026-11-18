class_name BattleMetaMatch
extends "res://chess/battle_match.gd"
## Battle Chess with the fairness-pass board layer (chess/battle_meta.gd): wounds persist, support and position change a duel,
## Resolve is earned on the board and spent in duels. The chess rules are exactly battle-checkmate-v1 (kings never duel; checkmate
## ends the game): this class only changes how much each fighter starts a duel with and what a finished duel leaves behind.
## Inherited behaviour (frozen capture transactions, trusted-authority results, validity checks) is untouched; the start HP the
## snapshot validator expects comes from the same meta state the combat authority is given, so the two always agree.
signal meta_changed
const Meta = preload("res://chess/battle_meta.gd")
var meta = Meta.new()
var _fought: Dictionary = {}   # {"summary": Dictionary, "report": Dictionary} of the validated duel waiting to be committed

func new_game(base_ms: int = 0, increment: int = 0, fen: String = BattleRules.START_FEN) -> Dictionary:
	var started = super.new_game(base_ms, increment, fen)
	meta.reset()
	_fought.clear()
	return started

func _start_hp(participant: Dictionary):
	return meta.start_hp(participant.pieceId, int(participant.stats.maxHp))

## The simulation start options for the pending duel: per-seat HP, Resolve, damage-taken and regen modifiers. Computed from the frozen
## position, so repeated calls (arena load, countdown start) return the same values.
func combat_options() -> Dictionary:
	if _pending.is_empty():
		return {}
	return {"seat_start": meta.seat_options(engine, _pending)}

func accept_result(value: Dictionary, source: Object) -> Dictionary:
	var accepted = super.accept_result(value, source)
	if accepted.ok and not accepted.get("duplicate", false) and is_instance_valid(source) and source.has_method("duel_summary"):
		var summary: Dictionary = source.call("duel_summary")
		# Trust the summary only if it agrees with the validated result; otherwise the duel still counts, with the result's HP.
		if summary.is_empty() or int(summary.get("attacker", {}).get("hp", -1)) != int(value.attackerHp) or int(summary.get("defender", {}).get("hp", -1)) != int(value.defenderHp):
			summary = _summary_from_result(value)
		_fought = {"summary": summary}
	elif accepted.ok and not accepted.get("duplicate", false):
		_fought = {"summary": _summary_from_result(value)}
	return accepted

func _summary_from_result(value: Dictionary) -> Dictionary:
	var r = _pending
	return {"attacker": {"hp": value.attackerHp, "max_hp": r.attacker.stats.maxHp, "resolve": 0.0, "resolve_start": 0.0},
			"defender": {"hp": value.defenderHp, "max_hp": r.defender.stats.maxHp, "resolve": 0.0, "resolve_start": 0.0}}

func commit_battle() -> Dictionary:
	if phase != "aftermath" or _terminal.is_empty() or _fought.is_empty():
		return super.commit_battle()
	var request: Dictionary = _pending.duplicate(true)
	var outcome: String = _terminal.outcome
	var mover: String = request.attacker.color
	var spared: String = request.attacker.pieceId if outcome == "attacker" else request.defender.pieceId
	meta.after_duel(engine, request, _fought.summary, outcome)
	_fought.clear()
	var committed = super.commit_battle()
	if committed.ok:
		meta.after_move(engine, registry, mover, spared)
		meta_changed.emit()
	return committed

func submit_request(request: Dictionary, authenticated_player_id: String, now: int = -1) -> Dictionary:
	var mover: String = engine.turn
	var response = super.submit_request(request, authenticated_player_id, now)
	if response.ok and phase == "board" and not response.has("battleId"):   # a quiet move was committed
		meta.after_move(engine, registry, mover)
		meta_changed.emit()
	return response

func cancel_pending() -> void:
	_fought.clear()
	super.cancel_pending()
