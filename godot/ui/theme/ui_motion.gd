extends RefCounted
## Tween-based micro-animations. All of them
##   * respect UiPrefs.reduce_motion (they jump straight to the end state),
##   * never block input (they only touch modulate / scale and never mouse_filter),
##   * are interruption-safe: starting a new animation on the same node kills the previous one first, and
##     settle() / leaving the tree always restores the resting state (alpha 1, scale 1),
##   * allocate only when started (one Tween), never per frame.
const Prefs = preload("res://ui/theme/ui_prefs.gd")
const DURATION := 0.18
const META := &"_ui_motion_tween"

static func enabled() -> bool:
	return not Prefs.reduce_motion

static func _kill(node: Node) -> void:
	if node.has_meta(META):
		var previous = node.get_meta(META)
		if previous is Tween and (previous as Tween).is_valid():
			(previous as Tween).kill()
		node.remove_meta(META)

## Restores the resting state of `node` and stops any running motion on it.
static func settle(node: CanvasItem) -> void:
	if not is_instance_valid(node):
		return
	_kill(node)
	node.modulate.a = 1.0
	if node is Control:
		(node as Control).scale = Vector2.ONE

static func _begin(node: CanvasItem) -> Tween:
	_kill(node)
	var tween := node.create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	node.set_meta(META, tween)
	if not node.tree_exiting.is_connected(settle.bind(node)):
		node.tree_exiting.connect(settle.bind(node), CONNECT_ONE_SHOT)
	return tween

## Screen / page transition: fade in with a tiny settle-scale (scale_from = 1.0 for a pure fade).
static func fade_in(node: CanvasItem, duration: float = DURATION, scale_from: float = 0.985) -> void:
	if node == null or not is_instance_valid(node):
		return
	if not enabled() or not node.is_inside_tree():
		settle(node)
		return
	var tween := _begin(node)
	tween.set_parallel(true)
	node.modulate.a = 0.0
	tween.tween_property(node, "modulate:a", 1.0, duration)
	if node is Control and scale_from != 1.0:
		var control := node as Control
		control.pivot_offset = control.size * 0.5
		control.scale = Vector2(scale_from, scale_from)
		tween.tween_property(control, "scale", Vector2.ONE, duration)

## Quick fade-out then calls `done` (immediately when motion is reduced). The node is left at alpha 0 until settle().
static func fade_out(node: CanvasItem, done: Callable = Callable(), duration: float = DURATION * 0.7) -> void:
	if not is_instance_valid(node):
		return
	if not enabled() or not node.is_inside_tree():
		if done.is_valid():
			done.call()
		return
	var tween := _begin(node)
	tween.tween_property(node, "modulate:a", 0.0, duration)
	if done.is_valid():
		tween.tween_callback(done)

## Small press pulse used for buttons (scale down then back).
static func press(node: Control) -> void:
	if not enabled() or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var tween := _begin(node)
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(0.96, 0.96)
	tween.tween_property(node, "scale", Vector2.ONE, 0.12)

## Pop-in for a dialog: its content fades in (the Window itself cannot be scaled).
static func dialog_pop(dialog: Window) -> void:
	if not is_instance_valid(dialog):
		return
	for child in dialog.get_children():
		if child is CanvasItem and not (child is Window):
			fade_in(child as CanvasItem, 0.16, 1.0)

## Toast entrance: fade in and a short slide from below via a transient offset is NOT used (containers own position);
## it is a fade + settle-scale like the pages.
static func toast_in(node: Control) -> void:
	fade_in(node, 0.16, 0.96)
