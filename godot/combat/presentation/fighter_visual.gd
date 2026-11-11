class_name FighterVisual
extends Node3D
## Placeholder humanoid built from primitives (no art assets). It only READS the fighter
## (state, timers, hitbox shape) and never changes combat. The model faces +Z, matching the
## gameplay heading at yaw = 0. Poses are driven by the same AttackDefinition timeline that
## drives hit windows (startup / active / recovery), so the swing a player sees is the swing the
## simulation resolves.

const S := CombatConstants.State

var fighter: FighterController
var rig: Node3D
var torso: Node3D
var head: Node3D
var arm_r: Node3D   # character's right arm sits at -X (it faces +Z)
var arm_l: Node3D
var leg_r: Node3D
var leg_l: Node3D
var weapon: Node3D
var shield: MeshInstance3D = null
var arc_fx: MeshInstance3D
var aura: MeshInstance3D
var _mats: Array[StandardMaterial3D] = []
var _walk_phase: float = 0.0
var _time: float = 0.0
var _arc_key: String = ""
var _pose: Dictionary = {"arm": -1.6, "arm_roll": 0.0, "lean": 0.0, "twist": 0.0, "crouch": 0.0, "shift": 0.0, "arm_l": -0.3}


func setup(f: FighterController) -> void:
	fighter = f
	var white := f.color == "w"
	var cloth := Color(0.86, 0.82, 0.7) if white else Color(0.3, 0.12, 0.36)
	var metal := Color(0.62, 0.64, 0.7) if f.role == "n" else Color(0.45, 0.36, 0.26)
	var trim := Color(0.85, 0.68, 0.22) if white else Color(0.75, 0.15, 0.2)
	var s := 1.04 if f.role == "n" else 0.94
	rig = Node3D.new()
	rig.scale = Vector3(s, s, s)
	add_child(rig)
	var body := Node3D.new()
	rig.add_child(body)
	torso = Node3D.new()
	torso.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(torso)
	var chest_w := 0.36 if f.role == "n" else 0.3
	_part(torso, CapsuleMesh.new(), Vector3(0.0, 0.32, 0.0), metal, func(m: CapsuleMesh): m.radius = chest_w * 0.8; m.height = 0.7)
	_part(torso, BoxMesh.new(), Vector3(0.0, 0.05, 0.0), cloth, func(m: BoxMesh): m.size = Vector3(chest_w * 1.5, 0.35, 0.3))
	_part(torso, BoxMesh.new(), Vector3(0.0, 0.62, 0.0), trim, func(m: BoxMesh): m.size = Vector3(chest_w * 1.9, 0.07, 0.34))
	head = Node3D.new()
	head.position = Vector3(0.0, 0.84, 0.0)
	torso.add_child(head)
	_part(head, SphereMesh.new(), Vector3.ZERO, metal.lightened(0.1), func(m: SphereMesh): m.radius = 0.16; m.height = 0.32)
	if f.role == "n":
		_part(head, CylinderMesh.new(), Vector3(0.0, 0.17, -0.02), trim, func(m: CylinderMesh): m.top_radius = 0.0; m.bottom_radius = 0.07; m.height = 0.3)
		_part(head, BoxMesh.new(), Vector3(0.0, 0.0, 0.14), Color(0.05, 0.05, 0.06), func(m: BoxMesh): m.size = Vector3(0.22, 0.03, 0.02))
	else:
		_part(head, SphereMesh.new(), Vector3(0.0, 0.07, -0.01), cloth, func(m: SphereMesh): m.radius = 0.17; m.height = 0.2)
	arm_r = _limb(torso, Vector3(-chest_w - 0.08, 0.66, 0.0), metal)
	arm_l = _limb(torso, Vector3(chest_w + 0.08, 0.66, 0.0), metal)
	leg_r = _limb(body, Vector3(-0.12, 0.95, 0.0), cloth, 0.82)
	leg_l = _limb(body, Vector3(0.12, 0.95, 0.0), cloth, 0.82)

	weapon = Node3D.new()
	weapon.position = Vector3(0.0, -0.58, 0.0)
	arm_r.add_child(weapon)
	if f.role == "p":
		# Spear: long shaft with a leaf head, extending along the forearm direction (-Y local).
		_part(weapon, CylinderMesh.new(), Vector3(0.0, -0.55, 0.0), Color(0.4, 0.27, 0.15), func(m: CylinderMesh): m.top_radius = 0.022; m.bottom_radius = 0.022; m.height = 2.1)
		_part(weapon, CylinderMesh.new(), Vector3(0.0, -1.72, 0.0), Color(0.8, 0.82, 0.86), func(m: CylinderMesh): m.top_radius = 0.0; m.bottom_radius = 0.06; m.height = 0.3)
	else:
		_part(weapon, BoxMesh.new(), Vector3(0.0, -0.55, 0.0), Color(0.85, 0.87, 0.92), func(m: BoxMesh): m.size = Vector3(0.07, 0.95, 0.018))
		_part(weapon, BoxMesh.new(), Vector3(0.0, -0.06, 0.0), trim, func(m: BoxMesh): m.size = Vector3(0.28, 0.04, 0.05))
		shield = _part(arm_l, BoxMesh.new(), Vector3(0.1, -0.35, 0.12), metal.darkened(0.15), func(m: BoxMesh): m.size = Vector3(0.1, 0.62, 0.44))

	arc_fx = MeshInstance3D.new()
	var arc_mat := StandardMaterial3D.new()
	arc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	arc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	arc_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.28)
	arc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	arc_fx.material_override = arc_mat
	arc_fx.position = Vector3(0.0, 0.9, 0.0)
	arc_fx.visible = false
	add_child(arc_fx)

	aura = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.65
	aura.mesh = ring
	var aura_mat := StandardMaterial3D.new()
	aura_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	aura_mat.albedo_color = {"p": Color(1.0, 0.25, 0.15), "n": Color(0.5, 0.7, 1.0), "b": Color(0.7, 0.4, 1.0),
			"r": Color(1.0, 0.7, 0.2), "q": Color(1.0, 0.3, 0.7)}.get(f.role, Color(0.5, 0.7, 1.0))
	aura.material_override = aura_mat
	aura.position = Vector3(0.0, 0.1, 0.0)
	aura.visible = false
	add_child(aura)
	_apply_pose(1.0)


