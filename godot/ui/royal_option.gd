class_name RoyalOption
extends RefCounted
## The "King's last stand" ruleset choice (battle-royal-v1, docs/architecture/BATTLE_ROYAL_V1.md) for LOCAL Battle Chess
## (two players on one device, or against the computer). It is an opt-in toggle, default OFF; the last choice is persisted in
## its own small file so it never competes with the application preferences (which rewrite their whole file on save).
##
## Used by the Play page (ui/application.gd) and by the New game dialog (app/main_opponent.gd): both build the same toggle +
## one short explanatory paragraph with `build()`. Online matches never show it (the online protocol cannot carry the sequence
## yet, see docs/architecture/BATTLE_ROYAL_V1.md "Online").
const PATH = "user://royal_options.cfg"
const TITLE = "King's last stand"
const EXPLANATION = "Checkmate is not the end. The mated King fights the pieces that give check, one duel at a time, and keeps its health, stamina and ability cooldown between duels. Win them all and those pieces are removed and the game goes on; lose one and it is checkmate."
## Preferences are only written to disk when this is true (tests that use the dialog headlessly can switch it off).
static var persist = true
static var _loaded = false
static var _value = false

## The saved choice (default false).
static func load_choice() -> bool:
	if _loaded:
		return _value
	_loaded = true
	var config = ConfigFile.new()
	if config.load(PATH) == OK:
		_value = bool(config.get_value("ruleset", "last_stand", false))
	return _value

static func save_choice(value: bool) -> void:
	_loaded = true
	_value = value
	if not persist:
		return
	var config = ConfigFile.new()
	config.set_value("ruleset", "last_stand", value)
	config.save(PATH)

## Forget the cached value (tests reload it from disk).
static func reset_cache() -> void:
	_loaded = false
	_value = false

## Toggle button + explanation under `parent`. `state` is the caller's Dictionary (key "royal"); `on_change` is called after the
## button edited it so the caller can rebuild its page. Returns the container (named "RoyalOption").
static func build(parent: Node, state: Dictionary, on_change: Callable, compact: bool = false) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.name = "RoyalOption"
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var heading = Label.new()
	heading.text = "RULESET"
	heading.add_theme_font_size_override("font_size", 13)
	heading.add_theme_color_override("font_color", Color("e5c586"))
	box.add_child(heading)
	var button = Button.new()
	button.name = "RoyalToggle"
	button.toggle_mode = true
	button.button_pressed = bool(state.get("royal", false))
	button.text = TITLE + (" · ON" if button.button_pressed else " · off")
	button.custom_minimum_size.y = 44
	button.tooltip_text = "Optional rule for Battle Chess. Off = the standard Battle checkmate."
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	OpponentUI.style_toggle(button)
	button.pressed.connect(func():
		state["royal"] = not bool(state.get("royal", false))
		save_choice(bool(state["royal"]))
		on_change.call())
	box.add_child(button)
	var text = Label.new()
	text.name = "RoyalExplanation"
	text.text = EXPLANATION
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = 250 if compact else 380
	text.add_theme_font_size_override("font_size", 13 if compact else 14)
	text.add_theme_color_override("font_color", Color("b6c4b5"))
	box.add_child(text)
	return box
