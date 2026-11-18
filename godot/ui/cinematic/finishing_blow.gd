extends Control
## Finishing-blow presentation: a short screen flash plus a vignette pulse and an optional shake of a CAMERA the caller hands in
## (Camera3D h_offset / v_offset, or Control position). PRESENTATION ONLY and local:
##   * it reads no combat state, writes none, and does not touch Engine.time_scale, physics ticks or any sim clock;
##   * the flash is edge-weighted (vignette), never a full-screen cover, and short (<= 0.35 s), so an attack telegraph is never hidden;
##   * off with Settings > Cinematics; reduce motion drops the shake and keeps a faint flash.
## HIT-STOP / SLOW-MO are deliberately NOT implemented: Engine.time_scale also scales the physics tick the authoritative duel
## simulation runs on, so using it could alter timings / determinism. SLOWMO_ENABLED stays false until the sim exposes a separate
## presentation clock (see README.md).
const T = preload("res://ui/theme/ui_tokens.gd")
const Common = preload("res://ui/cinematic/cine_common.gd")

const SLOWMO_ENABLED := false   # do not flip without a sim-independent presentation clock
const DURATION := 0.35
const SHAKE_PIXELS := 0.06      # Camera3D h/v offset units

signal finished

var elapsed := 0.0
var playing := false
var strength := 1.0
var vignette: ColorRect
var camera: Camera3D
var _rest := Vector2.ZERO

func _init() -> void:
	name = "FinishingBlow"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

## `blow_strength` 0..1 scales flash and shake. `shake_camera` is optional.
func play(blow_strength: float = 1.0, shake_camera: Camera3D = null, tint: Color = T.GOLD_HI) -> bool:
	if not Common.cinematics_on():
		finished.emit()
		queue_free()
		return false
	strength = clampf(blow_strength, 0.0, 1.0)
	camera = shake_camera
	if camera != null:
		_rest = Vector2(camera.h_offset, camera.v_offset)
	vignette = Common.make_vignette(0.0, tint)
	add_child(vignette)
	elapsed = 0.0
	playing = true
	visible = true
	_apply()
	return true

func _envelope() -> float:
	var u := clampf(elapsed / DURATION, 0.0, 1.0)
	return (1.0 - u) * (1.0 - u)

func advance(delta: float) -> void:
	if not playing:
		return
	elapsed += delta
	if elapsed >= DURATION:
		finish()
		return
	_apply()

func _apply() -> void:
	var e := _envelope() * strength
	var flash := 0.25 if Common.reduce_motion() else 0.55
	(vignette.material as ShaderMaterial).set_shader_parameter("strength", e * flash)
	if camera != null and is_instance_valid(camera) and not Common.reduce_motion():
		var t := elapsed * 70.0
		camera.h_offset = _rest.x + sin(t * 1.3) * SHAKE_PIXELS * e
		camera.v_offset = _rest.y + cos(t * 1.7) * SHAKE_PIXELS * e

func finish() -> void:
	if not playing:
		return
	playing = false
	if camera != null and is_instance_valid(camera):
		camera.h_offset = _rest.x
		camera.v_offset = _rest.y
	finished.emit()
	queue_free()

func _process(delta: float) -> void:
	advance(delta)

func _exit_tree() -> void:
	if playing and camera != null and is_instance_valid(camera):
		camera.h_offset = _rest.x
		camera.v_offset = _rest.y
