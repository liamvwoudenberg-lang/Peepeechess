extends SceneTree
## Presentation quality must affect existing/new 3D views and opt-in scenery, without changing physics or UI scale.
const Platform = preload("res://ui/platform_input.gd")
const ScreenMode = preload("res://ui/screen_mode.gd")
const Settings = preload("res://ui/application_settings.gd")
var checks := 0
var failures: Array[String] = []

class Scenery:
	extends Node
	var applied: Array[String] = []
	func _ready() -> void:
		add_to_group("courtyard_quality")
	func set_quality(value: String) -> void:
		applied.append(value)

class Gameplay:
	extends Node
	var touched := false
	func set_quality(_value: String) -> void:
		touched = true

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var original_ticks := Engine.physics_ticks_per_second
	var original_time := Engine.time_scale
	var ui_scale := root.content_scale_factor
	var platform := Platform.new()
	root.add_child(platform)
	var host := Node.new()
	root.add_child(host)
	var existing := SubViewport.new()
	existing.size = Vector2i(320, 180)
	host.add_child(existing)
	var decoration := Scenery.new()
	host.add_child(decoration)
	var gameplay := Gameplay.new()
	host.add_child(gameplay)
	await process_frame

	Platform.set_quality("low")
	expect(Engine.max_fps == 30, "low preset caps display at 30 FPS")
	expect(existing.msaa_3d == Viewport.MSAA_DISABLED, "low preset removes multisampling from an existing nested view")
	expect(is_equal_approx(existing.scaling_3d_scale, 0.75), "low preset reduces only the 3D resolution")
	expect(existing.positional_shadow_atlas_size == 0, "low preset removes positional shadow allocation")
	expect(not decoration.applied.is_empty() and decoration.applied.back() == "low", "existing opt-in scenery receives the preset")
	expect(not gameplay.touched, "a gameplay node with a similarly named method is never configured")

	var added := SubViewport.new()
	added.size = Vector2i(640, 360)
	host.add_child(added)
	var late_scenery := Scenery.new()
	host.add_child(late_scenery)
	var transient := Scenery.new()
	host.add_child(transient)
	host.remove_child(transient)
	transient.free()
	await process_frame
	await process_frame
	expect(added.msaa_3d == Viewport.MSAA_DISABLED and is_equal_approx(added.scaling_3d_scale, 0.75), "a later view inherits the current preset")
	expect(late_scenery.applied == ["low"], "scenery joining its group in ready inherits the preset once")

	Platform.set_quality("medium")
	expect(Platform.quality == "balanced" and Engine.max_fps == 60, "legacy medium preference resolves to balanced")
	expect(existing.msaa_3d == Viewport.MSAA_2X and added.msaa_3d == Viewport.MSAA_2X, "balanced updates both views")
	expect(is_equal_approx(existing.scaling_3d_scale, 1.0) and existing.positional_shadow_atlas_size == 2048, "balanced restores full render resolution and bounded shadow atlas")
	expect(late_scenery.applied.back() == "balanced", "scenery changes without reconstructing the board")
	Platform.set_quality("high")
	expect(existing.msaa_3d == Viewport.MSAA_4X and existing.positional_shadow_atlas_size == 4096, "high enables quality settings")
	expect(Engine.max_fps == 0, "high preserves the existing uncapped preference")
	Platform.set_quality("corrupt preference")
	expect(Platform.quality == "balanced", "unknown quality values use balanced")
	expect(Engine.physics_ticks_per_second == original_ticks and Engine.time_scale == original_time, "presets never change simulation rate or timescale")
	expect(root.content_scale_factor == ui_scale, "render scaling does not scale UI or touch targets")

	ScreenMode.available_override = -1
	expect(not ScreenMode.available() and not ScreenMode.toggle(), "headless cannot attempt browser or desktop fullscreen")
	Settings.loaded = true
	Settings.display_mode = "windowed"
	Settings.set_display_mode("fullscreen", false)
	expect(Settings.display_mode == "windowed", "unavailable fullscreen never changes the saved choice")
	host.queue_free()
	platform.queue_free()
	await process_frame
	print("Courtyard display: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
