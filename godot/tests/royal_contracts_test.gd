extends SceneTree
## battle-royal-v1 contract cases (godot/contracts/royal/v1/fixtures.json) through the Godot royal codec, with the same
## Node round-trip hook as contracts_test.gd: `-- <output.json>` writes the re-encoded valid payloads for Node to compare.
const Codec = preload("res://contracts/royal/v1/codec.gd")
const V1 = preload("res://contracts/codec.gd")

func _init() -> void:
	var problem = check()
	if not problem.is_empty():
		printerr("FAIL: ", problem)
		quit(1)

func check() -> String:
	var codec = Codec.new()
	var v1 = V1.new()
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/royal/v1/fixtures.json"))
	var roundtrips: Array = []
	var invalid = 0
	for case in cases:
		var decoded = codec.decode(case.type, JSON.stringify(case.payload, "", true, true))
		if decoded.ok != case.valid:
			return "royal contract mismatch: " + case.name
		if case.valid:
			var outbound = codec.encode(case.type, decoded.value)
			if not outbound.ok:
				return "royal encode failed: " + case.name
			roundtrips.append({"type": case.type, "payload": JSON.parse_string(outbound.text)})
		else:
			invalid += 1
		# v1 stays strict: a king-capable request / royal state is NOT a v1 BattleRequest / MatchState.
		if case.valid and case.type == "RoyalBattleRequest" and v1.valid("BattleRequest", case.payload):
			return "a king battle request must not validate as v1 BattleRequest"
		if case.valid and case.type == "RoyalMatchState" and v1.valid("MatchState", case.payload):
			return "a royal match state must not validate as v1 MatchState"
	if codec.decode("RoyalDuelRequest", "{broken").ok:
		return "malformed JSON accepted"
	var args = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file = FileAccess.open(args[0], FileAccess.WRITE)
		if file == null:
			return "Cannot write roundtrip file"
		file.store_string(JSON.stringify(roundtrips, "", true, true))
		file.close()
	print("PASS: ", cases.size(), " royal contract cases (", invalid, " invalid); v1 types stay strict")
	quit(0)
	return ""
