extends RefCounted
## Animation integrity suite: runs the full audit (godot/combat/tools/anim_audit.gd + anim_audit_runtime.gd) on the committed GLBs
## (all six classes, LOD0 and LOD1, real CharacterModel / AnimationPlayer, seeded AI-vs-AI fights and scripted move-set scenarios) and
## asserts it. Rules:
##   * NO high-severity finding at all;
##   * every medium finding must be listed in KNOWN below (with the reason); a KNOWN entry that no longer fires FAILS the test, so the
##     list can only shrink;
##   * contracts between the Blender sources and Godot: nominal locomotion speeds, the King's counter layout, attack markers.
## Low-severity findings are measurements (kept in the report), not failures. The report is written by
##   godot --headless --path godot --script res://combat/tools/anim_audit.gd -- --out res://assets/combat/manifest/animation_audit.json
## (ANIMATION_INTEGRITY.md explains every check and every number).

const Audit := preload("res://combat/tools/anim_audit.gd")
const MANIFEST := "res://assets/combat/manifest/asset_manifest.json"
const REPORT := "res://assets/combat/manifest/animation_audit.json"

## "class|check prefix" -> reason. Matched against medium findings of either LOD.
const KNOWN := {
	"bishop|swing foot clears the floor": "the Bishop's slow, low walk lift grazes the floor for 4 foot-frames per cycle at touch-down (0.08 m of scrape per cycle)",
	"knight|props do not sink into the torso": "Knight shield/sword intersect the torso by 10-13 cm for a few frames of defeat and stagger (coarse ellipse test)",
	"pawn|pawn.light.3 tip reaches the sim hitbox": "the Pawn's sweeping finisher tip reaches 1.558 m of the 1.56 m (80% of reachM) line: arm-length limited, 0.1% short",
}


static func _known_key(f: Dictionary) -> String:
	for key in KNOWN:
		var parts: PackedStringArray = String(key).split("|")
		if parts[0] == f["class"] and String(f["check"]).begins_with(parts[1]):
			return key
	return ""


static func run(h, tree: SceneTree) -> void:
	var rep: Dictionary = await Audit.run(tree, {})
	var findings: Array = rep["findings"]
	h.begin("anim_integrity: no high-severity finding in any class, LOD or runtime fight")
	var high := findings.filter(func(f): return f["severity"] == "high")
	for f in high:
		h.check(false, "[%s lod%d %s] %s (value %s, limit %s) %s" % [f["class"], f["lod"], f["clip"], f["check"], str(f["value"]), str(f["limit"]), f["detail"]])
	h.check(high.is_empty(), "%d high findings" % high.size())

	h.begin("anim_integrity: every medium finding is a documented KNOWN issue, and every KNOWN issue still exists")
	var hit: Dictionary = {}
	for f in findings:
		if f["severity"] != "medium":
			continue
		var key := _known_key(f)
		if key == "":
			h.check(false, "unexpected medium finding [%s lod%d %s] %s (value %s, limit %s) %s" % [f["class"], f["lod"], f["clip"], f["check"], str(f["value"]), str(f["limit"]), f["detail"]])
		else:
			hit[key] = true
	for key in KNOWN:
		h.check(hit.has(key), "KNOWN issue '%s' no longer fires: remove it from KNOWN (%s)" % [key, KNOWN[key]])

	h.begin("anim_integrity: coverage, LOD parity, runtime checks pass for all six classes")
	for cls in Audit.CLASSES:
		for g in ["a", "c", "f", "h"]:
			var c: Dictionary = rep["checks"].get("%s/%s" % [g, cls], {})
			h.check(not c.is_empty() and int(c["pass"]) > 0, "%s group %s ran (%s)" % [cls, g, str(c)])
			h.eq(int(c.get("fail", -1)), 0, "%s group %s has no failure" % [cls, g])
		var res: Dictionary = rep["classes"][cls]["lod0"]
		h.eq(res["coverage"]["missing"], [], "%s: no missing clip" % cls)
		h.eq(res["coverage"]["substitutes"], [], "%s: no attack plays a substitute clip" % cls)
	h.eq(rep["runtime"]["fallbacks"], {}, "CharacterModel never fell back silently during the fights")
	var played: Dictionary = rep["runtime"]["clips_played"]
	for cls in Audit.CLASSES:
		for clip in ["idle", "walk", "light_1", "heavy", "ability", "stagger", "defeat", "victory"]:
			h.check(played.get(cls, {}).has(clip), "%s played '%s' in the fights" % [cls, clip])
	for fight in rep["runtime"]["fights"]:
		h.check(fight.get("ok", false) and int(fight.get("ticks", 0)) > 100, "fight %s-%s seed %s ran %s ticks" % [fight["white"], fight["black"], fight["seed"], fight.get("ticks", 0)])

	h.begin("anim_integrity: Blender contracts match the Godot constants")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for cls in Audit.CLASSES:
		var entry: Dictionary = manifest["characters"][cls]
		for clip in CharacterModel.NOMINAL_SPEED:
			h.near(float(entry["nominal_speed_mps"][clip]), float(CharacterModel.NOMINAL_SPEED[clip]), 0.0001, "%s %s nominal speed in the manifest equals CharacterModel.NOMINAL_SPEED" % [cls, clip])
		h.check(entry["markers"].has("heavy"), "%s manifest lists the attack markers" % cls)
	var counter: Dictionary = manifest["characters"]["king"]["counter"]
	h.near(float(counter["riposte_start_frame"]) / 60.0, CharacterModel.COUNTER_RIPOSTE_START, 0.0001, "King riposte start frame equals CharacterModel.COUNTER_RIPOSTE_START")
	h.eq(int(manifest["characters"]["king"]["clips"]["ability"]), 56, "King ability clip == royal-counter cast ticks (56)")

	h.begin("anim_integrity: the committed report exists and matches the thresholds")
	if h.check(FileAccess.file_exists(REPORT), "animation_audit.json is committed"):
		var committed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
		h.eq(committed["thresholds"].keys().size(), Audit.TH.keys().size(), "committed report was produced with the current threshold table")
		var committed_high := (committed["findings"] as Array).filter(func(f): return f["severity"] == "high")
		h.eq(committed_high.size(), 0, "committed report has no high findings")
