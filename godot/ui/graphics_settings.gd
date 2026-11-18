class_name GraphicsSettings
extends RefCounted
## Quality presets (Low / Medium / High / Ultra) plus the individual cinematic toggles. Pure presentation: nothing here is read by the
## duel simulation, chess rules or the network, so it can never affect determinism. Persisted in user://graphics.cfg (own file: it never
## collides with application_settings.gd). Systems read the statics; they subscribe to events().changed to re-apply.
##
## The project renders with GL Compatibility. SSAO and TAA need the Forward+/Mobile renderer, so on Compatibility they are stored and shown
## but have no effect (renderer_supports() says which); everything else below works on every renderer.

class Events:
	extends RefCounted
	signal changed

const PRESET_ORDER := ["low", "medium", "high", "ultra"]
const PRESET_NAMES := {"low": "Low", "medium": "Medium", "high": "High", "ultra": "Ultra", "custom": "Custom"}
const AA_ORDER := ["off", "fxaa", "msaa", "taa"]
const SHADOW_ORDER := ["off", "low", "medium", "high"]
const FPS_ORDER := [0, 30, 60, 120, 144]
const KEYS := ["particles", "light_shafts", "fog", "bloom", "ssao", "shadows", "aa", "res_scale", "fps_cap", "vsync", "cinematics"]
const PRESETS := {
	"low": {"particles": false, "light_shafts": false, "fog": false, "bloom": false, "ssao": false, "shadows": "off", "aa": "off", "res_scale": 0.75, "fps_cap": 30, "vsync": true, "cinematics": true},
	"medium": {"particles": true, "light_shafts": false, "fog": true, "bloom": false, "ssao": false, "shadows": "low", "aa": "fxaa", "res_scale": 1.0, "fps_cap": 60, "vsync": true, "cinematics": true},
	"high": {"particles": true, "light_shafts": true, "fog": true, "bloom": true, "ssao": false, "shadows": "medium", "aa": "msaa", "res_scale": 1.0, "fps_cap": 0, "vsync": true, "cinematics": true},
	"ultra": {"particles": true, "light_shafts": true, "fog": true, "bloom": true, "ssao": true, "shadows": "high", "aa": "msaa", "res_scale": 1.0, "fps_cap": 0, "vsync": true, "cinematics": true},
}
const PATH := "user://graphics.cfg"

static var preset := "high"
static var particles := true
static var light_shafts := true
static var fog := true
static var bloom := true
static var ssao := false
static var shadows := "medium"
static var aa := "msaa"
static var res_scale := 1.0
static var fps_cap := 0
static var vsync := true
## Master switch for the short skippable intro / finishing-blow / victory cinematics (never gameplay timing).
static var cinematics := true
static var show_fps := false
static var loaded := false
static var _events: Events


static func events() -> Events:
	if _events == null:
		_events = Events.new()
	return _events


## What the current renderer can actually do for a setting.
static func renderer_supports(key: String) -> bool:
	var method := str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	if key == "ssao" or key == "aa_taa":
		return method != "gl_compatibility"
	return true


static func defaults() -> String:
	return "low" if OS.has_feature("mobile") else "high"


## Applies a named preset to every individual setting (the toggles stay editable afterwards; they flip the preset to "custom").
static func set_preset(name: String) -> void:
	if not PRESETS.has(name):
		return
	set_preset_silent(name)
	changed()


## Which preset the current toggles equal, or "custom".
static func detect_preset() -> String:
	var now := current()
	for name in PRESET_ORDER:
		var match_all := true
		for key in KEYS:
			if key != "cinematics" and now[key] != PRESETS[name][key]:
				match_all = false
				break
		if match_all:
			return name
	return "custom"


static func current() -> Dictionary:
	return {"particles": particles, "light_shafts": light_shafts, "fog": fog, "bloom": bloom, "ssao": ssao, "shadows": shadows, "aa": aa,
		"res_scale": res_scale, "fps_cap": fps_cap, "vsync": vsync, "cinematics": cinematics}


