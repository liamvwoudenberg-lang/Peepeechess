class_name MenuHeroProps
extends RefCounted
## Hero props and in-world displays of the cinematic menu stations (docs/ui/CINEMATIC_MENU.md, phases 3 and 4): the war room's map table for the
## campaign, the training yard's weapon rack, dummies and medals, the gallery's framed matches, the watchtower's rank banners and the friend name
## signs outside the walls. Everything is presentation: the page controls own input, `MenuWorld` forwards state (`set_campaign_display`,
## `set_training_medals`, `set_gallery`, `set_leaderboard`, `set_friends`) and picks props for clicks.
const NODE_COUNT := 12
const BOSS_NODES := [5, 8, 11]
const MAX_SIGNS := 3

# ---------------------------------------------------------------------------------------------------------------------
# war room: the campaign map table
# ---------------------------------------------------------------------------------------------------------------------
## Twelve nodes along an S-curve on a parchment map; locked = covered, cleared = banner, current = lit, boss = tall. Three boon pedestals in front.
static func build_warroom(world: Node3D) -> void:
	var at: Vector3 = world._station_point("warroom", 14.5, 11.5)
	var table: Node3D = world._holder("MapTable", at, world._facing_camera("warroom", at))
	table.scale = Vector3.ONE * 1.2
	var wood: Material = world._mat(Color("4b3524"), 0.9)
	for corner in [[-3.3, -2.3], [3.3, -2.3], [-3.3, 2.3], [3.3, 2.3]]:
		world._box(table, Vector3(0.5, 1.1, 0.5), Vector3(corner[0], 0.55, corner[1]), wood, "Leg")
	world._box(table, Vector3(7.4, 0.3, 5.4), Vector3(0, 1.25, 0), wood, "Top")
	var map: StandardMaterial3D = world._mat(Color.WHITE, 0.95)
	map.albedo_texture = _map_texture()
	world._box(table, Vector3(6.9, 0.05, 4.9), Vector3(0, 1.42, 0), map, "Map")
	var cleared_material: StandardMaterial3D = world._mat(Color("5aa05a"), 0.6)
	var locked_material: StandardMaterial3D = world._mat(Color("55555c"), 0.9)
	var current_material: StandardMaterial3D = world._mat(Color("f0c860"), 0.4)
	current_material.emission_enabled = true
	current_material.emission = Color("f0c860")
	current_material.emission_energy_multiplier = 1.6
	var boss_material: StandardMaterial3D = world._mat(Color("a8323c"), 0.5)
	var nodes: Array = []
	for i in NODE_COUNT:
		var local := node_position(i)
		var holder := Node3D.new()
		holder.name = "WarNode_%d" % i
		holder.position = local
		table.add_child(holder)
		var boss := i in BOSS_NODES
		var base := _cylinder(holder, 0.3 if boss else 0.22, 0.08, 0.0, world._mat(Color("c9b48a"), 0.8), "Base")
		var height := 0.85 if boss else 0.45
		var body := _cylinder(holder, 0.17 if boss else 0.11, height, 0.04 + height * 0.5, boss_material if boss else locked_material, "Piece")
		var flag: MeshInstance3D = world._box(holder, Vector3(0.28, 0.2, 0.02), Vector3(0.16, 0.62 if boss else 0.46, 0), cleared_material, "Flag")
		var cover: MeshInstance3D = world._box(holder, Vector3(0.46, 0.34 if not boss else 0.7, 0.46), Vector3(0, 0.2 if not boss else 0.38, 0), world._mat(Color("2c2c34"), 0.95), "Cover")
		nodes.append({"holder": holder, "body": body, "flag": flag, "cover": cover, "boss": boss, "base": base})
		world._register_prop("campaign_node_%d" % i, holder, table.to_global(local) + Vector3(0, 0.5, 0), 0.5)
	world.war_nodes = nodes
	world.war_materials = {"cleared": cleared_material, "locked": locked_material, "current": current_material, "boss": boss_material}
	world._register_prop("map_table", table, at + Vector3(0, 1.5, 0), 3.2)
	# three boon pedestals in front of the table (visible only while a boon is offered)
	var offers: Array = []
	for i in 3:
		var spot: Vector3 = world._station_point("warroom", 8.5, 14.0 - float(i) * 2.4)
		var pedestal: Node3D = world._holder("BoonPedestal_%d" % i, spot, world._facing_camera("warroom", spot))
		world._box(pedestal, Vector3(0.7, 0.9, 0.7), Vector3(0, 0.45, 0), wood, "Plinth")
		var gem_material: StandardMaterial3D = world._mat([Color("c0392b"), Color("2e86de"), Color("27ae60")][i], 0.3)
		gem_material.emission_enabled = true
		gem_material.emission = gem_material.albedo_color
		gem_material.emission_energy_multiplier = 1.2
		world._box(pedestal, Vector3(0.36, 0.36, 0.36), Vector3(0, 1.1, 0), gem_material, "Gem")
		var label := _label(pedestal, "", Vector3(0, 1.8, 0), 0.5)
		pedestal.visible = false
		offers.append({"node": pedestal, "label": label})
		world._register_prop("boon_%d" % i, pedestal, spot + Vector3(0, 1.1, 0), 0.7)
	world.war_offers = offers

