extends SceneTree
## Overlap / clipping / target-size audit of every application page, the chess screen and its dialogs, at several window
## sizes and UI scales. Headless and deterministic (motion reduced). Asserts that nothing visible overlaps anything else visible.
##
## Run: godot --headless --path godot --script res://tests/ui/ui_overlap_test.gd [-- options]
##   --report          print every finding (otherwise only the totals and the first few failing labels)
##   --sizes=1280x800,640x360   window sizes to test (default: the full matrix below)
##   --scales=1,1.5             UI scale factors (default 1 and 1.5; 1.5 is the largest the settings page allows)
##   --only=play,match          only scenarios whose id contains one of these words
##   --shots=DIR                also save one PNG per scenario into DIR (needs a rendering driver: run under xvfb-run, not --headless)
const AppScene = preload("res://ui/application.tscn")
const MainScene = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Results = preload("res://ui/results.gd")
const Check = preload("res://tests/ui/overlap_check.gd")
const Double = preload("res://tests/battle/test_combat_adapter.gd")
## 1280x800 is the design size; 640x360 is the project minimum (project.godot); 540x960 a phone in portrait; 800x480 a small
## landscape device; 2400x1080 a tall-and-wide phone.
const DEFAULT_SIZES := [Vector2i(1280, 800), Vector2i(1920, 1080), Vector2i(1024, 600), Vector2i(800, 480), Vector2i(640, 360), Vector2i(540, 960), Vector2i(2400, 1080)]
const BATTLE_FEN := "7k/8/8/4q3/3P4/8/8/7K w - - 0 1"
var checks := 0
var failures: Array = []
var findings: Array = []     # {"scenario": String, "kind": String, "text": String}
var report := false
var only: Array = []
var shots_dir := ""
var tag := ""

