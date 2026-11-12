extends "res://contracts/codec.gd"
## Public persistent-board game contract; v1 remains unchanged.
func _init() -> void:
	schema = JSON.parse_string(FileAccess.get_file_as_string("res://contracts/v2/schema.json"))