## Winding path across the 6.9 x 4.9 map (table-local x/z).
static func node_position(i: int) -> Vector3:
	var t := float(i) / float(NODE_COUNT - 1)
	return Vector3(lerpf(-2.9, 2.9, t), 1.48, 1.5 * sin(t * TAU * 1.25) * (1.0 - 0.15 * t) - 0.25 * cos(t * 9.0))

## Applies a CampaignRun's state: `status` is map | boon | lost | cleared | none, `index` the current encounter, `cleared` how many are done.
static func apply_campaign(world: Node3D, status: String, index: int, cleared: int, offers: Array = []) -> void:
	var nodes: Array = world.war_nodes
	for i in nodes.size():
		var n: Dictionary = nodes[i]
		var done := i < cleared
		var current := status in ["map", "boon"] and i == index and not done
		var locked := not done and not current
		(n.cover as Node3D).visible = locked
		(n.flag as Node3D).visible = done
		var material: Material = world.war_materials.current if current else (world.war_materials.cleared if done else (world.war_materials.boss if n.boss else world.war_materials.locked))
		(n.body as MeshInstance3D).material_override = material
		(n.holder as Node3D).scale = Vector3.ONE * (1.25 if current else 1.0)
	for i in world.war_offers.size():
		var o: Dictionary = world.war_offers[i]
		(o.node as Node3D).visible = status == "boon" and i < offers.size()
		if i < offers.size():
			(o.label as Label3D).text = String(offers[i]).capitalize().replace("_", " ")

static func _map_texture() -> ImageTexture:
	var image := Image.create(256, 160, false, Image.FORMAT_RGB8)
	for y in 160:
		for x in 256:
			var grain := 0.06 * sin(float(x) * 0.35) * sin(float(y) * 0.27) + 0.04 * sin(float(x + y) * 0.11)
			image.set_pixel(x, y, Color(0.80 + grain, 0.70 + grain, 0.50 + grain))
	# the road: a dotted line along the node path
	for step in 120:
		var t := float(step) / 119.0
		var p := node_position(int(round(t * float(NODE_COUNT - 1))))
		var q := Vector2(128.0 + p.x / 6.9 * 256.0, 80.0 + p.z / 4.9 * 160.0)
		if step % 2 == 0:
			for dx in 2:
				for dy in 2:
					var px := clampi(int(q.x) + dx, 0, 255)
					var py := clampi(int(q.y) + dy, 0, 159)
					image.set_pixel(px, py, Color(0.35, 0.22, 0.12))
	return ImageTexture.create_from_image(image)

