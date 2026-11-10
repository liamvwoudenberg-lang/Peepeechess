class_name CombatArena
extends Node3D
## Mount point for the combat module (planned convention in docs/architecture/ARCHITECTURE.md):
##
##   start_battle(request: Dictionary) -> Dictionary   BattleRequest in, {ok, code?, message?} out
##   submit_input(input: Dictionary)   -> Dictionary   CombatInput in (authority mode only)
##   apply_snapshot(snapshot: Dictionary)              CombatSnapshot in (presentation mode only)
##   stop_battle()
##   signals: combat_snapshot(snapshot) at 15 Hz, battle_finished(result) once, battle_started(request)
##
## Modes
##   AUTHORITY    runs a CombatSimulation locally and ticks it at 60 Hz from _physics_process. This is
##                what offline / hot-seat play and the standalone test arena use. It is NOT a trusted
##                online authority: in an online match the server hosts the CombatSimulation and this
##                node runs in PRESENTATION mode.
##   PRESENTATION never simulates; it only draws what apply_snapshot() delivers.
##
## Seats are configured with configure_seats() BEFORE start_battle():
##   {"player-white": {"type": "human", "scheme": "kb1"}, "player-black": {"type": "ai", "skill": 0.6}}

enum Mode { AUTHORITY, PRESENTATION }

signal combat_snapshot(snapshot: Dictionary)
signal battle_finished(result: Dictionary)
signal battle_started(request: Dictionary)

const Codec := preload("res://contracts/codec.gd")

@export var mode: Mode = Mode.AUTHORITY
## false = no meshes, cameras, HUD or input: a dedicated-server style headless arena.
@export var presentation_enabled: bool = true

var sim: CombatSimulation
var hud: CombatHud
var cameras: Array[ThirdPersonCamera] = []
var seats: Dictionary = {}

var _codec = null
var _visuals: StoneArenaVisuals = null
var _fighter_visuals: Array[FighterVisual] = []
var _inputs: Array[LocalInputSource] = []
var _ais: Array[CombatAI] = []
var _split_layer: CanvasLayer = null
var _last_snapshot_tick: int = -1
var _targets: Dictionary = {}
var _mouse_captured: bool = false


func _ready() -> void:
	sim = CombatSimulation.new()
	sim.name = "Simulation"
	add_child(sim)
	sim.event_emitted.connect(_on_event)
	sim.finished.connect(_on_finished)


func configure_seats(config: Dictionary) -> void:
	seats = config


# ---- public API ----------------------------------------------------------------------------
func start_battle(request: Dictionary) -> Dictionary:
	if _codec == null:
		_codec = Codec.new()
	stop_battle()
	var reply: Dictionary = sim.start(request)
	if not reply["ok"]:
		return reply
	if presentation_enabled:
		_build_presentation(request)
	_last_snapshot_tick = -1
	battle_started.emit(request)
	return {"ok": true}


func submit_input(input: Dictionary) -> Dictionary:
	if mode != Mode.AUTHORITY:
		return {"ok": false, "code": "FORBIDDEN", "message": "inputs go to the server, not to a presentation arena"}
	return sim.submit_input(input)


## Presentation mode: draw an authoritative snapshot. Older snapshots are discarded; fighters
## ease toward the new state rather than teleporting.
func apply_snapshot(snapshot: Dictionary) -> void:
	if mode != Mode.PRESENTATION or sim == null or sim.request.is_empty():
		return
	if not _codec.valid("CombatSnapshot", snapshot):
		return
	if int(snapshot["serverTick"]) < _last_snapshot_tick:
		return
	_last_snapshot_tick = int(snapshot["serverTick"])
	sim.server_tick = _last_snapshot_tick
	sim.countdown_remaining = int(snapshot["countdownTicksRemaining"])
	sim.duration_remaining = int(snapshot["durationTicksRemaining"])
	for entry in snapshot["fighters"]:
		var f := sim.fighter_by_id(entry["playerId"])
		if f == null:
			continue
		f.health.current = int(entry["hp"])
		f.stamina.current = float(entry["stamina"])
		f.sm.state = CombatConstants.STATE_NAMES.find(String(entry["state"]))
		f.sm.state_ticks = int(entry["stateTicks"])
		f.ability.cooldown_remaining = int(entry["cooldownTicks"])
		_targets[f.player_id] = {"pos": Vector3(entry["position"]["x"], 0.0, entry["position"]["z"]), "yaw": float(entry["yawRadians"])}
		f.velocity = Vector3(entry["velocity"]["x"], 0.0, entry["velocity"]["z"])
	for event in snapshot["events"]:
		if int(event["eventId"]) > _seen_event:
			_seen_event = int(event["eventId"])
			_on_event(event)
	if snapshot["result"] != null and sim.result.is_empty():
		sim.result = snapshot["result"]
		_on_finished(sim.result)


