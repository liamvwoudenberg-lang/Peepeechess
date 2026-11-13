extends SceneTree
## Design-system checks: contrast, theme coverage, preferences, kit helpers, HUD maths, touch targets, audio hook.
const T = preload("res://ui/theme/ui_tokens.gd")
const PeepeeTheme = preload("res://ui/theme/peepee_theme.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
const Audio = preload("res://ui/theme/ui_audio.gd")
const Hud = preload("res://ui/game_hud.gd")
const Settings = preload("res://ui/application_settings.gd")
const SettingsPage = preload("res://ui/settings_page.gd")
const AppScene = preload("res://ui/application.tscn")
const MainScene = preload("res://app/main.tscn")
const Results = preload("res://ui/results.gd")
var checks := 0
var failures: Array = []

func expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func run() -> void:
	Settings.loaded = true
	Prefs.path = "user://ui_theme_test.cfg"
	Prefs.loaded = true
	Prefs.reset_defaults()
	contrast()
	theme_coverage()
	await prefs_checks()
	await kit_checks()
	hud_checks()
	touch_checks()
	await settings_checks()
	await hud_scene_checks()
	await results_checks()
	if FileAccess.file_exists("user://ui_theme_test.cfg"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://ui_theme_test.cfg"))
	Settings.sign_out()
	Audio.shutdown()
	print("UI theme: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func contrast() -> void:
	expect(is_equal_approx(T.contrast(Color.BLACK, Color.WHITE), 21.0), "contrast of black on white is 21:1")
	expect(is_equal_approx(T.contrast(Color.WHITE, Color.WHITE), 1.0), "contrast of a colour with itself is 1:1")
	for pair in T.TEXT_PAIRS:
		var ratio: float = T.contrast(pair[1], pair[2])
		expect(ratio >= 4.5, "%s has contrast %.2f (>= 4.5 required)" % [pair[0], ratio])
	# decorative / large-text-only colours still meet the 3:1 large-text threshold
	for pair in [["TEXT_DIM on BG", T.TEXT_DIM, T.BG], ["TEXT_DIM on SURFACE", T.TEXT_DIM, T.SURFACE], ["GOLD_LO on BG", T.GOLD_LO, T.BG]]:
		expect(T.contrast(pair[1], pair[2]) >= 3.0, pair[0] + " meets 3:1 for large text")
	# focus ring against the surfaces it sits on (WCAG non-text contrast 3:1)
	for surface in [T.BG, T.SURFACE, T.SURFACE_2, T.SURFACE_3]:
		expect(T.contrast(T.GOLD_HI, surface) >= 3.0, "focus ring colour is visible on a surface (%.2f)" % T.contrast(T.GOLD_HI, surface))
	# colour-blind pair differs strongly in luminance, not only hue
	expect(absf(T.luminance(T.CB_MOVE) - T.luminance(T.CB_CAPTURE)) > 0.1, "colour-blind-safe highlight pair differs in luminance")

func theme_coverage() -> void:
	var theme := PeepeeTheme.build()
	var variations := {"Button": ["PrimaryButton", "DangerButton", "GhostButton", "NavButton", "NavButtonActive", "SegButton", "CardToggle", "IconButton"], "PanelContainer": ["CardPanel", "RaisedPanel", "SelectedPanel", "HudPanel", "InsetPanel", "BannerPanel", "DangerPanel", "ToastPanel", "PlayerCard", "PlayerCardActive", "CheckPanel", "ResultPanel", "TopBarPanel"], "Label": ["H1", "H2", "H3", "Muted", "Caption", "Accent", "DangerLabel", "SuccessLabel", "ClockLabel", "Wordmark"]}
	for base in variations:
		for variation in variations[base]:
			expect(theme.get_type_variation_base(variation) == base, "%s is a %s variation" % [variation, base])
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		for type_name in ["Button", "OptionButton", "PrimaryButton", "DangerButton", "SegButton", "CheckBox", "CheckButton"]:
			expect(theme.has_stylebox(state, type_name), "%s has a %s stylebox" % [type_name, state])
	for pair in [["LineEdit", "normal"], ["LineEdit", "focus"], ["TextEdit", "normal"], ["HSlider", "slider"], ["HSlider", "grabber_area"], ["TabContainer", "tab_selected"], ["TabContainer", "panel"], ["VScrollBar", "grabber"], ["HScrollBar", "scroll"], ["PopupMenu", "panel"], ["PopupMenu", "hover"], ["AcceptDialog", "panel"], ["Window", "embedded_border"], ["PanelContainer", "panel"], ["TooltipPanel", "panel"], ["ProgressBar", "fill"]]:
		expect(theme.has_stylebox(pair[1], pair[0]), "theme styles %s / %s" % pair)
	for pair in [["CheckButton", "checked"], ["CheckButton", "unchecked"], ["CheckBox", "checked"], ["CheckBox", "unchecked"], ["HSlider", "grabber"], ["OptionButton", "arrow"], ["Window", "close"]]:
		var icon := theme.get_icon(pair[1], pair[0])
		expect(icon != null and icon.get_width() > 4, "theme icon %s / %s is rasterised" % pair)
	var focus := theme.get_stylebox("focus", "Button") as StyleBoxFlat
	expect(focus.border_width_left >= T.FOCUS_RING and focus.bg_color.a == 0.0, "button focus is a transparent-filled ring of at least 3 px")
	# applies to every control type: a themed host resolves the shared look
	var host := Control.new()
	host.theme = theme
	root.add_child(host)
	var types := {"Button": Button.new(), "OptionButton": OptionButton.new(), "CheckBox": CheckBox.new(), "CheckButton": CheckButton.new(), "LineEdit": LineEdit.new(), "TextEdit": TextEdit.new(), "HSlider": HSlider.new(), "TabContainer": TabContainer.new(), "VScrollBar": VScrollBar.new(), "ProgressBar": ProgressBar.new(), "Label": Label.new(), "RichTextLabel": RichTextLabel.new(), "PanelContainer": PanelContainer.new(), "SpinBox": SpinBox.new(), "MenuButton": MenuButton.new(), "ItemList": ItemList.new()}
	for name in types:
		var node: Control = types[name]
		host.add_child(node)
		expect(node.get_theme_font_size("font_size") > 0 or node is ScrollBar or node is Slider or node is PanelContainer or node is TabContainer or node is ProgressBar, name + " resolves a font size from the shared theme")
		expect(node.get_theme_color("font_color") != Color(), name + " resolves a text colour") if name in ["Button", "Label", "LineEdit", "CheckBox"] else null
	expect(types["Button"].get_theme_stylebox("normal") == theme.get_stylebox("normal", "Button"), "Button inherits the shared normal style")
	var primary := Button.new()
	primary.theme_type_variation = "PrimaryButton"
	host.add_child(primary)
	expect(primary.get_theme_color("font_color") == T.TEXT_ON_GOLD, "primary button uses dark text on gold")
	host.queue_free()

func prefs_checks() -> void:
	Prefs.reset_defaults()
	expect(Prefs.ui_scale == 1.0 and not Prefs.reduce_motion and not Prefs.colorblind, "defaults: 100 % scale, motion on, standard highlights")
	Prefs.set_ui_scale(1.37)
	expect(is_equal_approx(Prefs.ui_scale, 1.35), "UI scale snaps to 5 % steps")
	Prefs.set_ui_scale(5.0)
	expect(Prefs.ui_scale == Prefs.MAX_SCALE, "UI scale clamps to 150 %")
	Prefs.set_ui_scale(0.1)
	expect(Prefs.ui_scale == Prefs.MIN_SCALE, "UI scale clamps to 80 %")
	Prefs.scale_auto = false
	Prefs.set_ui_scale(1.25)
	expect(is_equal_approx(root.content_scale_factor, 1.25), "UI scale applies to the window immediately")
	Prefs.set_reduce_motion(true)
	Prefs.set_colorblind(true)
	Prefs.sfx_volume = 0.4
	Prefs.ui_volume = 0.6
	Prefs.apply()
	expect(Prefs.save_preferences() == OK, "preferences save")
	var mix: Dictionary = Engine.get_meta("ui_mix", {})
	expect(is_equal_approx(float(mix.get("sfx", 1.0)), 0.4), "mixer levels are published for the combat audio layer")
	Prefs.reset_defaults()
	Prefs.load_preferences(true)
	expect(is_equal_approx(Prefs.ui_scale, 1.25) and Prefs.reduce_motion and Prefs.colorblind and is_equal_approx(Prefs.sfx_volume, 0.4) and is_equal_approx(Prefs.ui_volume, 0.6), "UI scale, reduce motion, colour-blind and mixer levels persist across a reload")
	expect(Prefs.move_highlight(Color.GREEN) == T.CB_MOVE and Prefs.capture_highlight(Color.RED) == T.CB_CAPTURE, "colour-blind option swaps board highlight colours")
	Prefs.reset_defaults()
	Prefs.apply()
	expect(root.content_scale_factor == 1.0 and Prefs.move_highlight(Color.GREEN) == Color.GREEN, "reset restores 100 % and normal highlights")
	Prefs.save_preferences()
	# a notified listener sees changes
	var seen := [0]
	var listener := func(): seen[0] += 1
	Prefs.add_listener(listener)
	Prefs.set_reduce_motion(true)
	Prefs.set_reduce_motion(false)
	expect(seen[0] == 2, "listeners are notified when settings change")
	Prefs.remove_listener(listener)
	Prefs.reset_defaults()
	Prefs.apply()
	await settle(1)

func touch_checks() -> void:
	# 420 dpi phone showing 2400x1080: the auto scale is capped at 150 %, targets grow to reach 44 dp
	var window := Vector2(2400, 1080)
	var scale := Prefs.recommended_scale(420.0, window)
	expect(scale >= 1.0 and scale <= Prefs.MAX_SCALE, "recommended scale stays within 100..150 %")
	var effective := Prefs.base_stretch(window) * scale
	var target := Prefs.touch_target(420.0, effective)
	var dp := target * effective * 160.0 / 420.0
	expect(dp >= 44.0 or target == 96, "touch target measures >= 44 dp (%.1f dp)" % dp)
	expect(Prefs.recommended_scale(160.0, Vector2(1280, 800)) == 1.0, "a desktop-density screen keeps 100 %")
	expect(Prefs.touch_target(0.0, 1.0) == 48, "unknown density falls back to 48 px targets")
	Kit.force_touch = true
	var button := Kit.button(root, "Touch", Callable())
	expect(button.custom_minimum_size.y >= 48.0, "buttons are at least 48 px tall on touch devices")
	button.queue_free()
	Kit.force_touch = false
	var pointer := Kit.button(root, "Pointer", Callable())
	expect(pointer.custom_minimum_size.y >= 40.0, "buttons are at least 40 px tall with a pointer")
	pointer.queue_free()

func kit_checks() -> void:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	Kit.install(host)
	expect(host.theme != null and host.get_node_or_null("UiInteract") != null, "Kit.install applies the theme and the interaction hook")
	var column := VBoxContainer.new()
	host.add_child(column)
	var chosen := []
	var seg := Kit.segmented(column, [["a", "A"], ["b", "B"], ["c", "C"]], "b", func(v): chosen.append(v))
	expect(seg.get_meta(&"value") == "b", "segmented control starts on the given value")
	(seg.get_child(2) as Button).button_pressed = true
	expect(seg.get_meta(&"value") == "c" and chosen == ["c"], "segmented control reports a change once")
	var slider := Kit.slider_row(column, "Vol", 0.5, 0.0, 1.0, 0.05, Callable())
	slider.value = 0.8
	expect((slider.get_meta(&"readout") as Label).text == "80%", "slider shows a live value read-out")
	var toggled := [false]
	var toggle := Kit.toggle_row(column, "T", false, func(on): toggled[0] = on)
	toggle.button_pressed = true
	expect(toggled[0], "toggle row reports changes")
	var state := Kit.empty_state(column, "trophy", "Nothing", "Detail", "Go", Callable())
	expect(state.get_parent() is PanelContainer, "empty state is a card")
	var err := Kit.error_state(column, "Boom", "Retry", Callable())
	expect(err != null, "error state builds")
	var loading := Kit.loading_state(column, "Loading")
	expect(loading != null, "loading state builds")
	var disabled := Kit.secondary(column, "Do it")
	Kit.disable_with_reason(disabled, "Sign in first")
	expect(disabled.disabled and disabled.tooltip_text == "Sign in first", "disabled buttons carry a reason")
	var asked := [false]
	var dialog := Kit.confirm(host, "Sure?", "Really?", "Yes", func(): asked[0] = true, true)
	await settle(2)
	expect(dialog.visible and dialog.get_ok_button().theme_type_variation == "DangerButton", "confirm dialog opens with a danger action")
	dialog.get_ok_button().pressed.emit()
	await settle(2)
	expect(asked[0], "confirm dialog calls back and frees itself")
	var modal := Kit.modal(host, "Info", func(body): Kit.label(body, "Hello"))
	await settle(2)
	expect(modal.visible, "modal dialog opens")
	modal.hide()
	modal.queue_free()
	var panel := Kit.toast(host, "Saved", "success")
	await settle(2)
	expect(panel != null and host.get_node_or_null("ToastLayer") != null, "toast layer is created on demand")
	# animated title background: runs only on the title screen, only with motion on, and stops when hidden
	var back = load("res://ui/theme/backdrop.gd").new()
	host.add_child(back)
	back.mode = "home"
	Prefs.reduce_motion = false
	await settle(2)
	expect(back.is_processing(), "title background animates when motion is on")
	Prefs.set_reduce_motion(true)
	expect(not back.is_processing(), "reduce motion stops the animated background")
	Prefs.set_reduce_motion(false)
	expect(back.is_processing(), "...and turning it off again resumes it")
	back.hide()
	expect(not back.is_processing(), "a hidden background does not animate")
	back.show()
	back.mode = "page"
	expect(not back.is_processing(), "ordinary pages use a static background")
	# every icon rasterises and unknown names do not crash
	for kind in Icons.KINDS + Icons.PIECES:
		expect(Icons.texture(kind, 32).get_width() == 32, "icon %s rasterises" % kind)
	expect(Icons.texture("no-such-icon", 16) != null, "an unknown icon name gives a placeholder")
	# audio hook is optional and clean up after itself
	Audio.force = true
	var audio := Audio.attach(host)
	expect(audio != null, "UI audio hook attaches the combat UI sounds")
	Audio.set_enabled(host, false)
	expect(not Prefs.ui_sounds, "UI sounds can be switched off")
	Prefs.ui_sounds = true
	Audio.force = false
	Audio.shutdown()
	host.queue_free()
	await settle(3)

func hud_checks() -> void:
	var start := Hud.captured_from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
	expect(start.w.is_empty() and start.b.is_empty() and start.balance == 0, "start position: nothing captured, balanced")
	var down := Hud.captured_from_fen("rnbqkbnr/ppp1pppp/8/8/8/8/PPPPPPPP/RNB1KBNR w KQkq - 0 1")
	expect(down.b.get("p", 0) == 1 and down.w.get("q", 0) == 1 and down.balance == -8, "captured pieces and material balance are derived from the FEN")
	var promoted := Hud.captured_from_fen("4k3/8/8/8/8/8/8/QQ2K3 w - - 0 1")
	expect(promoted.w.get("q", 0) == 0 and promoted.balance > 0, "promotion never yields negative captured counts")

func settings_checks() -> void:
	Settings.intro_seen = true   # these checks start on a page, not on the opening screen
	Prefs.reset_defaults()
	Settings.quality = "balanced"
	Settings.animations = true
	root.size = Vector2i(1280, 800)
	var shell: Control = AppScene.instantiate()
	root.add_child(shell)
	await settle(2)
	shell.navigate("settings")
	await settle(2)
	var preset := shell.find_child("QualityPreset", true, false)
	expect(preset != null, "settings page has a graphics preset control")
	(preset.get_child(0) as Button).button_pressed = true
	expect(Settings.quality == "low", "graphics preset Low sets the existing quality setting")
	(preset.get_child(2) as Button).button_pressed = true
	expect(Settings.quality == "high", "graphics preset High sets the existing quality setting")
	var master := shell.find_child("MasterVolume", true, false) as HSlider
	master.value = 0.35
	expect(is_equal_approx(Settings.volume, 0.35) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), 0.35), "master volume slider is applied to the Master bus immediately")
	var effects := shell.find_child("EffectsVolume", true, false) as HSlider
	effects.value = 0.5
	expect(is_equal_approx(Prefs.sfx_volume, 0.5), "effects slider updates the mixer level")
	var motion := shell.find_child("ReduceMotion", true, false) as CheckButton
	motion.button_pressed = true
	expect(Prefs.reduce_motion, "reduce motion toggle applies")
	var colour := shell.find_child("ColorblindHighlights", true, false) as CheckButton
	colour.button_pressed = true
	expect(Prefs.colorblind, "colour-blind toggle applies")
	var scale_slider := shell.find_child("UiScale", true, false) as HSlider
	scale_slider.value = 1.3
	scale_slider.drag_ended.emit(true)
	expect(is_equal_approx(root.content_scale_factor, 1.3) and is_equal_approx(Prefs.ui_scale, 1.3), "UI scale slider applies the window scale on release")
	var anim := shell.find_child("PieceAnimations", true, false) as CheckButton
	anim.button_pressed = false
	expect(not Settings.animations, "piece animation toggle applies")
	var config := ConfigFile.new()
	expect(config.load("user://preferences.cfg") == OK and str(config.get_value("presentation", "quality")) == "high" and config.get_value("presentation", "animations") == false, "settings persist to preferences.cfg")
	var ui_config := ConfigFile.new()
	expect(ui_config.load("user://ui_theme_test.cfg") == OK and ui_config.get_value("ui", "reduce_motion") == true and ui_config.get_value("ui", "colorblind") == true, "interface settings persist to the UI preferences file")
	# reset to defaults (immediate and persisted)
	SettingsPage.reset_defaults()
	expect(Settings.quality == "balanced" and Settings.animations and Settings.volume == 0.8 and not Prefs.reduce_motion and root.content_scale_factor == 1.0, "reset restores graphics, audio and interface defaults")
	shell.queue_free()
	await settle(3)

func hud_scene_checks() -> void:
	Prefs.reduce_motion = true
	Settings.launch = {"mode": "classic", "initialMs": 600000, "incrementMs": 0, "view3d": false}
	var game: Control = MainScene.instantiate()
	root.add_child(game)
	await settle(3)
	expect(game.hud.has("banner") and game.clock_white != null and game.clock_black != null, "chess HUD exposes banner and both clocks")
	var banner: PanelContainer = game.hud["banner"]
	expect(banner.theme_type_variation == "InsetPanel", "turn banner is neutral at the start")
	game.game.new_game(0, 0, "4k3/8/8/8/8/8/4R3/4K3 b - - 0 1")
	await settle(2)
	expect(banner.theme_type_variation == "CheckPanel" and game.status_label.text.begins_with("Check"), "check is announced with a check banner")
	expect(game.hud["card_b"].theme_type_variation == "PlayerCardActive" and game.hud["card_w"].theme_type_variation == "PlayerCard", "the side to move is highlighted")
	game.game.new_game(0, 0, "R5k1/5ppp/8/8/8/8/8/6K1 b - - 0 1")
	await settle(2)
	expect(banner.theme_type_variation == "ResultPanel" and game.status_label.text.contains("White wins"), "checkmate is announced with a result banner")
	for d in game.find_children("*", "AcceptDialog", true, false):
		if not (d is ConfirmationDialog):
			d.hide()
			d.queue_free()
	await settle(2)
	var flipped_before: int = game.hud["card_w"].get_index()
	game.set_flipped(true)
	expect(game.hud["card_w"].get_index() != flipped_before, "flipping the board swaps the player cards")
	# resign confirmation is a themed danger dialog
	game.game.new_game(600000, 0)
	game._confirm_resign()
	await settle(2)
	var dialogs := game.find_children("*", "ConfirmationDialog", true, false)
	expect(dialogs.size() >= 1 and (dialogs[-1] as ConfirmationDialog).get_ok_button().theme_type_variation == "DangerButton", "resign asks for confirmation with a danger button")
	(dialogs[-1] as ConfirmationDialog).get_cancel_button().pressed.emit()
	await settle(2)
	# rejected move => toast
	game._reject("That move is not legal.")
	await settle(2)
	expect(game.get_node_or_null("ToastLayer") != null and game.message_label.text == "That move is not legal.", "rejected input produces a status line and a toast")
	# promotion dialog buttons carry piece icons
	var icons := 0
	for button in game.promotion_dialog.find_children("*", "Button", true, false):
		if (button as Button).icon != null:
			icons += 1
	expect(icons == 4, "promotion dialog shows four piece buttons with icons")
	game.queue_free()
	await settle(3)

func results_checks() -> void:
	root.size = Vector2i(1280, 800)
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(host)
	Kit.install(host)
	var reviewed := [false]
	var dialog := Results.show_dialog(host, {"result": "1-0", "reason": "checkmate", "mode": "classic", "plies": 41}, func(): reviewed[0] = true, func(): pass)
	await settle(2)
	expect(dialog.visible and dialog.size.y < 500, "result dialog is compact (%d px tall)" % dialog.size.y)
	dialog.get_ok_button().pressed.emit()
	await settle(2)
	expect(reviewed[0], "result dialog Review board calls back")
	host.queue_free()
	await settle(3)
