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

const Music := preload("res://audio/music_director.gd")
const Codec := preload("res://contracts/codec.gd")
const CombatVfx := preload("res://combat/presentation/vfx/combat_vfx.gd")
const AUDIO_SCRIPT := "res://combat/audio/combat_audio.gd"

@export var mode: Mode = Mode.AUTHORITY
## false = no meshes, cameras, HUD or input: a dedicated-server style headless arena.
@export var presentation_enabled: bool = true
## Use the Blender-generated models when their GLBs exist; otherwise the procedural placeholder.
@export var use_models: bool = true
# --- BEGIN pit-world edit ---------------------------------------------------------------------
## true = the arena is mounted inside the shared BattleWorld (godot/world/): no own WorldEnvironment,
## lights restricted to the chamber render layers. Set before start_battle(). Default false = unchanged.
@export var embedded: bool = false
# --- END pit-world edit -----------------------------------------------------------------------

var sim: CombatSimulation
var hud: CombatHud
var cameras: Array[ThirdPersonCamera] = []
var seats: Dictionary = {}
## Presentation-only feedback layers (null without presentation): CombatVfx (sparks, trails, hitstop, camera feedback)
## and, when the audio module exists, CombatAudio.
var vfx: Node3D = null
var audio: Node = null
# --- BEGIN control-overlay edit ---------------------------------------------------------------
## In-battle controls cheat sheet (presentation/control_overlay.gd): one panel per local human seat, F1 / Share toggles it.
## Built once and reused between battles; hidden on the result screen. Null until the first presentation battle.
var overlay: ControlOverlay = null
# --- END control-overlay edit -----------------------------------------------------------------

var _codec = null
var _visuals: StoneArenaVisuals = null
var _fighter_visuals: Array[Node3D] = []
var _inputs: Array[LocalInputSource] = []
var _ais: Array[CombatAI] = []
var _split_layer: CanvasLayer = null
var _last_snapshot_tick: int = -1
var _targets: Dictionary = {}
var _mouse_captured: bool = false

## Online (PRESENTATION) mode only. See NETWORKING.md. The client model predicts the LOCAL fighter's
## movement, reconciles with snapshots, interpolates the remote fighter and de-duplicates events; it never
## sets HP or results (those are copied from validated snapshots).
const NetClient := preload("res://combat/net/combat_net_client.gd")
const RemoteInference := preload("res://combat/presentation/remote_action_inference.gd")
var net_client = null
var _net_local_id: String = ""
var _net_send: Callable = Callable()
var _net_builder: CombatInputBuilder = null
## false: the host application owns the input devices (e.g. OnlineCombatView / touch adapter run in the application's
## viewport and feed `net_client` directly), so the arena creates no LocalInputSource of its own.
var _net_own_input: bool = true
var _local_tick: int = 0
var _inference: Dictionary = {}


func _ready() -> void:
	sim = CombatSimulation.new()
	sim.name = "Simulation"
	add_child(sim)
	sim.event_emitted.connect(_on_event)
	sim.finished.connect(_on_finished)


func configure_seats(config: Dictionary) -> void:
	seats = config


## Online client: `local_player_id` is the authenticated seat this machine controls; `send` receives each
## CombatInput (one per 60 Hz tick) for the transport to deliver to the server. Call before start_battle().
## Snapshots from the server go to apply_snapshot(). Without this call PRESENTATION mode keeps its simple
## ease-to-snapshot behaviour (no prediction).
##
## `builder` (optional): the transport's own CombatInputBuilder for this seat, so there is exactly ONE sequence/counter
## stream (the online client restores it from the server's InputResume after a reconnect). Ignored when it belongs to
## another battle. `own_input` false: the caller feeds `net_client.set_intent()/press()` itself (see above).
func configure_network(local_player_id: String, send: Callable, builder: CombatInputBuilder = null, own_input: bool = true) -> void:
	_net_local_id = local_player_id
	_net_send = send
	_net_builder = builder
	_net_own_input = own_input
	seats = {local_player_id: {"type": "human", "scheme": "kb1"}}
	# Run after every input source in the same physics step, so this tick's intent is the one that is sent.
	process_priority = 100


