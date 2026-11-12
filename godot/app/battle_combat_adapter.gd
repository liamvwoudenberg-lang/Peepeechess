class_name BattleCombatAdapter
extends Node
## Codex-owned bridge to Claude's arena; contains no combat mechanics or winner logic.
signal arena_ready
signal snapshot_received(snapshot: Dictionary)
signal result_received(result: Dictionary)
signal failed(message: String)
const DEFAULT_SCENE = "res://combat/arena.tscn"
const Codec = preload("res://contracts/codec.gd")
var scene_path = DEFAULT_SCENE
var presentation_enabled = true
## Set by the computer opponent (chess/ai/computer_opponent.gd): {color, seat: {type:"ai", skill, style, attacker_style}}. That colour is
## fought by CombatAI; the human then always uses seat 1's controls whichever colour they play. Empty = two humans.
var computer_seat: Dictionary = {}
var arena: Node
var _loading = false
var _generation = 0
var _host: Node
var _request: Dictionary = {}
var _codec = Codec.new()

func available() -> bool:
	return ResourceLoader.exists(scene_path, "PackedScene")

## `options` is empty for every ordinary capture. battle-royal-v1 passes {"allow_experimental_roles": true, ...} for a
## king duel: only the king role is then relaxed, exactly like CombatSimulation.start does; everything else is validated.
func check_request(request: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not available():
		return {"ok": false, "error": "Combat is unavailable in this build. Return to the board or play Classic."}
	var experimental = bool(options.get("allow_experimental_roles", false))
	var checked: Dictionary = request
	if experimental and request.get("attacker") is Dictionary and request.get("defender") is Dictionary:
		checked = request.duplicate(true)
		for seat in ["attacker", "defender"]:
			if checked[seat].get("role", "") == "k":
				checked[seat]["role"] = "q"
	if not _codec.valid("BattleRequest", checked):
		return {"ok": false, "code": "INVALID_PAYLOAD", "error": "Invalid battle request."}
	# Capabilities come from the combat owner, never from a substitute fighter.
	if scene_path == DEFAULT_SCENE:
		var profile = load("res://combat/core/fighter_profile.gd")
		for participant in [request.attacker, request.defender]:
			if not (profile.supports_role(participant.role) or (experimental and profile.is_experimental_role(participant.role))):
				return {"ok": false, "code": "INVALID_PAYLOAD", "error": "Combat for %s is not implemented by the combat module yet. Cancel to return to the board." % {"p": "Pawn", "n": "Knight", "b": "Bishop", "r": "Rook", "q": "Queen", "k": "King"}[participant.role]}
	return {"ok": true}

func begin_load(request: Dictionary, host: Node, options: Dictionary = {}) -> Dictionary:
	stop()
	var supported = check_request(request, options)
	if not supported.ok:
		return supported
	_host = host
	var error = ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	if error != OK:
		return {"ok": false, "error": "The combat scene could not be queued for loading."}
	_loading = true
	return {"ok": true}

func _process(_delta: float) -> void:
	if not _loading:
		return
	var status = ResourceLoader.load_threaded_get_status(scene_path)
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		_loading = false
		failed.emit("The combat scene failed to load.")
	elif status == ResourceLoader.THREAD_LOAD_LOADED:
		_loading = false
		var resource = ResourceLoader.load_threaded_get(scene_path)
		if not resource is PackedScene or not is_instance_valid(_host):
			failed.emit("The combat scene or mount point is unavailable.")
			return
		arena = resource.instantiate()
		for method in ["start_battle", "stop_battle"]:
			if not arena.has_method(method):
				stop()
				failed.emit("The combat scene does not implement " + method + ".")
				return
		for event in ["combat_snapshot", "battle_finished"]:
			if not arena.has_signal(event):
				stop()
				failed.emit("The combat scene does not expose " + event + ".")
				return
		arena.connect("combat_snapshot", _snapshot.bind(_generation))
		arena.connect("battle_finished", _result.bind(_generation))
		_host.add_child(arena)
		arena_ready.emit()

func start(request: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not is_instance_valid(arena):
		return {"ok": false, "error": "The combat scene is not ready."}
	var supported = check_request(request, options)
	if not supported.ok:
		return supported
	if arena.has_method("configure_seats"):
		# Controls (claude/pads-input): White = Player 1's device, Black = Player 2's. Two pads -> one each; with fewer
		# pads the keyboard sets fill in (kb1 / kb2), exactly as before when no pad is connected. See combat/input/.
		var seats = {}
		var assignment: InputAssignment = InputAssignment.shared()
		assignment.lock_for_match()  # a pad that disconnects mid-fight keeps its seat (PadHold pauses the fight)
		for participant in [request.attacker, request.defender]:
			if not computer_seat.is_empty() and participant.color == computer_seat.color:
				seats[participant.playerId] = computer_seat.seat.duplicate()
				if participant.playerId == request.attacker.playerId:
					seats[participant.playerId].style = computer_seat.seat.get("attacker_style", computer_seat.seat.get("style", "balanced"))
			else:
				seats[participant.playerId] = {"type": "human", "scheme": assignment.scheme_for_color("w" if not computer_seat.is_empty() else participant.color)}
		arena.call("configure_seats", seats)
	for property in arena.get_property_list():
		if property.name == "presentation_enabled":
			arena.set("presentation_enabled", presentation_enabled)
	_request = request.duplicate(true)
	var response = arena.call("start_battle", request.duplicate(true)) if options.is_empty() else arena.call("start_battle", request.duplicate(true), options.duplicate(true))
	var outcome = _response(response)
	if outcome.ok and arena.has_method("configure_seats"):
		PadHold.attach(arena)  # pauses the fight if a seat's controller disconnects; resumes on reconnect
	return outcome

func _response(value: Variant) -> Dictionary:
	if value == null:
		return {"ok": true}
	if not value is Dictionary or not value.get("ok") is bool:
		return {"ok": false, "error": "The combat module returned an invalid response."}
	var response: Dictionary = value.duplicate(true)
	if not response.ok:
		response["error"] = response.get("error", response.get("message", "The combat module rejected the request."))
	return response

## true while a loaded arena is mounted and not loading a new one (battle-royal-v1 restarts it in place for the next duel
## of a sequence instead of reloading the scene; see BattleFlow.keep_arena_for_royal).
func has_live_arena() -> bool:
	return is_instance_valid(arena) and not _loading and arena.is_inside_tree()

## End/current resources of one seat as the trusted local simulation reports them ({} without a running arena). Only the
## royal ruleset reads this: the King's HP/stamina/cooldown carry over from the authority, never from a client packet.
func fighter_state(player_id: String) -> Dictionary:
	if not is_instance_valid(arena) or arena.get("sim") == null or not arena.sim.has_method("fighter_state"):
		return {}
	return arena.sim.fighter_state(player_id)

## The hosting layer supplies the authenticated seat; inputs contain intent only.
func submit_input(packet: Dictionary, authenticated_player_id: String) -> Dictionary:
	if not is_instance_valid(arena) or _request.is_empty() or not arena.has_method("submit_input"):
		return {"ok": false, "code": "FORBIDDEN", "error": "No active combat authority."}
	if not _codec.valid("CombatInput", packet):
		return {"ok": false, "code": "INVALID_PAYLOAD", "error": "Invalid combat input."}
	if packet.playerId != authenticated_player_id or authenticated_player_id not in [_request.attacker.playerId, _request.defender.playerId] or packet.matchId != _request.matchId or packet.battleId != _request.battleId:
		return {"ok": false, "code": "FORBIDDEN", "error": "Combat input does not belong to this seat and battle."}
	return _response(arena.call("submit_input", packet.duplicate(true)))

func _snapshot(value: Variant, generation: int) -> void:
	if generation == _generation and value is Dictionary:
		snapshot_received.emit(value.duplicate(true))

func _result(value: Variant, generation: int) -> void:
	if generation == _generation and value is Dictionary:
		result_received.emit(value.duplicate(true))

func stop() -> void:
	InputAssignment.shared().unlock()
	_generation += 1
	_loading = false
	_request.clear()
	if is_instance_valid(arena):
		var old = arena
		arena = null
		if old.has_method("stop_battle"):
			old.call("stop_battle")
		if old.get_parent():
			old.get_parent().remove_child(old)
		old.queue_free()

func _exit_tree() -> void:
	stop()
