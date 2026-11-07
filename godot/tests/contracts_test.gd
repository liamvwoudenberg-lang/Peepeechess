extends SceneTree
const Codec = preload("res://contracts/codec.gd")

func _init() -> void:
	var codec = Codec.new()
	var cases = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/v1/fixtures.json"))
	var roundtrips: Array = []
	for case in cases:
		var encoded = JSON.stringify(case.payload, "", true, true)
		var decoded = codec.decode(case.type, encoded)
		if decoded.ok != case.valid:
			printerr("Contract mismatch: ", case.name)
			quit(1)
			return
		if case.valid:
			var outbound = codec.encode(case.type, decoded.value)
			if not outbound.ok:
				quit(1)
				return
			roundtrips.append({"type": case.type, "payload": JSON.parse_string(outbound.text)})
	if codec.decode("CombatInput", "{broken").ok:
		quit(1)
		return
	var args = OS.get_cmdline_user_args()
	if args.size() == 1:
		var file = FileAccess.open(args[0], FileAccess.WRITE)
		if file == null:
			printerr("Cannot write roundtrip file")
			quit(1)
			return
		file.store_string(JSON.stringify(roundtrips, "", true, true))
	print("PASS: ", cases.size(), " shared contract cases; malformed JSON rejected")
	quit(0)
