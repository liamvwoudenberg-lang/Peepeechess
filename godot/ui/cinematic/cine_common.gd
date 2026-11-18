extends RefCounted
## Shared helpers for the presentation-only cinematic overlays in this folder. Nothing here touches simulation state:
## overlays are plain Controls that draw above the game, ignore the mouse (except to skip) and never read or write combat data.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const SKIP_GUARD := 0.15   ## ignore the press that may have triggered the overlay

## Settings > Cinematics (GraphicsSettings.cinematics). When off, overlays finish immediately.
static func cinematics_on() -> bool:
	return GraphicsSettings.cinematics

static func reduce_motion() -> bool:
	return Prefs.reduce_motion

static func is_skip(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventJoypadButton:
		return event.pressed
	return false

const VIGNETTE_SHADER := "shader_type canvas_item;\nuniform float strength = 0.5;\nuniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);\nvoid fragment() {\n\tvec2 p = UV - vec2(0.5);\n\tfloat d = smoothstep(0.25, 0.75, length(p * vec2(1.0, 0.9)));\n\tCOLOR = vec4(tint.rgb, d * strength);\n}\n"

static var _vignette_shader: Shader

## A full-screen edge vignette (cheap fake focus / depth-of-field falloff; Compatibility has no real DoF). The centre stays clear,
## so it can never hide an attack telegraph near the middle of the arena.
static func make_vignette(strength: float = 0.5, tint: Color = Color.BLACK) -> ColorRect:
	if _vignette_shader == null:
		_vignette_shader = Shader.new()
		_vignette_shader.code = VIGNETTE_SHADER
	var rect := ColorRect.new()
	rect.name = "Vignette"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var material := ShaderMaterial.new()
	material.shader = _vignette_shader
	material.set_shader_parameter("strength", strength)
	material.set_shader_parameter("tint", tint)
	rect.material = material
	return rect
