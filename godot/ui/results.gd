extends RefCounted
const Kit = preload("res://ui/theme/ui_kit.gd")
const Tokens = preload("res://ui/theme/ui_tokens.gd")
const Icons = preload("res://ui/theme/ui_icons.gd")
const Motion = preload("res://ui/theme/ui_motion.gd")
## Shared presentation for local and authoritative online results.
static func title(value: String, player_id: String = "", players: Dictionary = {}) -> String:
	if value == "1/2-1/2" or value == "draw":
		return "A well-fought draw"
	var winning_side = "w" if value == "1-0" else "b"
	if not player_id.is_empty() and players.has(winning_side):
		return "Victory" if players[winning_side] == player_id else "Defeat"
	return "White wins" if winning_side == "w" else "Black wins"

static func show_dialog(host: Control, data: Dictionary, review: Callable, menu: Callable) -> AcceptDialog:
	var dialog = AcceptDialog.new()
	dialog.title = title(str(data.get("result", "draw")), str(data.get("playerId", "")), data.get("players", {}))
	dialog.ok_button_text = "Review board"
	dialog.get_ok_button().theme_type_variation = "PrimaryButton"
	dialog.min_size = Vector2i(360, 200)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size.x = 340  # wrapping labels need a width or the dialog measures them one letter per line
	dialog.add_child(box)
	var victory = dialog.title == "Victory" or dialog.title.ends_with("wins")
	var defeat = dialog.title == "Defeat"
	var banner = HBoxContainer.new()
	banner.add_theme_constant_override("separation", 14)
	box.add_child(banner)
	banner.add_child(Icons.new("trophy" if victory else ("flag" if defeat else "shield"), 48, Tokens.GOLD if victory else (Tokens.DANGER if defeat else Tokens.TEXT_MUTED)))
	var heading = Kit.label(banner, dialog.title, "H1")
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var detail = Kit.label(box, str(data.get("reason", "Match complete")).replace("_", " ").capitalize(), "H3")
	var chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 8)
	box.add_child(chips)
	Kit.chip(chips, str(data.get("mode", "classic")).capitalize() + " Chess")
	Kit.chip(chips, str(data.get("plies", 0)) + " moves played", Tokens.TEXT_MUTED)
	var button = Kit.secondary(box, "Main menu")
	button.pressed.connect(func(): dialog.hide(); menu.call(); dialog.queue_free())
	dialog.confirmed.connect(func(): review.call(); dialog.queue_free())
	dialog.canceled.connect(func(): review.call(); dialog.queue_free())
	host.add_child(dialog)
	Kit.popup_in(host, dialog, 420, 260)
	Motion.dialog_pop(dialog)
	Kit.refit(dialog, Vector2i(360, 200))
	return dialog
