class_name WorldBattleBridge
extends Node
## Glue between the existing battle flow (BattleFlow + BattleCombatAdapter, unchanged contracts) and
## the pit presentation. It forwards flow facts to PitSequence and nothing else:
##
##   UI "Start battle"        -> start_battle(): pit.begin(request) + flow.confirm_capture()
##   adapter mounts the arena -> arena (placed in the chamber by PitChamber) -> pit.attach_arena
##   flow.result_ready        -> pit.present_result(result)   (authoritative, from the combat module)
##   pit.return_ready         -> flow.return_to_board()       (commits the chess result exactly once)
##   flow back to "board" without that commit (cancel / failure / disconnect / chess change) -> pit.abort
##
## The bridge never decides a winner and never edits the match.

signal presenting_changed(presenting: bool)

var flow: BattleFlow
var adapter: Node
var world: BattleWorld
var _return_requested := false
var _last_presenting := false


func setup(p_flow: BattleFlow, p_adapter: Node, p_world: BattleWorld) -> void:
	flow = p_flow
	adapter = p_adapter
	world = p_world
	flow.auto_return = false
	world.pit.require_arena = "arena" in adapter
	flow.phase_changed.connect(_on_phase)
	flow.result_ready.connect(_on_result)
	world.chamber.arena_mounted.connect(_on_arena_mounted)
	world.pit.return_ready.connect(_on_return_ready)
	world.pit.phase_changed.connect(_on_pit_phase)
	_royal_connect()  # king's last stand


func dispose() -> void:
	if world != null and is_instance_valid(world):
		world.pit.abort("disposed")
		for pair in [[flow.phase_changed, _on_phase], [flow.result_ready, _on_result], [world.chamber.arena_mounted, _on_arena_mounted], [world.pit.return_ready, _on_return_ready], [world.pit.phase_changed, _on_pit_phase]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
		_royal_disconnect()  # king's last stand
	if flow != null and is_instance_valid(flow):
		flow.auto_return = true
		flow.start_override = Callable()   # king's last stand
		flow.keep_arena_for_royal = false
	world = null


func is_presenting() -> bool:
	return world != null and not world.pit.is_idle()


## The UI's "Start battle". Returns {ok, error?}.
func start_battle() -> Dictionary:
	if flow.phase != "preview":
		return {"ok": false, "error": "No capture preview is ready."}
	var request: Dictionary = flow.game.pending_request()
	_return_requested = false
	if not world.pit.begin(request):
		return {"ok": false, "error": "The board could not present this capture."}
	var response: Dictionary = flow.confirm_capture()
	if not response.get("ok", false):
		world.pit.abort("battle did not start")
	return response


## "Skip": drop the presentation and commit the already-validated result at once.
func skip_to_board() -> void:
	if flow.phase == "aftermath":
		_return_requested = true
		world.pit.abort("skipped")
		flow.return_to_board()


func _on_phase(value: String) -> void:
	if value == "board" and not world.pit.is_idle() and not _return_requested:
		world.pit.abort("battle interrupted")
	if value == "board":
		_return_requested = false


func _on_result(result: Dictionary) -> void:
	world.pit.present_result(result)


func _on_arena_mounted(arena: Node) -> void:
	if arena.has_signal("battle_started"):
		arena.battle_started.connect(func(_request: Dictionary): world.pit.attach_arena(arena))


func _on_return_ready() -> void:
	if flow.phase == "aftermath":
		_return_requested = true
		flow.return_to_board()


func _on_pit_phase(_value: int) -> void:
	var now := is_presenting()
	if now != _last_presenting:
		_last_presenting = now
		presenting_changed.emit(now)


func _exit_tree() -> void:
	dispose()


# ======================================================================================================================
# BEGIN king's last stand (battle-royal-v1). The royal duels are mandatory and start by themselves: BattleFlow shows the banner
# and then calls `start_override` (instead of the UI's "Start battle"). The first duel descends once (pit.begin_sequence +
# pit.begin); every later duel of the same sequence is presented by the pit's INTERLUDE (pit.next_duel) and restarts the still
# mounted arena in place. The bridge still decides nothing: outcomes and the King's carried resources come from the flow/match.
# ======================================================================================================================

func _royal_connect() -> void:
	flow.start_override = Callable(self, "_royal_start")
	flow.keep_arena_for_royal = true
	world.pit.duel_cleared.connect(_on_duel_cleared)


func _royal_disconnect() -> void:
	if world != null and is_instance_valid(world) and world.pit.duel_cleared.is_connected(_on_duel_cleared):
		world.pit.duel_cleared.disconnect(_on_duel_cleared)


## Called by BattleFlow when a royal duel's banner is over. Returns {ok, error?}; only a pit failure is an error here (a failing
## confirm_capture has already been reported and recovered by the flow itself).
func _royal_start() -> Dictionary:
	var game = flow.game
	var request: Dictionary = game.pending_request()
	if request.is_empty() or not game.has_method("royal_request"):
		return {"ok": true}
	var pit: PitSequence = world.pit
	_return_requested = false
	if pit.is_idle():
		var progress: Dictionary = game.royal_progress()
		if not pit.begin_sequence(game.royal_request(), int(progress.get("duelIndex", 0))):
			return {"ok": false, "error": "The board could not present the King's last stand."}
		if not pit.begin(request):
			pit.end_sequence()
			return {"ok": false, "error": "The board could not present the King's last stand."}
	elif not pit.next_duel(request):
		return {"ok": false, "error": "The next duel could not be presented."}
	var response: Dictionary = flow.confirm_capture()
	if not response.get("ok", false):
		pit.abort("battle did not start")
	return {"ok": true}


## The King won a duel that is not the last: commit it (the match prepares the next duel and the banner shows).
func _on_duel_cleared(_index: int) -> void:
	if flow.phase == "aftermath":
		flow.return_to_board()
# END king's last stand