var _seen_event: int = 0


func stop_battle() -> void:
	_clear_presentation()
	if sim != null:
		sim.stop()
	_seen_event = 0
	_targets.clear()


# ---- ticking -------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if mode != Mode.AUTHORITY or sim == null or not sim.is_running():
		return
	if not _ais.is_empty():
		var snap := sim.snapshot()
		for ai in _ais:
			sim.submit_input(ai.think(snap))
	sim.step_tick()
	if sim.server_tick % CombatConstants.SNAPSHOT_EVERY_TICKS == 0 or not sim.is_running():
		combat_snapshot.emit(sim.snapshot())


func _process(_delta: float) -> void:
	if _visuals != null:
		for cam in cameras:
			if is_instance_valid(cam) and cam.target != null:
				_visuals.fade_occluders(cam.camera.global_position, cam.target.global_position + Vector3(0, 1.0, 0))
	if mode != Mode.PRESENTATION:
		return
	for pid in _targets:
		var f := sim.fighter_by_id(pid)
		if f == null:
			continue
		var t: Dictionary = _targets[pid]
		f.global_position = f.global_position.lerp(t["pos"], 0.35)
		f.yaw = lerp_angle(f.yaw, t["yaw"], 0.35)
		f.prev_position = f.global_position
		f.prev_yaw = f.yaw


# ---- events --------------------------------------------------------------------------------
func _on_event(event: Dictionary) -> void:
	if hud != null:
		hud.on_event(event)
	var kind: String = event["type"]
	var shake := 0.0
	match kind:
		"hit":
			shake = 0.08 + minf(float(event["damage"]) / 120.0, 0.25)
		"guardbreak":
			shake = 0.3
		"parry":
			shake = 0.2
		"block":
			shake = 0.05
	if shake > 0.0:
		for cam in cameras:
			cam.add_shake(shake)


func _on_finished(result: Dictionary) -> void:
	if hud != null:
		var winner := sim.fighter_by_id(result["winnerPlayerId"])
		var reasons := {"knockout": "Knockout", "timeout_hp": "Time - more health remaining", "timeout_tie": "Time - tie goes to the defender", "double_knockout": "Double knockout - defender holds"}
		var who := "%s (%s)" % [FighterRoster.display_name(winner.role), "White" if winner.color == "w" else "Black"] if winner != null else "?"
		hud.show_result("%s wins\n%s\n(attacker HP %d, defender HP %d)" % [who, reasons.get(result["reason"], result["reason"]), int(result["attackerHp"]), int(result["defenderHp"])])
	battle_finished.emit(result)
	_release_mouse()


