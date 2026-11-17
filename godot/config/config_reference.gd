extends RefCounted
## Builds the reference tables (docs/game/BALANCE_REFERENCE.md, docs/game/RULES_REFERENCE.md) from the metadata files, so the
## documentation of every key (meaning, unit, allowed range) cannot drift from what the loader enforces.
## Regenerate with:  godot --headless --path godot --script res://tools/config_docs.gd
## A test (config suite) fails when the committed documents differ from what this builds.
const Meta := preload("res://config/config_meta.gd")

const BALANCE_DOC := "res://../docs/game/BALANCE_REFERENCE.md"
const RULES_DOC := "res://../docs/game/RULES_REFERENCE.md"


static func balance_markdown() -> String:
	var m: Dictionary = Meta.meta("res://config/balance_meta.json")
	var lines: PackedStringArray = []
	lines.append("# Balance reference (generated)")
	lines.append("")
	lines.append("Generated from `godot/config/balance_meta.json` by `res://tools/config_docs.gd`. Do not edit by hand: change the metadata, then regenerate.")
	lines.append("The values live in `godot/config/balance.json`. A 'tick' is 1/60 s. Ranges are what the loader accepts, not recommendations.")
	lines.append("")
	_section(lines, "Role profiles (`profiles.<role>.*`)", "Movement feel, health-independent defences and the stamina/poise economy of each role.", m.get("profiles", {}))
	_section(lines, "Abilities (`abilities.<id>.*`)", "One block per ability (buffs, blink, counter stance, the Queen's combo).", m.get("abilities", {}))
	_section(lines, "Attack frame data (`attacks.<role>.light[i] / heavy / abilities.<id>`)", "The same keys apply to every light attack in the chain, the heavy and the ability swings.", m.get("attacks", {}))
	_section(lines, "Global blocks", "Hit stun, pacing, duel length and the attacker table.", m.get("paths", {}))
	return "\n".join(lines) + "\n"


static func rules_markdown() -> String:
	var m: Dictionary = Meta.meta("res://config/chess_rules_meta.json")
	var lines: PackedStringArray = []
	lines.append("# Rules configuration reference (generated)")
	lines.append("")
	lines.append("Generated from `godot/config/chess_rules_meta.json` by `res://tools/config_docs.gd`. Do not edit by hand: change the metadata, then regenerate.")
	lines.append("The values live in `godot/config/chess_rules.json`. `*` stands for a list position (`[*]`) or a name (a level number, a role, a boon id).")
	lines.append("")
	_section(lines, "All settings", "Everything in chess_rules.json.", m.get("paths", {}))
	return "\n".join(lines) + "\n"


static func _section(lines: PackedStringArray, title: String, intro: String, spec: Dictionary) -> void:
	lines.append("## " + title)
	lines.append("")
	lines.append(intro)
	lines.append("")
	lines.append("| Key | Type | Unit | Range | What it does |")
	lines.append("|---|---|---|---|---|")
	var keys: Array = spec.keys()
	keys.sort()
	for key in keys:
		var e: Dictionary = spec[key]
		var range_text := ""
		if e.has("min") or e.has("max"):
			range_text = "%s .. %s" % [Meta._n(e["min"]) if e.has("min") else "", Meta._n(e["max"]) if e.has("max") else ""]
		lines.append("| `%s` | %s | %s | %s | %s |" % [key, e.get("type", ""), e.get("unit", ""), range_text, String(e.get("doc", "")).replace("|", "/")])
	lines.append("")


static func write_all() -> int:
	var written := 0
	for pair in [[BALANCE_DOC, balance_markdown()], [RULES_DOC, rules_markdown()]]:
		var path: String = ProjectSettings.globalize_path(pair[0])
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("cannot write " + path)
			continue
		file.store_string(pair[1])
		written += 1
	return written


## True when the committed documents equal what the metadata generates (used by the test).
static func docs_current() -> Array:
	var stale: Array = []
	for pair in [[BALANCE_DOC, balance_markdown()], [RULES_DOC, rules_markdown()]]:
		var path: String = ProjectSettings.globalize_path(pair[0])
		if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != pair[1]:
			stale.append(String(pair[0]).get_file())
	return stale