# ---- public API ----------------------------------------------------------------------------
## `options` is passed straight to CombatSimulation.start (battle-royal-v1: king role + the King's carried resources);
## empty for every ordinary battle (strict v1 behaviour).
func start_battle(request: Dictionary, options: Dictionary = {}) -> Dictionary:
	if _codec == null:
		_codec = Codec.new()
	stop_battle()
	var reply: Dictionary = sim.start(request, options)
	if not reply["ok"]:
		return reply
	_local_tick = 0
	net_client = null
	_inference.clear()
	if mode == Mode.PRESENTATION and _net_local_id != "":
		var builder: CombatInputBuilder = _net_builder if _net_builder != null and _net_builder.battle_id == String(request["battleId"]) \
				and _net_builder.player_id == _net_local_id else null
		net_client = NetClient.new(request, _net_local_id, _net_send, builder)
		net_client.event_confirmed.connect(_on_event)
		net_client.result_received.connect(_on_net_result)
		for f in sim.fighters:
			_inference[f.player_id] = RemoteInference.new()
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
	if net_client != null:
		net_client.on_snapshot(snapshot, _local_tick)  # validates, orders, de-duplicates events, reconciles
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
	net_client = null
	_inference.clear()
	_clear_presentation()
	if sim != null:
		sim.stop()
	_seen_event = 0
	_targets.clear()


# ---- ticking -------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	if mode == Mode.PRESENTATION and net_client != null and sim != null and sim.is_running():
		net_step()
		return
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
	if sim != null and sim.is_running() and Engine.get_process_frames() % 6 == 0 and sim.fighters.size() == 2:
		var tree := get_tree()
		if tree != null and tree.root.has_node("MusicDirector"):
			var a = sim.fighters[0]
			var b = sim.fighters[1]
			Music.intensity(tree, Music.danger_from_health(float(a.health.current) / maxf(1.0, float(a.health.maximum)), float(b.health.current) / maxf(1.0, float(b.health.maximum))))
	if net_client != null:
		_refresh_net_views(float(_local_tick) + Engine.get_physics_interpolation_fraction())
	if _visuals != null:
		for cam in cameras:
			if is_instance_valid(cam) and cam.target != null:
				_visuals.fade_occluders(cam.camera.global_position, cam.target.global_position + Vector3(0, 1.0, 0))
	if mode != Mode.PRESENTATION or net_client != null:
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
	if vfx != null and is_instance_valid(vfx):
		vfx.on_event(event)  # also drives hitstop, hit reactions and camera feedback
	else:
		_fallback_shake(event)
	# Offline, CombatAudio listens to the simulation itself; online (PRESENTATION) events arrive only through here.
	# CombatAudio de-duplicates by eventId, so forwarding is always safe.
	if audio != null and is_instance_valid(audio) and mode == Mode.PRESENTATION and audio.has_method("on_event"):
		audio.on_event(event)


func _fallback_shake(event: Dictionary) -> void:
	var shake := 0.0
	match String(event["type"]):
		"hit":
			shake = 0.08 + minf(float(sim.felt_damage(int(event["damage"])) if sim != null else int(event["damage"])) / 120.0, 0.25)
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
	if overlay != null:
		overlay.on_battle_finished()  # control-overlay edit: the cheat sheet gives way to the result screen
	if hud != null:
		var winner := sim.fighter_by_id(result["winnerPlayerId"])
		var reasons := {"knockout": "Knockout", "timeout_hp": "Time - more health remaining", "timeout_tie": "Time - tie goes to the defender", "double_knockout": "Double knockout - defender holds"}
		var who := "%s (%s)" % [FighterRoster.display_name(winner.role), "White" if winner.color == "w" else "Black"] if winner != null else "?"
		hud.show_result("%s wins\n%s\n(attacker HP %d, defender HP %d)" % [who, reasons.get(result["reason"], result["reason"]), int(result["attackerHp"]), int(result["defenderHp"])])
	if vfx != null and is_instance_valid(vfx):
		vfx.on_result(result)  # winner victory pose / loser defeat pose / finish camera
	if audio != null and is_instance_valid(audio) and mode == Mode.PRESENTATION and audio.has_method("on_battle_finished"):
		audio.on_battle_finished(result)
	battle_finished.emit(result)
	_release_mouse()


