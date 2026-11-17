class_name CampaignNodes
extends RefCounted
## The 12 encounters of the campaign, in order. Every encounter is a real combat-engine duel (the same CombatSimulation as Battle Chess) wrapped as an
## ordinary lesson dictionary (see lesson_for) so TrainingSession / ObjectiveTracker run it. Kinds:
##   duel      fixed roles and attacker
##   position  a chess position (`fen`) and the capture to be played (`capture`, "e4d5"): the pieces on those squares are the duellists; the side that captures
##             is the attacker, exactly as in Battle Chess. The player fights for the side `player_side` (w|b).
##   boss      a duel with extra rewards; a lost boss ends the run
## Modifiers: `hp_fraction` (the player starts with that fraction of health) and `seconds` (a shorter time limit). Rewards are unlocks (cosmetic skins,
## arena palettes, bonus Training lessons) granted the first time the node is cleared.

const ChessRules = preload("res://config/chess_rules.gd")
static var LEVEL_BY_INDEX: Array = ChessRules.campaign_level_by_encounter()   # config/chess_rules.json: campaign.level_by_encounter

const NODES := [
	{"id": "n01_gate", "title": "The Gate", "kind": "duel", "summary": "Two pawns meet at the castle gate.", "player_role": "p", "opponent_role": "p", "attacker": "player"},
	{"id": "n02_squire", "title": "The Squire's Test", "kind": "position", "summary": "A pawn captures a knight: win the duel to keep the square.",
			"fen": "4k3/8/8/3n4/4P3/8/8/4K3 w - - 0 1", "capture": "e4d5", "player_side": "w", "reward": {"arena": "moonlit"}},
	{"id": "n03_watch", "title": "Night Watch", "kind": "duel", "summary": "A knight attacks your pawn: hold the line.", "player_role": "p", "opponent_role": "n", "attacker": "opponent"},
	{"id": "n04_lane", "title": "The Bishop's Lane", "kind": "position", "summary": "Your bishop takes a rook along the diagonal.",
			"fen": "4k3/8/8/8/3r4/8/1B6/4K3 w - - 0 1", "capture": "b2d4", "player_side": "w", "reward": {"skin": "gilded"}},
	{"id": "n05_bridge", "title": "The Rook Bridge", "kind": "duel", "summary": "Cross the bridge wounded: you start at 80% health.", "player_role": "r", "opponent_role": "b", "attacker": "player", "hp_fraction": 0.8},
	{"id": "n06_captain", "title": "Captain of the Guard", "kind": "boss", "summary": "The Captain's knight guards the inner ward.", "player_role": "b", "opponent_role": "n", "attacker": "opponent",
			"reward": {"lesson": "a01_knight_vs_pawn", "arena": "crypt"}},
	{"id": "n07_gambit", "title": "The Queen's Gambit", "kind": "position", "summary": "Your queen takes a pawn: finish it inside 45 seconds.",
			"fen": "4k3/8/8/8/3p4/8/8/3QK3 w - - 0 1", "capture": "d1d4", "player_side": "w", "seconds": 45.0},
	{"id": "n08_keep", "title": "The Keep", "kind": "duel", "summary": "A bishop storms your queen's court.", "player_role": "q", "opponent_role": "b", "attacker": "opponent", "reward": {"lesson": "a02_rook_vs_knight"}},
	{"id": "n09_warden", "title": "Warden of the Pit", "kind": "boss", "summary": "The Warden's queen waits above the pit.", "player_role": "r", "opponent_role": "q", "attacker": "opponent",
			"reward": {"skin": "obsidian", "lesson": "a03_bishop_vs_rook"}},
	{"id": "n10_stand", "title": "The King's Stand", "kind": "duel", "summary": "Your king stands alone against a queen, at 90% health.", "player_role": "k", "opponent_role": "q", "attacker": "opponent", "hp_fraction": 0.9},
	{"id": "n11_crossing", "title": "The Knight's Crossing", "kind": "duel", "summary": "A knight attacks a rook: win on the lunge.", "player_role": "n", "opponent_role": "r", "attacker": "player", "reward": {"arena": "ember"}},
	{"id": "n12_sovereign", "title": "The Pit Sovereign", "kind": "boss", "summary": "Queen against queen for the whole castle, at 85% health.", "player_role": "q", "opponent_role": "q", "attacker": "opponent",
			"hp_fraction": 0.85, "reward": {"skin": "ember", "lesson": "a04_queen_vs_king"}},
]


