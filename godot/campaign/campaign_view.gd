class_name CampaignView
extends TrainingView
## One campaign encounter on screen: the training fight view (real arena, real opponent AI at the node's level) with the run's boons applied to the player
## fighter and a campaign result flow instead of the lesson cards: a win offers three boons (pick one), a loss costs a life (retry) or ends the run
## (lost boss / no lives). Results go to CampaignProgress, never to the Training progress file.

signal run_changed

var campaign: CampaignProgress
var boon_summary: Dictionary = {}


func setup_campaign(p_campaign: CampaignProgress, p_store: ProgressStore) -> void:
	campaign = p_campaign
	var run := campaign.run
	var node_index := run.index if run != null else 0
	var lesson_data := CampaignNodes.lesson_for(node_index)
	seed_value = (run.seed_value if run != null else 1) * 31 + node_index * 7 + 1
	setup(lesson_data, String(lesson_data.get("difficulty", "normal")), p_store, "")


func _start_fight() -> void:
	await super._start_fight()
	if is_instance_valid(arena) and arena.get("sim") != null and campaign != null and campaign.run != null:
		boon_summary = CampaignBoons.apply(arena.sim, campaign.run.boons, PLAYER_ID)


# ---- results (override the lesson cards) -------------------------------------------------------------------------------
func _on_completed(_stats: Dictionary) -> void:
	_finish(true)


func _on_failed(_reason: String, _stats: Dictionary) -> void:
	_finish(false)


func _on_battle_finished(_result: Dictionary) -> void:
	if _ended:
		return
	if tracker != null:
		tracker.update()
	if _ended:
		return
	_finish(false)


func _finish(won: bool) -> void:
	if _ended:
		return
	_ended = true
	_freeze()
	if campaign == null or campaign.run == null:
		_show_campaign_card("Campaign", "There is no run in progress.", [["Back to the map", func(): exit_requested.emit(), true]])
		return
	var report := campaign.report_result(won)
	run_changed.emit()
	match String(report.get("event", "")):
		"boon":
			_show_boon_card(report)
		"advance":
			_show_campaign_card("Encounter won", "%s Every boon is already at its limit. On to the next encounter." % _rewards_text(report), [["Back to the map", func(): exit_requested.emit(), true]])
		"cleared":
			_show_campaign_card("Campaign cleared", "You won the Pit Sovereign's duel and took the castle. %s" % _rewards_text(report), [["Back to the map", func(): exit_requested.emit(), true]])
		"retry":
			_show_campaign_card("Not this time", "You lose a life. %d %s left. Try the encounter again, or return to the map." % [int(report["lives"]), "life" if int(report["lives"]) == 1 else "lives"],
					[["Try again", func(): _retry(), true], ["Back to the map", func(): exit_requested.emit(), false]])
		"run_over":
			var why := "The boss beat you." if String(report.get("reason", "")) == "boss" else "You are out of lives."
			_show_campaign_card("Run over", "%s You cleared %d of %d encounters. Unlocks are kept; start a new run from the map." % [why, campaign.run.nodes_cleared(), CampaignNodes.count()],
					[["Back to the map", func(): exit_requested.emit(), true]])
		_:
			_show_campaign_card("Campaign", "This result was ignored.", [["Back to the map", func(): exit_requested.emit(), true]])


func _retry() -> void:
	_ended = false
	_restart()


func _rewards_text(report: Dictionary) -> String:
	var rewards: Array = report.get("rewards", [])
	if rewards.is_empty():
		return ""
	var names: Array = []
	for r in rewards:
		var parts := String(r).split(":")
		names.append("%s: %s" % [String(parts[0]).capitalize(), String(parts[1]).capitalize().replace("_", " ")])
	return "Unlocked: %s." % ", ".join(names)


func _show_boon_card(report: Dictionary) -> void:
	var offer: Array = report.get("offer", [])
	var buttons: Array = []
	for id in offer:
		var boon_id: String = id
		buttons.append(["%s: %s" % [CampaignBoons.title(boon_id), CampaignBoons.text(boon_id)], func(): _take_boon(boon_id), buttons.is_empty()])
	_show_campaign_card("Encounter won", "%s Choose a boon for the rest of the run." % _rewards_text(report), buttons)


func _take_boon(id: String) -> void:
	campaign.run.pick_boon(id)
	campaign.save()
	run_changed.emit()
	exit_requested.emit()


## A result card: [[label, callable, primary], ...] (the first button gets the controller focus).
func _show_campaign_card(title_text: String, body: String, buttons: Array) -> void:
	_clear_card()
	_release_mouse()
	var made := _centered_plaque()
	_card = made[0].get_child(0)
	_card.set_meta("holder", made[0])
	var column: VBoxContainer = made[1]
	_label(column, title_text, 30, GOOD if title_text in ["Encounter won", "Campaign cleared"] else TEXT)
	_label(column, body, 18, WHITE)
	var first: Button = null
	for entry in buttons:
		var button := _button(column, String(entry[0]), entry[1], bool(entry[2]))
		if first == null:
			first = button
	if first != null:
		_install_pad(first)
