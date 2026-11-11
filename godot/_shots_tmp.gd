extends SceneTree
# usage: godot --path godot --script res://... can't: script lives outside project; copied to godot/tools_tmp? We load via --script absolute path.
const Settings = preload("res://ui/application_settings.gd")
var out := ""
var tag := ""

class FakeApi:
	extends Node
	func call_api(_method: int, path: String, _body: Dictionary = {}, _authenticate: bool = true) -> Dictionary:
		var record := {"matchId": "m1", "mode": "classic", "ranked": true, "whitePlayerId": "p1", "blackPlayerId": "p2", "whiteName": "Sir Galahad", "blackName": "Morgan", "result": "white", "reason": "checkmate", "finalFen": "x", "plies": 73, "completedAt": 1800000000000, "ratingChange": {"white": 16, "black": -16}}
		var lost := record.duplicate(true)
		lost.result = "black"
		lost.mode = "battle"
		lost.ranked = false
		if path.begins_with("/v1/history"):
			return {"ok": true, "data": {"matches": [record, lost, record], "nextOffset": 20}}
		if path.begins_with("/v1/leaderboard"):
			var out := []
			for i in 6:
				out.append({"playerId": "p%d" % (i + 1), "displayName": ["Sir Galahad", "Morgan", "Lancelot du Lac", "Guinevere", "Percival", "Tristan"][i], "classic": {"rating": 1800 - i * 60, "wins": 40 - i * 3, "losses": 8 + i, "draws": 3, "games": 55}, "battle": {"rating": 1700 - i * 50, "wins": 30, "losses": 9, "draws": 1, "games": 40}})
			return {"ok": true, "data": {"players": out}}
		return {"ok": false, "message": "offline"}

func args() -> Dictionary:
	var d := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv = a.substr(2).split("=", true, 1)
			d[kv[0]] = kv[1]
	return d

func snap(name: String) -> void:
	for i in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s_%s_%dx%d.png" % [out, tag, name, img.get_width(), img.get_height()])

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var a := args()
	out = a.get("out", "/tmp")
	tag = a.get("tag", "x")
	var which: String = a.get("which", "app")
	Settings.loaded = true
	root.content_scale_factor = float(a.get("scale", "1.0"))
	Settings.preferred_3d = false
	Settings.account = {"playerId": "p1", "displayName": "Sir Galahad", "username": "galahad", "classic": {"rating": 1432, "wins": 12, "losses": 5, "draws": 2, "games": 19}, "battle": {"rating": 1288, "wins": 4, "losses": 3, "draws": 0, "games": 7}}
	Settings.token = "x"
	if which == "app":
		var app = load("res://ui/application.tscn").instantiate()
		root.add_child(app)
		await snap("01_home")
		if app.has_method("navigate"):
			for p in ["play", "settings", "profile", "account"]:
				app.navigate(p)
				await snap("02_" + p)
			app.selected_mode = "battle"
			app.navigate("play")
			await snap("02_play_battle")
			app.online = true
			app.navigate("play")
			await snap("02_play_online")
	elif which == "game":
		var game = load("res://app/main.tscn").instantiate()
		root.add_child(game)
		await snap("03_game")
		game._switch_mode(1)
		await snap("04_battle_start")
		game._show_new()
		await snap("05_newdialog")
		game.new_dialog.hide()
		game._battle_phase("preview")
		game._capture_preview({"attacker": {"role": "n", "color": "w", "stats": {"maxHp": 80}}, "defender": {"role": "p", "color": "b", "square": "e5", "stats": {"maxHp": 40}}, "from": "c4", "to": "e5"})
		await snap("06_battle_card")
	elif which == "more":
		var app3 = load("res://ui/application.tscn").instantiate()
		root.add_child(app3)
		await process_frame
		app3.api.queue_free()
		var fake = FakeApi.new()
		app3.api = fake
		app3.add_child(fake)
		for p in ["history", "leaderboard"]:
			app3.navigate(p)
			await snap("08_" + p)
		app3.navigate("settings")
		await process_frame
		ControlsScreen.open(app3)
		await snap("09_controls")
		Settings.token = ""
		app3.navigate("profile")
		await snap("10_signedout_profile")
		app3.online = true
		app3.navigate("play")
		await snap("11_online_gate")
	elif which == "game2":
		var g = load("res://app/main.tscn").instantiate()
		root.add_child(g)
		await process_frame
		g.game.new_game(600000, 0, "r1bqkbnr/ppp2ppp/2n5/3pp3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4")
		g.game.start_clock()
		g.game.play("f3", "e5")
		g.game.play("c6", "e5")
		g.game.play("d2", "d4")
		await snap("12_game_moves")
		g.game.new_game(600000, 0, "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1")
		await snap("13_game_check")
		g.set_flipped(true)
		g._request_move("a7", "a8", true)
		await snap("14_promotion")
	elif which == "results":
		var app2 = load("res://ui/application.tscn").instantiate()
		root.add_child(app2)
		await process_frame
		var R = load("res://ui/results.gd")
		R.show_dialog(app2, {"result": "1-0", "reason": "checkmate", "mode": "classic", "plies": 41}, func(): pass, func(): pass)
		await snap("07_results")
	quit()
