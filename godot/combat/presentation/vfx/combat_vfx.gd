extends Node3D
## Combat feedback effects (presentation only): impact flashes and sparks, block / perfect-parry / guard-break /
## dodge feedback, per-ability effects, weapon and body trails, floating damage numbers, hitstop requests and
## camera feedback. It listens to the cosmetic event stream the simulation already emits and reads fighter state;
## it NEVER changes the simulation, its timing or any result.
##
## Readability rules: effects are small, short and low-alpha; attacks and the opponent's silhouette stay visible.
## Mobile rules: everything is pooled with hard caps (see CAPS_*), sparks are ONE MultiMesh draw call, sprites are
## textured unshaded quads (no GPU particles, no post processing), nothing is allocated per event after setup.
##
## Quality: `low` (auto on mobile or `--lowfx`) halves the caps and drops body trails / most numbers.
## `--reduce-motion` disables camera shake and FOV kicks. `--no-damage-numbers` hides numbers.

const S := CombatConstants.State
const Trail := preload("res://combat/presentation/vfx/trail_ribbon.gd")

static var low_quality: bool = false
static var reduce_motion: bool = false
static var show_numbers: bool = true

const CAPS_HIGH := {"sparks": 48, "sprites": 16, "numbers": 6, "trail_points": 12, "body_trails": true}
const CAPS_LOW := {"sparks": 20, "sprites": 8, "numbers": 3, "trail_points": 6, "body_trails": false}

const TRAIL_COLORS := {
	"p": Color(0.85, 0.92, 1.0, 0.55), "n": Color(0.9, 0.92, 1.0, 0.6), "b": Color(0.55, 0.7, 1.0, 0.6),
	"r": Color(1.0, 0.55, 0.25, 0.5), "q": Color(0.4, 0.95, 1.0, 0.6), "k": Color(1.0, 0.85, 0.4, 0.6),
}
const FURY_TRAIL := Color(1.0, 0.7, 0.2, 0.7)

var sim: CombatSimulation
var models: Dictionary = {}           # player_id -> Node3D (CharacterModel or placeholder)
var cameras: Array = []               # ThirdPersonCamera
var caps: Dictionary = CAPS_HIGH
var stats: Dictionary = {"events": 0, "sparks_spawned": 0, "sprites_spawned": 0, "numbers_spawned": 0,
		"hitstops": 0, "dropped_sparks": 0, "dropped_sprites": 0, "max_live_sparks": 0, "max_live_sprites": 0}

var _ring_tex: ImageTexture
var _glow_tex: ImageTexture
var _spark_node: MultiMeshInstance3D
var _spark_mm: MultiMesh
var _sp_pos: PackedVector3Array = PackedVector3Array()
var _sp_vel: PackedVector3Array = PackedVector3Array()
var _sp_life: PackedFloat32Array = PackedFloat32Array()
var _sp_max: PackedFloat32Array = PackedFloat32Array()
var _sp_col: PackedColorArray = PackedColorArray()
var _sp_cursor: int = 0
var _sp_live: int = 0
var _sprites: Array[Dictionary] = []
var _auras: Dictionary = {}           # player_id -> sprite entry (persistent ability aura)
var _numbers: Array[Dictionary] = []
var _fx: Dictionary = {}              # player_id -> per-fighter tracking {prev_state, prev_pos, trails, body_trail}
var _hold: int = 0
var _time: float = 0.0
## Final-blow slow motion (presentation): Engine.time_scale briefly drops so the knockout lands. ONLY when a real window is open and
## the fight is local (the arena enables it): online the server's clock cannot be slowed, tests run headless at fixed time.
var allow_slowmo: bool = false
const SLOWMO_SCALE := 0.3
const SLOWMO_REAL_SECONDS := 0.55
var _slowmo_end_msec: int = 0
var _ghost_clock: float = 0.0


