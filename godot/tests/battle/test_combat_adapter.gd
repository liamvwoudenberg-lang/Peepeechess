extends Node
## Test-only boundary double. Never selected by the application or scene resolver.
signal arena_ready
signal snapshot_received(snapshot: Dictionary)
signal result_received(result: Dictionary)
signal failed(message: String)
var start_calls = 0
var stop_calls = 0
var request: Dictionary = {}
var load_fails = false
var starts_fail = false
func available() -> bool:
	return true
func begin_load(value: Dictionary, _host: Node) -> Dictionary:
	request = value.duplicate(true)
	return {"ok": false, "error": "Fixture load failure."} if load_fails else {"ok": true}
func complete_load() -> void:
	arena_ready.emit()
func start(value: Dictionary) -> Dictionary:
	start_calls += 1
	request = value.duplicate(true)
	return {"ok": false, "error": "Fixture initialization failure."} if starts_fail else {"ok": true}
func stop() -> void:
	stop_calls += 1
func snapshot(tick_offset: int) -> Dictionary:
	var fighters: Array = []
	for p in [request.attacker, request.defender]:
		fighters.append({"playerId": p.playerId, "pieceId": p.pieceId, "position": {"x": 0, "y": 0, "z": 0}, "velocity": {"x": 0, "y": 0, "z": 0}, "yawRadians": 0, "hp": p.stats.maxHp, "stamina": p.stats.maxStamina, "state": "Idle", "stateTicks": 0, "cooldownTicks": 0, "lastInputSequence": 0})
	return {"schemaVersion": 1, "matchId": request.matchId, "battleId": request.battleId, "serverTick": request.startTick + tick_offset, "countdownTicksRemaining": maxi(0, 180 - tick_offset), "durationTicksRemaining": 5580 - maxi(180, tick_offset), "fighters": fighters, "events": [], "result": null}
func winner(outcome: String = "attacker") -> Dictionary:
	return {"schemaVersion": 1, "matchId": request.matchId, "battleId": request.battleId, "expectedRevision": request.expectedRevision, "resolvedTick": request.startTick + 181, "winnerPlayerId": request[outcome].playerId, "outcome": outcome, "reason": "knockout", "attackerHp": request.attacker.stats.maxHp if outcome == "attacker" else 0, "defenderHp": request.defender.stats.maxHp if outcome == "defender" else 0}
