class_name FighterRoster
extends RefCounted
## PROTOTYPE data for the standalone test arena and the tests ONLY.
##
## In the integrated game the chess/match authority builds BattleRequest (including
## FighterStats) from its own balance registry; the combat simulation reads every number from
## that request and never from this file. statsIds here are "combat-proto-v1.*" on purpose, so
## they cannot be mistaken for the authority-approved "balance-v1.*" registry.
##
## Pawn and Knight keep the original prototype numbers (statsId combat-proto-v1.*). Bishop, Rook and
## Queen load the approved snapshot res://chess/battle_stats.json (statsId c0-balance-v1.*, owned by
## Codex, read only here) so tests exercise the numbers the real Battle flow will send.
##
## Values convert the legacy src/battle/config.ts per CONTRACTS.md:
##   walk speed = 1.05 + speed * 0.29 m/s;   ticks = ceil(seconds * 60), min one tick.

const MATCH_ID := "local-match"
const C0_STATS_PATH := "res://chess/battle_stats.json"
const ABILITY_NAMES := {"p": "Last Stand", "n": "Lunging Strike", "b": "Blink", "r": "Fortress Guard", "q": "Royal Fury",
		"k": "Royal Counter"}
## The five roles the v1 contract can send (menus, soaks and the default matrix use these).
const ROLES := ["p", "n", "b", "r", "q"]
## Roles outside the v1 contract. Their requests fight only through `CombatSimulation.start(req, {"allow_experimental_roles": true})`.
const EXPERIMENTAL_ROLES := ["k"]
## Every role with combat tuning (six-class roster).
const ALL_ROLES := ["p", "n", "b", "r", "q", "k"]

static var _c0_cache: Dictionary = {}


static func ability_name(role: String) -> String:
	return String(ABILITY_NAMES.get(role, "Ability"))


## FighterStats for `role` from the approved C0 snapshot, with whole numbers as ints (JSON gives floats).
static func _c0_stats(role: String) -> Dictionary:
	if _c0_cache.is_empty():
		_c0_cache = JSON.parse_string(FileAccess.get_file_as_string(C0_STATS_PATH))
	var src: Dictionary = _c0_cache.get(role, {})
	var out := src.duplicate()
	for key in ["schemaVersion", "maxHp", "maxStamina", "baseDamage", "lightTicks", "heavyTicks", "parryTicks", "cooldownTicks"]:
		if out.has(key):
			out[key] = int(out[key])
	return out

## role -> FighterStats (contract shape)
static func stats_for(role: String) -> Dictionary:
	match role:
		"p":
			return {
				"schemaVersion": 1, "statsId": "combat-proto-v1.p", "role": "p",
				"maxHp": 80, "maxStamina": 120, "baseDamage": 12, "moveSpeedMps": 3.66, "reachM": 1.95,
				"lightTicks": 24, "heavyTicks": 53, "parryTicks": 11, "abilityId": "last-stand", "cooldownTicks": 900,
			}
		"n":
			return {
				"schemaVersion": 1, "statsId": "combat-proto-v1.n", "role": "n",
				"maxHp": 125, "maxStamina": 110, "baseDamage": 22, "moveSpeedMps": 3.08, "reachM": 1.65,
				"lightTicks": 32, "heavyTicks": 63, "parryTicks": 13, "abilityId": "lunging-strike", "cooldownTicks": 540,
			}
		"b", "r", "q", "k":
			return _c0_stats(role)
	return {}


static func display_name(role: String) -> String:
	return String(FighterProfile.for_role(role).get("display", role))


const _PIECE_IDS := {
	"w-p": "w-p-d2", "b-p": "b-p-e7", "w-n": "w-n-b1", "b-n": "b-n-g8",
	"w-b": "w-b-c1", "b-b": "b-b-f8", "w-r": "w-r-a1", "b-r": "b-r-h8", "w-q": "w-q-d1", "b-q": "b-q-d8",
	"w-k": "w-k-e1", "b-k": "b-k-e8",
}
## attacker origin squares chosen so the capture on e5/e4 is geometrically a real chess capture:
## pawn diagonal step, knight L, bishop diagonal (c3->e5, c6->e4), rook along the e-file (e1->e5, e8->e4),
## queen along a diagonal (b2->e5, b7->e4). All paths are empty in the generated position.
const _FROM := {
	"w-p": "d4", "w-n": "d3", "b-p": "d5", "b-n": "d6",
	"w-b": "c3", "b-b": "c6", "w-r": "e1", "b-r": "e8", "w-q": "b2", "b-q": "b7",
	"w-k": "d4", "b-k": "d5",  # a king captures one square away (experimental role, v1 forbids it)
}


static func faction_for(color: String) -> String:
	return "royal" if color == "w" else "skeletons"


static func combatant(role: String, color: String, square: String, player_id: String) -> Dictionary:
	return {
		"playerId": player_id,
		"pieceId": _PIECE_IDS["%s-%s" % [color, role]],
		"characterId": "%s.%s" % [faction_for(color), role],
		"color": color,
		"role": role,
		"square": square,
		"stats": stats_for(role),
	}


## A schema-valid BattleRequest for a local fight. The attacker captures on e5 (white) / e4 (black).
static func build_request(white_role: String, black_role: String, attacker_color: String = "w",
		battle_id: String = "local-battle-1", seed: int = 12345, start_tick: int = 0,
		match_id: String = MATCH_ID) -> Dictionary:
	var defender_color := "b" if attacker_color == "w" else "w"
	var attacker_role := white_role if attacker_color == "w" else black_role
	var defender_role := black_role if attacker_color == "w" else white_role
	var to_square := "e5" if attacker_color == "w" else "e4"
	var from_square: String = _FROM["%s-%s" % [attacker_color, attacker_role]]
	var attacker := combatant(attacker_role, attacker_color, from_square, "player-white" if attacker_color == "w" else "player-black")
	var defender := combatant(defender_role, defender_color, to_square, "player-white" if defender_color == "w" else "player-black")
	return {
		"schemaVersion": 1, "matchId": match_id, "battleId": battle_id, "expectedRevision": 1,
		"beforeFen": _fen(attacker, defender, from_square, to_square, attacker_color),
		"from": from_square, "to": to_square, "promotion": null,
		"attacker": attacker, "defender": defender,
		"arenaId": "stone-v1", "startTick": start_tick, "countdownTicks": 180, "durationTicks": 5400, "seed": seed,
	}


static func _fen(attacker: Dictionary, defender: Dictionary, from_sq: String, to_sq: String, side: String) -> String:
	var pieces := {"h8": "k", "h1": "K"}
	for combatant_data in [attacker, defender]:
		if combatant_data["role"] == "k":
			pieces.erase("h1" if combatant_data["color"] == "w" else "h8")  # the fighting king replaces the spare one
	pieces[from_sq] = _symbol(attacker)
	pieces[to_sq] = _symbol(defender)
	var rows: Array[String] = []
	for rank in range(8, 0, -1):
		var row := ""
		var empty := 0
		for file in 8:
			var sq := "%s%d" % [char(97 + file), rank]
			if pieces.has(sq):
				if empty > 0:
					row += str(empty)
					empty = 0
				row += String(pieces[sq])
			else:
				empty += 1
		if empty > 0:
			row += str(empty)
		rows.append(row)
	return "%s %s - - 0 1" % ["/".join(rows), side]


static func _symbol(combatant_data: Dictionary) -> String:
	var letter: String = combatant_data["role"]
	return letter.to_upper() if combatant_data["color"] == "w" else letter