class FakeApi:
	extends Node
	var friends_reply: Dictionary = {}
	func call_api(_method: int, path: String, _body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		var record := {"matchId": "m1", "mode": "classic", "ranked": true, "whitePlayerId": "p1", "blackPlayerId": "p2", "whiteName": "Sir Galahad", "blackName": "A Rather Long Opponent Name The Third", "result": "white", "reason": "checkmate", "finalFen": "x", "plies": 73, "completedAt": 1800000000000, "ratingChange": {"white": 16, "black": -16}}
		if path.begins_with("/v1/history"):
			return {"ok": true, "data": {"matches": [record, record], "nextOffset": 20}}
		if path.begins_with("/v1/leaderboard"):
			var stats := {"rating": 1432, "wins": 12, "losses": 5, "draws": 2, "games": 19}
			return {"ok": true, "data": {"players": [{"playerId": "p1", "displayName": "Sir Galahad", "classic": stats, "battle": stats}, {"playerId": "p2", "displayName": "An Extremely Long Display Name That Must Be Trimmed Not Clipped", "classic": stats, "battle": stats}]}}
		if path == "/v1/friends":
			return {"ok": true, "data": friends_reply} if not friends_reply.is_empty() else {"ok": false, "message": "offline"}
		return {"ok": false, "message": "offline"}

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func wanted(id: String) -> bool:
	if only.is_empty():
		return true
	for word in only:
		if id.contains(word):
			return true
	return false

## Default matrix (about two minutes headless): the design size at 100 % and 150 %, a small landscape window, a phone in portrait and a
## very wide phone. `--full` runs every size at 100 % and 150 %; `--sizes=` / `--scales=` pick their own.
const DEFAULT_CONFIGS := [[Vector2i(1280, 800), 1.0], [Vector2i(1280, 800), 1.5], [Vector2i(800, 480), 1.0], [Vector2i(540, 960), 1.0], [Vector2i(540, 960), 1.5], [Vector2i(2400, 1080), 1.0]]
## The battle flow (preview, drop, countdown, fight, result) is slow to drive; run it at these configs only.
const FLOW_CONFIGS := [[Vector2i(1280, 800), 1.0], [Vector2i(1280, 800), 1.5], [Vector2i(540, 960), 1.0]]
var run_flow_everywhere := false

func parse_args() -> Array:
	var configs: Array = DEFAULT_CONFIGS.duplicate()
	var sizes: Array = []
	var scales: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg == "--report":
			report = true
		elif arg == "--full":
			sizes = DEFAULT_SIZES.duplicate()
			scales = [1.0, 1.5]
		elif arg.begins_with("--sizes="):
			sizes = []
			for part in arg.trim_prefix("--sizes=").split(","):
				var xy := part.split("x")
				sizes.append(Vector2i(int(xy[0]), int(xy[1])))
		elif arg.begins_with("--scales="):
			scales = []
			for part in arg.trim_prefix("--scales=").split(","):
				scales.append(float(part))
		elif arg.begins_with("--only="):
			only = Array(arg.trim_prefix("--only=").split(","))
		elif arg.begins_with("--shots="):
			shots_dir = arg.trim_prefix("--shots=")
	if not sizes.is_empty() or not scales.is_empty():
		if sizes.is_empty():
			sizes = [Vector2i(1280, 800)]
		if scales.is_empty():
			scales = [1.0, 1.5]
		configs = []
		for size in sizes:
			for scale in scales:
				configs.append([size, scale])
		run_flow_everywhere = true
	return configs

## Records every problem the probes find on `host` for the scenario `id`, and one expectation per scenario.
func audit(id: String, host: Node, include_floating: bool = false) -> void:
	var label := "%s %s" % [tag, id]
	var found: Array = []
	for pair in Check.overlaps(host, include_floating):
		found.append(["overlap", "%s  ×  %s  (%dx%d at %d,%d)" % [Check.describe(pair.a), Check.describe(pair.b), int(pair.rect.size.x), int(pair.rect.size.y), int(pair.rect.position.x), int(pair.rect.position.y)]])
	for item in Check.problems(host):
		found.append([item.kind, "%s  %s" % [Check.describe(item.control), item.detail]])
	for control in Check.small_targets(host, 40.0):
		found.append(["small-target", Check.describe(control)])
	for entry in found:
		findings.append({"scenario": label, "kind": entry[0], "text": entry[1]})
		if report:
			printerr("  ", entry[0], " ", label, ": ", entry[1])
	expect(found.is_empty(), "%s has no overlap, overflow, clipped text or tiny target (%d found%s)" % [label, found.size(), ": " + str(found[0][1]) if not found.is_empty() else ""])

## Audits an application screen. While the capture card is up, a scrim dims the board and HUD underneath: those are then not "visible
## content", so only the overlay (the card, its scrim and header / footer buttons) is audited, and the card must fit the window.
func audit_screen(id: String, app: Control) -> void:
	if app.get("battle_scrim") != null and app.battle_scrim.visible:
		expect(app.battle_card.visible, "%s %s the scrim only appears with the capture card" % [tag, id])
		expect(root.get_visible_rect().grow(1.5).encloses(app.battle_card.get_global_rect()), "%s %s the capture card fits the window (%s in %s)" % [tag, id, str(app.battle_card.get_global_rect()), str(root.get_visible_rect().size)])
		audit(id + " (card)", app.battle_overlay)
	else:
		audit(id, app)

func shot(id: String) -> void:
	if shots_dir == "":
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var name := "%s__%s.png" % [id, tag.replace("@", "_").replace("%", "")]
	root.get_texture().get_image().save_png(shots_dir.path_join(name))

func run() -> void:
	var configs := parse_args()
	Settings.loaded = true
	Settings.intro_seen = true
	Settings.preferred_3d = false
	Settings.account = {"playerId": "p1", "displayName": "Sir Galahad of the Very Long Name", "username": "galahad", "classic": {"rating": 1432, "wins": 12, "losses": 5, "draws": 2, "games": 19}, "battle": {"rating": 1288, "wins": 4, "losses": 3, "draws": 0, "games": 7}}
	Settings.token = "overlap-test-token"
	Prefs.path = "user://ui_overlap_test.cfg"
	Prefs.loaded = true
	Prefs.reset_defaults()
	Prefs.reduce_motion = true
	Kit.toast_seconds = 0.2   # pages raise toasts of their own (service unreachable...); only the toast scenario keeps them
	await probe_checks()
	for config in configs:
		var size: Vector2i = config[0]
		var scale: float = config[1]
		root.size = size
		root.content_scale_factor = scale
		await settle(2)
		tag = "%dx%d@%d%%" % [size.x, size.y, roundi(scale * 100.0)]
		await shell_scenarios()
		await match_scenarios()
		if run_flow_everywhere or [size, scale] in FLOW_CONFIGS:
			await battle_flow_scenarios()
	root.content_scale_factor = 1.0
	var file := "user://ui_overlap_test.cfg"
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	Settings.sign_out()
	var by_kind := {}
	for finding in findings:
		by_kind[finding.kind] = int(by_kind.get(finding.kind, 0)) + 1
	print("UI overlap: %d checks, %d failures; findings by kind %s" % [checks, failures.size(), str(by_kind)])
	quit(0 if failures.is_empty() else 1)

# ------------------------------------------------------------------------------------------------ the probes themselves
## The audit must be able to see what it is looking for (and must not cry wolf): known good and bad layouts.
func probe_checks() -> void:
	root.size = Vector2i(1280, 800)
	root.content_scale_factor = 1.0
	await settle(2)
	var rig := Control.new()
	rig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(rig)
	var button := Button.new()
	button.text = "Under the label"
	button.position = Vector2(100, 100)
	rig.add_child(button)
	var label := Label.new()
	label.text = "Sitting on the button"
	label.position = Vector2(110, 110)
	rig.add_child(label)
	# a wide label whose short text is at its left end, next to a button standing in the empty part of its row: no overlap
	var title := Label.new()
	title.text = "Title"
	title.position = Vector2(100, 300)
	title.size = Vector2(900, 30)
	rig.add_child(title)
	var neighbour := Button.new()
	neighbour.text = "Beside the title"
	neighbour.position = Vector2(600, 300)
	rig.add_child(neighbour)
	# something scrolled out of view does not count, and a control hanging off the window is reported
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(100, 500)
	scroll.size = Vector2(300, 60)
	rig.add_child(scroll)
	var long_column := VBoxContainer.new()
	scroll.add_child(long_column)
	for i in 8:
		var row := Button.new()
		row.text = "Row %d" % i
		long_column.add_child(row)
	var hidden_under := Label.new()   # below the scroll viewport: must not be seen as covering anything
	hidden_under.text = "Not covered"
	hidden_under.position = Vector2(100, 700)
	rig.add_child(hidden_under)
	var stray := Button.new()
	stray.text = "Stray"
	stray.position = Vector2(-300, 20)
	rig.add_child(stray)
	await settle(3)
	var pairs := Check.overlaps(rig)
	expect(pairs.size() == 1 and ((pairs[0].a == button and pairs[0].b == label) or (pairs[0].a == label and pairs[0].b == button)), "probe: exactly the label sitting on the button is reported (%d pairs)" % pairs.size())
	expect(Check.problems(rig).any(func(p): return p.kind == "overflow-x" and p.control == stray), "probe: a control hanging off the window is reported")
	expect(Check.shown_rect(long_column.get_child(7)).size == Vector2.ZERO, "probe: a row scrolled out of its viewport has no visible rect")
	var tiny := Button.new()
	tiny.custom_minimum_size = Vector2(20, 20)
	tiny.position = Vector2(700, 600)
	rig.add_child(tiny)
	await settle(2)
	expect(Check.small_targets(rig, 40.0).has(tiny), "probe: a 20 px button is reported as a tiny target")
	rig.queue_free()
	await settle(2)
	# The combat HUD draws its bars itself (no controls to probe): its two panels must leave the middle free for the round timer.
	for width in [378.0, 420.0, 560.0, 800.0, 840.0, 1200.0, 1920.0]:
		var w: float = CombatHud.panel_width(width)
		var gap: float = (width - w - 24.0) - (24.0 + w)   # from the left panel's right edge to the right panel's left edge
		expect(gap >= 90.0 - 0.01 and w <= 360.0 and w >= 120.0, "combat HUD: at %d px the two bar panels (%.0f px each) leave %.0f px for the timer" % [int(width), w, gap])

# ------------------------------------------------------------------------------------------------ application pages
func friends_snapshot() -> Dictionary:
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var ada := {"playerId": "f-1", "username": "ada", "displayName": "Ada Lovelace-Wollstonecraft the Third", "online": true, "inMatch": false, "classicRating": 1250, "battleRating": 1180}
	var bob := {"playerId": "f-2", "username": "bob", "displayName": "Bob", "online": false, "inMatch": false, "classicRating": 1200, "battleRating": 1200}
	var cy := {"playerId": "f-3", "username": "cy_cy_cy_cy_cy_cy", "displayName": "Cy", "online": true, "inMatch": true, "classicRating": 1300, "battleRating": 1100}
	var challenge := {"code": "ABC234", "player": {"playerId": "f-1", "username": "ada", "displayName": "Ada Lovelace-Wollstonecraft the Third"}, "mode": "classic", "initialMs": 600000, "incrementMs": 0, "side": "black", "expiresAt": now_ms + 540000}
	return {"friends": [bob, ada, cy], "incoming": [{"playerId": "r-1", "username": "dee", "displayName": "Dee"}], "outgoing": [{"playerId": "o-1", "username": "eli", "displayName": "Eli"}], "challenges": {"incoming": [challenge], "outgoing": null}}

func shell_states() -> Array:
	var signed_in := func() -> void:
		Settings.token = "overlap-test-token"
	var signed_out := func() -> void:
		Settings.token = ""
	return [
		["home", "home", func(s): signed_in.call()],
		["play-classic-local", "play", func(s): signed_in.call(); s.selected_mode = "classic"; s.online = false; s.opponent = OpponentUI.default_state()],
		["play-classic-computer", "play", func(s): signed_in.call(); s.selected_mode = "classic"; s.online = false; s.opponent = {"kind": "computer", "level": 4, "color": "random"}],
		["play-battle-local", "play", func(s): signed_in.call(); s.selected_mode = "battle"; s.online = false; s.opponent = OpponentUI.default_state()],
		["play-battle-computer", "play", func(s): signed_in.call(); s.selected_mode = "battle"; s.online = false; s.opponent = {"kind": "computer", "level": 6, "color": "b"}],
		["play-battle-royal", "play", func(s): signed_in.call(); s.selected_mode = "battle"; s.online = false; s.opponent = OpponentUI.default_state(); s.ruleset = {"royal": true}],
		["play-online-signed-out", "play", func(s): signed_out.call(); s.selected_mode = "classic"; s.online = true],
		["play-online-classic", "play", func(s): signed_in.call(); s.selected_mode = "classic"; s.online = true; s.ranked = true],
		["play-online-battle", "play", func(s): signed_in.call(); s.selected_mode = "battle"; s.online = true; s.ranked = false; s.status = {"queue": {"mode": "battle"}, "allocation": null, "invite": {"code": "ABC234"}}],
		["friends", "friends", func(s): signed_in.call()],
		["friends-signed-out", "friends", func(s): signed_out.call()],
		["profile", "profile", func(s): signed_in.call()],
		["profile-signed-out", "profile", func(s): signed_out.call()],
		["history", "history", func(s): signed_in.call()],
		["leaderboard", "leaderboard", func(s): signed_in.call()],
		["settings", "settings", func(s): signed_in.call()],
		["account-signed-out", "account", func(s): signed_out.call()],
		["account-signed-in", "account", func(s): signed_in.call()],
	]

func new_shell() -> Control:
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(2)
	shell.api.queue_free()
	var api := FakeApi.new()
	api.friends_reply = friends_snapshot()
	shell.api = api
	shell.add_child(api)
	return shell

func shell_scenarios() -> void:
	var shell: Control = await new_shell()
	for state in shell_states():
		var id: String = state[0]
		if not wanted(id):
			continue
		shell.status = {"queue": null, "allocation": null, "invite": null}
		shell.ranked = false
		shell.ruleset = {"royal": false}
		state[2].call(shell)
		shell._reset_friends()
		shell.navigate(state[1])
		await settle(4)
		audit(id, shell)
		await shot(id)
	# the opening screen (title + "press any button" over the 3D castle)
	if wanted("intro"):
		shell.queue_free()
		await settle(2)
		Settings.reset_intro()
		shell = await new_shell()
		await settle(6)
		audit("home-intro", shell)
		await shot("home-intro")
	# dialogs and banners drawn over a page
	shell.navigate("play")
	await settle(3)
	if wanted("dialog"):
		var dialog := Results.show_dialog(shell, {"result": "1-0", "reason": "checkmate", "mode": "battle", "plies": 73, "note": "The King's last stand ended: the checkmate stands because the defending King could not survive another duel."}, func(): pass, func(): pass)
		await settle(4)
		audit("dialog-results", shell)
		var view := root.get_visible_rect().size
		expect(Vector2(dialog.size).x <= view.x + 1.0 and Vector2(dialog.size).y <= view.y + 1.0, "%s result dialog fits the window (%s in %s)" % [tag, str(dialog.size), str(view)])
		await shot("dialog-results")
		dialog.hide()
		dialog.queue_free()
		await settle(2)
	if wanted("controls"):
		var screen := ControlsScreen.open(shell)
		screen.autosave = false
		await settle(4)
		audit("controls-screen", screen)
		await shot("controls-screen")
		screen.queue_free()
		await settle(2)
	if wanted("toast"):
		Kit.toast_seconds = 30.0
		for text in ["Account service unreachable: check the address in Settings → Account service.", "Invite code copied.", "Welcome back, Sir Galahad of the Very Long Name."]:
			Kit.toast(shell, text, "danger")
		await settle(4)
		check_toasts(shell)
		await shot("toasts-over-play")
		Kit.toast_seconds = 0.2
	shell.queue_free()
	await settle(3)

## Toasts float over the page for a few seconds on purpose, so they are not audited against the page. What must hold: they stay inside the
## window, never overlap each other, and never swallow a click or tap (every part of a toast ignores the mouse).
func check_toasts(host: Node) -> void:
	var stack := host.get_node_or_null("ToastLayer/Anchor/Stack")
	expect(stack != null and stack.get_child_count() > 0, "%s toasts are shown" % tag)
	if stack == null:
		return
	var view := root.get_visible_rect()
	var panels: Array = stack.get_children()
	for i in panels.size():
		var panel := panels[i] as Control
		var rect := panel.get_global_rect()
		expect(view.grow(1.5).encloses(rect), "%s toast %d stays inside the window (%s in %s)" % [tag, i, str(rect), str(view.size)])
		for j in range(i + 1, panels.size()):
			expect(not rect.intersects((panels[j] as Control).get_global_rect().grow(-1.0)), "%s toasts %d and %d do not overlap" % [tag, i, j])
		var through := panel.mouse_filter == Control.MOUSE_FILTER_IGNORE
		for child in panel.find_children("*", "Control", true, false):
			through = through and (child as Control).mouse_filter == Control.MOUSE_FILTER_IGNORE
		expect(through, "%s toast %d lets clicks through to what lies under it" % [tag, i])

# ------------------------------------------------------------------------------------------------ chess screen
func match_scenarios() -> void:
	var specs := [
		["match-classic-2d", {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false}],
		["match-classic-3d", {"mode": "classic", "initialMs": 180000, "incrementMs": 2000, "view3d": true}],
		["match-classic-untimed", {"mode": "classic", "initialMs": 0, "incrementMs": 0, "view3d": false}],
		["match-classic-computer", {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false, "opponent": {"kind": "computer", "level": 6, "color": "w"}}],
		["match-battle-2d", {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false}],
		["match-battle-3d", {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": true}],
		["match-battle-royal", {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false, "royal": true}],
	]
	for spec in specs:
		var id: String = spec[0]
		if not wanted(id):
			continue
		Settings.launch = (spec[1] as Dictionary).duplicate(true)
		var app: Control = MainScene.instantiate()
		root.add_child(app)
		await settle(4)
		audit(id, app)
		await shot(id)
		# a long game: a full move list, captured pieces, a check and a status line
		var line := ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5", "a7a6", "b5c6", "d7c6", "e1g1", "f7f6", "d2d4", "e5d4", "f3d4", "c8d7", "b1c3", "d8e7", "c1e3", "e8c8", "d1e2", "g8h6", "a1d1", "h6g4", "e3d2", "g4e3", "d2e3", "e7e5"]
		var played := 0
		for move in line:
			var reply: Dictionary = app.game.play(move.substr(0, 2), move.substr(2, 2)) if app.game.has_method("play") else {"ok": false}
			if not reply.get("ok", false):
				break
			played += 1
			if app.game is BattleChessMatch and app.battle_overlay != null and app.battle_overlay.visible:
				break
		await settle(4)
		if wanted(id + "-long"):
			audit_screen(id + "-long (%d plies)" % played, app)
			await shot(id + "-long")
		if wanted("dialog") and not (app.game is BattleChessMatch):
			for dialog_name in ["new_dialog", "promotion_dialog", "draw_dialog", "fen_dialog"]:
				var dialog: Window = app.get(dialog_name)
				if dialog == null:
					continue
				if dialog_name == "promotion_dialog":
					app._promotion = {"from": "e7", "to": "e8"}
				dialog.popup_centered()
				await settle(3)
				audit(id + "-" + dialog_name, app)
				var view := root.get_visible_rect().size
				expect(Vector2(dialog.size).x <= view.x + 1.0 and Vector2(dialog.size).y <= view.y + 1.0, "%s %s-%s fits the window (%s in %s)" % [tag, id, dialog_name, str(dialog.size), str(view)])
				if dialog_name == "new_dialog" or dialog_name == "promotion_dialog":
					await shot(id + "-" + dialog_name.replace("_", "-"))
				dialog.hide()
				await settle(2)
		app.queue_free()
		await settle(3)
	# the capture preview card (Battle Chess): the position puts a Pawn next to a Queen
	if wanted("preview"):
		for use_3d in [false, true]:
			Settings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": use_3d}
			var app: Control = MainScene.instantiate()
			root.add_child(app)
			await settle(4)
			app.set_world_mode(false)
			app.battle_adapter.scene_path = "res://tests/battle/not_installed.tscn"
			app.game.new_game(0, 0, BATTLE_FEN)
			var fake = Double.new()
			app._configure_battle_flow(fake)
			app.battle_flow.set_process(false)
			app.game.play("d4", "e5")
			await settle(4)
			var id := "battle-preview-" + ("3d" if use_3d else "2d")
			audit(id, app.battle_overlay)   # the legacy overlay is opaque: what lies under it is not visible
			await shot(id)
			app.battle_flow.cancel_preview()
			app.queue_free()
			await settle(3)

# ------------------------------------------------------------------------------------------------ a battle, start to finish
## Drives the real capture flow of the pit world (BattleFlow -> PitSequence -> CombatArena, as tools/climb_audit.gd does) and
## audits the screen at each stage: the preview card, the trapdoor drop, the countdown, the fight (combat HUD) and the result.
func battle_flow_scenarios() -> void:
	if not wanted("flow"):
		return
	Engine.physics_ticks_per_second = 600   # the arena ticks one logical 60 Hz tick per physics frame
	Settings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false}
	var app: Control = MainScene.instantiate()
	root.add_child(app)
	await settle(3)
	app._switch_mode(1)
	app.game.new_game(0, 0, "4k3/8/8/4p3/8/5N2/8/4K3 w - - 0 1")
	app.board_3d.animation_enabled = false
	var world = app.board_3d.world
	world.auto_advance = false
	await settle(2)
	app.game.play("f3", "e5")
	await settle(3)
	# the card is modal: a dim scrim lies over the board and HUD, so only the card and its overlay are audited, and the card must fit
	expect(app.battle_card.visible and app.battle_scrim.visible, "%s the capture card comes with a scrim over the HUD" % tag)
	expect(root.get_visible_rect().grow(1.5).encloses(app.battle_card.get_global_rect()), "%s the capture card fits the window (%s in %s)" % [tag, str(app.battle_card.get_global_rect()), str(root.get_visible_rect().size)])
	audit("flow-1-preview", app.battle_overlay)
	await shot("flow-1-preview")
	app._start_battle_pressed()
	var pit = world.pit
	var done := {}
	var forced := false
	var fight_frames := 0
	var frames := 0
	while frames < 6000 and not done.has("result"):
		frames += 1
		world.advance(1.0 / 60.0)
		await process_frame
		if pit.phase == pit.Phase.DROP and not done.has("drop") and frames > 60:
			done["drop"] = true
			await settle(2)
			audit("flow-2-drop", app)
			await shot("flow-2-drop")
		if pit.phase == pit.Phase.COMBAT and world.chamber.arena_mount.get_child_count() > 0:
			var arena = world.chamber.arena_mount.get_child(0)
			if not done.has("countdown"):
				done["countdown"] = true   # the first frame of the combat phase: the 3-2-1 countdown
				await settle(2)
				audit("flow-3-countdown", app)
				await shot("flow-3-countdown")
			if arena.sim.phase == CombatSimulation.Phase.ACTIVE:
				fight_frames += 1
				if fight_frames == 60 and not done.has("fight"):
					done["fight"] = true
					await settle(2)
					audit("flow-4-fight", app)
					await shot("flow-4-fight")
				if fight_frames > 120 and not forced:
					forced = true
					arena.sim.defender().health.apply_damage(100000)   # the attacker wins
		if pit.phase == pit.Phase.RESOLVE and not done.has("result"):
			done["result"] = true   # the fight is over: the winner is announced, the camera is about to follow the climb
			await create_timer(0.8).timeout   # the controls cheat sheet fades out to make room for the result text
			audit("flow-5-result", app)
			await shot("flow-5-result")
	expect(done.has("countdown") and done.has("fight") and done.has("result"), "%s the battle flow reached the countdown, the fight and the result (%s)" % [tag, str(done.keys())])
	Engine.physics_ticks_per_second = 60
	app.queue_free()
	await settle(3)
