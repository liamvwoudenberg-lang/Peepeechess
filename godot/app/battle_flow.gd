class_name BattleFlow
extends Node
## Scene transitions and presentation timing around one authoritative transaction.
signal phase_changed(phase: String)
signal preview_requested(request: Dictionary)
signal result_ready(result: Dictionary)
signal returning_to_board
signal failed(message: String)
var game: BattleChessMatch
var adapter: Node
var host: Node
var phase = "board"
var _battle_id = ""
var _timer = 0.0
var _elapsed = 0.0
var _disposed = false
## pit-world hook: false = the presentation layer (godot/world/battle_bridge.gd) calls
## return_to_board() itself once its sequence is done, instead of the fixed 2 s aftermath timer.
var auto_return = true

func setup(match_game: BattleChessMatch, combat_adapter: Node, combat_host: Node) -> void:
	game = match_game
	adapter = combat_adapter
	host = combat_host
	game.bind_combat_authority(adapter)
	game.battle_prepared.connect(_prepared)
	game.changed.connect(_match_changed)
	adapter.arena_ready.connect(_arena_ready)
	adapter.snapshot_received.connect(_snapshot)
	adapter.result_received.connect(_result)
	adapter.failed.connect(_failure)

func _set_phase(value: String) -> void:
	if phase == value:
		return
	phase = value
	_elapsed = 0.0
	phase_changed.emit(phase)

func _prepared(request: Dictionary) -> void:
	_battle_id = request.battleId
	_set_phase("preview")
	preview_requested.emit(request.duplicate(true))

func confirm_capture() -> Dictionary:
	if phase != "preview" or not _pending_matches() or game.paused:
		return {"ok": false, "error": "No capture preview is ready."}
	_set_phase("loading")
	var response = adapter.begin_load(game.pending_request(), host)
	if not response.ok:
		_failure(response.error)
	return response

func cancel_preview() -> void:
	if phase == "preview":
		interrupt("Capture canceled.")

func _pending_matches() -> bool:
	var p = game.pending_request()
	return not p.is_empty() and p.battleId == _battle_id

func _arena_ready() -> void:
	if phase != "loading" or not _pending_matches():
		adapter.stop()
		return
	_set_phase("countdown")
	var response = adapter.start(game.pending_request())
	if not response.ok:
		_failure(response.error)

func _snapshot(snapshot: Dictionary) -> void:
	if phase not in ["countdown", "combat"] or not _pending_matches():
		return
	if not game.accept_snapshot(snapshot, adapter):
		failed.emit("An invalid or stale combat snapshot was ignored.")
		return
	_set_phase("countdown" if snapshot.countdownTicksRemaining > 0 else "combat")
	if snapshot.result != null:
		_result(snapshot.result)

func _result(value: Dictionary) -> void:
	if phase not in ["countdown", "combat", "aftermath"] or not _pending_matches():
		return
	var accepted = game.accept_result(value, adapter)
	if not accepted.ok:
		failed.emit(accepted.error)
		return
	if accepted.get("duplicate", false):
		return
	_set_phase("aftermath")
	_timer = 2.0
	result_ready.emit(value.duplicate(true))

func return_to_board() -> Dictionary:
	if phase != "aftermath" or not _pending_matches():
		return {"ok": false, "error": "No validated result is ready to return."}
	# Mark the presentation phase before commit emits changed; otherwise it can
	# look like an external interruption. This function never reapplies a result.
	_set_phase("returning")
	var committed = game.commit_battle()
	if not committed.ok:
		_failure(committed.error)
		return committed
	adapter.stop()
	_timer = 0.4
	returning_to_board.emit()
	return committed

func advance(seconds: float) -> void:
	if _disposed:
		return
	_elapsed += maxf(0, seconds)
	if phase == "loading" and _elapsed >= 15:
		_failure("Combat loading timed out; the board has not changed.")
	elif phase in ["countdown", "combat"] and _elapsed >= 105:
		_failure("The combat authority stopped responding; no winner was invented.")
	elif phase in ["aftermath", "returning"]:
		_timer -= maxf(0, seconds)
		if _timer <= 0:
			if phase == "aftermath":
				if auto_return:
					return_to_board()
			else:
				_battle_id = ""
				_set_phase("board")

func _process(delta: float) -> void:
	advance(delta)

func _match_changed() -> void:
	if phase not in ["board", "returning"] and not _pending_matches():
		adapter.stop()
		_battle_id = ""
		_set_phase("board")

func _failure(message: String) -> void:
	interrupt(message)
	failed.emit(message)

func interrupt(_reason: String = "Transition interrupted.") -> void:
	adapter.stop()
	_battle_id = ""
	_set_phase("board")
	if game.phase == "aftermath":
		game.commit_battle()
	elif not game.pending_request().is_empty():
		game.cancel_pending()

func dispose() -> void:
	if _disposed:
		return
	interrupt()
	_disposed = true
	if game.battle_prepared.is_connected(_prepared):
		game.battle_prepared.disconnect(_prepared)
	if game.changed.is_connected(_match_changed):
		game.changed.disconnect(_match_changed)
	game.bind_combat_authority(null)
	for pair in [["arena_ready", _arena_ready], ["snapshot_received", _snapshot], ["result_received", _result], ["failed", _failure]]:
		if adapter.is_connected(pair[0], pair[1]):
			adapter.disconnect(pair[0], pair[1])

func _exit_tree() -> void:
	dispose()
