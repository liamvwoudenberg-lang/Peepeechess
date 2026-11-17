class_name MenuWorld
extends Node3D
## The persistent 3D world of the cinematic menu (docs/ui/CINEMATIC_MENU.md). It wraps the castle of an OpeningScene, owns the camera rig,
## and places the station props and one paladin per station. Pages are places: `fly_to_page()` flies the camera there.
##
## Input stays in the Controls (focus, tooltips, hit testing); the props only look and react (`hover_prop`, `select_prop`,
## `set_play_selection`, `set_exterior_selection`). Everything here is presentation: no simulation, no network.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const PALADIN_UNIT := 1.0   ## spawn_paladin() already divides by the model's source height; scale in the station table is metres

signal arrived(station_id: String)

var scene: Node3D                  ## the OpeningScene (castle, lights, embers, mist)
var rig := MenuCameraRig.new()
var quality := "balanced"
var paladins := {}                 ## station id -> state dictionary
var props := {}                    ## prop id -> {node, point}
var _clock := 0.0
var _hover_point := Vector3.INF
var _hover_station := ""
var _preview_pieces: Array[Node3D] = []
var _preview_material: StandardMaterial3D
var _lamp_material: StandardMaterial3D
var _banner_materials := {}
var _sign_materials := {}
var _audio: Node = null
var _built := {}
var _play_state := ["classic", "local", true]
var _exterior_kind := "friends"
# hero props (MenuHeroProps): filled when their station is first visited
var war_nodes: Array = []
var war_materials := {}
var war_offers: Array = []
var medal_discs: Array = []
var gallery_frames: Array = []
var rank_banners: Array = []
var friend_signs: Array = []
var _display := {}               ## data the pages pushed before a station existed: applied when it is built

## `opening_scene`: an OpeningScene that has been built. The rig takes over its camera once `start()` is called (so the opening
## screen can still drive the first glide), or at once when `start_at` is given.
func setup(opening_scene: Node3D, quality_name: String = "balanced", start_at: String = "") -> void:
	name = "MenuWorld"
	scene = opening_scene
	quality = quality_name
	rig.reduced_motion = Prefs.reduce_motion
	scene.set("rig", rig)
	rig.arrived.connect(_on_arrived)
	rig.flight_started.connect(_on_flight_started)
	scene.add_child(self)
	if start_at != "":
		start(start_at)

## Hand the camera to the rig, resting at `station_id` (the home station equals the opening screen's final menu pose).
func start(station_id: String = "home") -> void:
	_ensure_station(station_id)
	rig.place(station_id)
	_greet(station_id, true)

func fly_to_station(id: String) -> float:
	_ensure_station(id)
	rig.reduced_motion = Prefs.reduce_motion
	return rig.fly_to(id, Prefs.reduce_motion)

## A station's paladin and props are built the first time the camera is sent there (phones only pay for what the player visits).
func _ensure_station(id: String) -> void:
	if not MenuStations.STATIONS.has(id) or _built.has(id):
		return
	_built[id] = true
	_build_paladin(id)
	match id:
		"hall": _build_hall_props()
		"exterior": _build_exterior_props()
		"armoury": _build_armoury_props()
		"yard":
			_build_yard_props()
			MenuHeroProps.build_yard_extra(self)
		"warroom": MenuHeroProps.build_warroom(self)
		"gallery", "archive": MenuHeroProps.build_gallery(self, id)
		"tower": MenuHeroProps.build_tower(self)
	if id == "exterior":
		MenuHeroProps.build_friend_signs(self)
	_apply_display()

func built_stations() -> Array:
	return _built.keys()

## Draw nodes the menu layer adds on top of the castle (its own budget, see the menu world test).
func stats() -> Dictionary:
	var meshes := 0
	for node in find_children("*", "", true, false):
		if node is MeshInstance3D or node is Label3D:
			meshes += 1
	for state in paladins.values():
		if is_instance_valid(state.node):
			meshes += (state.node as Node).find_children("*", "MeshInstance3D", true, false).size()
	for piece in _preview_pieces:
		meshes += piece.find_children("*", "MeshInstance3D", true, false).size()
	return {"draw_nodes": meshes, "stations": _built.size()}

