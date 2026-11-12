extends "res://contracts/codec.gd"
## battle-royal-v1 last-stand sequence contract. Additive: the v1 schema/fixtures/codec are untouched and every v1
## type (BattleResult, CombatSnapshot, ...) is validated by an unmodified copy of its v1 definition.
const ROYAL_SCHEMA_PATH = "res://contracts/royal/v1/schema.json"

func _init() -> void:
	schema = JSON.parse_string(FileAccess.get_file_as_string(ROYAL_SCHEMA_PATH))
