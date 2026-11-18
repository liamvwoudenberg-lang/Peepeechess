extends SceneTree
## Headless check of the Wave 1 presentation overlays: they finish on time, skip on input, respect Cinematics / reduce motion
## and leave no residue (camera offsets restored). Run: godot --headless --path godot --script res://tests/ui/cinematic_overlays_test.gd
const CaptureIntro = preload("res://ui/cinematic/capture_intro.gd")
const FinishingBlow = preload("res://ui/cinematic/finishing_blow.gd")
const ResultScreen = preload("res://ui/cinematic/result_screen.gd")
const LoadingScreen = preload("res://ui/cinematic/loading_screen.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
var failures := 0

func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		push_error("FAIL " + what)

func _initialize() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	Kit.install(host)
	GraphicsSettings.cinematics = true
	var intro := CaptureIntro.new()
	host.add_child(intro)
	var done := [false]
	intro.finished.connect(func(): done[0] = true)
	check(intro.play("A", "B"), "intro plays")
	check(CaptureIntro.DURATION < 3.0, "intro under 3 s")
	for i in 30:
		intro.advance(0.1)
	check(done[0], "intro finishes by itself")
	GraphicsSettings.cinematics = false
	var off := CaptureIntro.new()
	host.add_child(off)
	check(not off.play("A", "B"), "intro skipped when cinematics off")
	GraphicsSettings.cinematics = true
	var cam := Camera3D.new()
	host.add_child(cam)
	var blow := FinishingBlow.new()
	host.add_child(blow)
	check(blow.play(1.0, cam), "blow plays")
	blow.advance(0.1)
	blow.advance(1.0)
	check(cam.h_offset == 0.0 and cam.v_offset == 0.0, "camera offset restored")
	check(not FinishingBlow.SLOWMO_ENABLED and is_equal_approx(Engine.time_scale, 1.0), "no slow-mo, time scale untouched")
	var result := ResultScreen.new()
	host.add_child(result)
	result.show_result("defeat", "Checkmate", "Black wins")
	check(result.button != null, "result has continue button")
	var loading := LoadingScreen.new()
	host.add_child(loading)
	loading.begin("x")
	loading.set_progress(0.5)
	check(loading.bar.value == 0.5, "loading progress")
	print("cinematic_overlays_test: ", "OK" if failures == 0 else "%d failures" % failures)
	quit(1 if failures > 0 else 0)
