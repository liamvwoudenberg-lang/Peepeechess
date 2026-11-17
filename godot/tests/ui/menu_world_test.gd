extends SceneTree
## The cinematic menu (docs/ui/CINEMATIC_MENU.md, phases 1-2): station data, camera rig flights (long first, short later, interrupt, back,
## skip, reduce-motion, instant mode), the world's paladins and props, the page -> station mapping through the real application, the
## quality tiers, a one-row tab bar at 1280 and 720 px, and the skip-on-input contract.
const AppScene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const OpeningScene = preload("res://ui/opening/opening_scene.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	Settings.loaded = true
	Settings.intro_seen = true
	Settings.token = ""
	Prefs.loaded = true
	Prefs.reset_defaults()
	stations_and_pages()
	rig_flights()
	await world_in_the_application()
	await quality_tiers()
	await tab_row()
	await skip_on_input()
	await reduce_motion()
	print("MENU WORLD: %d checks; failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

# ---------------------------------------------------------------- station data
func stations_and_pages() -> void:
	check(MenuStations.IDS.size() == 9, "nine stations")
	for id in MenuStations.IDS:
		check(MenuStations.STATIONS.has(id), "station %s exists" % id)
		var s := MenuStations.station(id)
		check((s.pos as Vector3).distance_to(s.look) > 1.0 and float(s.fov) > 30.0 and float(s.fov) < 90.0, "%s: a sane camera" % id)
		check(not is_nan(MenuStations.paladin_position(id).x), "%s: the paladin has a place" % id)
	for page in ["home", "play", "training", "campaign", "friends", "profile", "history", "leaderboard", "settings", "account"]:
		check(MenuStations.STATIONS.has(MenuStations.station_for_page(page)), "page %s has a station" % page)
	check(MenuStations.station_for_page("friends") == "exterior", "Friends is outside the walls")
	check(MenuStations.station_for_page("account") == "exterior", "signing in is outside the walls")
	check(MenuStations.station_for_page("play", true) == "exterior", "online play is outside the walls")
	check(MenuStations.station_for_page("play", false) == "hall", "local play is in the hall")
	check(MenuStations.station_for_page("unknown") == "hall", "an unknown page falls back to the hall")
	var home := MenuStations.station("home")
	check((home.pos as Vector3).is_equal_approx(OpeningScene.CAM_B) and (home.look as Vector3).is_equal_approx(OpeningScene.LOOK_B), "the home station is the opening glide's final pose")
	# every station's paladin stands on the ground side the camera can see (in front of it, within 25 m)
	for id in MenuStations.IDS:
		var s := MenuStations.station(id)
		var at := MenuStations.paladin_position(id)
		var forward: Vector3 = ((s.look as Vector3) - (s.pos as Vector3))
		forward.y = 0.0
		var to: Vector3 = at - (s.pos as Vector3)
		to.y = 0.0
		check(to.length() < 25.0 and forward.normalized().dot(to.normalized()) > 0.8, "%s: the paladin is in front of the camera" % id)
	# the way to and from the exterior passes through the gate
	for pair in [["hall", "exterior"], ["home", "exterior"], ["yard", "exterior"]]:
		var path: Array = MenuStations.via(pair[0], pair[1])
		var passes := false
		for point in path:
			if absf(point.x) < 1.0 and point.z > 2.0 and point.z < 30.0:
				passes = true
		check(passes, "%s -> %s passes the gate" % pair)
	var back_path: Array = MenuStations.via("exterior", "hall")
	var forward_path: Array = MenuStations.via("hall", "exterior")
	check(back_path.size() == forward_path.size() and (back_path[0] as Vector3).is_equal_approx(forward_path[forward_path.size() - 1]), "the way back is the same path reversed")

# ---------------------------------------------------------------- the rig
func rig_flights() -> void:
	MenuCameraRig.instant_override = 0
	var rig := MenuCameraRig.new()
	var arrivals: Array[String] = []
	rig.arrived.connect(func(id): arrivals.append(id))
	rig.place("home")
	check(rig.active and not rig.flying and rig.current_id == "home", "placed at home")
	var d := rig.fly_to("hall")
	check(is_equal_approx(d, MenuCameraRig.LONG_FLIGHT), "the first flight into a station is long (%.2f s)" % d)
	check(rig.flying and rig.current_id == "hall", "flying to the hall")
	var start_pos := rig.pos
	rig.advance(0.016)
	check(rig.pos.distance_to(start_pos) < 0.5, "the flight starts gently (ease-in)")
	var previous := rig.pos
	var worst_step := 0.0
	var time := 0.016
	while rig.flying and time < 4.0:
		rig.advance(1.0 / 60.0)
		time += 1.0 / 60.0
		worst_step = maxf(worst_step, rig.pos.distance_to(previous))
		previous = rig.pos
	check(not rig.flying and arrivals == ["hall"], "arrived at the hall (once)")
	check(absf(time - MenuCameraRig.LONG_FLIGHT) < 0.1, "the long flight takes about 2.5 s (%.2f s)" % time)
	check(rig.pos.is_equal_approx(MenuStations.station("hall").pos) and rig.look.is_equal_approx(MenuStations.station("hall").look), "rests exactly on the station")
	check(worst_step < 1.2, "the camera never jumps (largest step %.2f m)" % worst_step)
	# every later flight is short
	rig.fly_to("home")
	rig.advance(5.0)
	var again := rig.fly_to("hall")
	check(is_equal_approx(again, MenuCameraRig.SHORT_FLIGHT), "a later flight is short (%.2f s)" % again)
	rig.advance(5.0)
	check(rig.current_id == "hall" and not rig.flying, "short flight done")
	# interrupt: retarget in mid-flight from the current pose
	rig.place("home")
	rig.fly_to("exterior")
	for i in 40:
		rig.advance(1.0 / 60.0)
	var mid := rig.pos
	check(rig.flying, "still flying after 0.67 s")
	rig.fly_to("hall")
	rig.advance(0.001)
	check(rig.pos.distance_to(mid) < 0.6, "an interrupted flight continues from where the camera is (no jump: %.2f m)" % rig.pos.distance_to(mid))
	rig.advance(10.0)
	check(rig.current_id == "hall" and not rig.flying, "the retargeted flight arrives")
	# back reverses the last flight
	rig.place("home")
	rig.fly_to("armoury")
	rig.advance(10.0)
	check(rig.back() and rig.current_id == "home", "back flies to the station we came from")
	rig.advance(10.0)
	check(not rig.flying and rig.current_id == "home", "back arrived")
	var empty := MenuCameraRig.new()
	empty.place("home")
	check(not empty.back(), "back with nothing behind returns false")
	# skip jumps to the end
	rig.fly_to("tower")
	rig.advance(0.3)
	rig.skip()
	check(not rig.flying and rig.current_id == "tower" and rig.pos.is_equal_approx(MenuStations.station("tower").pos), "skip ends the flight on the station")
	# fly-past beats: the look target glances at the exterior's statues during the long first flight into it
	var glance := MenuCameraRig.new()
	glance.place("hall")
	glance.fly_to("exterior")
	var looked_aside := false
	for i in 200:
		glance.advance(1.0 / 60.0)
		if glance.look.x < -3.0 and glance.look.z > 5.0 and glance.flying:
			looked_aside = true
	check(looked_aside, "the first flight to the exterior glances at the bridge giants on the way")
	# reduce-motion: a 150 ms crossfade, no roll
	var calm := MenuCameraRig.new()
	calm.place("home")
	calm.reduced_motion = true
	var rd := calm.fly_to("hall")
	check(is_equal_approx(rd, MenuCameraRig.REDUCED_FLIGHT), "reduce-motion flights last 150 ms")
	var max_roll := 0.0
	while calm.flying:
		calm.advance(0.016)
		max_roll = maxf(max_roll, absf(calm.roll))
	check(max_roll == 0.0 and calm.pos.is_equal_approx(MenuStations.station("hall").pos), "no roll, ends on the station")
	# instant mode: no flights at all
	MenuCameraRig.instant_override = 1
	var instant := MenuCameraRig.new()
	instant.place("home")
	var di := instant.fly_to("yard")
	check(di == 0.0 and not instant.flying and instant.current_id == "yard", "instant mode arrives at once")
	MenuCameraRig.instant_override = 0

# ---------------------------------------------------------------- the world inside the application
func fresh_app(width: int = 1280, height: int = 800):
	root.size = Vector2i(width, height)
	var app = AppScene.instantiate()
	root.add_child(app)
	return app

func settle(frames: int = 4) -> void:
	for i in frames:
		await process_frame

func world_in_the_application() -> void:
	MenuCameraRig.instant_override = 1
	Settings.quality = "balanced"
	var app = fresh_app()
	await settle()
	check(is_instance_valid(app.world), "balanced quality builds the menu world")
	if not is_instance_valid(app.world):
		app.queue_free()
		return
	var world: MenuWorld = app.world
	check(world.rig.active and world.current_station() == "home", "home station on the title page")
	var expected := {"play": "hall", "training": "yard", "campaign": "warroom", "friends": "exterior", "profile": "gallery",
		"history": "archive", "leaderboard": "tower", "settings": "armoury", "account": "exterior", "home": "home"}
	for page in expected:
		app.navigate(page)
		await settle(2)
		check(world.current_station() == expected[page], "%s -> %s (got %s)" % [page, expected[page], world.current_station()])
		check(world.paladins.has(expected[page]) and is_instance_valid(world.paladin_at(expected[page])), "a paladin stands at the %s station" % expected[page])
	# online play is outside the walls, local play inside
	app.online = true
	app.navigate("play")
	await settle(2)
	check(world.current_station() == "exterior", "online play flies outside the walls")
	app.online = false
	app.navigate("play")
	await settle(2)
	check(world.current_station() == "hall", "back to local play: the hall")
	# the preview table reflects the chosen setup
	app.selected_mode = "battle"
	app.navigate("play")
	await settle(2)
	check(world.play_selection() == "battle", "the preview table shows Battle")
	var battle_visible := 0
	var classic_visible := 0
	for piece in world._preview_pieces:
		if piece.visible:
			if piece.get_meta("mode") == "battle":
				battle_visible += 1
			else:
				classic_visible += 1
	check(battle_visible == 2 and classic_visible == 0, "Battle shows its two pieces only (%d / %d)" % [battle_visible, classic_visible])
	app.selected_mode = "classic"
	app.navigate("play")
	await settle(2)
	var classic_pieces := 0
	for piece in world._preview_pieces:
		if piece.visible and piece.get_meta("mode") == "classic":
			classic_pieces += 1
	check(classic_pieces == 2, "Classic shows two kings")
	# hover and select make the station paladin react
	var knight: Node3D = world.paladin_at("hall")
	var before := knight.transform
	world.hover_prop("banner_battle")
	for i in 30:
		world.advance(1.0 / 60.0)
	check(not knight.transform.basis.is_equal_approx(before.basis), "hovering a banner turns the paladin toward it")
	world.clear_hover()
	for i in 60:
		world.advance(1.0 / 60.0)
	world.select_prop("banner_classic")
	check(world.paladin_clip("hall") == "bow", "selecting makes the paladin bow (clip: %s)" % world.paladin_clip("hall"))
	world.select_prop("banner_classic")
	check(world.paladin_clip("hall") == "salute", "the next selection salutes (clip: %s)" % world.paladin_clip("hall"))
	# the station paladins are RIGGED: a skeleton, real clips that advance, a look modifier that turns the head
	check(world.is_rigged("hall"), "the hall paladin is a rigged PaladinModel")
	var rigged: PaladinModel = world.paladins["hall"].model
	check(rigged != null and rigged.skeleton != null and rigged.player != null and rigged.player.has_animation("greet") and rigged.player.has_animation("bow") and rigged.player.has_animation("salute") and rigged.player.has_animation("look_around"), "the paladin has a skeleton and the menu clips (greet, bow, salute, look_around)")
	var position_before := rigged.player.current_animation_position
	await settle(12)
	check(rigged.player.is_playing() and rigged.player.current_animation_position != position_before, "the clip advances over frames (%.3f -> %.3f)" % [position_before, rigged.player.current_animation_position])
	var look: MenuLookModifier = world.paladins["hall"].look
	check(look != null and look.has_bones(), "the head/spine look modifier found its bones")
	world.hover_prop("banner_battle")
	for i in 40:
		world.advance(1.0 / 60.0)
	await settle(3)
	check(absf(look.applied) > 0.02, "hovering a prop turns the head through the look modifier (%.3f rad)" % look.applied)
	world.clear_hover()
	for i in 80:
		world.advance(1.0 / 60.0)
	await settle(3)
	check(absf(look.applied) < 0.05, "...and it turns back when the hover ends (%.3f rad)" % look.applied)
	# only the paladin at the current station is animated
	var other: PaladinModel = null
	for id in world.paladins:
		if id != world.current_station() and world.paladins[id].model != null:
			other = world.paladins[id].model
	check(other == null or is_zero_approx(other.player.speed_scale), "paladins at other stations hold their pose (no skeleton cost)")
	# a flight makes the station it leaves step aside and the arrival walks back in
	MenuCameraRig.instant_override = 0
	world.fly_to_station("yard")
	check(is_equal_approx(float(world.paladins["hall"].aside_target), 1.0), "the paladin the camera leaves steps aside")
	check(world.paladin_clip("hall") == "walk", "...walking (clip: %s)" % world.paladin_clip("hall"))
	world.skip()
	MenuCameraRig.instant_override = 1
	await settle(2)
	# budgets: the scene plus the menu layer stays modest on phones
	var stats: Dictionary = app.scene3d.stats()
	var layer: Dictionary = world.stats()
	check(int(stats.draw_nodes) <= 80, "the castle itself keeps its draw-node budget (%d)" % int(stats.draw_nodes))
	check(int(layer.draw_nodes) <= 160 and int(layer.stations) == world.built_stations().size(), "the menu layer after visiting every station stays modest (%d nodes, %d stations built)" % [int(layer.draw_nodes), int(layer.stations)])
	check(int(stats.lights) <= 10, "no extra real lights (%d)" % int(stats.lights))
	var fresh = fresh_app()
	await settle()
	check(is_instance_valid(fresh.world) and fresh.world.built_stations() == ["home"], "a fresh menu builds only the home station")
	check(int(fresh.world.stats().draw_nodes) <= 40, "...which costs at most 40 draw nodes on top of the castle (%d)" % int(fresh.world.stats().draw_nodes))
	fresh.queue_free()
	await settle(2)
	app.queue_free()
	await settle(2)

func quality_tiers() -> void:
	MenuCameraRig.instant_override = 1
	Settings.quality = "low"
	var app = fresh_app()
	await settle()
	check(not is_instance_valid(app.world), "the low tier keeps the flat menu (no world)")
	for page in ["play", "settings", "friends"]:
		app.navigate(page)
		await settle(2)
		check(app.page == page, "low tier: %s page opens" % page)
	app.queue_free()
	await settle(2)
	Settings.quality = "high"
	app = fresh_app()
	await settle()
	check(is_instance_valid(app.world), "high quality builds the world")
	app.queue_free()
	await settle(2)
	Settings.quality = "balanced"

func tab_row() -> void:
	MenuCameraRig.instant_override = 1
	for width in [1280, 720]:
		var app = fresh_app(width, 800)
		await settle()
		app.navigate("play")
		await settle(4)
		var tops := {}
		var rights := 0.0
		for key in app._menu_buttons:
			var button: Button = app._menu_buttons[key]
			tops[int(round(button.global_position.y))] = true
			rights = maxf(rights, button.global_position.x + button.size.x)
		check(tops.size() == 1, "%d px: the tab row is one row (%d distinct tops)" % [width, tops.size()])
		check(rights <= float(width) + 1.0, "%d px: the tabs stay inside the window (right edge %.0f)" % [width, rights])
		if width == 720:
			check(app.nav_icon_only, "720 px: tabs fall back to icons")
			for key in app._menu_buttons:
				check((app._menu_buttons[key] as Button).tooltip_text != "", "icon-only tab %s keeps a tooltip label" % key)
		app.queue_free()
		await settle(2)

func skip_on_input() -> void:
	MenuCameraRig.instant_override = 0
	var app = fresh_app()
	await settle()
	app.navigate("play")
	await settle(1)
	var world: MenuWorld = app.world
	check(world.is_flying(), "a real flight is running (first flight to the hall)")
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_SPACE
	app._input(event)
	check(not world.is_flying() and world.current_station() == "hall", "any key skips to the end of the flight")
	app.navigate("training")
	await settle(1)
	check(world.is_flying(), "another flight (first into the yard)")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	app._input(click)
	check(not world.is_flying(), "a click skips too")
	# the page fades out during a flight and back in after it
	app.navigate("campaign")
	await settle(3)
	check(app.page_scroll.modulate.a < 0.99, "the page is faded while the camera flies (%.2f)" % app.page_scroll.modulate.a)
	world.skip()
	for i in 90:
		await process_frame
	check(app.page_scroll.modulate.a > 0.99, "the page fades back in after arrival (%.2f)" % app.page_scroll.modulate.a)
	app.queue_free()
	await settle(2)
	MenuCameraRig.instant_override = 1

func reduce_motion() -> void:
	MenuCameraRig.instant_override = 0
	Prefs.reduce_motion = true
	var app = fresh_app()
	await settle()
	app.navigate("play")
	await settle(1)
	var world: MenuWorld = app.world
	check(world.is_flying() and world.rig.progress() < 0.5, "reduce-motion still flies, as a short crossfade")
	world.rig.advance(0.2)
	check(not world.is_flying() and world.current_station() == "hall", "the 150 ms crossfade is over after 0.2 s")
	check(is_zero_approx(world.rig.roll), "no roll under reduce-motion")
	app.queue_free()
	await settle(2)
	Prefs.reduce_motion = false
	MenuCameraRig.instant_override = -1