static func count() -> int:
	return NODES.size()


static func node(index: int) -> Dictionary:
	return NODES[index] if index >= 0 and index < NODES.size() else {}


static func index_of(id: String) -> int:
	for i in NODES.size():
		if String(NODES[i]["id"]) == id:
			return i
	return -1


static func is_boss(index: int) -> bool:
	return String(node(index).get("kind", "")) == "boss"


static func level(index: int) -> String:
	return LEVEL_BY_INDEX[clampi(index, 0, LEVEL_BY_INDEX.size() - 1)]


## The duellists of a node: {player_role, opponent_role, attacker} ("player" | "opponent"), from the fixed roles or from the FEN + capture.
## Returns {} when the position is not a legal capture.
static func matchup(data: Dictionary) -> Dictionary:
	if String(data.get("kind", "")) != "position":
		return {"player_role": String(data["player_role"]), "opponent_role": String(data["opponent_role"]), "attacker": String(data.get("attacker", "player"))}
	var chess := ClassicChess.new()
	if not bool(chess.load_fen(String(data["fen"])).get("ok", false)):
		return {}
	var capture := String(data["capture"])
	if capture.length() != 4:
		return {}
	var from_piece := String(chess.board[ClassicChess.index(capture.substr(0, 2))])
	var to_piece := String(chess.board[ClassicChess.index(capture.substr(2, 2))])
	if from_piece == "" or to_piece == "" or ClassicChess.side(from_piece) == ClassicChess.side(to_piece):
		return {}
	var player_side := String(data.get("player_side", "w"))
	var attacker_is_player := ClassicChess.side(from_piece) == player_side
	var player_piece := from_piece if attacker_is_player else to_piece
	var opponent_piece := to_piece if attacker_is_player else from_piece
	return {"player_role": player_piece.to_lower(), "opponent_role": opponent_piece.to_lower(), "attacker": "player" if attacker_is_player else "opponent"}


## The node as a lesson dictionary (valid for LessonSchema) so the training runner can play it.
static func lesson_for(index: int) -> Dictionary:
	var data := node(index)
	if data.is_empty():
		return {}
	var m := matchup(data)
	if m.is_empty():
		return {}
	var lesson := {
		"id": "campaign_" + String(data["id"]), "title": String(data["title"]), "summary": String(data["summary"]), "category": "beginner", "order": index + 1,
		"player_role": m["player_role"], "opponent_role": m["opponent_role"], "behaviour": "normal", "difficulty": level(index), "attacker": m["attacker"],
		"arena": "stone-v1", "objectives": [{"id": "win", "type": "win", "text": "Win the duel"}], "fail": [], "campaign": true,
	}
	if data.has("hp_fraction"):
		lesson["constraints"] = {"player_hp_fraction": float(data["hp_fraction"])}
	if data.has("seconds"):
		lesson["duration_seconds"] = float(data["seconds"])
	return lesson


## Every problem in the node table (empty = valid): schema, matchups, unique ids, rewards that exist.
static func validate(lessons: LessonCatalog = null) -> Array:
	var problems: Array = []
	var seen := {}
	for i in NODES.size():
		var id := String(NODES[i]["id"])
		if seen.has(id):
			problems.append("duplicate id " + id)
		seen[id] = true
		var lesson := lesson_for(i)
		if lesson.is_empty():
			problems.append("%s: no valid matchup" % id)
			continue
		problems.append_array(LessonSchema.validate(lesson))
		var reward: Dictionary = NODES[i].get("reward", {})
		for key in reward:
			if key == "skin" and not (String(reward[key]) in CampaignProgress.SKINS):
				problems.append("%s: unknown skin" % id)
			elif key == "arena" and not (String(reward[key]) in CampaignProgress.ARENAS):
				problems.append("%s: unknown arena" % id)
			elif key == "lesson" and lessons != null and lessons.get_lesson(String(reward[key])).is_empty():
				problems.append("%s: unknown lesson %s" % [id, String(reward[key])])
	return problems