static func configure_from_args() -> void:
	var all: Array = []
	all.append_array(OS.get_cmdline_args())
	all.append_array(OS.get_cmdline_user_args())
	low_quality = OS.has_feature("mobile") or ("--lowfx" in all)
	reduce_motion = "--reduce-motion" in all
	show_numbers = not ("--no-damage-numbers" in all)
	ThirdPersonCamera.reduce_motion = reduce_motion


func setup(p_sim: CombatSimulation, quality_low: bool = false) -> void:
	sim = p_sim
	caps = CAPS_LOW if (quality_low or low_quality) else CAPS_HIGH
	_ring_tex = _make_ring_texture()
	_glow_tex = _make_glow_texture()
	_build_sparks()
	for i in int(caps["sprites"]):
		_sprites.append(_make_sprite_entry(false))
	for i in int(caps["numbers"]):
		_numbers.append(_make_number_entry())
	for f in sim.fighters:
		_fx[f.player_id] = {"prev_state": -1, "prev_pos": f.global_position, "trails": [], "body_trail": null,
				"trail_color": TRAIL_COLORS.get(f.role, Color(1, 1, 1, 0.5))}
		_auras[f.player_id] = _make_sprite_entry(true)


func register_model(player_id: String, model: Node3D) -> void:
	models[player_id] = model
	var info: Dictionary = _fx.get(player_id, {})
	if info.is_empty():
		return
	var points := int(caps["trail_points"])
	if model.has_method("weapon_segments") and points >= 2:
		for _i in 2:  # at most two weapons (Queen)
			info["trails"].append(Trail.new(self, points))
		if bool(caps["body_trails"]):
			info["body_trail"] = Trail.new(self, points)


# ---- textures --------------------------------------------------------------------------------
static func _make_ring_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - absf(d - 0.82) / 0.13, 0.0, 1.0)
			a *= clampf((1.0 - d) * 8.0 + 1.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)


static func _make_glow_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * a))
	return ImageTexture.create_from_image(img)


# ---- pools -----------------------------------------------------------------------------------
func _build_sparks() -> void:
	var n := int(caps["sparks"])
	var box := BoxMesh.new()
	box.size = Vector3(0.014, 0.014, 0.18)
	_spark_mm = MultiMesh.new()
	_spark_mm.transform_format = MultiMesh.TRANSFORM_3D
	_spark_mm.use_colors = true
	_spark_mm.mesh = box
	_spark_mm.instance_count = n
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.vertex_color_use_as_albedo = true
	box.material = mat
	_spark_node = MultiMeshInstance3D.new()
	_spark_node.multimesh = _spark_mm
	_spark_node.top_level = true
	_spark_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spark_node.extra_cull_margin = 50.0
	add_child(_spark_node)
	_sp_pos.resize(n)
	_sp_vel.resize(n)
	_sp_life.resize(n)
	_sp_max.resize(n)
	_sp_col.resize(n)
	for i in n:
		_sp_life[i] = 0.0
		_spark_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))


func _make_sprite_entry(persistent: bool) -> Dictionary:
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = _glow_tex
	quad.material = mat
	var node := MeshInstance3D.new()
	node.mesh = quad
	node.top_level = true
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visible = false
	add_child(node)
	return {"node": node, "mat": mat, "t": 0.0, "life": 0.0, "s0": 1.0, "s1": 1.0, "col": Color.WHITE,
			"persistent": persistent, "alive": false}


func _make_number_entry() -> Dictionary:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.005
	label.font_size = 48
	label.outline_size = 10
	label.modulate = Color.WHITE
	label.top_level = true
	label.visible = false
	add_child(label)
	return {"node": label, "t": 0.0, "life": 0.0, "start": Vector3.ZERO, "alive": false}


func live_sparks() -> int:
	return _sp_live


func live_sprites() -> int:
	var n := 0
	for s in _sprites:
		if s["alive"]:
			n += 1
	for pid in _auras:
		if _auras[pid]["alive"]:
			n += 1
	return n


func live_numbers() -> int:
	var n := 0
	for e in _numbers:
		if e["alive"]:
			n += 1
	return n


