class_name OnlineTouchCombatInput
extends Control
## Device adapter only: virtual controls produce the same world-space CombatInput as any pad.
var client: OnlineChessClient
var view: OnlineCombatView
var enabled = false
var _fingers: Dictionary = {}
var _regions: Dictionary = {}
var _look = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _layout() -> void:
	var s = clampf(size.x / 900.0, 0.65, 1.15)
	var d = 54.0 * s
	var pad = Vector2(18, size.y - d * 3 - 14)
	_regions = {
		"up": Rect2(pad + Vector2(d, 0), Vector2.ONE * d),
		"left": Rect2(pad + Vector2(0, d), Vector2.ONE * d),
		"down": Rect2(pad + Vector2(d, d * 2), Vector2.ONE * d),
		"right": Rect2(pad + Vector2(d * 2, d), Vector2.ONE * d),
	}
	var origin = Vector2(size.x - d * 3 - 18, size.y - d * 3 - 14)
	var actions = ["light", "heavy", "dodge", "parry", "ability", "block", "sprint"]
	for i in actions.size():
		_regions[actions[i]] = Rect2(origin + Vector2(i % 3, i / 3) * d, Vector2.ONE * (d - 3))

func _input(event: InputEvent) -> void:
	if not enabled or not visible or view == null or view.arena == null:
		_fingers.clear()
		_look = -1
		return
	_layout()
	if event is InputEventScreenTouch:
		if not event.pressed:
			_fingers.erase(event.index)
			if _look == event.index:
				_look = -1
		else:
			var point = event.position - global_position
			for action in _regions:
				if _regions[action].has_point(point):
					_fingers[event.index] = action
					if action in ["light", "heavy", "dodge", "parry", "ability"] and view.net_client() != null:
						view.net_client().press(action)
					get_viewport().set_input_as_handled()
					return
			if Rect2(Vector2.ZERO, size).has_point(point):
				_look = event.index
	elif event is InputEventScreenDrag and event.index == _look:
		view.arena.cameras[0].add_look(event.relative.x * 0.004, event.relative.y * 0.004)
		get_viewport().set_input_as_handled()

func _physics_process(_delta: float) -> void:
	# The arena's tick (process priority 100) runs after this one and sends the intent set here for the same tick.
	if not enabled or not visible or not client.authenticated or view.net_client() == null or client.frame.state.phase != "combat":
		return
	var held = _fingers.values()
	var move = Vector2(float("right" in held) - float("left" in held), float("up" in held) - float("down" in held)).normalized()
	var yaw = view.arena.cameras[0].view_heading()
	var heading = Vector3(sin(yaw), 0, cos(yaw))
	var right = Vector3(-heading.z, 0, heading.x)
	var world = right * move.x + heading * move.y
	# Same intent path as keyboard/pad: the predicted local fighter, one CombatInput per tick built by the arena's client.
	view.net_client().set_intent(world.x, world.z, view.arena.sim.fighter_by_id(client.player_id).yaw, true, "sprint" in held, "block" in held)

func _process(_delta: float) -> void:
	if enabled and visible:
		queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	_layout()
	var font = ThemeDB.fallback_font
	for action in _regions:
		var rect: Rect2 = _regions[action]
		draw_rect(rect, Color(0.15, 0.4, 0.4, 0.85) if action in _fingers.values() else Color(0.06, 0.13, 0.18, 0.75))
		draw_rect(rect, Color(0.8, 0.7, 0.4, 0.8), false, 1)
		draw_string(font, rect.position + Vector2(3, rect.size.y * 0.58), action.capitalize(), HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6, 12)