# ---- presentation --------------------------------------------------------------------------
func _build_presentation(request: Dictionary) -> void:
	if _visuals == null:
		_visuals = StoneArenaVisuals.new()
		_visuals.name = "ArenaVisuals"
		_visuals.embedded = embedded  # pit-world edit
		add_child(_visuals)
		_visuals.build(CharacterModel.prefer_lod1)
	for f in sim.fighters:
		var visual: Node3D = null
		if use_models and (PaladinFighter.wanted(f.role) or CharacterModel.available(f.role, 1 if CharacterModel.prefer_lod1 else 0)):
			var model: CharacterModel = PaladinFighter.new() if PaladinFighter.wanted(f.role) else CharacterModel.new()
			add_child(model)
			if model.setup(f):
				visual = model
			else:
				remove_child(model)
				model.queue_free()
		if visual == null:
			var placeholder := FighterVisual.new()
			add_child(placeholder)
			placeholder.setup(f)
			visual = placeholder
		visual.name = "Visual_" + f.color
		_fighter_visuals.append(visual)

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
	_build_control_overlay(humans)  # control-overlay edit
	CombatDebug.attach(self)  # developer overlay (F3 / --combat-debug): hurt circles, live hit sector, state panel; invisible by default

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
	_build_feedback_layers(viewers)

	_ais.clear()
	_inputs.clear()
	for f in sim.fighters:
		var seat: Dictionary = seats.get(f.player_id, {"type": "ai", "skill": 0.6})
		var builder := CombatInputBuilder.new(request["matchId"], request["battleId"], f.player_id)
		if mode != Mode.AUTHORITY and net_client == null:
			continue
		if seat.get("type", "ai") == "human" and net_client != null and not _net_own_input:
			continue
		if seat.get("type", "ai") == "human":
			var source := LocalInputSource.new()
			source.scheme = String(seat.get("scheme", "kb1"))
			source.builder = builder
			source.fighter = f
			source.camera = cameras[humans.find(f.player_id)] if viewers.size() > 0 else null
			source.submit = Callable(self, "_submit_ignore_result")
			if net_client != null:
				source.net_client = net_client
			source.mouse_look = humans.size() == 1 and source.scheme == "kb1"
			add_child(source)
			_inputs.append(source)
			if source.mouse_look:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_captured = true
		elif mode == Mode.AUTHORITY:
			var opp := sim.opponent_of(f)
			_ais.append(CombatAI.new(builder, f.stats, opp.stats, int(request["seed"]) + (7 if f.color == "w" else 13), float(seat.get("skill", 0.6)), String(seat.get("style", "balanced"))))


signal rematch_requested
signal menu_requested


## VFX (always) and audio (when the module is present) for this battle. Both are presentation only.
func _build_feedback_layers(viewers: Array) -> void:
	CombatVfx.configure_from_args()
	vfx = CombatVfx.new()
	vfx.name = "CombatVfx"
	add_child(vfx)
	vfx.setup(sim, CharacterModel.prefer_lod1)
	vfx.allow_slowmo = mode == Mode.AUTHORITY and DisplayServer.get_name() != "headless"
	for i in sim.fighters.size():
		vfx.register_model(sim.fighters[i].player_id, _fighter_visuals[i])
	vfx.cameras = cameras.duplicate()
	if audio == null and (ResourceLoader.exists(AUDIO_SCRIPT) or FileAccess.file_exists(AUDIO_SCRIPT)):
		var script = load(AUDIO_SCRIPT)
		if script != null:
			audio = script.new()
	if audio != null:
		if audio.get_parent() == null:
			add_child(audio)
		if audio.has_method("setup"):
			audio.setup(self, sim)
		# Victory/defeat sting from the viewer's perspective: the first human, else the online seat.
		var viewer_id := _net_local_id if _net_local_id != "" else (String(viewers[0]) if not viewers.is_empty() and seats.get(viewers[0], {}).get("type", "") == "human" else "")
		if "local_player_id" in audio:
			audio.local_player_id = viewer_id
		if hud != null and audio.has_method("attach_ui"):
			audio.attach_ui(hud)


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


