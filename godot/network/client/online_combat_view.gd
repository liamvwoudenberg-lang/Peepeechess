class_name OnlineCombatView
extends Node
## Uses Claude's arena in PRESENTATION mode. Its local simulation never ticks or settles chess.
const Arena = preload("res://combat/arena.tscn")
const Source = preload("res://combat/presentation/local_input_source.gd")
var arena: CombatArena
var source: LocalInputSource
var client: OnlineChessClient
var battle_id = ""
var input_scheme = "kb1"
var touch_enabled = false
var _host: SubViewport

func setup(network_client: OnlineChessClient, host: SubViewport) -> void:
	client = network_client
	_host = host
	client.combat_received.connect(apply_snapshot)

func sync(frame: Dictionary) -> void:
	if frame.state.battle == null or frame.state.phase not in ["combat", "aftermath"]:
		stop()
		return
	var request: Dictionary = frame.state.battle
	if request.battleId != battle_id:
		stop()
		arena = Arena.instantiate()
		arena.mode = CombatArena.Mode.PRESENTATION
		arena.configure_seats({client.player_id: {"type": "human", "scheme": input_scheme}})
		_host.add_child(arena)
		var reply = arena.start_battle(request)
		if not reply.ok:
			client.protocol_error.emit(client._error("INTERNAL", "The local combat presentation could not initialize."))
			stop()
			return
		battle_id = request.battleId
		source = Source.new()
		source.scheme = input_scheme
		source.builder = client.input_builder
		source.fighter = arena.sim.fighter_by_id(client.player_id)
		source.camera = arena.cameras[0]
		source.submit = client.submit_combat_input
		source.mouse_look = input_scheme == "kb1"
		# Input lives in the application's viewport; the arena viewport only draws.
		add_child(source)
	if source != null:
		source.builder = client.input_builder
		source.enabled = client.authenticated and frame.state.phase == "combat" and not touch_enabled
	if arena != null and arena.overlay != null:  # control-overlay edit: show the device the local seat really uses
		arena.overlay.set_seat_scheme(client.player_id, "touch" if touch_enabled else input_scheme, input_scheme == "kb1" and not touch_enabled)
	if not client.latest_combat.is_empty():
		apply_snapshot(client.latest_combat)

func apply_snapshot(snapshot: Dictionary) -> void:
	if arena != null and snapshot.battleId == battle_id:
		arena.apply_snapshot(snapshot)

func stop() -> void:
	if source != null:
		source.enabled = false
		remove_child(source)
		source.queue_free()
		source = null
	if arena != null:
		arena.stop_battle()
		_host.remove_child(arena)
		arena.queue_free()
		arena = null
	battle_id = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and arena != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# control-overlay edit: the arena's SubViewport receives no input here ("the arena viewport only draws"), so F1 / Share are relayed.
	if arena != null and arena.overlay != null:
		arena.overlay.handle_event(event)

func _exit_tree() -> void:
	stop()
