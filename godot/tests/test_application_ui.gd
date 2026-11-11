extends SceneTree
const Scene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
const Api = preload("res://ui/account_api.gd")
const Results = preload("res://ui/results.gd")
const Local = preload("res://app/main.tscn")
var checks = 0
var failures: Array = []
var shell: Control
class HistoryApi:
	extends Node
	signal proceed
	var requests: Array = []
	var replies: Array = []
	var wait_for_reply = false
	func call_api(_method: int, path: String, _body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		requests.append(path)
		if wait_for_reply:
			await proceed
		return replies.pop_front()

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func screenshot(name: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + name + ".png")
	print("Screenshot: ", ProjectSettings.globalize_path("user://" + name + ".png"))

func run() -> void:
	root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.preferred_3d = false
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	shell = Scene.instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	expect(shell.page == "play", "main menu opens on Play")
	expect(root.get_node_or_null("PlatformInput") != null, "application installs persistent controller adapter")
	expect(shell.content.get_child_count() >= 4, "mode cards and game setup rendered")
	await screenshot("application-play")
	for target in ["account", "settings", "profile", "history", "leaderboard", "play"]:
		shell.navigate(target)
		expect(shell.page == target and shell.content.get_child_count() >= 3, "navigation opens " + target)
	shell.selected_mode = "classic"
	shell.selected_time = 2
	expect(shell.match_options() == {"mode": "classic", "ranked": false, "initialMs": 600000, "incrementMs": 0}, "Classic setup selects supported rapid control")
	shell.selected_mode = "battle"
	expect(shell.match_options().initialMs == 0 and shell.match_options().incrementMs == 0, "Battle setup forces C0 untimed clocks")
	shell.online = true
	shell.navigate("play")
	expect(shell.invite_edit == null, "signed-out player gets sign-in gate before online controls")
	Settings.account = {"playerId": "test-profile", "displayName": "Test Knight", "username": "test_knight", "classic": {"rating": 1232, "wins": 2, "losses": 1, "draws": 0, "games": 3}, "battle": {"rating": 1200, "wins": 0, "losses": 0, "draws": 0, "games": 0}}
	Settings.token = "memory-only-test-token"
	shell.navigate("play")
	expect(shell.invite_edit != null and shell.account_badge.text == "Test Knight", "authenticated menu exposes private matches and account")
	shell._accept_status({"ok": true, "data": {"status": {"queue": {"mode": "battle", "ranked": false}, "allocation": null, "invite": null}}}, false)
	expect(shell.queue_label.text.contains("Battle") and shell.queue_label.text.contains("Searching"), "queue state is displayed without changing gameplay")
	shell._accept_status({"ok": true, "data": {"status": {"queue": null, "allocation": null, "invite": {"code": "ABC234", "expiresAt": 999}}}})
	expect(shell.queue_label.text.contains("ABC234"), "private invite status displays server-issued code")
	await screenshot("application-online")
	shell.status = {"queue": null, "allocation": null, "invite": null}
	var history_api = HistoryApi.new()
	shell.api.queue_free()
	shell.api = history_api
	shell.add_child(history_api)
	var summary = {"matchId": "summary-1", "mode": "classic", "ranked": true, "whitePlayerId": "test-profile", "blackPlayerId": "opponent", "whiteName": "Test Knight", "blackName": "Other Knight", "result": "white", "reason": "checkmate", "finalFen": "position", "plies": 73, "completedAt": 1800000000000, "ratingChange": {"white": 16, "black": -16}}
	history_api.replies.append({"ok": true, "data": {"matches": [summary], "nextOffset": 20}})
	shell.navigate("history")
	expect(history_api.requests[-1] == "/v1/history/summary?limit=20&offset=0", "history requests bounded summary page without full move arrays")
	expect(shell._history_more_button != null and shell._history_more_button.text == "Load older matches", "history exposes pagination for older records")
	history_api.wait_for_reply = true
	history_api.replies.append({"ok": false, "message": "Temporary failure"})
	shell._history_more_button.pressed.emit()
	shell._load_history(shell._refresh_generation, 20)
	expect(history_api.requests.size() == 2 and shell._history_more_button.disabled, "duplicate history pagination taps cannot issue concurrent requests")
	history_api.proceed.emit()
	await process_frame
	expect(not shell._history_more_button.disabled, "failed history page can be retried")
	history_api.wait_for_reply = false
	var older = summary.duplicate(true)
	older.matchId = "summary-2"
	history_api.replies.append({"ok": true, "data": {"matches": [older], "nextOffset": null}})
	shell._history_more_button.pressed.emit()
	expect(history_api.requests[-1] == "/v1/history/summary?limit=20&offset=20", "pagination requests server-provided next offset")
	expect(shell._history_more_button == null, "last history page removes older-record button")
	var history_cards = 0
	for child in shell.content.get_children():
		if child is PanelContainer:
			history_cards += 1
	expect(history_cards == 2, "older history summaries append without replacing current records")
	history_api.wait_for_reply = true
	history_api.replies.append({"ok": true, "data": {"matches": [summary], "nextOffset": 20}})
	shell.navigate("history")
	shell.navigate("settings")
	history_api.proceed.emit()
	await process_frame
	expect(shell.page == "settings" and shell._history_more_button == null and not shell._history_loading, "stale history response cannot append records after navigation")
	Settings.sign_out()
	shell.navigate("settings")
	await screenshot("application-settings")
	expect(Api.permitted_url("https://accounts.example.org"), "HTTPS account service accepted")
	for bad in ["http://accounts.example.org", "http://localhost.evil.test", "http://127.0.0.1.evil.test", "https://user:password@evil.test", "file:///tmp/service", "http://192.168.0.1:3100"]:
		expect(not Api.permitted_url(bad), "unsafe account service rejected: " + bad)
	for good in ["http://127.0.0.1:3100", "http://localhost:3100", "http://[::1]:3100"]:
		expect(Api.permitted_url(good), "explicit loopback development accepted")
	expect(Results.title("1-0") == "White wins", "local result identifies winner")
	expect(Results.title("1/2-1/2") == "A well-fought draw", "draw result displayed")
	expect(Results.title("0-1", "black-account", {"w": "white-account", "b": "black-account"}) == "Victory", "online result uses authoritative player IDs")
	expect(Results.title("1-0", "black-account", {"w": "white-account", "b": "black-account"}) == "Defeat", "opponent win maps to defeat")
	Settings.preferred_3d = true
	Settings.animations = false
	Settings.quality = "low"
	expect(Settings.save_preferences() == OK, "presentation preferences saved")
	expect(Engine.max_fps == 30, "low graphics preference only limits presentation frame rate")
	Settings.set_combat_input(true)
	expect(not root.get_node("PlatformInput").cursor_enabled, "gamepad pointer yields to combat")
	Settings.set_combat_input(false)
	expect(root.get_node("PlatformInput").cursor_enabled, "gamepad pointer resumes on board")
	var config = ConfigFile.new()
	expect(config.load("user://preferences.cfg") == OK and config.get_value("presentation", "view3d") == true, "presentation preference persists")
	expect(not config.has_section_key("network", "token") and not config.has_section("account"), "account credentials never saved in preferences")
	Settings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": true}
	var local = Local.instantiate()
	root.add_child(local)
	await process_frame
	expect(local.game is BattleChessMatch and not local.game.timed, "menu launch initializes existing Battle C0 authority")
	expect(local._view_3d and not local.board_2d.visible and local.board_3d.visible, "menu launch preserves selected 3D perspective")
	expect(Settings.launch.is_empty(), "launch intent consumed exactly once")
	expect(not local.board_2d.animation_enabled and not local.board_3d.animation_enabled, "both local views honor animation preference")
	local.game.new_game(0)
	var state = local.game.match_state()
	local.set_view(false)
	expect(local.game.match_state() == state and not Settings.preferred_3d, "view switch preserves state and updates only local preference")
	local.queue_free()
	await process_frame
	Settings.launch = {"mode": "classic", "initialMs": 180000, "incrementMs": 2000, "view3d": false}
	local = Local.instantiate()
	root.add_child(local)
	await process_frame
	expect(not local.game is BattleChessMatch and local.game.initial_ms == 180000 and local.game.increment_ms == 2000, "menu launch initializes existing Classic clocks")
	local.queue_free()
	shell.queue_free()
	await process_frame
	Settings.sign_out()
	Settings.quality = "balanced"
	Settings.animations = true
	Settings.save_preferences()
	print("Application UI: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
