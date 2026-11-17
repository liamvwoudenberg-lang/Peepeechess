class_name CampaignRun
extends RefCounted
## One run of the campaign: a state machine over the 12 encounters. Pure data (no scene, no files): CampaignProgress saves `to_dict()`.
##
##   status "map"      the next encounter is `index`; start it
##   status "boon"     the last encounter was won: `offer` holds three boons, pick one with pick_boon()
##   status "lost"     the run ended (a lost boss, or no lives left)
##   status "cleared"  all encounters won
## A lost ordinary encounter costs one life and may be retried; a lost boss ends the run at once.

const ChessRules = preload("res://config/chess_rules.gd")
static var START_LIVES: int = ChessRules.campaign_start_lives()   # config/chess_rules.json: campaign.start_lives

var seed_value: int = 1
var index: int = 0
var lives: int = START_LIVES
var boons: Array = []
var status: String = "map"
var offer: Array = []
var cleared: Array = []     # ids of encounters won in this run
var lost_at: String = ""


static func start(p_seed: int) -> CampaignRun:
	var run := CampaignRun.new()
	run.seed_value = p_seed
	return run


func current_node() -> Dictionary:
	return CampaignNodes.node(index)


func is_over() -> bool:
	return status == "lost" or status == "cleared"


## Reports the result of the current encounter. Returns {event, ...}: "boon" (offer ready), "cleared", "retry" (lives left), "run_over" (run ended).
func report(won: bool) -> Dictionary:
	if status != "map":
		return {"event": "ignored"}
	var data := current_node()
	if won:
		var id := str(data["id"])
		if not cleared.has(id):
			cleared.append(id)
		if index + 1 >= CampaignNodes.count():
			status = "cleared"
			return {"event": "cleared", "node": id}
		offer = CampaignBoons.offer(seed_value, index, boons)
		status = "boon" if not offer.is_empty() else "map"
		if status == "map":
			index += 1
		return {"event": "boon" if status == "boon" else "advance", "node": id, "offer": offer.duplicate()}
	if CampaignNodes.is_boss(index):
		status = "lost"
		lost_at = str(data["id"])
		return {"event": "run_over", "reason": "boss", "node": lost_at}
	lives -= 1
	if lives <= 0:
		lives = 0
		status = "lost"
		lost_at = str(data["id"])
		return {"event": "run_over", "reason": "lives", "node": lost_at}
	return {"event": "retry", "lives": lives}


## Takes one of the offered boons and moves to the next encounter. False for a boon that was not offered.
func pick_boon(id: String) -> bool:
	if status != "boon" or not offer.has(id):
		return false
	boons.append(id)
	offer = []
	index += 1
	status = "map"
	return true


func nodes_cleared() -> int:
	return cleared.size()


func to_dict() -> Dictionary:
	return {"seed": seed_value, "index": index, "lives": lives, "boons": boons.duplicate(), "status": status, "offer": offer.duplicate(), "cleared": cleared.duplicate(), "lost_at": lost_at}


## Rebuilds a run from saved data, clamping everything; null when it is not a usable run.
static func from_dict(data) -> CampaignRun:
	if not (data is Dictionary):
		return null
	var run := CampaignRun.new()
	run.seed_value = int(data.get("seed", 1))
	run.index = clampi(int(data.get("index", 0)), 0, CampaignNodes.count() - 1)
	run.lives = clampi(int(data.get("lives", START_LIVES)), 0, START_LIVES)
	var status_value := str(data.get("status", "map"))
	run.status = status_value if status_value in ["map", "boon", "lost", "cleared"] else "map"
	for id in data.get("boons", []):
		if CampaignBoons.BOONS.has(str(id)) and CampaignBoons.stack_of(run.boons, str(id)) < CampaignBoons.MAX_STACK:
			run.boons.append(str(id))
	for id in data.get("offer", []):
		if CampaignBoons.BOONS.has(str(id)) and not run.offer.has(str(id)):
			run.offer.append(str(id))
	if run.status == "boon" and run.offer.is_empty():
		run.status = "map"
	for id in data.get("cleared", []):
		if CampaignNodes.index_of(str(id)) >= 0 and not run.cleared.has(str(id)):
			run.cleared.append(str(id))
	run.lost_at = str(data.get("lost_at", ""))
	return run
