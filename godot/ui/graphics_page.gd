class_name GraphicsPage
extends RefCounted
## "Graphics and cinematics" card on the Settings page: preset selector plus every individual toggle, all applied at once and persisted by
## GraphicsSettings. Rebuilt in place when a preset changes the toggles.
const Kit = preload("res://ui/theme/ui_kit.gd")
const G = preload("res://ui/graphics_settings.gd")

static func build(parent: Container) -> void:
	var card := Kit.card(parent)
	card.name = "GraphicsCard"
	_fill(card)

static func _fill(card: VBoxContainer) -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	Kit.section_header(card, "Graphics and cinematics", "gear")
	Kit.label(card, "Quality preset")
	var presets := Kit.segmented(card, [["low", "Low"], ["medium", "Medium"], ["high", "High"], ["ultra", "Ultra"]], G.preset if G.preset != "custom" else "", func(value):
		G.set_preset(value)
		_fill.call_deferred(card))
	presets.name = "GraphicsPreset"
	Kit.muted(card, "Current: %s%s. Every setting below can be changed on its own." % [G.PRESET_NAMES[G.preset], " (your own mix)" if G.preset == "custom" else ""])
	_toggle(card, "Particles", "particles", "Embers, flame and smoke effects.")
	_toggle(card, "Light shafts", "light_shafts", "Soft beams of light through the fog.")
	_toggle(card, "Fog", "fog", "Atmospheric haze in the castle courtyard.")
	_toggle(card, "Bloom", "bloom", "Glow around torches and bright metal.")
	_toggle(card, "Ambient occlusion (SSAO)", "ssao", "Contact shadows. Needs the Forward+ renderer; has no effect on this build's Compatibility renderer." if not G.renderer_supports("ssao") else "Contact shadows in crevices.")
	Kit.label(card, "Shadow quality")
	Kit.segmented(card, [["off", "Off"], ["low", "Low"], ["medium", "Medium"], ["high", "High"]], G.shadows, func(v): G.set_value("shadows", v)).name = "ShadowQuality"
	Kit.label(card, "Anti-aliasing")
	Kit.segmented(card, [["off", "Off"], ["fxaa", "FXAA"], ["msaa", "MSAA"], ["taa", "TAA"]], G.aa, func(v): G.set_value("aa", v)).name = "AntiAliasing"
	if not G.renderer_supports("aa_taa"):
		Kit.muted(card, "TAA needs the Forward+ renderer; on this build it falls back to no anti-aliasing.")
	Kit.label(card, "Resolution scale")
	Kit.slider_row(card, "3D resolution", G.res_scale, 0.5, 1.0, 0.05, func(v): G.set_value("res_scale", v), func(v): return "%d%%" % roundi(v * 100.0))
	Kit.label(card, "Frame rate limit")
	Kit.segmented(card, [[0, "Unlimited"], [30, "30"], [60, "60"], [120, "120"], [144, "144"]], G.fps_cap, func(v): G.set_value("fps_cap", v)).name = "FpsCap"
	_toggle(card, "VSync", "vsync", "Matches the monitor refresh; removes tearing.")
	_toggle(card, "Cinematics", "cinematics", "Short, skippable intro, finishing-blow and victory moments. Never changes gameplay timing.")
	var fps := Kit.toggle_row(card, "Show FPS (F3)", G.show_fps, func(on): G.set_value("show_fps", on), "Frame rate and frame time in the top-left corner.")
	fps.name = "ShowFps"

static func _toggle(card: Container, title: String, key: String, hint: String) -> void:
	var row := Kit.toggle_row(card, title, bool(G.current()[key]), func(on): G.set_value(key, on), hint)
	row.name = "Toggle_" + key
