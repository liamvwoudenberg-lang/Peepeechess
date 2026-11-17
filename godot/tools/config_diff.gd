extends SceneTree
## Shows which tuning values differ.
##
##   godot --headless --path godot --script res://tools/config_diff.gd                      # working copy vs git HEAD
##   godot --headless --path godot --script res://tools/config_diff.gd -- other.json         # working copy vs another file
##   godot --headless --path godot --script res://tools/config_diff.gd -- chess_rules        # the rules file instead of balance
##
## One line per changed number: `profiles.n.armor: 0.2 -> 0.25`. Exit code 0 when nothing differs, 2 when something does
## (handy in scripts); documentation keys (underscore) are ignored.
const Tools := preload("res://config/config_tools.gd")
const Balance := preload("res://combat/data/balance_data.gd")


func _initialize() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	var which := "balance"
	var other_path := ""
	for arg in args:
		if arg in ["balance", "chess_rules"]:
			which = arg
		elif not arg.begins_with("--"):
			other_path = arg
	var res_path := "res://config/%s.json" % which
	var repo_path := "godot/config/%s.json" % which
	var current: Dictionary = Tools.read_json(res_path)
	var baseline: Dictionary = Tools.read_json(other_path) if not other_path.is_empty() else Tools.git_head_json(repo_path)
	if baseline.is_empty():
		print("no baseline to compare with (git HEAD unavailable or the other file is missing)")
		quit(1)
		return
	var rows: Array = Tools.diff(Tools.flatten(baseline), Tools.flatten(current))
	if rows.is_empty():
		print("no differences in %s" % repo_path)
		quit(0)
		return
	print("%d difference(s) in %s (baseline -> working copy):" % [rows.size(), repo_path])
	print(Tools.format_diff(rows))
	if which == "balance":
		print("(pairings to re-measure: use config_quicksim.gd <pairing> after changing a role's numbers; the full recalibration is in docs/game/BALANCE_GUIDE.md)")
	quit(2)