func fly_to_page(page: String, online: bool = false) -> float:
	return fly_to_station(MenuStations.station_for_page(page, online))

func current_station() -> String:
	return rig.current_id

func is_flying() -> bool:
	return rig.flying

func skip() -> void:
	rig.skip()

func back() -> bool:
	return rig.back()

# ---------------------------------------------------------------------------------------------------------------------
# paladins: one at each station, idle breathing, a nod on arrival, a look at a hovered prop, a bow on select
# ---------------------------------------------------------------------------------------------------------------------
const ROLE_CODE := {"pawn": "p", "knight": "n", "bishop": "b", "rook": "r", "queen": "q", "king": "k"}
const ASIDE_DISTANCE := 1.6      ## a paladin steps this far out of the camera's way when a flight starts (metres)
const IDLE_VARIATION_EVERY := Vector2(11.0, 19.0)   ## seconds between 'look around' idles

## The station paladin: a RIGGED paladin (PaladinModel + PaladinClips, the same characters as the board and the duels) with a looping idle,
## a greeting on arrival, a head/upper-body look at the hovered prop (MenuLookModifier), a bow or salute on select and a step aside when the
## camera flies off. Without the rigged asset it falls back to the old static statue (tilts only).
func _build_paladin(id: String) -> void:
	var spec: Dictionary = MenuStations.station(id).paladin
	var at := MenuStations.paladin_position(id)
	var cam_pos: Vector3 = MenuStations.station(id).pos
	var yaw := MenuStations.yaw_toward(at, cam_pos)
	var code: String = ROLE_CODE.get(spec.role, "p")
	var side := "w" if spec.side == "light" else "b"
	var state := {"pos": at, "yaw": yaw, "scale": float(spec.scale), "look_off": 0.7, "look_target": 0.0,
		"phase": float(paladins.size()) * 1.3, "model": null, "look": null, "aside": 1.0, "aside_target": 0.0, "aside_dir": _aside_direction(id),
		"variation_in": randf_range(IDLE_VARIATION_EVERY.x, IDLE_VARIATION_EVERY.y), "select_count": 0, "clip": "idle"}
	var model: PaladinModel = PaladinModel.create(code, side, float(spec.scale)) if PaladinModel.available(code) else null
	if model != null and model.skeleton != null and model.player != null:
		model.name = "StationPaladin_" + id
		add_child(model)
		var look := MenuLookModifier.new()
		look.name = "MenuLook"
		model.skeleton.add_child(look)
		look.setup(model.skeleton)
		state.model = model
		state.look = look
		state.node = model
	else:
		if model != null:
			model.queue_free()
		var placement := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * float(spec.scale)), at)
		var node: Node3D = scene.call("spawn_paladin", spec.role, spec.side, placement)
		if node == null:
			return
		node.reparent(self)   # the menu layer owns its nodes (the scene's own stats and budget exclude them)
		node.name = "StationPaladin_" + id
		state.node = node
	paladins[id] = state
	_apply_paladin(state)
	_play(state, "idle")

func _aside_direction(id: String) -> Vector3:
	var s := MenuStations.station(id)
	var forward: Vector3 = (s.look - s.pos)
	forward.y = 0.0
	if forward.length() < 0.01:
		return Vector3.RIGHT
	return Vector3.UP.cross(forward.normalized())   # the camera's left: the paladin steps further out of the page's way

func _apply_paladin(state: Dictionary) -> void:
	var node: Node3D = state.node
	if not is_instance_valid(node):
		return
	var body_yaw: float = float(state.yaw) + float(state.look_off) * (0.6 if state.model != null else 1.0)
	var at: Vector3 = state.pos + state.aside_dir * ASIDE_DISTANCE * float(state.aside)
	if state.model != null:
		node.transform = Transform3D(Basis(Vector3.UP, body_yaw), at)
		var look: MenuLookModifier = state.look
		if is_instance_valid(look):
			look.yaw = float(state.look_off) * 0.4
	else:
		var unit := Basis.from_scale(Vector3.ONE / PaladinModel.SOURCE_HEIGHT)
		node.transform = Transform3D(Basis(Vector3.UP, body_yaw) * Basis.from_scale(Vector3.ONE * float(state.scale)) * unit, at)

