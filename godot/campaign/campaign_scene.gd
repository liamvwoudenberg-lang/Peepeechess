extends Node
## Full-screen scene of one campaign encounter. Launched by ui/campaign_page.gd with Settings.launch = {"campaign": {"start": true}}; the encounter is the run's
## current node (the run lives in CampaignProgress). Leaving returns to the application's Campaign page.

const Settings = preload("res://ui/application_settings.gd")
const APPLICATION := "res://ui/application.tscn"

var view: CampaignView


func _ready() -> void:
	var launch := Settings.take_launch()
	var campaign := CampaignProgress.shared()
	if not launch.has("campaign") or campaign.run == null or campaign.run.status != "map":
		_leave()
		return
	view = CampaignView.new()
	view.setup_campaign(campaign, DuelAi.store())
	view.exit_requested.connect(_leave)
	add_child(view)


func _leave() -> void:
	Settings.launch = {"menu": "campaign"}
	get_tree().change_scene_to_file(APPLICATION)
