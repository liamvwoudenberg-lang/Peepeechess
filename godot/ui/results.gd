extends RefCounted
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
	dialog.min_size = Vector2i(350, 180)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	dialog.add_child(box)
	var heading = Label.new()
	heading.text = dialog.title
	heading.add_theme_font_size_override("font_size", 30)
	box.add_child(heading)
	var detail = Label.new()
	detail.text = str(data.get("reason", "Match complete")).replace("_", " ") + "\n" + str(data.get("mode", "classic")).capitalize() + " Chess · " + str(data.get("plies", 0)) + " moves played"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)
	var button = Button.new()
	button.text = "Main menu"
	button.custom_minimum_size.y = 48
	button.pressed.connect(func(): dialog.hide(); menu.call(); dialog.queue_free())
	box.add_child(button)
	dialog.confirmed.connect(func(): review.call(); dialog.queue_free())
	dialog.canceled.connect(func(): review.call(); dialog.queue_free())
	host.add_child(dialog)
	dialog.popup_centered()
	return dialog
