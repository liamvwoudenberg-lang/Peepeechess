extends RefCounted
## Settings page: Graphics, Interface and accessibility, Audio, Controls, Account service. Every control applies at
## once and is persisted (application_settings.gd for presentation/volume, theme/ui_prefs.gd for UI scale, reduce
## motion, colour-blind highlights and the extra mixer levels). Built into app.content by SettingsPage.build(app).
const Settings = preload("res://ui/application_settings.gd")
const Kit = preload("res://ui/theme/ui_kit.gd")
const T = preload("res://ui/theme/ui_tokens.gd")
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const Audio = preload("res://ui/theme/ui_audio.gd")
const QUALITY_TEXT := {
	"low": "Low: 30 FPS, no antialiasing. Best for older phones and long battery life.",
	"balanced": "Medium: 60 FPS, 2x antialiasing. A good default for most devices.",
	"high": "High: uncapped frame rate, 4x antialiasing. Needs a capable GPU.",
}

static func _save() -> void:
	Settings.save_preferences()

static func build(app: Control) -> void:
	var content: VBoxContainer = app.content
	var heading := Kit.heading(content, "Make yourself at home.", "Presentation settings belong to this device. They never change the match rules or your opponent's camera.")
	app.title_label = heading[0]
	app.subtitle_label = heading[1]
	var columns := Kit.responsive(content, 980.0, T.S4)
	columns.name = "SettingsColumns"
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", T.S4)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", T.S4)
	columns.add_child(right)
	_graphics(app, left)
	_interface(app, left)
	_audio(app, right)
	_controls(app, right)
	_service(app, right)
	_footer(app, content)

static func _graphics(_app: Control, parent: Container) -> void:
	var card := Kit.card(parent)
	Kit.section_header(card, "Graphics", "gear")
	Kit.label(card, "Quality preset")
	var hint := Kit.muted(card, QUALITY_TEXT.get(Settings.quality, QUALITY_TEXT.balanced))
	var presets := Kit.segmented(card, [["low", "Low"], ["balanced", "Medium"], ["high", "High"]], Settings.quality, func(value):
		Settings.quality = value
		_save()
		hint.text = QUALITY_TEXT[value])
	presets.name = "QualityPreset"
	card.move_child(hint, presets.get_index() + 1)
	Kit.label(card, "Default board")
	var board := Kit.segmented(card, [[false, "2D (top-down)"], [true, "3D (orbit)"]], Settings.preferred_3d, func(value):
		Settings.preferred_3d = value
		_save())
	board.name = "BoardView"
	var animations := Kit.toggle_row(card, "Piece animations", Settings.animations, func(on):
		Settings.animations = on
		_save(), "Move and capture animations on the board.")
	animations.name = "PieceAnimations"
	var touch := Kit.toggle_row(card, "Touch combat controls", Settings.touch_controls, func(on):
		Settings.touch_controls = on
		_save(), "On-screen buttons for duels. Turn off when you play with a controller or keyboard.")
	touch.name = "TouchControls"

static func _interface(app: Control, parent: Container) -> void:
	var card := Kit.card(parent)
	Kit.section_header(card, "Interface and accessibility", "user")
	var show_auto := Kit.touch()
	var auto_toggle: CheckButton = null
	var scale_slider: HSlider = Kit.slider_row(card, "UI scale", Prefs.ui_scale, Prefs.MIN_SCALE, Prefs.MAX_SCALE, 0.05, Callable(), func(v): return "%d%%" % roundi(v * 100.0))
	scale_slider.name = "UiScale"
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.45
	scale_slider.add_child(timer)
	var commit := func():
		Prefs.scale_auto = false
		Prefs.set_ui_scale(scale_slider.value)
		Prefs.save_preferences()
	timer.timeout.connect(commit)
	scale_slider.value_changed.connect(func(_v): timer.start())   # debounced so dragging does not rescale under the pointer
	scale_slider.drag_ended.connect(func(changed): if changed: timer.stop(); commit.call())
	if show_auto:
		auto_toggle = Kit.toggle_row(card, "Automatic scale for this screen", Prefs.scale_auto, func(on):
			Prefs.scale_auto = on
			Prefs.apply()
			Prefs.save_preferences(), "Picks a readable size for your phone's density.")
		auto_toggle.name = "AutoScale"
	Kit.muted(card, "80 to 150 percent. Applies immediately to every screen.")
	var motion := Kit.toggle_row(card, "Reduce motion", Prefs.reduce_motion, func(on):
		Prefs.set_reduce_motion(on)
		Prefs.save_preferences(), "Skips screen transitions, slides and the animated menu background.")
	motion.name = "ReduceMotion"
	var colour := Kit.toggle_row(card, "Colour-blind-safe highlights", Prefs.colorblind, func(on):
		Prefs.set_colorblind(on)
		Prefs.save_preferences(), "Blue and orange board highlights instead of green and red.")
	colour.name = "ColorblindHighlights"