## Rough count of "particles" on screen: sparks + sprites + number labels + trail ribbons.
func particle_budget_used() -> int:
	var trails := 0
	for pid in _fx:
		for t in _fx[pid]["trails"]:
			if t.count >= 2:
				trails += 1
		if _fx[pid]["body_trail"] != null and _fx[pid]["body_trail"].count >= 2:
			trails += 1
	return live_sparks() + live_sprites() + live_numbers() + trails


# ---- spawning --------------------------------------------------------------------------------
func spawn_sparks(origin: Vector3, direction: Vector3, count: int, color: Color, speed: float = 3.5, spread: float = 0.7) -> void:
	var n := _sp_pos.size()
	for _i in count:
		var slot := -1
		for j in n:  # find a free slot starting at the cursor; otherwise recycle the oldest (cursor)
			var k := (_sp_cursor + j) % n
			if _sp_life[k] <= 0.0:
				slot = k
				break
		if slot < 0:
			stats["dropped_sparks"] += 1
			slot = _sp_cursor
		_sp_cursor = (slot + 1) % n
		var jitter := Vector3(randf_range(-1, 1), randf_range(-0.4, 1.0), randf_range(-1, 1)) * spread
		var v := (direction.normalized() + jitter).normalized() * speed * randf_range(0.55, 1.15)
		if _sp_life[slot] <= 0.0:
			_sp_live += 1
		_sp_pos[slot] = origin
		_sp_vel[slot] = v
		_sp_life[slot] = randf_range(0.16, 0.32)
		_sp_max[slot] = _sp_life[slot]
		_sp_col[slot] = color
		stats["sparks_spawned"] += 1
	stats["max_live_sparks"] = maxi(int(stats["max_live_sparks"]), _sp_live)


func spawn_sprite(pos: Vector3, size0: float, size1: float, color: Color, life: float, texture: String = "glow") -> void:
	var entry: Dictionary = {}
	var oldest := -1.0
	for s in _sprites:
		if not s["alive"]:
			entry = s
			break
		if float(s["t"]) / maxf(float(s["life"]), 0.001) > oldest:
			oldest = float(s["t"]) / maxf(float(s["life"]), 0.001)
			entry = s
	if entry.is_empty():
		return
	if entry["alive"]:
		stats["dropped_sprites"] += 1
	_start_sprite(entry, pos, size0, size1, color, life, texture)
	stats["sprites_spawned"] += 1
	stats["max_live_sprites"] = maxi(int(stats["max_live_sprites"]), live_sprites())


func _start_sprite(entry: Dictionary, pos: Vector3, size0: float, size1: float, color: Color, life: float, texture: String) -> void:
	entry["t"] = 0.0
	entry["life"] = life
	entry["s0"] = size0
	entry["s1"] = size1
	entry["col"] = color
	entry["alive"] = true
	entry["mat"].albedo_texture = _ring_tex if texture == "ring" else _glow_tex
	entry["node"].global_position = pos
	entry["node"].scale = Vector3(size0, size0, 1.0)
	entry["mat"].albedo_color = color
	entry["node"].visible = true


func spawn_number(pos: Vector3, value: int, color: Color) -> void:
	if not show_numbers or _numbers.is_empty():
		return
	var entry: Dictionary = {}
	for e in _numbers:
		if not e["alive"]:
			entry = e
			break
	if entry.is_empty():
		entry = _numbers[0]
	entry["t"] = 0.0
	entry["life"] = 0.7
	entry["start"] = pos
	entry["alive"] = true
	var label: Label3D = entry["node"]
	label.text = str(value)
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.global_position = pos
	label.visible = true
	stats["numbers_spawned"] += 1


