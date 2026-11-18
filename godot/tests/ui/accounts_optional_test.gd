extends SceneTree
## Accounts are OFF by default (the account service is not deployed): the game must be fully usable without signing in.
## No Sign in button, no account-only tabs, no "Sign in to play online" wall on the Play page, and room-code online play reachable.
const Scene = preload("res://ui/application.tscn")
const Settings = preload("res://ui/application_settings.gd")
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 800)
	Settings.loaded = true
	Settings.token = ""
	Settings.account.clear()
	Settings.launch.clear()
	Settings.accounts_enabled = false   # the shipped default; forced here because the UI suites run with PEEPEECHESS_ACCOUNTS=1 to keep the account screens covered
	expect(not bool(ProjectSettings.get_setting("peepeechess/accounts/enabled", false)), "the project ships with accounts off")
	var shell = Scene.instantiate()
	root.add_child(shell)
	await process_frame
	await process_frame
	shell.navigate("play")
	shell.online = true
	shell.navigate("play")
	await process_frame
	expect(not shell.account_badge.visible, "no Sign in button when accounts are off")
	for target in ["friends", "profile", "history", "leaderboard"]:
		expect(not shell._menu_buttons.has(target), "the %s tab is hidden when accounts are off" % target)
		shell.navigate(target)
		await process_frame
		expect(shell.page == "play", "opening the %s page falls back to Play" % target)
	var texts: Array = []
	for button in shell.find_children("*", "Button", true, false):
		if button.is_visible_in_tree():   # the hidden account badge keeps its text but is not shown
			texts.append(String(button.text))
	expect(not texts.any(func(t): return "Sign in" in t), "no button on the online Play page asks to sign in")
	expect(shell.find_child("RoomCodeButton", true, false) != null, "the room-code button is on the Play page")
	print("ACCOUNTS OPTIONAL: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
