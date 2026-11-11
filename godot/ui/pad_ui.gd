class_name PadUi
extends Node
## Gamepad (and keyboard) navigation for the application's own screens, added as ONE helper node per scene:
##
##   PadUi.install(self, {"scopes": ["battle_overlay"], "prefer": "content", "back": Callable, "board": true})
##
## It does not change project.godot. What it does, all at runtime:
##   * InputMap: makes sure Cross (JOY_BUTTON_A) is ui_accept, Circle (B) is ui_cancel, L1/R1 are ui_focus_prev/next
##     (Godot's defaults differ by platform/build). The D-pad and left stick already map to ui_up/down/left/right.
##   * Focus guard: once the player navigates with a pad or keys ("nav mode", switched off again by mouse or touch)
##     keyboard/pad focus is never lost. If nothing is focused (a page was rebuilt, a dialog opened, a focused button
##     was disabled or freed) the next sensible control is focused; the first pad press only reveals the focus. It
##     looks inside the topmost visible dialog window first, then inside the visible "scope" overlay, then the scene.
##   * ScrollContainers follow focus.
##   * Combat: while a fight is running with a pad seat the guard releases focus and stays out of the way (Cross is
##     dodge there and must never also press a focused button). It comes back 0.8 s after the fight ends.
##   * "back": Circle (ui_cancel from a pad) calls the host's callable when no dialog is open.
##   * "board": adds a BoardPadCursor to the board screen; Options toggles between board cursor mode and menu focus.

signal board_mode_changed(board_mode: bool)

const FOCUS_RESUME_DELAY := 0.8
const SCOPE_GROUP := "pad_ui_scope"

var root: Node
var scope_names: Array[String] = []
var prefer_name: String = ""
var back: Callable = Callable()
var board: bool = false
var assignment: InputAssignment
var cursor: BoardPadCursor
var board_mode: bool = false
var nav_mode: bool = false
var enabled: bool = true
var _last_focus_center := Vector2.ZERO
var _resume_at: float = 0.0
var _was_combat: bool = false
var _synced_game = null
var _synced_interaction = null
var _time: float = 0.0
var _windows: Array = []  # of Window


static func install(p_root: Node, options: Dictionary = {}) -> PadUi:
	ensure_actions()
	for child in p_root.get_children():
		if child is PadUi:
			return child
	var ui := PadUi.new()
	ui.name = "PadUi"
	ui.root = p_root
	ui.assignment = options.get("assignment", InputAssignment.shared())
	for scope in options.get("scopes", []):
		ui.scope_names.append(String(scope))
	ui.prefer_name = String(options.get("prefer", ""))
	ui.back = options.get("back", Callable())
	ui.board = bool(options.get("board", false))
	ui.board_mode = ui.board
	p_root.add_child(ui)
	return ui


static func ensure_actions() -> void:
	_ensure("ui_accept", JOY_BUTTON_A)       # Cross
	_ensure("ui_cancel", JOY_BUTTON_B)       # Circle
	_ensure("ui_focus_next", JOY_BUTTON_RIGHT_SHOULDER)  # R1
	_ensure("ui_focus_prev", JOY_BUTTON_LEFT_SHOULDER)   # L1