func _part(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, configure: Callable) -> MeshInstance3D:
	configure.call(mesh)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mat.metallic = 0.25
	node.material_override = mat
	_mats.append(mat)
	parent.add_child(node)
	return node


func _limb(parent: Node3D, pos: Vector3, color: Color, length: float = 0.6) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	parent.add_child(pivot)
	_part(pivot, CapsuleMesh.new(), Vector3(0.0, -length * 0.5, 0.0), color, func(m: CapsuleMesh): m.radius = 0.075; m.height = length)
	return pivot


func _process(delta: float) -> void:
	if fighter == null or not is_instance_valid(fighter) or not fighter.is_inside_tree():
		return
	_time += delta
	var alpha := Engine.get_physics_interpolation_fraction()
	global_position = fighter.prev_position.lerp(fighter.global_position, alpha)
	rig.rotation.y = lerp_angle(fighter.prev_yaw, fighter.yaw, alpha)
	arc_fx.rotation.y = rig.rotation.y
	_target_pose()
	_apply_pose(1.0 - exp(-26.0 * delta))
	_animate_legs(delta)
	_effects()


func _target_pose() -> void:
	var f := fighter
	var sm := f.sm
	var knight := f.role == "n"
	var t := {"arm": -1.55, "arm_roll": 0.0, "lean": 0.0, "twist": 0.0, "crouch": 0.0, "shift": 0.0, "arm_l": -0.25}
	if knight:
		t["arm_l"] = -1.0
	match sm.state:
		S.ATTACKING, S.ABILITY_CASTING:
			if sm.attack != null:
				_attack_pose(t, sm)
			else:
				t["arm"] = -3.0
				t["arm_l"] = -3.0
				t["lean"] = -0.15
		S.BLOCKING:
			t["arm_l"] = -1.5
			t["arm"] = -1.2
			t["arm_roll"] = 0.9
			t["crouch"] = 0.06
		S.PARRYING:
			var k := clampf(float(sm.state_ticks) / 6.0, 0.0, 1.0)
			t["arm"] = lerpf(-1.1, -2.0, k)
			t["twist"] = lerpf(-0.4, 0.5, k)
		S.DODGING:
			t["crouch"] = 0.28
			t["lean"] = 0.45
			t["arm"] = -0.6
		S.STAGGERED:
			t["lean"] = -0.4
			t["arm"] = -0.4
			t["arm_l"] = 0.4
			t["shift"] = -0.1
		S.DEFEATED:
			t["lean"] = 0.0
			t["arm"] = 0.3
	_pose = t


