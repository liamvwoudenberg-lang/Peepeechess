extends RefCounted
## Application-owned presentation hook. The arena keeps its simulation, events, cameras, input and pit lifecycle.
## Installing after start_battle also covers royal duels, which rebuild their HUD on every round.
const CompactHud = preload("res://app/courtyard_combat_hud.gd")

static func install(arena: Node, player_id: String = "") -> CombatHud:
	if arena == null or arena.get("hud") == null:
		return null
	var old: CombatHud = arena.hud
	if old is CourtyardCombatHud:
		return old
	var compact := CompactHud.new()
	compact.name = "Hud"
	compact.local_player_id = player_id
	if compact.local_player_id == "":
		for fighter in arena.sim.fighters:
			if arena.seats.get(fighter.player_id, {}).get("type", "") == "human":
				compact.local_player_id = fighter.player_id
				break
	compact.visible = old.visible  # the pit hides overlays during the drop, then releases them itself
	compact.set_names(old._names.duplicate())
	var context := old.context_text()
	arena.remove_child(old)
	old.queue_free()
	arena.hud = compact
	arena.add_child(compact)
	compact.setup(arena.sim, "")
	compact.damage_projection = _project_damage.bind(arena)
	compact.set_context(context)
	compact.rematch_requested.connect(func(): arena.rematch_requested.emit())
	compact.menu_requested.connect(func(): arena.menu_requested.emit())
	if arena.audio != null and arena.audio.has_method("attach_ui"):
		arena.audio.attach_ui(compact)
	if arena.overlay != null:
		# Help stays one F1 / Share / touch-? away, without an automatic instruction panel over a fight.
		arena.overlay.request_mode(ControlOverlay.Mode.OFF)
	return compact

## The original two-human arena uses two rendering viewports. Project into the first visible view; a single-view
## local pit uses the active world camera and online uses its own third-person camera, all without moving fighters.
static func _project_damage(fighter: FighterController, arena: Node) -> Dictionary:
	if not is_instance_valid(arena) or not is_instance_valid(fighter):
		return {"visible": false}
	var camera: Camera3D = arena.get_viewport().get_camera_3d()
	var panel: Control = null
	if arena.cameras.size() > 1 and arena._split_layer != null and arena._split_layer.visible:
		camera = arena.cameras[0].camera
		panel = camera.get_viewport().get_parent() as Control
	var point := fighter.global_position + Vector3.UP * 1.7
	if camera == null or camera.is_position_behind(point):
		return {"visible": false}
	var position := camera.unproject_position(point)
	if panel != null:
		position = panel.global_position + position * panel.size / camera.get_viewport().get_visible_rect().size.max(Vector2.ONE)
	return {"visible": true, "position": position}
