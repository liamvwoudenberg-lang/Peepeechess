extends SceneTree
## Headless: presets round-trip, a single toggle makes the preset "custom", invalid values are ignored, nothing throws.
func _initialize() -> void:
	var bad := 0
	for name in GraphicsSettings.PRESET_ORDER:
		GraphicsSettings.set_preset_silent(name)
		if GraphicsSettings.detect_preset() != name:
			bad += 1
			print("FAIL preset ", name)
	GraphicsSettings.set_preset_silent("high")
	GraphicsSettings._assign("fog", false)
	if GraphicsSettings.detect_preset() != "custom":
		bad += 1
		print("FAIL custom")
	GraphicsSettings._assign("aa", "bogus")
	GraphicsSettings._assign("res_scale", 9.0)
	if GraphicsSettings.aa == "bogus" or GraphicsSettings.res_scale > 1.0:
		bad += 1
		print("FAIL clamp")
	GraphicsSettings.apply()
	print("graphics_settings: ", "OK" if bad == 0 else "FAILED %d" % bad)
	quit(bad)
