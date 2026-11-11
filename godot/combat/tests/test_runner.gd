extends SceneTree
## Headless combat test runner.
##   godot --headless --path godot --script res://combat/tests/test_runner.gd
##   godot --headless --path godot --script res://combat/tests/test_runner.gd -- components attacks
## Exit code 0 only if every check passed. Run the editor import first so global classes exist.

const Harness := preload("res://combat/tests/test_harness.gd")
const SUITES: Dictionary = {
	"components": "res://combat/tests/test_components.gd",
	"contracts": "res://combat/tests/test_contracts.gd",
	"input": "res://combat/tests/test_input.gd",
	"movement": "res://combat/tests/test_movement.gd",
	"attacks": "res://combat/tests/test_attacks.gd",
	"defense": "res://combat/tests/test_defense.gd",
	"abilities": "res://combat/tests/test_abilities.gd",
	"endings": "res://combat/tests/test_endings.gd",
	"adapter": "res://combat/tests/test_adapter.gd",
	"roles": "res://combat/tests/test_roles.gd",
	"balance": "res://combat/tests/test_balance.gd",
	"king": "res://combat/tests/test_king.gd",
	"royal": "res://combat/tests/test_royal.gd",
	"matchups": "res://combat/tests/test_matchups.gd",
	"net": "res://combat/tests/test_net.gd",
	"net_latency": "res://combat/tests/test_net_latency.gd",
	"net_arena": "res://combat/tests/test_net_arena.gd",
	"audio": "res://combat/tests/test_audio.gd",
	"touch": "res://combat/tests/test_touch.gd",
	"pads": "res://combat/tests/test_pads.gd",
	"assets": "res://combat/tests/test_assets.gd",
	"polish": "res://combat/tests/test_polish.gd",
	"world_assets": "res://combat/tests/test_world_assets.gd",
	"soak": "res://combat/tests/test_soak.gd",
}


func _initialize() -> void:
	# Nodes added to the root during _initialize are not inside the tree yet; wait one frame.
	await process_frame
	var harness = Harness.new()
	var wanted: PackedStringArray = OS.get_cmdline_user_args()
	var started := Time.get_ticks_msec()
	for suite_name in SUITES:
		if wanted.size() > 0 and not (suite_name in wanted):
			continue
		print("== %s" % suite_name)
		var suite = load(SUITES[suite_name])
		await suite.run(harness, self)
	print("(%d ms)" % (Time.get_ticks_msec() - started))
	# Leave nothing behind: free whatever the suites parked in the tree and drop the static sound cache so the
	# engine reports no leaked resources at exit (Codex's native-combat gate treats any ERROR: line as a failure).
	for child in root.get_children():
		child.queue_free()
	await process_frame
	await process_frame
	load("res://combat/audio/combat_audio.gd").clear_library()
	# The audio server releases stopped playbacks on its own mix thread; give it a moment before the engine shuts down.
	await create_timer(0.5).timeout
	var report := harness.report()
	await process_frame
	quit(report)
