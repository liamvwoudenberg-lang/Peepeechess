extends Node
## Hooks every button under `root` (now and later) with the press micro-animation and, optionally, UI sounds.
## One node per screen, added by UiKit.install(). Buttons are hooked once (meta flag), signals are plain connects
## (no per-frame work).
const Motion = preload("res://ui/theme/ui_motion.gd")
const Audio = preload("res://ui/theme/ui_audio.gd")
var root: Node
var hooked := 0

func _ready() -> void:
	if root == null:
		root = get_parent()
	_hook_tree(root)
	get_tree().node_added.connect(_on_node_added)
	Audio.attach(root, self)

func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is BaseButton and root != null and is_instance_valid(root) and root.is_ancestor_of(node):
		_hook(node)

func _hook_tree(node: Node) -> void:
	if node is BaseButton:
		_hook(node)
	for child in node.get_children():
		_hook_tree(child)

func _hook(button: BaseButton) -> void:
	if button.has_meta(&"_ui_hooked"):
		return
	button.set_meta(&"_ui_hooked", true)
	hooked += 1
	button.button_down.connect(func(): Motion.press(button))
