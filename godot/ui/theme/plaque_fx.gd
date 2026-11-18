class_name PlaqueFx
extends Control
## Glow and drifting teal wisps around a plaque button that is selected (hovered, focused, or a chosen / primary button). A child of the
## button, drawn behind it, never intercepts the mouse. Purely cosmetic UI: it reads the button's state and never touches game state or
## the duel simulation. Reduce-motion and the "particles" graphics setting turn the wisps off (the halo stays, without pulsing).
##
##   PlaqueFx.sync(button)   creates / updates / removes the effect from the button's current state (called by UiInteract).
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const PLATE_VARIATIONS := ["", "PrimaryButton", "SegButton", "NavButtonActive", "DangerButton"]
const SELECTED_VARIATIONS := ["PrimaryButton", "NavButtonActive"]
const MAX_PARTICLES_HOVER := 16
const MAX_PARTICLES_SELECTED := 9
const HALO := Color("62e6d8")

static var _dot: ImageTexture

var target: BaseButton
var intensity := 0.0        # 0 = off, 1 = hovered / focused, ~0.5 = selected at rest
var _t := 0.0
var _particles: CPUParticles2D
var _halo := StyleBoxFlat.new()


## True when this button is a plaque that should glow (ghost, icon and nav buttons are flat and never do).
static func is_plaque(button: BaseButton) -> bool:
	return button.get_class() == "Button" and String(button.theme_type_variation) in PLATE_VARIATIONS


static func wanted_intensity(button: BaseButton) -> float:
	if button.disabled or not button.is_visible_in_tree():
		return 0.0
	if button.is_hovered() or button.has_focus():
		return 1.0
	if String(button.theme_type_variation) in SELECTED_VARIATIONS or (button.toggle_mode and button.button_pressed):
		return 0.5
	return 0.0


static func sync(button: BaseButton) -> void:
	if not is_instance_valid(button) or not is_plaque(button):
		return
	var want := wanted_intensity(button)
	var fx := button.get_node_or_null("PlaqueFx") as PlaqueFx
	if want <= 0.0:
		if fx != null:
			fx.queue_free()
		return
	if fx == null:
		fx = PlaqueFx.new()
		fx.name = "PlaqueFx"
		fx.target = button
		button.add_child(fx)
	fx.set_intensity(want)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_halo.bg_color = Color(0, 0, 0, 0)
	_halo.set_corner_radius_all(14)


func _ready() -> void:
	resized.connect(_layout_particles)
	_layout_particles()


func set_intensity(value: float) -> void:
	intensity = value
	var motion := not Prefs.reduce_motion and GraphicsSettings.particles
	if motion and _particles == null:
		_make_particles()
	if _particles != null:
		_particles.amount = MAX_PARTICLES_HOVER if value >= 1.0 else MAX_PARTICLES_SELECTED
		_particles.emitting = motion
	set_process(motion)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if intensity <= 0.0:
		return
	var pulse := 1.0 if (Prefs.reduce_motion or not GraphicsSettings.particles) else 0.82 + 0.18 * sin(_t * 2.6)
	var a := 0.34 * intensity * pulse
	_halo.shadow_color = Color(HALO.r, HALO.g, HALO.b, a)
	_halo.shadow_size = roundi(10.0 + 12.0 * intensity)
	draw_style_box(_halo, Rect2(Vector2(2, 2), size - Vector2(4, 4)))


func _layout_particles() -> void:
	if _particles != null:
		_particles.position = size * 0.5
		_particles.emission_rect_extents = size * 0.5 - Vector2(2, 2)


func _make_particles() -> void:
	_particles = CPUParticles2D.new()
	_particles.local_coords = false
	_particles.lifetime = 1.9
	_particles.preprocess = 0.8
	_particles.explosiveness = 0.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.direction = Vector2(0, -1)
	_particles.spread = 38.0
	_particles.gravity = Vector2(0, -16)
	_particles.initial_velocity_min = 4.0
	_particles.initial_velocity_max = 14.0
	_particles.scale_amount_min = 0.7
	_particles.scale_amount_max = 1.5
	_particles.texture = _soft_dot()
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	ramp.colors = PackedColorArray([Color(0.75, 1.0, 0.97, 0.0), Color(0.45, 0.95, 0.88, 0.85), Color(0.25, 0.7, 0.8, 0.0)])
	_particles.color_ramp = ramp
	add_child(_particles)
	_layout_particles()


static func _soft_dot() -> ImageTexture:
	if _dot == null:
		var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for y in 16:
			for x in 16:
				var r := Vector2(x - 7.5, y - 7.5).length() / 8.0
				image.set_pixel(x, y, Color(1, 1, 1, clampf(1.0 - r, 0.0, 1.0) * 1.0))
		_dot = ImageTexture.create_from_image(image)
	return _dot
