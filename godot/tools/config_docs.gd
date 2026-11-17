extends SceneTree
## Regenerates docs/game/BALANCE_REFERENCE.md and docs/game/RULES_REFERENCE.md from the metadata files.
##
##   godot --headless --path godot --script res://tools/config_docs.gd
##
## Run it after changing config/balance_meta.json or config/chess_rules_meta.json (the config test fails while the committed
## documents are stale).
const Reference := preload("res://config/config_reference.gd")


func _initialize() -> void:
	await process_frame
	var written: int = Reference.write_all()
	print("wrote %d reference document(s) under docs/game/" % written)
	quit(0 if written == 2 else 1)