# ---------------------------------------------------------------------------------------------------------------------
# training yard: weapon rack, two more dummies, a medal wall
# ---------------------------------------------------------------------------------------------------------------------
static func build_yard_extra(world: Node3D) -> void:
	var wood: Material = world._mat(Color("6a4a2c"), 0.9)
	var steel: Material = world._mat(Color("9aa4b0"), 0.4, 0.7)
	var rack_at: Vector3 = world._station_point("yard", 12.0, 7.5)
	var rack: Node3D = world._holder("WeaponRack", rack_at, world._facing_camera("yard", rack_at))
	world._box(rack, Vector3(3.2, 0.14, 0.14), Vector3(0, 1.9, 0), wood, "Bar")
	world._box(rack, Vector3(0.16, 2.0, 0.16), Vector3(-1.5, 1.0, 0), wood, "PostA")
	world._box(rack, Vector3(0.16, 2.0, 0.16), Vector3(1.5, 1.0, 0), wood, "PostB")
	for i in 5:
		world._box(rack, Vector3(0.09, 1.5, 0.04), Vector3(-1.2 + float(i) * 0.6, 1.15, 0.12), steel, "Blade_%d" % i)
		world._box(rack, Vector3(0.32, 0.06, 0.06), Vector3(-1.2 + float(i) * 0.6, 1.88, 0.12), world._mat(Color("b59754"), 0.4, 0.5), "Guard_%d" % i)
	world._register_prop("weapon_rack", rack, rack_at + Vector3(0, 1.2, 0), 1.8)
	var wood_light: Material = world._mat(Color("c8b38a"), 0.9)
	for entry in [[16.0, 10.0], [14.0, 12.5]]:
		var at: Vector3 = world._station_point("yard", float(entry[0]), float(entry[1]))
		var dummy: Node3D = world._holder("Dummy", at, world._facing_camera("yard", at))
		world._box(dummy, Vector3(0.22, 2.0, 0.22), Vector3(0, 1.0, 0), wood, "Post")
		world._box(dummy, Vector3(1.1, 0.18, 0.18), Vector3(0, 1.55, 0), wood, "Arms")
		world._box(dummy, Vector3(0.48, 0.48, 0.4), Vector3(0, 2.1, 0), wood_light, "Head")
	# the medal wall: eight slots (a lesson each), lit by what you earned
	var wall_at: Vector3 = world._station_point("yard", 17.0, 6.0, 0.0)
	var wall: Node3D = world._holder("MedalWall", wall_at, world._facing_camera("yard", wall_at))
	world._box(wall, Vector3(5.0, 2.6, 0.12), Vector3(0, 2.4, 0), world._mat(Color("3a2c20"), 0.9), "Board")
	var slots: Array = []
	for i in 8:
		var disc := _cylinder(wall, 0.24, 0.05, 0.0, world._mat(Color("55555c"), 0.5, 0.3), "Medal_%d" % i)
		disc.rotation.x = PI * 0.5
		disc.position = Vector3(-1.9 + float(i % 4) * 1.25, 2.9 - float(i / 4) * 1.1, 0.1)
		slots.append(disc)
	world.medal_discs = slots
	world._register_prop("medal_wall", wall, wall_at + Vector3(0, 2.4, 0), 2.4)

## `medals`: one entry per lesson slot, 0 = none, 1 = bronze, 2 = silver, 3 = gold.
static func apply_medals(world: Node3D, medals: Array) -> void:
	var palette := [Color("55555c"), Color("b0743c"), Color("c8ccd4"), Color("f0c860")]
	for i in world.medal_discs.size():
		var tier := clampi(int(medals[i]) if i < medals.size() else 0, 0, 3)
		var material := StandardMaterial3D.new()
		material.albedo_color = palette[tier]
		material.metallic = 0.6 if tier > 0 else 0.2
		material.roughness = 0.35
		if tier > 0:
			material.emission_enabled = true
			material.emission = palette[tier]
			material.emission_energy_multiplier = 0.5
		(world.medal_discs[i] as MeshInstance3D).material_override = material

# ---------------------------------------------------------------------------------------------------------------------
# gallery: framed paintings of recent matches
# ---------------------------------------------------------------------------------------------------------------------
static func build_gallery(world: Node3D, station_id: String = "gallery") -> void:
	var frame_material: Material = world._mat(Color("b59754"), 0.4, 0.5)
	var frames: Array = world.gallery_frames
	for i in 6:
		var at: Vector3 = world._station_point(station_id, 14.0 + float(i % 2) * 0.6, 11.5 - float(i) * 1.72)
		var holder: Node3D = world._holder("Frame_%s_%d" % [station_id, i], at, world._facing_camera(station_id, at))
		world._box(holder, Vector3(1.5, 2.3, 0.1), Vector3(0, 3.4, 0), frame_material, "Frame")
		var canvas_material: StandardMaterial3D = world._mat(Color("30303c"), 0.9)
		var canvas: MeshInstance3D = world._box(holder, Vector3(1.2, 2.0, 0.06), Vector3(0, 3.4, 0.05), canvas_material, "Canvas")
		var label := _label(holder, "", Vector3(0, 2.0, 0.1), 0.28)
		frames.append({"canvas": canvas, "material": canvas_material, "label": label, "slot": i})
		world._register_prop("%s_%d" % [station_id, i], holder, at + Vector3(0, 3.4, 0), 1.2)
	world.gallery_frames = frames