## Sets one toggle by key (the Settings page and tests use this), refreshes the preset label, applies and saves.
static func set_value(key: String, value: Variant) -> void:
	_assign(key, value)
	preset = detect_preset()
	changed()


## The one place every setting is written (static code cannot use set()); invalid values are ignored.
static func _assign(key: String, value: Variant) -> void:
	match key:
		"particles": particles = bool(value)
		"light_shafts": light_shafts = bool(value)
		"fog": fog = bool(value)
		"bloom": bloom = bool(value)
		"ssao": ssao = bool(value)
		"shadows": shadows = str(value) if str(value) in SHADOW_ORDER else shadows
		"aa": aa = str(value) if str(value) in AA_ORDER else aa
		"res_scale": res_scale = clampf(float(value), 0.5, 1.0)
		"fps_cap": fps_cap = int(value) if int(value) in FPS_ORDER else fps_cap
		"vsync": vsync = bool(value)
		"cinematics": cinematics = bool(value)
		"show_fps": show_fps = bool(value)


static func changed() -> void:
	apply()
	save()
	events().changed.emit()


static func load_preferences() -> void:
	if loaded:
		return
	loaded = true
	set_preset_silent(defaults())
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key in KEYS + ["show_fps"]:
			if config.has_section_key("graphics", key):
				_assign(key, config.get_value("graphics", key))
	preset = detect_preset()
	apply()


static func set_preset_silent(name: String) -> void:
	for key in KEYS:
		_assign(key, PRESETS[name][key])
	preset = name


static func save() -> void:
	var config := ConfigFile.new()
	for key in KEYS:
		config.set_value("graphics", key, current()[key])
	config.set_value("graphics", "show_fps", show_fps)
	config.save(PATH)


## ---- applying ----------------------------------------------------------------------------------------------------------------------
## Engine / viewport level settings. Environment-level ones (fog, bloom, SSAO) are applied by apply_environment(), which the worlds call
## from their own apply step when events().changed fires.
static func apply() -> void:
	# keep the legacy 3-step value (used by the opening scene build) in step with the preset
	var legacy: String = {"low": "low", "medium": "balanced", "high": "high", "ultra": "high", "custom": "balanced"}[preset]
	preload("res://ui/application_settings.gd").quality = legacy
	Engine.max_fps = fps_cap
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var atlas: int = {"off": 1024, "low": 2048, "medium": 4096, "high": 8192}[shadows]
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality({"off": RenderingServer.SHADOW_QUALITY_HARD, "low": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "medium": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "high": RenderingServer.SHADOW_QUALITY_SOFT_HIGH}[shadows])
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		_apply_viewports(tree.root)


static func _apply_viewports(node: Node) -> void:
	if node is Viewport:
		var vp := node as Viewport
		vp.msaa_3d = {"off": Viewport.MSAA_DISABLED, "fxaa": Viewport.MSAA_DISABLED, "msaa": Viewport.MSAA_4X if preset == "ultra" else Viewport.MSAA_2X, "taa": Viewport.MSAA_DISABLED}[aa]
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
		vp.use_taa = aa == "taa" and renderer_supports("aa_taa")
		vp.scaling_3d_scale = res_scale
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	for child in node.get_children():
		_apply_viewports(child)


## Fog / bloom / SSAO on an Environment the world owns. `base_fog_density` is the world's own density (0 keeps fog off whatever the toggle).
static func apply_environment(env: Environment, base_fog_density: float = -1.0) -> void:
	if env == null:
		return
	if base_fog_density >= 0.0:
		env.fog_enabled = fog and base_fog_density > 0.0
		env.fog_density = base_fog_density
	env.glow_enabled = bloom
	if bloom:
		env.glow_intensity = 0.55
		env.glow_strength = 0.9
		env.glow_bloom = 0.04
		env.glow_hdr_threshold = 1.1
	env.ssao_enabled = ssao and renderer_supports("ssao")