## Plays `clip` on the station paladin's skeleton: one-shots return to the looping idle by themselves. Reduce-motion keeps the idle pose still.
func _play(state: Dictionary, clip: String, blend: float = 0.2) -> void:
	state.clip = clip
	var model: PaladinModel = state.model
	if model == null or not is_instance_valid(model) or not model.player.is_inside_tree():
		return
	var player := model.player
	if not player.has_animation(clip):
		return
	if Prefs.reduce_motion:
		player.play("idle", 0.0)
		player.seek(0.0, true)
		player.pause()
		return
	player.play(clip, blend)
	if clip != "idle" and player.get_animation(clip).loop_mode == Animation.LOOP_NONE:
		player.queue("idle")

func paladin_at(station_id: String) -> Node3D:
	return paladins[station_id].node if paladins.has(station_id) else null

## The clip a station paladin is playing (tests and the page read this): "idle", "greet", "bow", "salute", "look_around", "walk".
func paladin_clip(station_id: String) -> String:
	if not paladins.has(station_id):
		return ""
	var model: PaladinModel = paladins[station_id].model
	if model != null and is_instance_valid(model) and model.player != null and model.player.is_playing():
		return String(model.player.current_animation)
	return String(paladins[station_id].clip)

func is_rigged(station_id: String) -> bool:
	return paladins.has(station_id) and paladins[station_id].model != null

func _greet(station_id: String, instant: bool = false) -> void:
	if not paladins.has(station_id):
		return
	var state: Dictionary = paladins[station_id]
	state.look_target = 0.0
	state.aside_target = 0.0
	if instant or Prefs.reduce_motion:
		state.look_off = 0.0
		state.aside = 0.0
		_apply_paladin(state)
		_play(state, "idle")
	else:
		_play(state, "walk" if float(state.aside) > 0.05 else "greet")   # it walks back into place first, then greets (see advance)

## Hovering a prop makes the current station's paladin look at it.
func hover_prop(prop_id: String) -> void:
	var id := rig.current_id
	if not paladins.has(id) or not props.has(prop_id):
		return
	var state: Dictionary = paladins[id]
	var point: Vector3 = props[prop_id].point
	_hover_station = id
	_hover_point = point
	var want := MenuStations.yaw_toward(state.pos, point) - float(state.yaw)
	state.look_target = wrapf(want, -PI, PI) * 0.8
	if Prefs.reduce_motion:
		state.look_off = state.look_target
		_apply_paladin(state)

func clear_hover() -> void:
	if _hover_station != "" and paladins.has(_hover_station):
		paladins[_hover_station].look_target = 0.0
		if Prefs.reduce_motion:
			paladins[_hover_station].look_off = 0.0
			_apply_paladin(paladins[_hover_station])
	_hover_station = ""
	_hover_point = Vector3.INF

## Selecting something: the paladin bows, or salutes on every second selection.
func select_prop(prop_id: String = "") -> void:
	var id := rig.current_id
	if paladins.has(id) and not Prefs.reduce_motion:
		var state: Dictionary = paladins[id]
		state.select_count += 1
		_play(state, "salute" if int(state.select_count) % 2 == 0 else "bow", 0.15)
	if props.has(prop_id):
		_pulse(prop_id)

# ---------------------------------------------------------------------------------------------------------------------
# props
# ---------------------------------------------------------------------------------------------------------------------
func _station_point(id: String, fwd: float, left: float, y: float = 0.0) -> Vector3:
	var s := MenuStations.station(id)
	var pos: Vector3 = s.pos
	var look: Vector3 = s.look
	var forward := Vector3(look.x - pos.x, 0.0, look.z - pos.z).normalized()
	var side := Vector3(forward.z, 0.0, -forward.x)
	var p := pos + forward * fwd + side * left
	return Vector3(p.x, float(s.ground) + y, p.z)

