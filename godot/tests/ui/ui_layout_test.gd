extends SceneTree
## Layout, focus and transition checks for every application page and the chess screen at six resolutions
## (plus UI-scale 150 %). Headless and deterministic: motion is reduced where positions are compared.
const AppScene = preload("res://ui/application.tscn")
const MainScene = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Safe = preload("res://ui/theme/safe_margin.gd")
const PAGES := ["home", "play", "online", "profile", "history", "leaderboard", "settings", "account"]
const SIZES := [Vector2i(1280, 720), Vector2i(1600, 720), Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(2560, 1080), Vector2i(800, 600)]
var checks := 0
var failures: Array = []
var quiet := false

class FakeApi:
	extends Node
	func call_api(_method: int, path: String, _body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		var record := {"matchId": "m1", "mode": "classic", "ranked": true, "whitePlayerId": "p1", "blackPlayerId": "p2", "whiteName": "Sir Galahad", "blackName": "A Rather Long Opponent Name The Third", "result": "white", "reason": "checkmate", "finalFen": "x", "plies": 73, "completedAt": 1800000000000, "ratingChange": {"white": 16, "black": -16}}
		if path.begins_with("/v1/history"):
			return {"ok": true, "data": {"matches": [record, record], "nextOffset": 20}}
		if path.begins_with("/v1/leaderboard"):
			var stats := {"rating": 1432, "wins": 12, "losses": 5, "draws": 2, "games": 19}
			return {"ok": true, "data": {"players": [{"playerId": "p1", "displayName": "Sir Galahad", "classic": stats, "battle": stats}, {"playerId": "p2", "displayName": "An Extremely Long Display Name That Must Be Trimmed Not Clipped", "classic": stats, "battle": stats}]}}
		return {"ok": false, "message": "offline"}

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func inside_scroll(node: Control, host: Node) -> bool:
	var parent := node.get_parent()
	while parent != null and parent != host:
		if parent is ScrollContainer:
			return true
		parent = parent.get_parent()
	return false

func audit(label: String, host: Control, safe: Rect2 = Rect2()) -> int:
	var view := root.get_visible_rect().size
	var area := safe if safe.size.x > 0.0 else Rect2(Vector2.ZERO, view)
	var problems := 0
	for node in host.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.get_window() != root:
			continue
		if control.name in ["ToastLayer", "Anchor", "Stack"]:
			continue
		var rect := control.get_global_rect()
		var scrolled := inside_scroll(control, host)
		var interactive := control is BaseButton or control is LineEdit or control is Slider or control is SpinBox
		var texty := (control is Label and (control as Label).text != "") or (control is Button and (control as Button).text != "")
		if rect.position.x < area.position.x - 1.5 or rect.end.x > area.end.x + 1.5:
			problems += 1
			if not quiet: printerr("  overflow-x ", label, " ", control.get_path(), " ", rect, " area ", area)
		if not scrolled and (rect.position.y < area.position.y - 1.5 or rect.end.y > area.end.y + 1.5) and not (control is ScrollContainer):
			problems += 1
			if not quiet: printerr("  overflow-y ", label, " ", control.get_path(), " ", rect, " area ", area)
		if (interactive or texty) and (control.size.x <= 0.0 or control.size.y <= 0.0):
			problems += 1
			if not quiet: printerr("  zero-size ", label, " ", control.get_path())
		if texty:
			var minimum := control.get_combined_minimum_size()
			var is_trimmed := control is Label and (control as Label).text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING
			if not is_trimmed and (control.size.x + 0.5 < minimum.x or control.size.y + 0.5 < minimum.y):
				problems += 1
				if not quiet: printerr("  clipped-text ", label, " ", control.get_path(), " size ", control.size, " min ", minimum)
	return problems

func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func interactive_controls(host: Node) -> Array:
	var found: Array = []
	for node in host.find_children("*", "Control", true, false):
		var c := node as Control
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and c.get_window() == root:
			if c is BaseButton and (c as BaseButton).disabled:
				continue
			if c is LineEdit and not (c as LineEdit).editable:
				continue
			found.append(c)
	return found

func open_page(shell: Control, page: String) -> void:
	if page == "online":
		shell.online = true
		shell.navigate("play")
	else:
		shell.online = false
		shell.navigate(page)
	await settle(3)

func run() -> void:
	Settings.loaded = true
	Settings.preferred_3d = false
	Settings.account = {"playerId": "p1", "displayName": "Sir Galahad of the Very Long Name", "username": "galahad", "classic": {"rating": 1432, "wins": 12, "losses": 5, "draws": 2, "games": 19}, "battle": {"rating": 1288, "wins": 4, "losses": 3, "draws": 0, "games": 7}}
	Settings.token = "layout-test-token"
	Prefs.path = "user://ui_layout_test.cfg"
	Prefs.loaded = true
	Prefs.reset_defaults()
	Prefs.reduce_motion = true
	Kit.toast_seconds = 0.2
	var total_problems := 0
	var configs: Array = []
	for size in SIZES:
		configs.append([size, 1.0])
	configs.append([Vector2i(1280, 800), 1.5])
	configs.append([Vector2i(800, 600), 1.5])
	for config in configs:
		var size: Vector2i = config[0]
		root.size = size
		root.content_scale_factor = config[1]
		await settle(2)
		var tag := "%dx%d@%d%%" % [size.x, size.y, roundi(config[1] * 100.0)]
		var shell: Control = AppScene.instantiate()
		root.add_child(shell)
		await settle(2)
		shell.api.queue_free()
		shell.api = FakeApi.new()
		shell.add_child(shell.api)
		for page in PAGES:
			await open_page(shell, page)
			await settle(2)
			var count := audit(tag + " " + page, shell)
			total_problems += count
			expect(count == 0, "page %s has no overflow / zero-size / clipped text at %s" % [page, tag])
			var controls := interactive_controls(shell)
			expect(controls.size() >= 2, "page %s exposes interactive controls at %s" % [page, tag])
		shell.queue_free()
		await settle(2)
		# chess screen
		Settings.launch = {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false}
		var game: Control = MainScene.instantiate()
		root.add_child(game)
		await settle(4)
		var count2 := audit(tag + " game", game)
		expect(count2 == 0, "chess screen has no overflow / zero-size / clipped text at " + tag)
		game.queue_free()
		await settle(3)
	root.content_scale_factor = 1.0
	root.size = Vector2i(1280, 800)
	await settle(2)
	await safe_area_checks()
	await focus_checks()
	await transition_checks()
	var file := "user://ui_layout_test.cfg"
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	Settings.sign_out()
	print("UI layout: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func safe_area_checks() -> void:
	# the audit itself must detect problems: a button hanging off the left edge and a zero-size button
	var probe := Control.new()
	root.add_child(probe)
	var stray := Button.new()
	stray.text = "stray"
	probe.add_child(stray)
	stray.position = Vector2(-500, 10)
	var empty := Button.new()
	empty.text = "empty"
	empty.custom_minimum_size = Vector2.ZERO
	probe.add_child(empty)
	await settle(2)
	quiet = true
	expect(audit("probe", probe) >= 1, "layout audit detects an overflowing control")
	quiet = false
	probe.queue_free()
	# pure maths: a 2400x1080 phone with a 90 px cut-out on the left and a 66 px gesture bar below
	var inset := Safe.insets_from(Rect2i(90, 0, 2310, 1014), Vector2i(2400, 1080), Vector2i(2400, 1080), Vector2(1778, 800))
	expect(is_equal_approx(inset.left, 90.0 * 1778.0 / 2400.0) and inset.right == 0.0 and is_equal_approx(inset.bottom, 66.0 * 800.0 / 1080.0), "safe-area insets convert physical to logical px")
	expect(Safe.insets_from(Rect2i(), Vector2i(2400, 1080), Vector2i(2400, 1080), Vector2(1778, 800)).left == 0.0, "an empty safe rect yields no insets")
	root.size = Vector2i(2400, 1080)
	await settle(2)
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(3)
	var frame: MarginContainer = null
	for node in shell.find_children("*", "MarginContainer", true, false):
		if node.has_method("apply_margins"):
			frame = node
			break
	expect(frame != null, "application uses a safe-area frame")
	if frame != null:
		frame.inset_override = {"left": 60.0, "top": 30.0, "right": 40.0, "bottom": 24.0}
		frame.apply_margins()
		await settle(3)
		var view := root.get_visible_rect().size
		var safe := Rect2(Vector2(60, 30), view - Vector2(100, 54))
		var problems := audit("notch", shell.find_child("Home", true, false) if shell.find_child("Home", true, false) != null else shell, safe)
		expect(problems == 0, "home page respects a simulated notch / gesture-bar inset")
	shell.queue_free()
	await settle(2)

func focus_checks() -> void:
	root.size = Vector2i(1280, 800)
	await settle(2)
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(2)
	shell.api.queue_free()
	shell.api = FakeApi.new()
	shell.add_child(shell.api)
	var pad: PadUi = shell.get_node_or_null("PadUi")
	expect(pad != null, "pad / keyboard navigation helper is installed")
	for page in PAGES:
		await open_page(shell, page)
		await settle(2)
		var controls := interactive_controls(shell)
		if controls.is_empty():
			expect(false, "page %s has focusable controls" % page)
			continue
		var visited := {}
		var current: Control = controls[0]
		current.grab_focus()
		var lost := false
		for step in controls.size() + 4:
			visited[current] = true
			var next := current.find_next_valid_focus()
			if next == null or not (next in controls):
				lost = true
				break
			current = next
			current.grab_focus()
		var reached := 0
		for c in controls:
			if visited.has(c):
				reached += 1
		expect(not lost, "keyboard focus never leaves the page's controls on " + page)
		expect(reached == controls.size(), "Tab order reaches all %d interactive controls on %s (reached %d)" % [controls.size(), page, reached])
		# the focus ring must be visible: every focusable Button style has a focus box with a border of 3 px
		var sample := controls[0] as Control
		if sample is Button:
			var focus_box := sample.get_theme_stylebox("focus") as StyleBoxFlat
			expect(focus_box != null and focus_box.border_width_left >= 3 and focus_box.border_color.a > 0.9, "focus ring stylebox is a visible 3 px border on " + page)
		# pad nav mode: after a rebuild the guard puts focus back on something usable
		if pad != null:
			pad.nav_mode = true
			var before: Control = root.gui_get_focus_owner()
			if before != null:
				before.release_focus()
			await settle(3)
			var owner: Control = root.gui_get_focus_owner()
			expect(owner != null and owner.is_visible_in_tree(), "focus is never lost in controller mode on " + page)
			pad.nav_mode = false
	shell.queue_free()
	await settle(2)

func transition_checks() -> void:
	Prefs.reduce_motion = false
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(2)
	shell.api.queue_free()
	shell.api = FakeApi.new()
	shell.add_child(shell.api)
	# rapid interrupted navigation
	for page in ["settings", "play", "profile", "history", "home", "leaderboard", "settings"]:
		shell.navigate(page)
		await process_frame
	expect(shell.page == "settings", "last navigation wins after interrupted transitions")
	await create_timer(0.4).timeout
	expect(is_equal_approx(shell.content.modulate.a, 1.0) and shell.content.scale == Vector2.ONE, "page container ends fully visible after interrupted transitions")
	expect(shell.content.find_child("SettingsColumns", true, false) != null and shell.content.find_child("Home", true, false) == null, "only the last page is in the tree after interrupted transitions")
	# freeing a node mid-animation is safe and settle() restores the resting state
	var node := Control.new()
	root.add_child(node)
	Motion.fade_in(node, 0.5)
	expect(node.modulate.a < 1.0, "fade_in starts transparent when motion is on")
	Motion.settle(node)
	expect(is_equal_approx(node.modulate.a, 1.0) and node.scale == Vector2.ONE, "settle restores alpha and scale")
	Motion.fade_in(node, 0.5)
	node.queue_free()
	await settle(2)
	# reduce motion: instant
	Prefs.reduce_motion = true
	var instant := Control.new()
	root.add_child(instant)
	Motion.fade_in(instant, 0.5)
	expect(is_equal_approx(instant.modulate.a, 1.0), "reduce motion skips the fade")
	instant.queue_free()
	# toasts: capped, expire
	Prefs.reduce_motion = false
	for i in 6:
		Kit.toast(shell, "Toast %d" % i, "info")
	await settle(2)
	var stack := shell.get_node("ToastLayer/Anchor/Stack")
	expect(stack.get_child_count() <= Kit.MAX_TOASTS, "no more than %d toasts at once" % Kit.MAX_TOASTS)
	await create_timer(0.9).timeout
	expect(stack.get_child_count() == 0, "toasts remove themselves")
	shell.queue_free()
	await settle(3)
