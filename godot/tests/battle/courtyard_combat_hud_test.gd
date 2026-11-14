extends SceneTree
const Hud = preload("res://app/courtyard_combat_hud.gd")
var checks := 0
var failures: Array[String] = []

func _init() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: ", message)

func run() -> void:
	var sim := CombatSimulation.new()
	root.add_child(sim)
	var request := FighterRoster.build_request("p", "q", "w", "hud-1", 7, 0)
	expect(sim.start(request).ok, "real simulation request starts")
	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(sim, "WASD permanent instructions must not appear")
	hud.set_process(false)
	hud.set_names({request.attacker.playerId: "P1", request.defender.playerId: "CPU"})
	expect(hud is CombatHud, "drop-in existing arena HUD interface")
	expect(hud._icon_textures.size() == 4, "exactly four action icons")
	expect(hud._message_box == null and hud._help_label == null, "no chess hints or centre event stack")
	hud._process(0.0)
	expect(hud._center_label.visible, "countdown is temporary")
	sim.phase = CombatSimulation.Phase.ACTIVE
	var before := sim.snapshot().duplicate(true)
	hud._process(0.1)
	expect(not hud._center_label.visible and hud._center_label.text == "", "active fight has no centre-screen text")
	hud.set_context("LAST STAND · DUEL 2/3")
	expect(hud.context_text() == "LAST STAND · DUEL 2/3", "royal context contract remains supported")
	hud.set_context("")
	expect(not hud._context_label.visible, "empty royal context is hidden")
	var event := {"eventId": 1, "type": "hit", "damage": 12, "targetPlayerId": request.defender.playerId}
	hud.on_event(event)
	hud.on_event(event)
	expect(hud._damage.size() == 1, "snapshot event replay creates one damage number")
	hud._update_damage(0.2)
	expect(not hud._damage[0].label.visible, "no camera means no centre fallback")
	for id in range(2, 20):
		event.eventId = id
		hud.on_event(event)
	expect(hud._damage.size() == Hud.MAX_DAMAGE_LABELS, "bounded floating label pool")
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(0, 4, -8)
	camera.look_at(Vector3.ZERO)
	hud.view_camera = camera
	hud._update_damage(0.1)
	expect(hud._damage[0].label.visible, "damage follows a real camera projection")
	var position: Vector2 = hud._damage[0].label.position
	camera.position.x += 2.0
	camera.look_at(Vector3.ZERO)
	hud._update_damage(0.0)
	expect(not hud._damage[0].label.position.is_equal_approx(position), "floating labels follow camera movement")
	hud._update_damage(Hud.DAMAGE_SECONDS)
	expect(hud._damage.is_empty(), "all damage numbers expire in under one second")
	hud.show_result("White wins\nno permanent result panel")
	hud._process(1.5)
	expect(not hud._result_label.visible, "result headline expires automatically")
	for extent in [Vector2i(360, 800), Vector2i(800, 360), Vector2i(1280, 800), Vector2i(1920, 1080)]:
		root.size = extent
		await process_frame
		hud._layout()
		var logical_width := root.get_visible_rect().size.x
		expect(hud._timer_label.position.x >= 0 and hud._timer_label.get_rect().end.x <= logical_width, "timer remains in scaled viewport %s" % extent)
	expect(sim.snapshot() == before, "HUD events, layout, timers and results never mutate the simulation")
	hud.queue_free()
	camera.queue_free()
	sim.stop()
	sim.queue_free()
	await process_frame
	print("COURTYARD COMBAT HUD: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