func _mat(color: Color, rough: float = 0.8, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

func _box(parent: Node3D, size: Vector3, at: Vector3, material: Material, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func _holder(node_name: String, at: Vector3, yaw: float) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = at
	holder.rotation.y = yaw
	add_child(holder)
	return holder

func _facing_camera(id: String, at: Vector3) -> float:
	return MenuStations.yaw_toward(at, MenuStations.station(id).pos)

func _register_prop(prop_id: String, node: Node3D, point: Vector3, radius: float = 1.4) -> void:
	props[prop_id] = {"node": node, "point": point, "pulse": 0.0, "radius": radius}

## The prop under a screen position (ray against each prop's pick sphere, nearest to the camera), or "" . Used for clicks on the 3D stage.
func pick(camera: Camera3D, screen_position: Vector2) -> String:
	if camera == null:
		return ""
	var origin := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var best := ""
	var best_distance := INF
	for id in props:
		var prop: Dictionary = props[id]
		var node: Node3D = prop.node
		if not is_instance_valid(node) or not node.is_visible_in_tree():
			continue
		var to_center: Vector3 = prop.point - origin
		var along := to_center.dot(direction)
		if along <= 0.0:
			continue
		var miss := (to_center - direction * along).length()
		if miss <= float(prop.radius) and along < best_distance:
			best_distance = along
			best = String(id)
	return best

## The great hall (Play): two banners for the two games and a small table with a live board preview of the chosen setup.
func _build_hall_props() -> void:
	var gold := _mat(Color("b59754"), 0.4, 0.5)
	var pole_color := _mat(Color("3a2c20"), 0.9)
	var specs := [["banner_classic", 8.4, Color("9b2330"), "classic"], ["banner_battle", 3.6, Color("233a78"), "battle"]]
	for spec in specs:
		var at := _station_point("hall", 14.0, float(spec[1]))
		var holder := _holder("Banner_" + str(spec[3]), at, _facing_camera("hall", at))
		_box(holder, Vector3(0.14, 5.2, 0.14), Vector3(0, 2.6, 0), pole_color, "Pole")
		_box(holder, Vector3(2.2, 0.16, 0.16), Vector3(0, 4.9, 0), gold, "Bar")
		var cloth_material := _mat(spec[2], 0.9)
		cloth_material.emission_enabled = true
		cloth_material.emission = Color(spec[2])
		cloth_material.emission_energy_multiplier = 0.0
		cloth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_box(holder, Vector3(1.8, 3.6, 0.05), Vector3(0, 3.0, 0.02), cloth_material, "Cloth")
		_box(holder, Vector3(0.9, 0.9, 0.06), Vector3(0, 3.4, 0.07), gold, "Crest")
		_banner_materials[spec[3]] = cloth_material
		_register_prop(str(spec[0]), holder, at + Vector3(0, 3.0, 0))
	# the table with the board preview
	var table_at := _station_point("hall", 8.0, 1.2)
	var table := _holder("PreviewTable", table_at, _facing_camera("hall", table_at))
	_box(table, Vector3(1.9, 1.0, 1.9), Vector3(0, 0.5, 0), _mat(Color("4b3524"), 0.9), "Pedestal")
	_preview_material = _mat(Color.WHITE, 0.7)
	_preview_material.albedo_texture = _checker_texture()
	_preview_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_box(table, Vector3(1.7, 0.08, 1.7), Vector3(0, 1.04, 0), _preview_material, "Board")
	_lamp_material = _mat(Color("7fbf6a"), 0.5)
	_lamp_material.emission_enabled = true
	_lamp_material.emission = Color("7fbf6a")
	_lamp_material.emission_energy_multiplier = 1.4
	_box(table, Vector3(0.16, 0.16, 0.16), Vector3(0.75, 1.18, 0.75), _lamp_material, "Lamp")
	_register_prop("preview", table, table_at + Vector3(0, 1.2, 0))
	# Classic shows two kings, Battle a knight facing a pawn: four small statue pieces, two visible at a time.
	var table_forward := Vector3(sin(table.rotation.y), 0.0, cos(table.rotation.y))
	for entry in [["king", "light", "classic", -1.0], ["king", "dark", "classic", 1.0], ["knight", "light", "battle", -1.0], ["pawn", "dark", "battle", 1.0]]:
		var spot := table_at + Vector3(0.0, 1.08, 0.0) + table_forward * 0.45 * float(entry[3])
		var yaw := table.rotation.y + (PI if float(entry[3]) < 0.0 else 0.0)
		var piece: Node3D = scene.call("spawn_paladin", entry[0], entry[1], Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * 1.1), spot))
		if piece != null:
			piece.reparent(self)
			piece.name = "PreviewPiece_%s_%s" % [entry[2], entry[1]]
			piece.set_meta("mode", entry[2])
			_preview_pieces.append(piece)
	set_play_selection(_play_state[0], _play_state[1], _play_state[2])