## `results`: strings "win" | "loss" | "draw" (newest first); empty slots stay dark.
static func apply_gallery(world: Node3D, results: Array) -> void:
	var colors := {"win": Color("3f8f5a"), "loss": Color("8f3f3f"), "draw": Color("8f8f4f")}
	for f in world.gallery_frames:
		var slot := int(f.slot)
		var key := String(results[slot]) if slot < results.size() else ""
		(f.material as StandardMaterial3D).albedo_color = colors.get(key, Color("30303c"))
		(f.label as Label3D).text = key.capitalize()

# ---------------------------------------------------------------------------------------------------------------------
# watchtower: rank banners
# ---------------------------------------------------------------------------------------------------------------------
static func build_tower(world: Node3D) -> void:
	var gold: Material = world._mat(Color("b59754"), 0.4, 0.5)
	var banners: Array = []
	var colors := [Color("c9a227"), Color("aeb4bd"), Color("b0743c")]
	for i in 3:
		var at: Vector3 = world._station_point("tower", 9.0, 9.5 - float(i) * 3.0, 4.0 - float(i) * 0.8)
		var holder: Node3D = world._holder("RankBanner_%d" % i, at, world._facing_camera("tower", at))
		world._box(holder, Vector3(2.0, 0.14, 0.14), Vector3(0, 4.6, 0), gold, "Bar")
		var cloth_material: StandardMaterial3D = world._mat(colors[i], 0.9)
		cloth_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		world._box(holder, Vector3(1.6, 3.8, 0.05), Vector3(0, 2.6, 0), cloth_material, "Cloth")
		var label := _label(holder, "%d" % (i + 1), Vector3(0, 3.6, 0.08), 0.9)
		var name_label := _label(holder, "", Vector3(0, 1.6, 0.08), 0.3)
		banners.append({"name": name_label, "rank": label})
		world._register_prop("rank_%d" % i, holder, at + Vector3(0, 2.6, 0), 1.6)
	world.rank_banners = banners

static func apply_leaderboard(world: Node3D, names: Array) -> void:
	for i in world.rank_banners.size():
		(world.rank_banners[i].name as Label3D).text = String(names[i]) if i < names.size() else ""

# ---------------------------------------------------------------------------------------------------------------------
# outside the walls: friend name signs on the signpost
# ---------------------------------------------------------------------------------------------------------------------
static func build_friend_signs(world: Node3D) -> void:
	var wood: Material = world._mat(Color("5a3f28"), 0.9)
	var signs: Array = []
	for i in MAX_SIGNS:
		var at: Vector3 = world._station_point("exterior", 8.5, 5.4 - float(i) * 1.8, 0.0)
		var holder: Node3D = world._holder("FriendSign_%d" % i, at, world._facing_camera("exterior", at))
		world._box(holder, Vector3(0.12, 2.6, 0.12), Vector3(0, 1.3, 0), wood, "Post")
		world._box(holder, Vector3(1.6, 0.6, 0.1), Vector3(0, 2.3, 0.05), wood, "Board")
		var label := _label(holder, "", Vector3(0, 2.3, 0.12), 0.26)
		holder.visible = false
		signs.append({"node": holder, "label": label})
		world._register_prop("friend_%d" % i, holder, at + Vector3(0, 2.3, 0), 1.0)
	world.friend_signs = signs

static func apply_friends(world: Node3D, names: Array) -> void:
	for i in world.friend_signs.size():
		var s: Dictionary = world.friend_signs[i]
		(s.node as Node3D).visible = i < names.size()
		if i < names.size():
			(s.label as Label3D).text = String(names[i])

# ---------------------------------------------------------------------------------------------------------------------
static func _cylinder(parent: Node3D, radius: float, height: float, y: float, material: Material, node_name: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.8
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = material
	node.position = Vector3(0, y, 0)
	node.name = node_name
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

static func _label(parent: Node3D, text: String, at: Vector3, size: float) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.pixel_size = 0.01
	label.font_size = int(size * 100.0)
	label.modulate = Color("f4eddc")
	label.outline_modulate = Color(0.02, 0.03, 0.08, 0.95)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.shaded = false
	parent.add_child(label)
	return label
