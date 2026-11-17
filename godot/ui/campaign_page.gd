class_name CampaignPage
extends RefCounted
## The Campaign page of the application: the run's path of 12 encounters (done / current / locked, level, modifiers, rewards), the boons taken, lives, and the
## unlocked arenas and skins to equip. All logic is in godot/campaign/. Runs entirely offline; no account needed.

const Kit = preload("res://ui/theme/ui_kit.gd")
const Settings = preload("res://ui/application_settings.gd")
const SCENE := "res://campaign/campaign_scene.tscn"
const LEVEL_NAMES := {"easy": "Easy", "normal": "Normal", "hard": "Hard", "expert": "Expert"}


static func build(app: Control) -> void:
	var campaign := CampaignProgress.shared()
	Kit.heading(app.content, "Take the castle.", "Twelve duels from the gate to the pit. Pick a boon after every win; a lost boss ends the run, but your unlocks stay.")
	_run_card(app, campaign)
	if campaign.run != null:
		_path_card(app, campaign)
	_unlocks_card(app, campaign)


static func _run_card(app: Control, campaign: CampaignProgress) -> void:
	var card := Kit.card(app.content)
	var run := campaign.run
	var best := "Best run: %d of %d encounters  ·  runs started %d  ·  campaigns cleared %d" % [campaign.best_cleared, CampaignNodes.count(), campaign.runs_started, campaign.runs_cleared]
	if run == null:
		Kit.label(card, "No run in progress.", "H3")
		Kit.label(card, best, "Muted")
		var row := Kit.flow(card)
		var start := Kit.button(row, "Start a new run", func(): _new_run(app), "PrimaryButton", "crown")
		start.name = "NewRun"
		return
	var node := run.current_node()
	match run.status:
		"map":
			Kit.label(card, "Next: %s (%d of %d)" % [String(node.get("title", "")), run.index + 1, CampaignNodes.count()], "H3")
		"boon":
			Kit.label(card, "Choose a boon to continue.", "H3")
		"lost":
			Kit.label(card, "Run over: you cleared %d of %d encounters." % [run.nodes_cleared(), CampaignNodes.count()], "H3")
		"cleared":
			Kit.label(card, "Campaign cleared!", "H3")
	Kit.label(card, "Lives: %d of %d  ·  %s" % [run.lives, CampaignRun.START_LIVES, _boons_text(run)], "Muted")
	Kit.label(card, best, "Muted")
	var row := Kit.flow(card)
	if run.status == "map":
		var go := Kit.button(row, "Fight: %s" % String(node.get("title", "")), func(): launch_node(app), "PrimaryButton", "sword")
		go.name = "FightNode"
	elif run.status == "boon":
		for id in run.offer:
			var boon: String = id
			var pick := Kit.button(row, "%s: %s" % [CampaignBoons.title(boon), CampaignBoons.text(boon)], func(): _pick(app, boon), "PrimaryButton" if boon == run.offer[0] else "")
			pick.name = "Boon_" + boon
	if run.is_over():
		var again := Kit.button(row, "Start a new run", func(): _new_run(app), "PrimaryButton", "crown")
		again.name = "NewRun"
	else:
		var abandon := Kit.button(row, "Abandon run", func(): campaign.abandon_run(); app.navigate("campaign"))
		abandon.name = "AbandonRun"


static func _boons_text(run: CampaignRun) -> String:
	if run.boons.is_empty():
		return "no boons yet"
	var names: Array = []
	for id in run.boons:
		names.append(CampaignBoons.title(String(id)))
	return "boons: " + ", ".join(names)


