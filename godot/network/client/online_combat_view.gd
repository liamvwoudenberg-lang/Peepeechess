class_name OnlineCombatView
extends Node
## Mounts Claude's arena for an authoritative server battle and drives it through its NETWORK CLIENT path
## (CombatArena.configure_network -> CombatNetClient): the local fighter is predicted from local input and reconciled
## with every snapshot, the remote fighter is interpolated, events are de-duplicated, HP/stamina/cooldown/results come
## only from validated server snapshots. The arena's own simulation never ticks and never settles chess.
##
## Every input device feeds the SAME predicted fighter: the keyboard/mouse/gamepad LocalInputSource created here (it lives
## in the application's viewport, the arena viewport only draws) and the on-screen touch adapter both call
## `net_client()` (`set_intent` once per frame/tick, `press` per button edge). The arena's tick then sends exactly one
## CombatInput per 60 Hz physics tick built by the ONE CombatInputBuilder owned by OnlineChessClient, so sequence numbers
## and cumulative press counters survive reconnects (the server's InputResume restores that builder).
##
## Interface a host (lobby, BattleWorld presentation) relies on:
##   setup(client, host_viewport)  once;  sync(frame)  on every MatchFrame;  stop();  arena / source / net_client()
##   `host_viewport` receives the arena instance; the view only needs a SubViewport (or any Node) to parent it to.
const Arena = preload("res://combat/arena.tscn")
const Source = preload("res://combat/presentation/local_input_source.gd")
var arena: CombatArena
var source: LocalInputSource
var client: OnlineChessClient
var battle_id = ""
var input_scheme = "kb1"
var touch_enabled = false
var _host: Node
## For a world presentation (BattleWorld/pit): mounted after `start_battle` (the arena is already a child of the host), unmounted
## just before the arena is freed. `host` may be any Node (a SubViewport in the lobby, an ArenaMount Node3D in the pit world).
signal arena_mounted(arena: CombatArena)
signal arena_unmounted

func setup(network_client: OnlineChessClient, host: Node) -> void:
	client = network_client
	_host = host
	client.combat_received.connect(apply_snapshot)
	client.clocks_received.connect(_clock_sync)
	client.connection_changed.connect(_connection_changed)

## The arena's prediction/reconciliation client for the running battle (null when no battle is mounted). Input devices
## talk to this: `set_intent(move_x, move_z, yaw, lock, sprint, block)` and `press("light"|"heavy"|"dodge"|"parry"|"ability")`.
func net_client():
	return arena.net_client if arena != null else null

func sync(frame: Dictionary) -> void:
	if frame.state.battle == null or frame.state.phase not in ["combat", "aftermath"]:
		stop()
		return
	var request: Dictionary = frame.state.battle
	if request.battleId != battle_id:
		stop()
		arena = Arena.instantiate()
		arena.mode = CombatArena.Mode.PRESENTATION
		# The transport owns the seat's builder (restored from InputResume); the arena sends through the same client.
		arena.configure_network(client.player_id, client.submit_combat_input, client.input_builder, false)
		_host.add_child(arena)
		var reply = arena.start_battle(request)
		if not reply.ok or arena.net_client == null:
			client.protocol_error.emit(client._error("INTERNAL", "The local combat presentation could not initialize."))
			stop()
			return
		battle_id = request.battleId
		source = Source.new()
		source.scheme = input_scheme
		source.net_client = arena.net_client
		source.fighter = arena.sim.fighter_by_id(client.player_id)
		source.camera = arena.cameras[0]
		source.mouse_look = input_scheme == "kb1"
		# Input lives in the application's viewport; the arena viewport only draws.
		add_child(source)
		arena_mounted.emit(arena)
	if source != null:
		source.net_client = arena.net_client
		source.enabled = client.authenticated and frame.state.phase == "combat" and not touch_enabled
	if not client.latest_combat.is_empty():
		apply_snapshot(client.latest_combat)

func apply_snapshot(snapshot: Dictionary) -> void:
	if arena != null and snapshot.battleId == battle_id:
		arena.apply_snapshot(snapshot)

## The 5 Hz ClockSync carries the server tick (equal to the combat tick while a battle runs): one more sample for the
## client's clock estimate, which survives a lost snapshot.
func _clock_sync(sync_message: Dictionary) -> void:
	var net = net_client()
	if net != null and client.frame.get("state", {}).get("phase") == "combat" and sync_message.matchId == client.frame.state.matchId:
		if int(sync_message.serverTick) >= int(client.frame.state.battle.startTick):
			net.on_clock_sync(int(sync_message.serverTick), arena._local_tick)

## A lost connection must not leave the predicted fighter running on its last intent: go neutral (nothing is sent while
## unauthenticated anyway; the server neutralises a silent seat after 15 ticks and the prediction must agree).
func _connection_changed(connected: bool) -> void:
	var net = net_client()
	if net != null and not connected:
		net.set_intent(0.0, 0.0, arena.sim.fighter_by_id(client.player_id).yaw, true, false, false)

func stop() -> void:
	if source != null:
		source.enabled = false
		remove_child(source)
		source.queue_free()
		source = null
	if arena != null:
		arena_unmounted.emit()
		arena.stop_battle()
		_host.remove_child(arena)
		arena.queue_free()
		arena = null
	battle_id = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and arena != null:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
	stop()
