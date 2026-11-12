extends Node
## Packaged-binary smoke test, run by tools/package/smoke_linux.sh against an EXPORTED Linux binary built from the
## same staging project as the distributed one (this script is the only extra file packed into that variant):
##   Peepeechess-smoke.x86_64 --headless      (its main scene is res://smoke/package_smoke.tscn; release templates do not
##                                              run --script, so the smoke variant swaps the project's main scene)
## It checks that runtime-read data files and imported audio survive packing, that the application shell loads and
## navigates, and that local Classic and Battle matches start and accept a move. Exit code 0 only if every check passes.
const Shell = preload("res://ui/application.tscn")
const Local = preload("res://app/main.tscn")
const Settings = preload("res://ui/application_settings.gd")
const CombatAudio = preload("res://combat/audio/combat_audio.gd")
var checks := 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	print(("ok   " if value else "FAIL ") + label)
	if not value:
		failures.append(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var root := get_tree().root
	root.size = Vector2i(1280, 800)
	for path in ["res://chess/battle_stats.json", "res://combat/data/balance_v1.json", "res://assets/combat/audio/manifest.json",
			"res://assets/combat/arena/stone_arena_lights.json", "res://assets/combat/manifest/asset_manifest.json",
			"res://assets/world/manifest/world_manifest.json", "res://contracts/v2/schema.json"]:
		var text := FileAccess.get_file_as_string(path)
		expect(not text.is_empty() and typeof(JSON.parse_string(text)) == TYPE_DICTIONARY, "packed JSON readable: " + path)
	var library := CombatAudio.load_library(true)
	expect(library.size() >= 10, "combat audio library loads packed WAV streams (%d sounds)" % library.size())
	Settings.loaded = true
	Settings.preferred_3d = false
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	var shell = Shell.instantiate()
	root.add_child(shell)
	for i in 3:
		await get_tree().process_frame
	expect(shell.page == "home", "application opens on the title screen")  # ui-polish: the Play page is one button away
	for target in ["account", "settings", "profile", "history", "leaderboard", "play"]:
		shell.navigate(target)
		expect(shell.page == target and shell.content.get_child_count() >= 3, "menu navigation opens " + target)
	shell.queue_free()
	await get_tree().process_frame
	# Local Classic match from the menu launch intent.
	Settings.launch = {"mode": "classic", "initialMs": 0, "incrementMs": 0, "view3d": false}
	var local = Local.instantiate()
	root.add_child(local)
	for i in 3:
		await get_tree().process_frame
	expect(local.game != null and not (local.game is BattleChessMatch), "local Classic match is created")
	var reply: Dictionary = local.game.play("e2", "e4")
	expect(reply.get("ok", false), "Classic: e2-e4 accepted by the rules authority")
	reply = local.game.play("e7", "e5")
	expect(reply.get("ok", false), "Classic: e7-e5 accepted")
	reply = local.game.play("e2", "e4")
	expect(not reply.get("ok", false), "Classic: illegal repeat of e2-e4 rejected")
	expect(local.game.match_state().get("mode") == "classic", "Classic: match state reports mode classic")
	local.queue_free()
	await get_tree().process_frame
	# Local Battle Chess match (loads battle_stats.json and the combat adapter).
	Settings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false}
	local = Local.instantiate()
	root.add_child(local)
	for i in 3:
		await get_tree().process_frame
	expect(local.game is BattleChessMatch, "local Battle Chess match is created")
	expect(local.game.match_state().get("mode") == "battle", "Battle: match state reports mode battle")
	local.queue_free()
	await get_tree().process_frame
	print("Package smoke: %d checks, %d failures" % [checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