func _checker_texture() -> ImageTexture:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 8:
			image.set_pixel(x, y, Color("d9d2bf") if (x + y) % 2 == 0 else Color("3d5560"))
	return ImageTexture.create_from_image(image)

## Reflect the chosen Play setup on the preview table: the pieces (Classic: two kings; Battle: a knight and a pawn that will fight),
## the banner that glows, the lamp (local green, computer amber, online blue) and the board tint (2D board flatter, 3D board richer).
func set_play_selection(mode: String, opponent: String, view_3d: bool) -> void:
	_play_state = [mode, opponent, view_3d]
	_selected_mode = mode
	for key in _banner_materials:
		var material: StandardMaterial3D = _banner_materials[key]
		material.emission_energy_multiplier = 0.9 if key == mode else 0.0
	if _lamp_material != null:
		var color: Color = {"local": Color("7fbf6a"), "computer": Color("e0a23b"), "online": Color("5b9bd8")}.get(opponent, Color("7fbf6a"))
		_lamp_material.albedo_color = color
		_lamp_material.emission = color
	if _preview_material != null:
		_preview_material.albedo_color = Color.WHITE if view_3d else Color(0.78, 0.8, 0.84)
	for piece in _preview_pieces:
		piece.visible = piece.get_meta("mode") == mode
	_selected_mode = mode

var _selected_mode := "classic"

func play_selection() -> String:
	return _selected_mode

## Outside the walls: a signpost with two boards (Friends, Online) on the bridge, an unlit campfire glow, and the selected board lit.
func _build_exterior_props() -> void:
	var at := _station_point("exterior", 14.0, 6.2)
	var holder := _holder("Signpost", at, _facing_camera("exterior", at))
	var wood := _mat(Color("4b3524"), 0.9)
	_box(holder, Vector3(0.28, 3.6, 0.28), Vector3(0, 1.8, 0), wood, "Post")
	var names := ["friends", "online"]
	for i in 2:
		var board := _mat(Color("6a4a2c") if i == 0 else Color("2d4a6a"), 0.8)
		board.emission_enabled = true
		board.emission = Color("ffcf70")
		board.emission_energy_multiplier = 0.0
		var y := 3.0 - 1.1 * i
		_box(holder, Vector3(2.5, 0.8, 0.14), Vector3(1.35 if i == 0 else -1.35, y, 0.2), board, "Board_" + names[i])
		var label := Label3D.new()
		label.text = names[i].to_upper()
		label.font_size = 56
		label.pixel_size = 0.0072
		label.outline_size = 10
		label.modulate = Color("f6e3b0")
		label.position = Vector3(1.35 if i == 0 else -1.35, y, 0.3)
		label.no_depth_test = false
		holder.add_child(label)
		_sign_materials[names[i]] = board
		_register_prop("sign_" + names[i], holder, at + Vector3(1.35 if i == 0 else -1.35, y, 0.0))
	# a campfire by the road: stacked logs and an additive glow (no extra real light: the bridge torches already light it)
	var fire_at := _station_point("exterior", 9.0, 7.5)
	var fire := _holder("Campfire", fire_at, 0.0)
	for i in 3:
		var log := _box(fire, Vector3(1.2, 0.18, 0.18), Vector3(0, 0.12 + 0.1 * (i % 2), 0), wood, "Log%d" % i)
		log.rotation.y = i * PI / 3.0
	var flame := _mat(Color("ff8a2a"), 0.4)
	flame.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame.albedo_color = Color(1.0, 0.55, 0.16, 0.9)
	flame.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flame.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var glow := _box(fire, Vector3(0.55, 0.9, 0.55), Vector3(0, 0.55, 0), flame, "Flame")
	glow.rotation.y = 0.6
	set_exterior_selection(_exterior_kind)

