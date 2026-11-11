class_name MorphFx
extends Node3D
## One pooled flash + dust burst, used when a chess piece morphs into a fighter (and back). Nodes are
## created once; play() only restarts them, so repeated captures allocate nothing.

const W := preload("res://world/world_constants.gd")
const DURATION := 0.5

var playing := false
var _time := DURATION
var _light: OmniLight3D
var _flash: MeshInstance3D
var _flash_material: StandardMaterial3D
var _dust: CPUParticles3D


func _init() -> void:
	name = "MorphFx"
	visible = false
	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.light_energy = 0.0
	_light.light_cull_mask = W.LAYER_CHAMBER | W.LAYER_BOARD
	add_child(_light)
	_flash = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_flash.mesh = sphere
	_flash_material = StandardMaterial3D.new()
	_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_material.albedo_color = Color(1, 0.9, 0.6, 0.0)
	_flash.material_override = _flash_material
	_flash.layers = W.LAYER_CHAMBER | W.LAYER_BOARD
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flash)
	_dust = CPUParticles3D.new()
	_dust.one_shot = true
	_dust.emitting = false
	_dust.amount = 18
	_dust.lifetime = 0.7
	_dust.explosiveness = 0.95
	_dust.direction = Vector3(0, 1, 0)
	_dust.spread = 80.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.6
	_dust.gravity = Vector3(0, -2.0, 0)
	_dust.scale_amount_min = 0.7
	_dust.scale_amount_max = 1.4
	var puff := SphereMesh.new()
	puff.radius = 0.07
	puff.height = 0.14
	puff.radial_segments = 6
	puff.rings = 3
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color(0.62, 0.58, 0.5, 0.8)
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = puff_material
	_dust.mesh = puff
	_dust.layers = W.LAYER_CHAMBER | W.LAYER_BOARD
	add_child(_dust)


func set_low_quality(low: bool) -> void:
	_dust.amount = 8 if low else 18


## `pos` is in this node's parent frame.
func play(pos: Vector3, color: Color = Color(1, 0.9, 0.6)) -> void:
	position = pos
	visible = true
	playing = true
	_time = 0.0
	_flash_material.albedo_color = Color(color.r, color.g, color.b, 0.0)
	_light.light_color = color
	_dust.restart()
	_dust.emitting = true
	_step()


func stop() -> void:
	playing = false
	_time = DURATION
	_light.light_energy = 0.0
	_flash_material.albedo_color.a = 0.0
	_dust.emitting = false
	visible = false


func advance(dt: float) -> void:
	if not playing:
		return
	_time += dt
	_step()
	if _time >= DURATION * 1.5:
		stop()


func _step() -> void:
	var u := clampf(_time / DURATION, 0.0, 1.0)
	var pulse := sin(u * PI)
	_flash.scale = Vector3.ONE * (0.3 + 1.1 * u)
	_flash_material.albedo_color.a = 0.45 * pulse
	_light.light_energy = 6.0 * pulse