static func _ensure(action: String, button: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventJoypadButton and int(existing.button_index) == button:
			if existing.device != -1:
				existing.device = -1
			return
	var event := InputEventJoypadButton.new()
	event.button_index = button as JoyButton
	event.device = -1  # -1 = any pad (the default device 0 would ignore Player 2's controller)
	InputMap.action_add_event(action, event)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for node in root.find_children("*", "ScrollContainer", true, false):
		_follow(node)
	for node in get_tree().root.find_children("*", "Window", true, false):
		_track_window(node)
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is ScrollContainer:
		_follow(node)
	elif node is Window:
		_track_window(node)


## While an embedded dialog has focus, Godot delivers input to that Window only (the main scene's _input is skipped),
## so every dialog gets its own small guard that reveals focus inside it on the first navigation press.
func _track_window(window: Window) -> void:
	if window == get_tree().root or window in _windows:
		return
	_windows.append(window)
	var guard := _WindowGuard.new()
	guard.ui = self
	window.add_child(guard)


class _WindowGuard:
	extends Node
	var ui: PadUi

	func _input(event: InputEvent) -> void:
		var window := get_parent() as Window
		if ui == null or not is_instance_valid(ui) or window == null or not window.visible or not ui.enabled:
			return
		if event is InputEventJoypadButton and event.pressed and event.is_action_pressed("ui_cancel") and window is AcceptDialog:
			# AcceptDialog closes on the Escape KEY only (observed on Godot 4.6.3): do what its cancel does for Circle.
			window.hide()
			window.emit_signal("canceled")
			window.set_input_as_handled()
			return
		if ui._is_nav_event(event):
			ui.nav_mode = true
			if ui._needs_focus(window) and ui._grab(window):
				window.set_input_as_handled()


func _follow(scroll: ScrollContainer) -> void:
	scroll.follow_focus = true


func set_board_mode(value: bool) -> void:
	if not board or value == board_mode:
		return
	board_mode = value
	if board_mode:
		var owner := _viewport().gui_get_focus_owner()
		if owner != null:
			owner.release_focus()
	board_mode_changed.emit(board_mode)


# ---- input ---------------------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventJoypadButton and event.pressed:
		nav_mode = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		nav_mode = true
	elif event is InputEventKey and event.pressed and not event.echo and (event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down") \
			or event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right") or event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_focus_prev")):
		nav_mode = true
	elif event is InputEventMouseButton or event is InputEventScreenTouch or (event is InputEventMouseMotion and event.relative.length() > 3.0 and event.device != InputEvent.DEVICE_ID_EMULATION):
		nav_mode = false
	if not nav_mode or _combat_active() or _board_owns_pad():
		return
	# A navigation press with nothing focused only reveals the focus (it is not also applied).
	if _is_nav_event(event) and _needs_focus(_viewport()):
		if _grab(_viewport()):
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or _combat_active() or not (event is InputEventJoypadButton) or not event.pressed or _popup_window() != null:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if board and not board_mode:
		set_board_mode(true)  # Circle in menu focus goes back to the board
		get_viewport().set_input_as_handled()
	elif not board_mode and back.is_valid():
		back.call()
		get_viewport().set_input_as_handled()


func _is_nav_event(event: InputEvent) -> bool:
	if event is InputEventJoypadButton and not event.pressed:
		return false
	if event is InputEventJoypadMotion and absf(event.axis_value) < 0.5:
		return false
	if event is InputEventKey and (not event.pressed or event.echo):
		return false
	for action in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_focus_next", "ui_focus_prev"]:
		if event.is_action(action):
			return true
	return false


# ---- per-frame ---------------------------------------------------------------------------------------------
func _process(delta: float) -> void:
	_time += delta
	if not enabled:
		return
	var combat := _combat_active()
	if combat:
		if not _was_combat:
			var owner := get_tree().root.gui_get_focus_owner()
			if owner != null:
				owner.release_focus()
		_was_combat = true
		_resume_at = _time + FOCUS_RESUME_DELAY
	elif _was_combat and _time >= _resume_at:
		_was_combat = false
	if board:
		_sync_board()
	if combat or _was_combat or not nav_mode or _board_owns_pad():
		return
	var vp := _viewport()
	var owner := vp.gui_get_focus_owner()
	if owner != null and owner.is_visible_in_tree():
		_last_focus_center = owner.get_global_rect().get_center()
	if _needs_focus(vp):
		_grab(vp)


## True while the board cursor (not menu focus) is what the pad drives: board mode, no dialog, and the host lets the
## board be used (not during the capture preview / combat phases).
func _board_owns_pad() -> bool:
	return board and board_mode and cursor != null and is_instance_valid(cursor) and cursor.is_usable() and _popup_window() == null


func _viewport() -> Viewport:
	var window := _popup_window()
	return window if window != null else get_tree().root


## The topmost visible dialog / popup window (embedded or native), or null.
func _popup_window() -> Window:
	var found: Window = null
	_windows = _windows.filter(func(w): return is_instance_valid(w))
	for window in _windows:
		if window.visible:
			found = window
	return found


func _combat_active() -> bool:
	for node in get_tree().get_nodes_in_group("pad_combat_input"):
		var source := node as LocalInputSource
		if source == null or not source.enabled or source.fighter == null or not is_instance_valid(source.fighter):
			continue
		var sim := source.fighter.get_parent()
		if sim != null and sim.has_method("is_running") and sim.is_running():
			return true
	return false


## The overlay that owns focus right now: the last visible control of group "pad_ui_scope" (dialog-like overlays such
## as ControlsScreen / JoinPrompt add themselves), else the last visible host-named scope (e.g. main's battle overlay).
func _scope() -> Control:
	var found: Control = null
	for name in scope_names:
		var candidate: Variant = root.get(name)
		if candidate is Control and (candidate as Control).is_visible_in_tree():
			found = candidate
	for node in get_tree().get_nodes_in_group(SCOPE_GROUP):
		if node is Control and (node as Control).is_visible_in_tree():
			found = node
	return found


func _focusable(c: Control, vp: Viewport) -> bool:
	# FOCUS_ALL only: FOCUS_CLICK is mouse-only and FOCUS_ACCESSIBILITY (4.6, labels) cannot hold the keyboard/pad focus.
	if c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree() or c.get_viewport() != vp:
		return false
	if c is BaseButton and (c as BaseButton).disabled:
		return false
	if c is LineEdit and not (c as LineEdit).editable:
		return false
	return true


func _needs_focus(vp: Viewport) -> bool:
	var owner := vp.gui_get_focus_owner()
	if owner == null or not _focusable(owner, vp):
		return true
	var scope := _scope() if vp == get_tree().root else null
	return scope != null and not scope.is_ancestor_of(owner) and scope != owner


func _grab(vp: Viewport) -> bool:
	var base: Node = vp
	var scope := _scope() if vp == get_tree().root else null
	if scope != null:
		base = scope
	var candidates: Array[Control] = []
	var preferred: Array[Control] = []
	var prefer: Variant = root.get(prefer_name) if prefer_name != "" and vp == get_tree().root and scope == null else null
	for node in base.find_children("*", "Control", true, false):
		var c := node as Control
		if c != null and _focusable(c, vp):
			candidates.append(c)
			if prefer is Control and (prefer as Control).is_ancestor_of(c):
				preferred.append(c)
	if base is Control and _focusable(base as Control, vp):
		candidates.push_front(base as Control)
	if candidates.is_empty():
		return false
	var pool := preferred if not preferred.is_empty() else candidates
	var best: Control = pool[0]
	if _last_focus_center != Vector2.ZERO and preferred.is_empty() and vp == get_tree().root:  # dialogs: first control (e.g. Queen)
		var best_d := INF
		for c in pool:
			var d := c.get_global_rect().get_center().distance_squared_to(_last_focus_center)
			if d < best_d:
				best_d = d
				best = c
	best.grab_focus()
	return true


# ---- board cursor ---------------------------------------------------------------------------------------------
func _sync_board() -> void:
	var game: Variant = root.get("game")
	var interaction: Variant = root.get("interaction")
	if game == null or interaction == null:
		return
	if cursor == null or not is_instance_valid(cursor) or game != _synced_game or interaction != _synced_interaction:
		if cursor != null and is_instance_valid(cursor):
			cursor.queue_free()
		cursor = BoardPadCursor.create(game, interaction, assignment)
		cursor.square_rect_provider = Callable(self, "_square_rect")
		cursor.quarter_turns_provider = Callable(self, "_quarter_turns")
		cursor.menu_requested.connect(func(): set_board_mode(not board_mode))
		cursor.input_used.connect(func(): nav_mode = true)
		add_child(cursor)
		var board_2d: Variant = root.get("board_2d")
		if board_2d is Control and (board_2d as Control).get_parent() is Control:
			cursor.attach_overlay((board_2d as Control).get_parent())
		_synced_game = game
		_synced_interaction = interaction
	cursor.active = board_mode and not _combat_active()
	cursor.strict_turns = game is BattleChessMatch
	var board_3d: Variant = root.get("board_3d")
	cursor.keyboard = board_3d is Control and (board_3d as Control).visible


func _quarter_turns() -> int:
	var board_3d: Variant = root.get("board_3d")
	if board_3d is Control and (board_3d as Control).visible:
		return roundi(float(board_3d.get("yaw")) / (PI * 0.5))
	var board_2d: Variant = root.get("board_2d")
	return 2 if board_2d != null and bool(board_2d.get("flipped")) else 0


func _square_rect(at: int) -> Rect2:
	var board_3d: Variant = root.get("board_3d")
	if board_3d is Control and (board_3d as Control).visible and board_3d.get("camera") is Camera3D and board_3d.get("viewport_3d") is SubViewport:
		var camera: Camera3D = board_3d.get("camera")
		var view: SubViewport = board_3d.get("viewport_3d")
		var scale := (board_3d as Control).size / Vector2(maxf(1.0, view.size.x), maxf(1.0, view.size.y))
		var centre := BoardInteraction.world_position(at) + Vector3(0, 0.05, 0)
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for corner in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(-0.5, 0, 0.5), Vector3(0.5, 0, 0.5)]:
			if camera.is_position_behind(centre + corner):
				return Rect2()
			var p := camera.unproject_position(centre + corner) * scale
			low = low.min(p)
			high = high.max(p)
		return Rect2(low, high - low)
	var board_2d: Variant = root.get("board_2d")
	if board_2d is Control and (board_2d as Control).visible and board_2d.has_method("square_center"):
		var pitch: float = float(board_2d.call("board_rect").size.x) / 8.0
		return Rect2(board_2d.call("square_center", at) - Vector2.ONE * pitch * 0.5, Vector2.ONE * pitch)
	return Rect2()