func set_exterior_selection(kind: String) -> void:
	_exterior_kind = kind
	for key in _sign_materials:
		(_sign_materials[key] as StandardMaterial3D).emission_energy_multiplier = 0.55 if key == kind else 0.0

## The armoury (Settings): a weapon rack with shields and swords, and an anvil.
func _build_armoury_props() -> void:
	var at := _station_point("armoury", 13.0, 3.0)
	var rack := _holder("WeaponRack", at, _facing_camera("armoury", at))
	var wood := _mat(Color("4b3524"), 0.9)
	var iron := _mat(Color("5a5e68"), 0.4, 0.7)
	var gold := _mat(Color("b59754"), 0.4, 0.5)
	_box(rack, Vector3(0.2, 2.8, 0.2), Vector3(-1.5, 1.4, 0), wood, "PostL")
	_box(rack, Vector3(0.2, 2.8, 0.2), Vector3(1.5, 1.4, 0), wood, "PostR")
	_box(rack, Vector3(3.3, 0.16, 0.2), Vector3(0, 2.6, 0), wood, "Beam")
	_box(rack, Vector3(3.3, 0.16, 0.2), Vector3(0, 1.4, 0), wood, "Shelf")
	for i in 3:
		var blade := _box(rack, Vector3(0.1, 1.9, 0.03), Vector3(-0.9 + 0.9 * i, 1.55, 0.2), iron, "Sword%d" % i)
		blade.rotation.z = 0.0
		_box(rack, Vector3(0.5, 0.08, 0.08), Vector3(-0.9 + 0.9 * i, 0.6, 0.2), gold, "Guard%d" % i)
	var anvil := _station_point("armoury", 9.5, -1.6)
	var anvil_holder := _holder("Anvil", anvil, _facing_camera("armoury", anvil))
	_box(anvil_holder, Vector3(0.9, 0.7, 0.9), Vector3(0, 0.35, 0), wood, "Stump")
	_box(anvil_holder, Vector3(1.2, 0.35, 0.5), Vector3(0, 0.88, 0), iron, "AnvilTop")
	_register_prop("armoury_rack", rack, at + Vector3(0, 1.6, 0))

## The training yard: a practice dummy.
func _build_yard_props() -> void:
	var at := _station_point("yard", 12.0, 5.5)
	var dummy := _holder("PracticeDummy", at, _facing_camera("yard", at))
	var wood := _mat(Color("6a4a2c"), 0.9)
	_box(dummy, Vector3(0.22, 2.2, 0.22), Vector3(0, 1.1, 0), wood, "Post")
	_box(dummy, Vector3(1.3, 0.2, 0.2), Vector3(0, 1.7, 0), wood, "Arms")
	_box(dummy, Vector3(0.55, 0.55, 0.45), Vector3(0, 2.3, 0), _mat(Color("c8b38a"), 0.9), "Head")
	_register_prop("dummy", dummy, at + Vector3(0, 1.6, 0))

func _pulse(prop_id: String) -> void:
	if props.has(prop_id):
		props[prop_id].pulse = 1.0

# ---------------------------------------------------------------------------------------------------------------------
# per frame
# ---------------------------------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	advance(delta)