static func _audio(app: Control, parent: Container) -> void:
	var card := Kit.card(parent)
	Kit.section_header(card, "Audio", "flag")
	var master := Kit.slider_row(card, "Master volume", Settings.volume, 0.0, 1.0, 0.05, func(v):
		Settings.volume = v
		_save())
	master.name = "MasterVolume"
	var effects := Kit.slider_row(card, "Effects (combat)", Prefs.sfx_volume, 0.0, 1.0, 0.05, func(v):
		Prefs.sfx_volume = v
		Prefs.apply()
		Prefs.save_preferences())
	effects.name = "EffectsVolume"
	var interface := Kit.slider_row(card, "Interface sounds", Prefs.ui_volume, 0.0, 1.0, 0.05, func(v):
		Prefs.ui_volume = v
		Prefs.apply()
		Prefs.save_preferences())
	interface.name = "InterfaceVolume"
	if AudioServer.get_bus_index("Music") != -1:
		var music := Kit.slider_row(card, "Music", Prefs.music_volume, 0.0, 1.0, 0.05, func(v):
			Prefs.music_volume = v
			Prefs.apply()
			Prefs.save_preferences())
		music.name = "MusicVolume"
	var sounds := Kit.toggle_row(card, "Menu hover and click sounds", Prefs.ui_sounds, func(on):
		Audio.set_enabled(app, on)
		Prefs.save_preferences())
	sounds.name = "UiSounds"

static func _controls(app: Control, parent: Container) -> void:
	var card := Kit.card(parent)
	Kit.section_header(card, "Controls", "controller")
	Kit.muted(card, "Rebind keys and buttons, choose which device plays each side, and tune your controller.")
	Kit.primary(card, "Controls and controllers", func(): ControlsScreen.open(app), "controller")
	Kit.muted(card, "Keyboard and mouse: click or drag a piece. Touch: tap or drag. 3D: orbit with right-drag or swipe, zoom with scroll or pinch. Controller: use the focused controls and board cursor. Esc releases the combat mouse.")

static func _service(app: Control, parent: Container) -> void:
	var card := Kit.card(parent)
	Kit.section_header(card, "Account service", "cloud")
	Kit.label(card, "Service address")
	app.api_edit = app._field(card, "https://accounts.example.com")
	app.api_edit.max_length = 200
	app.api_edit.text = Settings.api_url
	app.api_edit.text_submitted.connect(func(_t): app._save_api_url())
	Kit.secondary(card, "Save service address", app._save_api_url)
	Kit.ghost(card, "Advanced direct-server lobby", func():
		Settings.launch = {}
		app.get_tree().change_scene_to_file("res://network/client/online_lobby.tscn"))

static func reset_defaults() -> void:
	Settings.preferred_3d = false
	Settings.animations = true
	Settings.quality = "balanced"
	Settings.volume = 0.8
	Settings.touch_controls = DisplayServer.is_touchscreen_available()
	Settings.save_preferences()
	Prefs.reset_defaults()
	Prefs.save_preferences()
	Prefs.apply()

static func _footer(app: Control, parent: Container) -> void:
	var row := Kit.flow(parent)
	var reset := Kit.danger(row, "Reset to defaults", func():
		Kit.confirm(app, "Reset settings?", "Graphics, interface and audio settings return to their defaults. Controls and your account are not changed.", "Reset", func():
			reset_defaults()
			app.navigate("settings")
			Kit.toast(app, "Settings reset to defaults.", "success"), true))
	reset.name = "ResetDefaults"
