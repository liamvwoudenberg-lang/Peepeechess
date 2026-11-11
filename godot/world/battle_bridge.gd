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


func dispose() -> void:
	if world != null and is_instance_valid(world):
		world.pit.abort("disposed")
		for pair in [[flow.phase_changed, _on_phase], [flow.result_ready, _on_result], [world.chamber.arena_mounted, _on_arena_mounted], [world.pit.return_ready, _on_return_ready], [world.pit.phase_changed, _on_pit_phase]]:
			if pair[0].is_connected(pair[1]):
				pair[0].disconnect(pair[1])
	if flow != null and is_instance_valid(flow):
		flow.auto_return = true
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