# --- BEGIN control-overlay edit ---------------------------------------------------------------
## Seats shown by the overlay: the human seats (online PRESENTATION: only the local one). AI seats show nothing.
func _build_control_overlay(humans: Array[String]) -> void:
	var list: Array = []
	for pid in humans:
		if _net_local_id != "" and pid != _net_local_id:
			continue
		var f := sim.fighter_by_id(pid)
		var scheme := String(seats[pid].get("scheme", "kb1"))
		list.append({"id": pid, "color": f.color, "role": f.role, "scheme": scheme, "mouse": humans.size() == 1 and scheme == "kb1"})
	if overlay == null:
		overlay = ControlOverlay.new()
		add_child(overlay)
	overlay.begin(list)
# --- END control-overlay edit -----------------------------------------------------------------


func _controls_hint(humans: Array[String]) -> String:
	if humans.is_empty():
		return "AI vs AI demonstration"
	var lines: Array[String] = []
	for i in humans.size():
		# Generated from the live bindings (combat/input/control_bindings.gd), so rebinding and the connected
		# pad's own button names (Cross/Circle vs A/B) show up here.
		lines.append("P%d  %s" % [i + 1, ControlBindings.shared().hint_text(String(seats[humans[i]].get("scheme", "kb1")))])
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
	if overlay != null and is_instance_valid(overlay):
		overlay.end()  # control-overlay edit (the node itself is reused by the next battle)
	if vfx != null and is_instance_valid(vfx):
		_discard(vfx)
	vfx = null
	# The audio node is reused between battles (its voice pools are expensive to rebuild); it is silenced here.
	if audio != null and is_instance_valid(audio) and audio.has_method("setup"):
		audio.setup(self, null)
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


# ---- online (net client) path ------------------------------------------------------------------
## One 60 Hz client tick: the net client sends this tick's CombatInput and advances prediction.
func net_step() -> void:
	_local_tick += 1
	net_client.tick(_local_tick)
	_refresh_net_views(float(_local_tick))


func _on_net_result(result: Dictionary) -> void:
	if net_client != null:
		net_client.active = false  # the battle is decided: stop sending inputs for it
	if sim.result.is_empty():
		sim.result = result
		_on_finished(result)


## Copies what the net client says to draw onto the proxy fighters. HP/stamina/cooldown come from
## validated snapshots; position of the local fighter is predicted, the remote one interpolated.
func _refresh_net_views(local_tick: float) -> void:
	if net_client == null or net_client.latest.is_empty():
		return
	for f in sim.fighters:
		var v: Dictionary = net_client.view(f.player_id, local_tick)
		if v.is_empty():
			continue
		f.global_position = v["position"]
		f.prev_position = f.global_position
		f.yaw = float(v["yawRadians"]) if v.has("yawRadians") else f.yaw
		f.prev_yaw = f.yaw
		f.health.current = int(v["hp"])
		f.stamina.current = float(v["stamina"])
		f.ability.cooldown_remaining = int(v["cooldownTicks"])
		f.velocity = v["velocity"]
		var state_index: int = CombatConstants.STATE_NAMES.find(String(v["state"]))
		if state_index >= 0:
			_inference[f.player_id].apply(f, state_index, int(v["stateTicks"]))
	var latest: Dictionary = net_client.latest["snap"] if net_client.latest.has("snap") else net_client.latest
	if latest.has("serverTick"):
		sim.server_tick = int(latest["serverTick"])
		sim.countdown_remaining = int(latest["countdownTicksRemaining"])
		sim.duration_remaining = int(latest["durationTicksRemaining"])