# ---- hitstop (presentation only) -------------------------------------------------------------
## Freezes the two involved models' animation, plus this layer's own particles/trails, for `frames` DISPLAY frames.
## It never touches the simulation, Engine.time_scale or any tick counter; models re-sync from state_ticks after.
func request_hitstop(player_ids: Array, frames: int) -> void:
	frames = clampi(frames, 0, 5)
	if frames <= 0:
		return
	_hold = maxi(_hold, frames)
	stats["hitstops"] += 1
	for pid in player_ids:
		var m: Node3D = models.get(pid, null)
		if m != null and is_instance_valid(m) and m.has_method("hold"):
			m.hold(frames)


func hold_frames() -> int:
	return _hold


## True while the final-blow slow motion is running.
func slowmo_active() -> bool:
	return _slowmo_end_msec > 0


func request_slowmo(real_seconds: float = SLOWMO_REAL_SECONDS) -> bool:
	if not allow_slowmo or reduce_motion or _slowmo_end_msec > 0:
		return false
	Engine.time_scale = SLOWMO_SCALE
	_slowmo_end_msec = Time.get_ticks_msec() + int(real_seconds * 1000.0)
	stats["slowmos"] = int(stats.get("slowmos", 0)) + 1
	return true


func _end_slowmo() -> void:
	if _slowmo_end_msec > 0:
		_slowmo_end_msec = 0
		Engine.time_scale = 1.0


func _exit_tree() -> void:
	_end_slowmo()  # never leave the whole game slowed down


# ---- events ----------------------------------------------------------------------------------
func on_event(event: Dictionary) -> void:
	if sim == null:
		return
	stats["events"] += 1
	var actor := sim.fighter_by_id(String(event.get("actorPlayerId", "")))
	var target := sim.fighter_by_id(String(event.get("targetPlayerId", "")))
	if actor == null or target == null:
		return
	var kind := String(event["type"])
	var tpos := target.global_position + Vector3(0, 1.15, 0)
	var apos := actor.global_position + Vector3(0, 1.15, 0)
	var dir := CombatConstants.flat(tpos - apos)
	dir = dir.normalized() if dir.length() > 0.01 else CombatConstants.heading(actor.yaw)
	var contact := tpos - dir * target.hurt_radius() * 0.9
	var ids := [actor.player_id, target.player_id]
	match kind:
		"hit":
			var damage := int(event["damage"])   # the HP actually removed (the number shown)
			var felt := sim.felt_damage(damage)   # the blow's strength before the duel-length scale (the feel)
			var power := clampf(float(felt) / 40.0, 0.2, 1.0)
			spawn_sprite(contact, 0.2 + 0.35 * power, 0.5 + 0.7 * power, Color(1.0, 0.8, 0.5, 0.75), 0.14)
			spawn_sparks(contact, dir + Vector3(0, 0.25, 0), 5 + int(power * 7.0), Color(1.0, 0.75, 0.4, 0.9), 3.0 + 2.0 * power)
			if damage > 0:   # a graze that only builds up the carried fraction takes no whole HP: no number
				spawn_number(target.global_position + Vector3(0, 2.05, 0), damage, Color(1.0, 0.85, 0.6) if felt < 20 else Color(1.0, 0.55, 0.3))
			request_hitstop(ids, 2 + felt / 18)
			_target_react(target, "hit", felt, dir)
			_camera_event("heavy_hit" if felt >= 20 else "hit", 0.08 + 0.2 * power, dir)
			if not target.health.is_alive():   # the knockout blow: bigger burst, a heavy camera punch and slow motion
				spawn_sprite(contact, 0.4, 2.2, Color(1.0, 0.95, 0.8, 0.8), 0.3, "ring")
				spawn_sparks(contact, dir + Vector3(0, 0.4, 0), 14, Color(1.0, 0.85, 0.5, 1.0), 5.0, 1.2)
				request_hitstop(ids, 5)
				_camera_event("final", 0.45, dir)
				request_slowmo()
		"block":
			spawn_sprite(contact, 0.2, 0.55, Color(0.6, 0.8, 1.0, 0.7), 0.12)
			spawn_sparks(contact, -dir + Vector3(0, 0.3, 0), 7, Color(0.7, 0.85, 1.0, 0.9), 2.8, 0.9)
			request_hitstop(ids, 2)
			_target_flash(target, Color(0.5, 0.72, 1.0), 0.35)
			_camera_event("block", 0.06, dir)
		"parry":
			# actor = the attacker whose blow was parried; target = the parrier. Distinct gold, larger, then a short freeze.
			spawn_sprite(contact, 0.3, 2.0, Color(1.0, 0.85, 0.35, 0.85), 0.3, "ring")
			spawn_sprite(contact, 0.25, 0.9, Color(1.0, 1.0, 0.85, 0.8), 0.12)
			spawn_sprite(target.global_position + Vector3(0, 0.08, 0), 0.5, 4.2, Color(1.0, 0.9, 0.5, 0.35), 0.4, "ring")  # ground shockwave
			spawn_sparks(contact, -dir + Vector3(0, 0.2, 0), 12, Color(1.0, 0.88, 0.45, 0.95), 4.2, 1.0)
			request_hitstop(ids, 5)
			_target_flash(target, Color(1.0, 0.82, 0.3), 0.4)
			_target_flash(actor, Color(1.0, 0.95, 0.7), 0.25)
			_camera_event("parry", 0.2, dir)
		"guardbreak":
			spawn_sprite(contact, 0.3, 1.1, Color(1.0, 0.25, 0.15, 0.8), 0.22)
			spawn_sparks(contact, dir + Vector3(0, 0.3, 0), 10, Color(1.0, 0.3, 0.2, 0.9), 3.5, 1.0)
			if int(event["damage"]) > 0:
				spawn_number(target.global_position + Vector3(0, 2.05, 0), int(event["damage"]), Color(1.0, 0.4, 0.3))
			request_hitstop(ids, 4)
			_target_flash(target, Color(1.0, 0.2, 0.12), 0.45)
			_camera_event("guardbreak", 0.3, dir)
		"dodge":
			# target = the fighter whose i-frames evaded the blow: a subtle cool flash, no freeze.
			spawn_sprite(tpos, 0.4, 1.0, Color(0.5, 0.95, 1.0, 0.3), 0.18)
			spawn_sparks(tpos, -dir, 4, Color(0.6, 0.95, 1.0, 0.6), 2.0, 1.2)
		"ability":
			_ability_event(actor, target)


