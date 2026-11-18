extends SceneTree
## Gothic plaque buttons: the theme gives every plaque type a 9-slice texture style in all four states, the art is deterministic and cheap to
## generate, text stays readable on the interior, and the glow / wisp effect appears for hover, focus and selected buttons only, with
## reduce-motion and the particles setting turning the wisps off.
const GP = preload("res://ui/theme/gothic_plaque.gd")
const Fx = preload("res://ui/theme/plaque_fx.gd")
const PeepeeTheme = preload("res://ui/theme/peepee_theme.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const T = preload("res://ui/theme/ui_tokens.gd")
var checks = 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_usec()
	var theme: Theme = PeepeeTheme.build(1.0)
	var build_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("  theme build with plaque art: %.0f ms" % build_ms)
	for type_name in ["Button", "PrimaryButton", "SegButton", "NavButtonActive", "DangerButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			expect(theme.get_stylebox(state, type_name) is StyleBoxTexture, "%s %s is a plaque texture style" % [type_name, state])
	expect(theme.get_stylebox("normal", "GhostButton") is StyleBoxFlat, "ghost buttons stay flat (not plaques)")
	# deterministic: the same variant and state always renders the same pixels
	var a: Image = GP._render(GP.VARIANTS["plate"], "normal")
	var b: Image = GP._render(GP.VARIANTS["plate"], "normal")
	expect(a.get_data() == b.get_data(), "plaque art is deterministic")
	expect(a.get_pixel(0, 0).a < 0.2 and a.get_pixel(GP.SIZE / 2, GP.SIZE / 2).a > 0.99, "corners are cut (transparent), the interior is opaque")
	expect(build_ms < 1500.0, "generating all plaque art is cheap (%.0f ms)" % build_ms)
	# readability: label colours against the interior colours of their variant (>= 4.5:1)
	for variant in GP.VARIANTS:
		var p: Dictionary = GP.VARIANTS[variant]
		for key in ["text", "text_hover"]:
			for fill in ["fill_top", "fill_bot"]:
				var ratio: float = T.contrast(p[key], p[fill])
				expect(ratio >= 4.5, "%s %s on %s has contrast %.1f (>= 4.5)" % [variant, key, fill, ratio])
	# effects
	var host := Control.new()
	host.theme = theme
	root.add_child(host)
	var plain := Button.new()
	plain.text = "Plain"
	var primary := Button.new()
	primary.text = "Primary"
	primary.theme_type_variation = "PrimaryButton"
	var ghost := Button.new()
	ghost.text = "Ghost"
	ghost.theme_type_variation = "GhostButton"
	var chip := Button.new()
	chip.text = "Chip"
	chip.theme_type_variation = "SegButton"
	chip.toggle_mode = true
	for button in [plain, primary, ghost, chip]:
		host.add_child(button)
	await process_frame
	for button in [plain, primary, ghost, chip]:
		Fx.sync(button)
	expect(plain.get_node_or_null("PlaqueFx") == null, "a resting plain plaque has no glow")
	expect(primary.get_node_or_null("PlaqueFx") != null, "a primary button glows at rest (it is the selected action)")
	expect(ghost.get_node_or_null("PlaqueFx") == null, "flat ghost buttons never glow")
	chip.button_pressed = true
	Fx.sync(chip)
	expect(chip.get_node_or_null("PlaqueFx") != null, "a chosen chip glows")
	plain.grab_focus()
	Fx.sync(plain)
	await process_frame
	var fx := plain.get_node_or_null("PlaqueFx") as PlaqueFx
	expect(fx != null and fx.intensity >= 1.0, "a focused plaque glows fully")
	expect(fx != null and fx.mouse_filter == Control.MOUSE_FILTER_IGNORE, "the effect never takes the mouse")
	var emitting_on := fx != null and fx.get_child_count() > 0 and (fx.get_child(0) as CPUParticles2D).emitting
	expect(emitting_on, "wisps emit while focused")
	var saved := Prefs.reduce_motion
	Prefs.reduce_motion = true
	fx.set_intensity(1.0)
	expect(not (fx.get_child(0) as CPUParticles2D).emitting, "reduce-motion stops the wisps")
	Prefs.reduce_motion = saved
	plain.release_focus()
	Fx.sync(plain)
	await process_frame
	expect(not is_instance_valid(plain.get_node_or_null("PlaqueFx")) or plain.get_node("PlaqueFx").is_queued_for_deletion(), "the glow goes away with the focus")
	print("GOTHIC STYLE: ", checks, " checks; failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