static func _path_card(app: Control, campaign: CampaignProgress) -> void:
	var run := campaign.run
	var card := Kit.card(app.content)
	Kit.label(card, "THE PATH", "Accent")
	for i in CampaignNodes.count():
		var data := CampaignNodes.node(i)
		var done := run.cleared.has(String(data["id"]))
		var current := i == run.index and run.status == "map"
		var row := Kit.flow(card)
		var info := VBoxContainer.new()
		info.custom_minimum_size.x = 420
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var state := "Done" if done else ("Next" if current else ("Locked" if i > run.index else "Missed"))
		var kind := "  ·  BOSS" if CampaignNodes.is_boss(i) else ""
		Kit.label(info, "%d. %s%s  ·  %s" % [i + 1, String(data["title"]), kind, state], "H3" if current else "Body")
		Kit.label(info, "%s  ·  %s%s" % [String(data["summary"]), LEVEL_NAMES.get(CampaignNodes.level(i), ""), _modifier_text(data)], "Muted")
		var reward := _reward_text(data)
		if reward != "":
			Kit.label(info, "Reward: " + reward, "Muted")


static func _modifier_text(data: Dictionary) -> String:
	var out := ""
	if data.has("hp_fraction"):
		out += "  ·  %d%% health" % roundi(float(data["hp_fraction"]) * 100.0)
	if data.has("seconds"):
		out += "  ·  %d s limit" % int(data["seconds"])
	if String(data.get("kind", "")) == "position":
		out += "  ·  from a chess position"
	return out


static func _reward_text(data: Dictionary) -> String:
	var reward: Dictionary = data.get("reward", {})
	var parts: Array = []
	for key in ["skin", "arena", "lesson"]:
		if reward.has(key):
			parts.append("%s %s" % [key, String(reward[key]).replace("_", " ")])
	return ", ".join(parts)


static func _unlocks_card(app: Control, campaign: CampaignProgress) -> void:
	var card := Kit.card(app.content)
	Kit.label(card, "UNLOCKS", "Accent")
	Kit.label(card, "Arena palettes colour the pit's moonlight. Skins are saved for the paladin models.", "Muted")
	var arenas := Kit.flow(card)
	var default_arena := Kit.button(arenas, "Arena: stone" + (" ✓" if campaign.equipped_arena == "" else ""), func(): campaign.equip_arena(""); app.navigate("campaign"), "PrimaryButton" if campaign.equipped_arena == "" else "")
	default_arena.name = "Arena_default"
	for id in CampaignProgress.ARENAS:
		var arena: String = id
		var unlocked := campaign.unlocked_arenas.has(arena)
		var button := Kit.button(arenas, ("Arena: %s" % arena.capitalize()) + (" ✓" if campaign.equipped_arena == arena else ("" if unlocked else " (locked)")),
				func(): campaign.equip_arena(arena); app.navigate("campaign"), "PrimaryButton" if campaign.equipped_arena == arena else "")
		button.name = "Arena_" + arena
		button.disabled = not unlocked
	var skins := Kit.flow(card)
	for id in CampaignProgress.SKINS:
		var skin: String = id
		var unlocked := campaign.unlocked_skins.has(skin)
		var button := Kit.button(skins, ("Skin: %s" % skin.capitalize()) + (" ✓" if campaign.equipped_skin == skin else ("" if unlocked else " (locked)")),
				func(): campaign.equip_skin("" if campaign.equipped_skin == skin else skin); app.navigate("campaign"), "PrimaryButton" if campaign.equipped_skin == skin else "")
		button.name = "Skin_" + skin
		button.disabled = not unlocked
	if not campaign.unlocked_lessons.is_empty():
		Kit.label(card, "Bonus Training lessons open: %d (they no longer wait for the earlier lessons)." % campaign.unlocked_lessons.size(), "Muted")


static func _new_run(app: Control) -> void:
	CampaignProgress.shared().start_run(int(Time.get_unix_time_from_system()) % 1000000)
	app.navigate("campaign")


static func _pick(app: Control, boon: String) -> void:
	var campaign := CampaignProgress.shared()
	if campaign.run != null and campaign.run.pick_boon(boon):
		campaign.save()
	app.navigate("campaign")


static func launch_node(app: Control) -> void:
	Settings.launch = {"campaign": {"start": true}}
	app.get_tree().change_scene_to_file(SCENE)
