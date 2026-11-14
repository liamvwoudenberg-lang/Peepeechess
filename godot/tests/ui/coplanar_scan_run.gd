extends SceneTree
## Dev tool: prints the coplanar overlapping triangle pairs of the opening scene (grouped), and with `plane=<y>` the first positions.
##   godot --headless --path godot --script res://tests/ui/coplanar_scan_run.gd -- [quality] [plane=0]
const Scan = preload("res://tests/ui/coplanar_scan.gd")
const OpeningScene = preload("res://ui/opening/opening_scene.gd")
func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var q: String = args[0] if args.size() > 0 else "balanced"
	var s := OpeningScene.new()
	root.add_child(s)
	s.build(q, false, 0.0)
	await process_frame
	var r := Scan.scan(s)
	print(q, ": triangles ", r["triangles"], ", coplanar same-facing overlapping pairs ", r["pairs"].size())
	var seen := {}
	for p in r["pairs"]:
		var k := "%s | %s | plane %.3f n=%s" % [p["a"], p["b"], p["plane"], str(p["normal"].snapped(Vector3(0.01, 0.01, 0.01)))]
		seen[k] = int(seen.get(k, 0)) + 1
	for k in seen:
		print("  ", seen[k], "x ", k)
	if args.size() > 1:
		var plane := float(args[1].trim_prefix("plane="))
		var shown := 0
		for p in r["pairs"]:
			if absf(p["plane"] - plane) < 0.01 and shown < 400:
				print("   at ", p["at"].snapped(Vector3(0.01, 0.01, 0.01)), " ", p["a"], "/", p["b"])
				shown += 1
	s.queue_free()
	await process_frame
	quit()
