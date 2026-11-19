extends SceneTree
## PRODUCT CHECK: runs against the PACKED game (what a player gets), not the source tree. Every feature built so far must be reachable and its
## data present in the pack. Usage (scripts/test-product-pack.mjs does all of it):
##   godot --headless --path godot --export-pack "Windows Desktop" /tmp/game.pck
##   godot --headless --main-pack /tmp/game.pck --script res://tools/product_check.gd
## Prints one line per feature; flags that are OFF on purpose are listed as "off by design" (not failures).
const Balance = preload("res://combat/data/balance_data.gd")
const CombatAudio = preload("res://combat/audio/combat_audio.gd")
const Settings = preload("res://ui/application_settings.gd")
var checks := 0
var failures: Array = []
var off_by_design: Array = []

func expect(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("MISSING: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	_balance_and_rules()
	_audio()
	_online()
	_board_and_scenery()
	await _application_screens()
	await _board_screen()
	print("")
	for line in off_by_design:
		print("  off by design: ", line)
	print("PRODUCT CHECK: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _balance_and_rules() -> void:
	var rules := Balance.duel_rules()
	expect(rules.has("defender") and rules.has("failed_attack") and rules.has("resolve"), "fairness pass: duel rules (defender edge, failed-attack cost, Resolve) are in the packed balance data")
	expect(Balance.meta().has("persistence") and Balance.meta().has("healing") and Balance.meta().has("support"), "fairness pass: board layer data (persistent damage, healing, support, comeback)")
	expect(ResourceLoader.exists("res://chess/battle_meta_match.gd") and ResourceLoader.exists("res://chess/battle_meta.gd"), "fairness pass: BattleMetaMatch is packed")
	expect(not Balance.stamp().is_empty() and Balance.stamp().begins_with("balance-v1:"), "tuning stamp for the online version check: " + Balance.stamp())
	var anti := Balance.anti_mash()
	expect(not anti.is_empty(), "anti-mash rules and numbers are packed")
	if not bool(anti.get("enabled", false)):
		off_by_design.append("duel anti-mash rules (anti_mash.enabled=false until calibrated; TODO 'Do next' 2)")

func _audio() -> void:
	expect(FileAccess.file_exists(CombatAudio.REAL_MANIFEST_PATH), "real sound effects: manifest is packed")
	var library: Dictionary = CombatAudio.load_library(true)
	var needed := ["swing_sword", "hit_steel_light", "block", "parry", "dodge", "victory", "defeat", "ui_click", "ui_hover", "ui_confirm", "ui_deny", "chess_move", "chess_capture", "chess_castle", "chess_check", "chess_checkmate", "chess_promote", "chess_win", "chess_lose", "capture_shatter", "amb_wind", "amb_torch", "amb_mystic"]
	var missing: Array = []
	for sound in needed:
		if not library.has(sound) or (library[sound] as Array).is_empty():
			missing.append(sound)
	expect(missing.is_empty(), "real sound effects load from the pack (missing: %s)" % str(missing))
	expect(library.has("swing_sword") and (library["swing_sword"][0] as AudioStream).get_class() == "AudioStreamOggVorbis", "sound effects are the real recordings (Ogg), not the synthesized WAVs")
	expect(ResourceLoader.exists("res://audio/board_sounds.gd") and ResourceLoader.exists("res://audio/music_director.gd") and ResourceLoader.exists("res://audio/audio_buses.gd"), "chess sounds, music director and audio buses are packed")

func _online() -> void:
	var server = load("res://network/server/dedicated_server.gd")
	expect(server != null and int(server.ROOM_CODE_LENGTH) == 6, "online: 6-character room codes")
	var client = load("res://network/client/network_client.gd")
	expect(client != null and String(client.build_info().get("tuning", "")) == Balance.stamp(), "online: the client sends its tuning stamp for the version check")
	var cert := X509Certificate.new()
	expect(cert.load("res://network/trusted_server.crt") == OK, "online: the server certificate is packed and valid (players need no file)")
	expect(String(ProjectSettings.get_setting("peepeechess/network/default_server", "")) != "", "online: the default server address is set (" + String(ProjectSettings.get_setting("peepeechess/network/default_server", "")) + ")")
	expect(ResourceLoader.exists("res://network/client/online_lobby.tscn") and ResourceLoader.exists("res://network/relay/relay_bridge.gd") and ResourceLoader.exists("res://network/host/hosted_game.gd"), "online: lobby, relay bridge and host-on-PC code are packed")
	if not Settings.accounts_enabled:
		off_by_design.append("accounts / sign-in (peepeechess/accounts/enabled=false until the account service is deployed; docs/deployment/ACCOUNTS.md)")

func _board_and_scenery() -> void:
	var look = load("res://world/board_look.gd")
	expect(look != null and bool(look.SCENERY_ENABLED), "new board scenery (dais, braziers, flagstone ring) is switched ON")
	expect(ResourceLoader.exists("res://boards/board_scenery.gd") and ResourceLoader.exists("res://boards/board_fx.gd"), "board scenery and effects code are packed")
	expect(ResourceLoader.exists("res://ui/opening/menu_plaques.gd") and ResourceLoader.exists("res://ui/campaign_page.gd"), "3D menu plaques and the campaign page are packed")

func _application_screens() -> void:
	Settings.loaded = true
	Settings.token = ""
	Settings.launch.clear()
	var shell = load("res://ui/application.tscn").instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.online = true
	shell.navigate("play")
	await process_frame
	expect(shell.find_child("RoomCodeButton", true, false) != null, "Play page: the 'Create or join a room code' button is there")
	var texts: Array = []
	for button in shell.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():
			texts.append(String(button.text))
	if not Settings.accounts_enabled:
		expect(not texts.any(func(t): return "Sign in" in t), "Play page: no sign-in wall while accounts are off")
	shell.queue_free()
	await process_frame
	var lobby = load("res://network/client/online_lobby.tscn").instantiate()
	BoardSounds.force = true
	root.add_child(lobby)
	await process_frame
	var labels: Array = []
	for button in lobby.find_children("*", "Button", true, false):
		labels.append(String(button.text))
	expect(labels.any(func(t): return "Create Battle room" in t) and labels.any(func(t): return "Join room" in t), "lobby: Create Battle room / Join room buttons")
	expect(lobby.get_node_or_null("BoardSounds") != null, "lobby: chess sounds are attached to the online board")
	lobby.queue_free()
	await process_frame

func _board_screen() -> void:
	BoardSounds.force = true
	var main = load("res://app/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	expect(main.get_node_or_null("BoardSounds") != null, "local board: chess sounds are attached")
	main._switch_mode(1, false)   # Battle Chess
	await process_frame
	expect(main.game is BattleMetaMatch, "local Battle Chess runs the fairness-pass match (persistent damage, Resolve, support)")
	main.queue_free()
	await process_frame
