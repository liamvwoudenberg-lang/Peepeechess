class_name BattleFlow
extends Node
## Scene transitions and presentation timing around one authoritative transaction.
signal phase_changed(phase: String)
signal preview_requested(request: Dictionary)
signal result_ready(result: Dictionary)
signal returning_to_board
signal failed(message: String)
## battle-royal-v1 only (the game's own signals, re-emitted for the presentation layer; never fire in C0 / legacy Battle).
signal sequence_started(info: Dictionary)
signal duel_started(index: int, total: int, king_hp: int)
signal duel_finished(index: int, total: int, summary: Dictionary)
signal sequence_finished(summary: Dictionary)
## A king's-last-stand duel is mandatory: it shows the banner this long, then starts by itself (no cancel).
const ROYAL_BANNER_SECONDS = 1.5
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
# --- king's last stand (battle-royal-v1) hooks; never used by Classic / C0 Battle ---------------------------------------
## The pit world's bridge sets `start_override`: it is called (instead of confirm_capture) when a royal duel's banner is over and
## must itself call confirm_capture(); it returns {ok, error?}. A failure is handled like any other failed start (bounded retry).
var start_override: Callable = Callable()
## true = between two duels of one sequence the arena of the previous duel stays mounted and is restarted in place (no scene
## reload); the pit presentation then stays in the chamber. false (default) = the arena is freed after every duel.
var keep_arena_for_royal = false
# --- end king's last stand ----------------------------------------------------------------------------------------------

func setup(match_game: BattleChessMatch, combat_adapter: Node, combat_host: Node) -> void:
	game = match_game
	adapter = combat_adapter
	host = combat_host
	game.bind_combat_authority(adapter)
	game.battle_prepared.connect(_prepared)
	game.changed.connect(_match_changed)
	for name in ["sequence_started", "duel_started", "duel_finished", "sequence_finished"]:
		if game.has_signal(name):
			game.connect(name, Callable(self, "_on_" + name))
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

func _on_sequence_started(info: Dictionary) -> void:
	sequence_started.emit(info)

func _on_duel_started(index: int, total: int, king_hp: int) -> void:
	duel_started.emit(index, total, king_hp)

func _on_duel_finished(index: int, total: int, summary: Dictionary) -> void:
	duel_finished.emit(index, total, summary)

func _on_sequence_finished(summary: Dictionary) -> void:
	sequence_finished.emit(summary)

func _royal_duel() -> bool:
	return game.has_method("royal_active") and game.call("royal_active")

## True while the pending fight is a battle-royal-v1 duel (mandatory, banner instead of the capture preview).
func is_royal_duel() -> bool:
	return _royal_duel()

func _prepared(request: Dictionary) -> void:
	_battle_id = request.battleId
	_timer = ROYAL_BANNER_SECONDS
	_set_phase("preview")
	preview_requested.emit(request.duplicate(true))

func confirm_capture() -> Dictionary:
	if phase != "preview" or not _pending_matches() or game.paused:
		return {"ok": false, "error": "No capture preview is ready."}
	_set_phase("loading")
	var options: Dictionary = game.combat_options()
	if keep_arena_for_royal and not options.is_empty() and adapter.has_method("has_live_arena") and adapter.call("has_live_arena"):
		_arena_ready()  # king's last stand: the previous duel's arena is still mounted; restart it in place
		return {"ok": true}
	var response = adapter.begin_load(game.pending_request(), host) if options.is_empty() else adapter.begin_load(game.pending_request(), host, options)
	if not response.ok:
		_failure(response.error)
	return response

func cancel_preview() -> void:
	if phase == "preview" and not _royal_duel():
		interrupt("Capture canceled.")

func _pending_matches() -> bool:
	var p = game.pending_request()
	return not p.is_empty() and p.battleId == _battle_id

func _arena_ready() -> void:
	if phase != "loading" or not _pending_matches():
		adapter.stop()
		return
	_set_phase("countdown")
	var options: Dictionary = game.combat_options()
	var response = adapter.start(game.pending_request()) if options.is_empty() else adapter.start(game.pending_request(), options)
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
	if not (keep_arena_for_royal and _royal_duel() and phase == "preview"):  # king's last stand: the next duel reuses the arena
		adapter.stop()
	if phase == "returning": # not when the commit prepared the next duel of a royal sequence
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
	elif phase == "preview" and _royal_duel():
		_timer -= maxf(0, seconds)
		if _timer <= 0:
			_timer = ROYAL_BANNER_SECONDS # retried after a refusal (for example while paused)
			if start_override.is_valid():
				var started = start_override.call()
				if started is Dictionary and not started.get("ok", true) and phase == "preview" and not game.paused:
					_failure(str(started.get("error", "The duel could not start.")))
			else:
				confirm_capture()
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
		game.cancel_pending() # a royal duel is retried from its unchanged start state (bounded), see BattleRoyalMatch

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
	for name in ["sequence_started", "duel_started", "duel_finished", "sequence_finished"]:
		if game.has_signal(name) and game.is_connected(name, Callable(self, "_on_" + name)):
			game.disconnect(name, Callable(self, "_on_" + name))
	for pair in [["arena_ready", _arena_ready], ["snapshot_received", _snapshot], ["result_received", _result], ["failed", _failure]]:
		if adapter.is_connected(pair[0], pair[1]):
			adapter.disconnect(pair[0], pair[1])

func _exit_tree() -> void:
	dispose()