func _target_react(target: FighterController, kind: String, damage: int, dir: Vector3) -> void:
	var m: Node3D = models.get(target.player_id, null)
	if m != null and is_instance_valid(m) and m.has_method("react"):
		m.react(kind, damage, dir)


func _target_flash(f: FighterController, color: Color, strength: float) -> void:
	var m: Node3D = models.get(f.player_id, null)
	if m != null and is_instance_valid(m) and m.has_method("flash"):
		m.flash(color, strength)


func _camera_event(kind: String, amount: float, dir: Vector3) -> void:
	for cam in cameras:
		if is_instance_valid(cam) and cam.has_method("feedback"):
			cam.feedback(kind, amount, dir)


func _ability_event(actor: FighterController, target: FighterController) -> void:
	var pos := actor.global_position
	var chest := pos + Vector3(0, 1.1, 0)
	match actor.ability.ability_id:
		"last-stand":
			spawn_sprite(pos + Vector3(0, 0.15, 0), 0.6, 3.0, Color(1.0, 0.2, 0.15, 0.55), 0.55, "ring")
			_camera_event("ability", 0.1, Vector3.ZERO)
		"lunging-strike":
			spawn_sprite(chest, 0.5, 1.2, Color(1.0, 0.95, 0.8, 0.4), 0.2)
			_camera_event("dash", 0.0, CombatConstants.heading(actor.yaw))
		"blink":
			spawn_sprite(chest, 0.5, 1.6, Color(0.7, 0.55, 1.0, 0.65), 0.25)
			spawn_sparks(chest, Vector3.UP, 8, Color(0.75, 0.6, 1.0, 0.9), 2.2, 1.4)
			_camera_event("dash", 0.0, CombatConstants.heading(actor.yaw))
		"fortress-guard":
			spawn_sprite(pos + Vector3(0, 0.1, 0), 0.8, 2.4, Color(0.7, 0.85, 1.0, 0.45), 0.4, "ring")
			_camera_event("ability", 0.12, Vector3.ZERO)
		"royal-fury":
			spawn_sprite(chest, 0.6, 2.0, Color(1.0, 0.7, 0.2, 0.5), 0.3)
			spawn_sprite(pos + Vector3(0, 0.1, 0), 0.6, 2.6, Color(1.0, 0.6, 0.15, 0.45), 0.4, "ring")
			_camera_event("ability", 0.1, Vector3.ZERO)
		"royal-counter":
			spawn_sprite(pos + Vector3(0, 0.15, 0), 0.7, 2.2, Color(1.0, 0.88, 0.4, 0.55), 0.45, "ring")
			_camera_event("ability", 0.08, Vector3.ZERO)
		_:
			spawn_sprite(chest, 0.5, 1.4, Color(0.9, 0.8, 1.0, 0.4), 0.25)