## Advances paladin reactions and prop pulses (the rig itself is advanced by the OpeningScene). Tests call this with explicit steps.
func advance(delta: float) -> void:
	_clock += delta
	var step := 1.0 if Prefs.reduce_motion else 1.0 - exp(-7.0 * minf(delta, 0.1))
	for id in paladins:
		var state: Dictionary = paladins[id]
		state.look_off = lerpf(state.look_off, state.look_target, step)
		var was_aside: float = state.aside
		state.aside = move_toward(state.aside, state.aside_target, delta / 0.9) if not Prefs.reduce_motion else state.aside_target
		var model: PaladinModel = state.model
		if model != null and is_instance_valid(model) and model.player != null:
			# only the paladin the camera is at (or flying to) is animated: the others hold their pose and cost nothing
			var active: bool = id == rig.current_id or (rig.flying and id == rig.origin_id)
			model.player.speed_scale = 1.0 if active else 0.0
			if not Prefs.reduce_motion and active:
				if state.clip == "walk" and was_aside > 0.02 and state.aside <= 0.02:
					_play(state, "greet")   # back in place: the greeting
				elif state.clip == "idle" or paladin_clip(id) == "idle":
					state.variation_in -= delta
					if state.variation_in <= 0.0:
						state.variation_in = randf_range(IDLE_VARIATION_EVERY.x, IDLE_VARIATION_EVERY.y)
						_play(state, "look_around", 0.4)
		_apply_paladin(state)
	for id in props:
		var prop: Dictionary = props[id]
		if prop.pulse > 0.0:
			prop.pulse = maxf(0.0, prop.pulse - delta / 0.4)

func _on_arrived(station_id: String) -> void:
	_greet(station_id)
	arrived.emit(station_id)

func _on_flight_started(_station_id: String, _duration: float) -> void:
	_hover_station = ""
	clear_hover()
	# the paladin the camera leaves steps out of its way (it walks aside while the camera flies off)
	var leaving := rig.origin_id
	if paladins.has(leaving) and not Prefs.reduce_motion:
		var state: Dictionary = paladins[leaving]
		state.aside_target = 1.0
		_play(state, "walk", 0.25)
	if is_instance_valid(_audio) and _audio.has_method("play_ui"):
		_audio.call("play_ui", "back")   # the existing UI 'back' swish doubles as the flight whoosh (no new sound ids)

func set_audio(audio: Node) -> void:
	_audio = audio

# ---------------------------------------------------------------------------------------------------------------------
# displays: the pages push their data, the props show it (applied at once if the station exists, else when it is built)
# ---------------------------------------------------------------------------------------------------------------------
## Campaign: `status` map | boon | lost | cleared | none, `index` the current encounter, `cleared` the encounters won, `offers` the boon ids on offer.
func set_campaign_display(status: String, index: int, cleared: int, offers: Array = []) -> void:
	_display["campaign"] = [status, index, cleared, offers]
	_apply_display()

func set_training_medals(medals: Array) -> void:
	_display["medals"] = medals
	_apply_display()

func set_gallery(results: Array) -> void:
	_display["gallery"] = results
	_apply_display()

func set_leaderboard(names: Array) -> void:
	_display["leaderboard"] = names
	_apply_display()

func set_friends(names: Array) -> void:
	_display["friends"] = names
	_apply_display()

func _apply_display() -> void:
	if _display.has("campaign") and not war_nodes.is_empty():
		var c: Array = _display["campaign"]
		MenuHeroProps.apply_campaign(self, c[0], c[1], c[2], c[3])
	if _display.has("medals") and not medal_discs.is_empty():
		MenuHeroProps.apply_medals(self, _display["medals"])
	if _display.has("gallery") and not gallery_frames.is_empty():
		MenuHeroProps.apply_gallery(self, _display["gallery"])
	if _display.has("leaderboard") and not rank_banners.is_empty():
		MenuHeroProps.apply_leaderboard(self, _display["leaderboard"])
	if _display.has("friends") and not friend_signs.is_empty():
		MenuHeroProps.apply_friends(self, _display["friends"])
