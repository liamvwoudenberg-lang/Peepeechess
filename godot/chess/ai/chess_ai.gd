class_name ChessAI
extends RefCounted
## Computer opponent: six difficulty levels over ChessSearch. See README.md in this folder.
##
## `choose_move(engine)` is synchronous (tests, tools). Games use ChessAIJob, which runs the same search on a
## worker thread (or frame-sliced where threads are unavailable) with cancellation.
##
## Determinism: for a given level, seed and sequence of positions the chosen moves are identical when the
## search ends on depth/node limits (`deterministic = true` removes the wall clock entirely). With a wall-clock
## limit the depth reached depends on machine speed, so moves can differ between machines.
const ChessRules = preload("res://config/chess_rules.gd")
static var LEVELS: Dictionary = ChessRules.computer_levels()   # config/chess_rules.json: computer_levels
static var MIN_LEVEL: int = ChessRules.min_computer_level()
static var MAX_LEVEL: int = ChessRules.max_computer_level()
var level = 3
var seed_value = 1
## Multiplies every level's wall-clock budget (mobile devices use less; tests use more headroom).
var time_scale = 1.0
## Multiplies every level's node cap (tests shrink it for speed; 1.0 = shipped strength).
var node_scale = 1.0
## true: ignore the wall clock, stop on depth / node limits only (bit-for-bit reproducible).
var deterministic = false
var search: ChessSearch
var last_result: Dictionary = {}

func _init(p_level: int = 3, p_seed: int = 1) -> void:
	level = clampi(p_level, MIN_LEVEL, MAX_LEVEL)
	seed_value = p_seed
	search = ChessSearch.new()

static func level_config(value: int) -> Dictionary:
	return LEVELS[clampi(value, MIN_LEVEL, MAX_LEVEL)].duplicate()

static func level_name(value: int) -> String:
	return LEVELS[clampi(value, MIN_LEVEL, MAX_LEVEL)].name

## Combat skill 0..1 and CombatAI styles for the Battle Chess duel controlled by this level. `style` is used when the
## computer defends, `attack_style` when it attacks: the reactive styles (defensive / duelist) never start a fight, and
## a tie goes to the defender, so an attacking computer that waited for a passive human would simply lose by timeout.
static func combat_profile(value: int) -> Dictionary:
	var config = LEVELS[clampi(value, MIN_LEVEL, MAX_LEVEL)]
	return {"skill": config.skill, "style": config.style, "attack_style": config.attack_style}

func new_game() -> void:
	search.clear_tables()
	last_result = {}

## A private copy of the position the search is free to mutate (never the live match engine).
static func clone_engine(source):
	var copy = BattleChessRules.new() if source.has_method("capture_restriction") else ClassicChess.new()
	copy.board = source.board.duplicate()
	copy.turn = source.turn
	copy.castling = source.castling
	copy.ep = source.ep
	copy.halfmove = source.halfmove
	copy.fullmove = source.fullmove
	return copy

## Zobrist hashes of the positions that occurred earlier in the game (for repetition scores).
static func history_hashes(source) -> Array:
	ChessZobrist.ensure()
	var hashes: Array = []
	for p in source.positions:
		hashes.append(ChessZobrist.hash_position(p.board, p.turn, p.castling, p.ep))
	return hashes

## Search limits for the current level. `opts`: time_ms (override), max_depth, node_limit.
func config_for(source, opts: Dictionary = {}) -> Dictionary:
	var base = LEVELS[level]
	var config: Dictionary = base.duplicate()
	var time_ms = int(opts.get("time_ms", int(base.time_ms * time_scale)))
	config["time_ms"] = 0 if deterministic else maxi(20, time_ms)
	config["node_limit"] = int(opts.get("node_limit", maxi(60, int(base.node_limit * node_scale))))
	config["max_depth"] = int(opts.get("max_depth", base.max_depth))
	config["seed"] = seed_value * 1000003 + source.history.size() * 7919 + (1 if source.turn == "b" else 0)
	config["history_hashes"] = history_hashes(source)
	return config

## Synchronous search. Returns {ok, move, from, to, promotion, score, depth, nodes, elapsed_ms, mate, ...}.
func choose_move(source, opts: Dictionary = {}) -> Dictionary:
	var copy = clone_engine(source)
	var config = config_for(source, opts)
	last_result = search.run(copy, config)
	return last_result

func cancel() -> void:
	search.request_stop()

## Static evaluation from the side to move's point of view (cheap; no search).
static func static_eval(source) -> int:
	ChessEval.ensure()
	var score = ChessEval.evaluate(source.board, source.turn, source.has_method("capture_restriction"))
	return score if source.turn == "w" else -score