# ---- result ----------------------------------------------------------------------------------
## Outcome presentation: winner plays victory, loser defeat (double knockout: both defeat) and the cameras
## frame the winner. Presentation only.
func on_result(result: Dictionary) -> void:
	if sim == null:
		return
	var double_ko: bool = String(result.get("reason", "")) == "double_knockout"
	var winner_id := String(result.get("winnerPlayerId", ""))
	for f in sim.fighters:
		var m: Node3D = models.get(f.player_id, null)
		if m == null or not is_instance_valid(m) or not m.has_method("set_outcome"):
			continue
		m.set_outcome(f.player_id == winner_id and not double_ko)
	var winner := sim.fighter_by_id(winner_id)
	for f in sim.fighters:
		if f.player_id != winner_id or double_ko:
			var base := f.global_position
			spawn_sprite(base + Vector3(0, 0.08, 0), 0.6, 3.4, Color(0.9, 0.35, 0.2, 0.45), 0.9, "ring")
			spawn_sparks(base + Vector3(0, 0.9, 0), Vector3.UP, 16, Color(1.0, 0.55, 0.25, 0.9), 2.4, 1.6)
	for cam in cameras:
		if is_instance_valid(cam) and cam.has_method("set_finish"):
			cam.set_finish(winner if not double_ko else null)


# ---- per-frame -------------------------------------------------------------------------------
func _process(delta: float) -> void:
	if _slowmo_end_msec > 0 and Time.get_ticks_msec() >= _slowmo_end_msec:
		_end_slowmo()
	if sim == null or sim.fighters.size() < 2:
		return
	var dt := delta
	if _hold > 0:
		_hold -= 1
		dt = 0.0
	_time += dt
	_update_sparks(dt)
	_update_sprites(dt)
	_update_numbers(dt)
	for f in sim.fighters:
		if is_instance_valid(f) and f.is_inside_tree():
			_track_fighter(f, dt)


func _update_sparks(dt: float) -> void:
	if _sp_live == 0 or dt <= 0.0:
		return
	var live := 0
	for i in _sp_pos.size():
		var life := _sp_life[i]
		if life <= 0.0:
			continue
		life -= dt
		if life <= 0.0:
			_sp_life[i] = 0.0
			_spark_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
			continue
		_sp_life[i] = life
		live += 1
		var v := _sp_vel[i]
		v.y -= 5.0 * dt
		v *= maxf(0.0, 1.0 - 3.0 * dt)
		_sp_vel[i] = v
		_sp_pos[i] += v * dt
		var forward := v.normalized() if v.length() > 0.01 else Vector3.FORWARD
		var up := Vector3.UP if absf(forward.y) < 0.98 else Vector3.RIGHT
		var k := life / _sp_max[i]
		var basis := Basis.looking_at(forward, up).scaled(Vector3(k, k, 0.4 + 0.6 * k))
		_spark_mm.set_instance_transform(i, Transform3D(basis, _sp_pos[i]))
		var c := _sp_col[i]
		_spark_mm.set_instance_color(i, Color(c.r, c.g, c.b, c.a * k))
	_sp_live = live