func _attack_pose(t: Dictionary, sm: CombatStateMachine) -> void:
	var atk := sm.attack
	var total := float(sm.attack_total)
	var u := float(sm.state_ticks) / total
	var thrust := atk.animation.begins_with("thrust") or atk.animation == "lunge_thrust" or atk.animation == "lunge"
	var win := atk.active_window(sm.attack_total)
	var s_end := float(win.x) / total
	var a_end := float(win.y) / total
	var wind_arm := -1.1 if thrust else -2.7
	var strike_arm := -1.57 if thrust else -0.85
	var wind_shift := -0.25 if thrust else -0.05
	var strike_shift := 0.35 if thrust else 0.12
	var arm := wind_arm
	var shift := wind_shift
	var twist := 0.0
	if u < s_end:
		var k := u / s_end
		arm = lerpf(-1.55, wind_arm, k)
		shift = lerpf(0.0, wind_shift, k)
		twist = lerpf(0.0, -0.5 if not thrust else -0.2, k)
	elif u < a_end:
		var k2 := (u - s_end) / maxf(a_end - s_end, 0.001)
		arm = lerpf(wind_arm, strike_arm, k2)
		shift = lerpf(wind_shift, strike_shift, k2)
		twist = lerpf(-0.5 if not thrust else -0.2, 0.6 if not thrust else 0.15, k2)
	else:
		var k3 := (u - a_end) / maxf(1.0 - a_end, 0.001)
		arm = lerpf(strike_arm, -1.55, k3)
		shift = lerpf(strike_shift, 0.0, k3)
		twist = lerpf(0.6 if not thrust else 0.15, 0.0, k3)
	t["arm"] = arm
	t["shift"] = shift
	t["twist"] = twist
	t["lean"] = 0.2 if u >= s_end and u < a_end else 0.0
	t["crouch"] = 0.1 if sm.attack.kind == AttackDefinition.Kind.HEAVY else 0.0


func _apply_pose(k: float) -> void:
	var p := _pose
	var cur_arm: float = lerpf(arm_r.rotation.x, float(p["arm"]), k)
	arm_r.rotation.x = cur_arm
	arm_r.rotation.z = lerpf(arm_r.rotation.z, float(p["arm_roll"]), k)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, float(p["arm_l"]), k)
	torso.rotation.x = lerpf(torso.rotation.x, float(p["lean"]), k)
	torso.rotation.y = lerpf(torso.rotation.y, float(p["twist"]), k)
	rig.position.y = lerpf(rig.position.y, -float(p["crouch"]), k)
	rig.position.z = lerpf(rig.position.z, float(p["shift"]), k)
	if fighter.sm.state == S.DEFEATED:
		var fall := clampf(float(fighter.sm.state_ticks) / 22.0, 0.0, 1.0)
		rig.rotation.x = lerpf(rig.rotation.x, -PI * 0.5 * fall, 0.4)
		rig.position.y = lerpf(rig.position.y, 0.22 * fall, 0.4)
	else:
		rig.rotation.x = lerpf(rig.rotation.x, 0.0, k)


func _animate_legs(delta: float) -> void:
	var speed := fighter.velocity.length()
	var moving := speed > 0.3 and fighter.sm.state != S.DEFEATED
	if moving:
		_walk_phase += delta * (4.0 + speed * 1.6)
	var swing := 0.0
	if moving:
		swing = sin(_walk_phase) * clampf(speed / 4.0, 0.2, 0.9)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, swing, 0.4)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, -swing, 0.4)
	if fighter.sm.state == S.IDLE:
		torso.position.y = 0.95 + sin(_time * 2.2) * 0.008


func _effects() -> void:
	var f := fighter
	var flash := 0.0
	if f.hit_react_ticks > 0 or f.sm.state == S.STAGGERED:
		flash = 0.7
	for m in _mats:
		m.emission_enabled = flash > 0.0
		m.emission = Color(1.0, 0.25, 0.15)
		m.emission_energy_multiplier = flash
	# Live hitbox sector (doubles as the visual swing trail).
	var shape := f.hitbox.shape(f)
	var active: bool = shape.get("active", false)
	arc_fx.visible = active
	if active:
		var key := "%.2f_%.0f" % [float(shape["reach"]), float(shape["arc_degrees"])]
		if key != _arc_key:
			_arc_key = key
			arc_fx.mesh = _sector_mesh(float(shape["reach"]), float(shape["arc_degrees"]))
	var buffed := f.ability.buff_active() or (f.sm.state == S.ABILITY_CASTING)
	aura.visible = buffed
	if buffed:
		aura.rotation.y = _time * 3.0
		aura.scale = Vector3.ONE * (1.0 + 0.08 * sin(_time * 8.0))


static func _sector_mesh(reach: float, arc_degrees: float) -> ArrayMesh:
	var half := deg_to_rad(arc_degrees * 0.5)
	var steps := 14
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	verts.append(Vector3.ZERO)
	for i in steps + 1:
		var a := lerpf(-half, half, float(i) / float(steps))
		verts.append(Vector3(sin(a) * reach, 0.0, cos(a) * reach))
	for i in steps:
		indices.append_array([0, i + 2, i + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
