extends SceneTree
## Headless combat test runner.
##   godot --headless --path godot --script res://combat/tests/test_runner.gd
##   godot --headless --path godot --script res://combat/tests/test_runner.gd -- components attacks
## Exit code 0 only if every check passed. Run the editor import first so global classes exist.

const Harness := preload("res://combat/tests/test_harness.gd")
const Balance := preload("res://combat/data/balance_data.gd")
## The shipped pacing (BALANCE.md "Pacing": slower swings, dearer swings, wider parry window and richer parry reward, all in
## balance_v1.json) is not the documented frame data the mechanics suites assert exact numbers against (24-tick light, 11-tick parry
## window, 12 x 1.25 riposte ...). Those suites run under this override, which restores the frame data they were written for, so they
## keep proving the MECHANICS; the suites below run on the data as shipped, and the pacing suite pins what the shipped pacing changed.
const RAW_PACING_PATCH := "res://combat/tests/raw_pacing.json"
const SHIPPED_DATA_SUITES := ["balance", "attacker_edge", "pacing", "anim_integrity", "soak", "world", "pit_climb", "overlay", "world_assets", "assets", "polish", "contracts"]
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
	"royal_flow": "res://combat/tests/test_royal_flow.gd",
	"matchups": "res://combat/tests/test_matchups.gd",
	"attacker_edge": "res://combat/tests/test_attacker_edge.gd",
	"pacing": "res://combat/tests/test_pacing.gd",
	"paladin_board": "res://combat/tests/test_paladin_board.gd",
	"net": "res://combat/tests/test_net.gd",
	"net_latency": "res://combat/tests/test_net_latency.gd",
	"net_arena": "res://combat/tests/test_net_arena.gd",
	"net_roles": "res://combat/tests/test_net_roles.gd",
	"audio": "res://combat/tests/test_audio.gd",
	"music": "res://combat/tests/test_music.gd",
	"touch": "res://combat/tests/test_touch.gd",
	"pads": "res://combat/tests/test_pads.gd",
	"assets": "res://combat/tests/test_assets.gd",
	"polish": "res://combat/tests/test_polish.gd",
	"world_assets": "res://combat/tests/test_world_assets.gd",
	"soak": "res://combat/tests/test_soak.gd",
	"world": "res://combat/tests/test_world.gd",
	"pit_climb": "res://combat/tests/test_pit_climb.gd",
	"overlay": "res://combat/tests/test_overlay.gd",
	"anim_integrity": "res://combat/tests/test_anim_integrity.gd",
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
		var raw: bool = not (suite_name in SHIPPED_DATA_SUITES)
		print("== %s%s" % [suite_name, " (documented frame data)" if raw else ""])
		if raw:
			var errors := Balance.apply_override(JSON.parse_string(FileAccess.get_file_as_string(RAW_PACING_PATCH)))
			assert(errors.is_empty(), "raw pacing patch refused: %s" % str(errors))
		var suite = load(SUITES[suite_name])
		await suite.run(harness, self)
		if raw:
			Balance.clear_override()
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
	OS.delay_msec(400)  # real time: --fixed-fps makes the timer above virtual, the audio thread still needs wall-clock time
	var report := harness.report()
	await process_frame
	quit(report)