func _update_sprites(dt: float) -> void:
	for s in _sprites:
		if s["alive"]:
			_step_sprite(s, dt)
	for pid in _auras:
		var a: Dictionary = _auras[pid]
		if a["alive"] and not a["persistent"]:
			_step_sprite(a, dt)


func _step_sprite(s: Dictionary, dt: float) -> void:
	s["t"] += dt
	var k := clampf(float(s["t"]) / maxf(float(s["life"]), 0.001), 0.0, 1.0)
	if k >= 1.0:
		s["alive"] = false
		s["node"].visible = false
		return
	var grow := 1.0 - (1.0 - k) * (1.0 - k)
	var size := lerpf(float(s["s0"]), float(s["s1"]), grow)
	var node: MeshInstance3D = s["node"]
	node.scale = Vector3(size, size, 1.0)
	var c: Color = s["col"]
	var fade := 1.0 - k
	s["mat"].albedo_color = Color(c.r, c.g, c.b, c.a * fade * fade)


func _update_numbers(dt: float) -> void:
	for e in _numbers:
		if not e["alive"]:
			continue
		e["t"] += dt
		var k := float(e["t"]) / float(e["life"])
		var label: Label3D = e["node"]
		if k >= 1.0:
			e["alive"] = false
			label.visible = false
			continue
		label.global_position = e["start"] + Vector3(0, 0.7 * k, 0)
		var c := label.modulate
		var a := 1.0 - k * k
		label.modulate = Color(c.r, c.g, c.b, a)
		label.outline_modulate = Color(0, 0, 0, 0.9 * a)  # fade the outline too, or a fading number reads as a black blob


func _track_fighter(f: FighterController, dt: float) -> void:
	var info: Dictionary = _fx.get(f.player_id, {})
	if info.is_empty():
		return
	var state: int = f.sm.state
	var pos := f.global_position
	var prev_state: int = info["prev_state"]
	var prev_pos: Vector3 = info["prev_pos"]
	# --- dodge start: a quick ground streak behind the dodge direction (subtle)
	if state == S.DODGING and prev_state != S.DODGING:
		var back := -f.sm.dodge_dir
		spawn_sprite(pos + Vector3(0, 0.08, 0) + back * 0.3, 0.5, 1.1, Color(0.8, 0.85, 0.9, 0.22), 0.25)
		spawn_sparks(pos + Vector3(0, 0.1, 0), back, 3, Color(0.85, 0.85, 0.8, 0.35), 1.2, 1.0)
	# --- dodge afterimage: faint ghosts left along the path, every ~3 frames while the roll lasts
	if state == S.DODGING:
		_ghost_clock += dt
		if _ghost_clock >= 0.05:
			_ghost_clock = 0.0
			var tint: Color = info["trail_color"]
			spawn_sprite(pos + Vector3(0, 1.0, 0), 0.9, 0.7, Color(tint.r, tint.g, tint.b, 0.28), 0.22)
	# --- blink: origin + destination flashes (a position jump while casting), trail reset
	var jumped := (pos - prev_pos).length() > 2.0 and prev_state != -1
	if jumped and state == S.ABILITY_CASTING:
		spawn_sprite(prev_pos + Vector3(0, 1.1, 0), 0.7, 0.1, Color(0.7, 0.55, 1.0, 0.7), 0.22)
		spawn_sprite(pos + Vector3(0, 1.1, 0), 0.2, 1.4, Color(0.75, 0.6, 1.0, 0.7), 0.3)
		spawn_sparks(pos + Vector3(0, 1.0, 0), Vector3.UP, 8, Color(0.75, 0.6, 1.0, 0.9), 2.5, 1.4)
	if jumped and info["body_trail"] != null:
		info["body_trail"].clear()
	info["prev_state"] = state
	info["prev_pos"] = pos
	_update_aura(f, state)
	_update_trails(f, info, state, dt, jumped)