# ---- presentation --------------------------------------------------------------------------
func _build_presentation(request: Dictionary) -> void:
	if _visuals == null:
		_visuals = StoneArenaVisuals.new()
		_visuals.name = "ArenaVisuals"
		add_child(_visuals)
		_visuals.build()
	for f in sim.fighters:
		var fv := FighterVisual.new()
		fv.name = "Visual_" + f.color
		add_child(fv)
		fv.setup(f)
		_fighter_visuals.append(fv)
		# Hide the collision-capsule owner's own meshes: fighters carry no meshes, visuals do.

	hud = CombatHud.new()
	hud.name = "Hud"
	add_child(hud)
	var names := {}
	var humans: Array[String] = []
	var hint := ""
	for f in sim.fighters:
		var seat: Dictionary = seats.get(f.player_id, {"type": "ai", "skill": 0.6})
		if seat.get("type", "ai") == "human":
			humans.append(f.player_id)
			names[f.player_id] = "P%d" % humans.size()
		else:
			names[f.player_id] = "CPU" if mode == Mode.AUTHORITY else ""
	hud.set_names(names)
	hud.setup(sim, _controls_hint(humans))
	hud.rematch_requested.connect(func(): rematch_requested.emit())
	hud.menu_requested.connect(func(): menu_requested.emit())

	cameras.clear()
	var viewers := humans.duplicate()
	if viewers.is_empty():
		viewers.append(sim.fighters[0].player_id)  # spectator view for AI vs AI
	for index in viewers.size():
		var f := sim.fighter_by_id(viewers[index])
		var cam := ThirdPersonCamera.new()
		cam.name = "Camera%d" % index
		if viewers.size() == 2:
			_ensure_split_layer()
			var container: SubViewportContainer = _split_layer.get_node("Row").get_child(index)
			container.get_child(0).add_child(cam)
		else:
			add_child(cam)
		cam.bind(f, sim.opponent_of(f))
		cameras.append(cam)

	_ais.clear()
	_inputs.clear()
	for f in sim.fighters:
		var seat: Dictionary = seats.get(f.player_id, {"type": "ai", "skill": 0.6})
		var builder := CombatInputBuilder.new(request["matchId"], request["battleId"], f.player_id)
		if mode != Mode.AUTHORITY:
			continue
		if seat.get("type", "ai") == "human":
			var source := LocalInputSource.new()
			source.scheme = String(seat.get("scheme", "kb1"))
			source.builder = builder
			source.fighter = f
			source.camera = cameras[humans.find(f.player_id)] if viewers.size() > 0 else null
			source.submit = Callable(self, "_submit_ignore_result")
			source.mouse_look = humans.size() == 1 and source.scheme == "kb1"
			add_child(source)
			_inputs.append(source)
			if source.mouse_look:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_captured = true
		else:
			var opp := sim.opponent_of(f)
			_ais.append(CombatAI.new(builder, f.stats, opp.stats, int(request["seed"]) + (7 if f.color == "w" else 13), float(seat.get("skill", 0.6))))


signal rematch_requested
signal menu_requested


func _submit_ignore_result(packet: Dictionary) -> void:
	sim.submit_input(packet)


func _ensure_split_layer() -> void:
	if _split_layer != null:
		return
	_split_layer = CanvasLayer.new()
	_split_layer.layer = 0
	var row := HBoxContainer.new()
	row.name = "Row"
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 4)
	_split_layer.add_child(row)
	for _i in 2:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var viewport := SubViewport.new()
		viewport.handle_input_locally = false
		viewport.size = Vector2i(640, 720)
		container.add_child(viewport)
		row.add_child(container)
	add_child(_split_layer)


func _controls_hint(humans: Array[String]) -> String:
	if humans.is_empty():
		return "AI vs AI demonstration"
	var lines: Array[String] = []
	for i in humans.size():
		var scheme: String = String(seats[humans[i]].get("scheme", "kb1"))
		match scheme:
			"kb1":
				lines.append("P%d  WASD move · Shift sprint · LMB/F light · RMB/G heavy · Q hold block · E parry · Space dodge · R ability · Tab lock-on · mouse/Z,X camera" % (i + 1))
			"kb2":
				lines.append("P%d  Arrows move · Ctrl sprint · J light · K heavy · U hold block · I parry · L dodge · O ability · P lock-on · ,/. camera" % (i + 1))
			_:
				lines.append("P%d  Pad: stick move · X light · Y heavy · LB block · RB parry · A dodge · B ability · LT sprint · L3 lock" % (i + 1))
	return "\n".join(lines)


func _clear_presentation() -> void:
	_release_mouse()
	# Detach at once (not just queue_free): a queued node would keep running for a frame against
	# fighters the simulation has already removed, and would also keep its name.
	for node in _fighter_visuals + _inputs + cameras:
		_discard(node)
	_fighter_visuals.clear()
	_inputs.clear()
	_ais.clear()
	cameras.clear()
	if hud != null and is_instance_valid(hud):
		_discard(hud)
	hud = null
	if _split_layer != null and is_instance_valid(_split_layer):
		_discard(_split_layer)
	_split_layer = null


func _discard(node: Node) -> void:
	if not is_instance_valid(node):
		return
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _release_mouse() -> void:
	if _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false