func _update_aura(f: FighterController, state: int) -> void:
	var a: Dictionary = _auras[f.player_id]
	var id := String(f.ability.ability_id)
	var casting := state == S.ABILITY_CASTING
	var buff := f.ability.buff_active()
	var want := false
	var pos := f.global_position
	var size := 1.4
	var color := Color(1, 1, 1, 0.2)
	var tex := "ring"
	match id:
		"last-stand":
			want = buff or casting
			pos += Vector3(0, 0.12, 0)
			size = 1.3 + 0.1 * sin(_time * 8.0)
			color = Color(1.0, 0.25, 0.15, 0.3)
		"fortress-guard":
			want = buff or casting
			pos += Vector3(0, 0.95, 0)
			size = 2.0
			color = Color(0.7, 0.88, 1.0, 0.16)
		"royal-fury":
			want = buff or casting
			pos += Vector3(0, 1.1, 0)
			size = 1.9 + 0.12 * sin(_time * 10.0)
			color = Color(1.0, 0.65, 0.2, 0.2)
			tex = "glow"
		"royal-counter":
			want = casting
			pos += Vector3(0, 0.12, 0)
			size = 1.5
			color = Color(1.0, 0.88, 0.4, 0.4)
	if not want:
		if a["alive"]:
			a["alive"] = false
			a["node"].visible = false
		return
	if not a["alive"]:
		a["alive"] = true
		a["node"].visible = true
		a["mat"].albedo_texture = _ring_tex if tex == "ring" else _glow_tex
	a["node"].global_position = pos
	a["node"].scale = Vector3(size, size, 1.0)
	a["mat"].albedo_color = color


func _update_trails(f: FighterController, info: Dictionary, state: int, dt: float, jumped: bool) -> void:
	var m: Node3D = models.get(f.player_id, null)
	var trails: Array = info["trails"]
	var color: Color = FURY_TRAIL if (f.ability.ability_id == "royal-fury" and f.ability.buff_active()) else info["trail_color"]
	var attack_live := f.sm.attack_active() or (state == S.ABILITY_CASTING and f.sm.attack != null and f.sm.attack.forward_speed(f.sm.state_ticks, f.sm.attack_total) > 0.0)
	if m != null and is_instance_valid(m) and m.has_method("weapon_segments") and not trails.is_empty():
		var segs: Array = m.weapon_segments() if (attack_live and dt > 0.0) else []
		for i in trails.size():
			var t = trails[i]
			t.color = color
			if i < segs.size():
				t.push(segs[i]["base"], segs[i]["tip"])
			t.update(dt)
	var body = info["body_trail"]
	if body != null:
		var moving_fast := state == S.DODGING or (state == S.ABILITY_CASTING and f.sm.attack != null and f.sm.attack.forward_speed(f.sm.state_ticks, f.sm.attack_total) > 0.0)
		body.color = Color(0.85, 0.95, 1.0, 0.22) if state == S.DODGING else Color(1.0, 0.95, 0.8, 0.35)
		if moving_fast and dt > 0.0 and not jumped:
			body.push(f.global_position + Vector3(0, 0.3, 0), f.global_position + Vector3(0, 1.5, 0))
		body.update(dt)


## Releases everything between battles.
func reset_effects() -> void:
	for i in _sp_pos.size():
		_sp_life[i] = 0.0
		_spark_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO), Vector3.ZERO))
	_sp_live = 0
	for s in _sprites:
		s["alive"] = false
		s["node"].visible = false
	for pid in _auras:
		_auras[pid]["alive"] = false
		_auras[pid]["node"].visible = false
	for e in _numbers:
		e["alive"] = false
		e["node"].visible = false
	for pid in _fx:
		for t in _fx[pid]["trails"]:
			t.clear()
		if _fx[pid]["body_trail"] != null:
			_fx[pid]["body_trail"].clear()
	_hold = 0
	_end_slowmo()
