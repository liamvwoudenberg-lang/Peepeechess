class_name ChessZobrist
extends RefCounted
## Zobrist hashing for the AI. Keys come from a fixed-seed generator, so hashes (and therefore
## transposition-table behaviour and seeded self-play) are identical on every machine and run.
## `ensure()` must be called on the main thread before a search thread starts.
const SEED = 0x5EED0C4E55
const INDEX = {"P": 0, "N": 1, "B": 2, "R": 3, "Q": 4, "K": 5, "p": 6, "n": 7, "b": 8, "r": 9, "q": 10, "k": 11}
static var piece_keys := PackedInt64Array()
static var castle_keys := PackedInt64Array()
static var ep_keys := PackedInt64Array()
static var turn_key := 0
static var _built := false

static func ensure() -> void:
	if _built:
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = SEED
	piece_keys.resize(768)
	for i in range(768):
		piece_keys[i] = (rng.randi() << 32) | rng.randi()
	castle_keys.resize(16)
	for i in range(16):
		castle_keys[i] = (rng.randi() << 32) | rng.randi()
	ep_keys.resize(8)
	for i in range(8):
		ep_keys[i] = (rng.randi() << 32) | rng.randi()
	turn_key = (rng.randi() << 32) | rng.randi()
	_built = true

static func castle_mask(castling: String) -> int:
	var mask = 0
	if castling.contains("K"):
		mask |= 1
	if castling.contains("Q"):
		mask |= 2
	if castling.contains("k"):
		mask |= 4
	if castling.contains("q"):
		mask |= 8
	return mask

## Hash of a position. The en passant file is only mixed in when a pawn of the side to move could
## actually capture, matching the repetition convention of the rules engine.
static func hash_position(board: Array, turn: String, castling: String, ep: int) -> int:
	var h = 0
	for sq in range(64):
		var p: String = board[sq]
		if p != "":
			h ^= piece_keys[INDEX[p] * 64 + sq]
	if turn == "b":
		h ^= turn_key
	h ^= castle_keys[castle_mask(castling)]
	if ep >= 0:
		var file = ep % 8
		var capturable = false
		if turn == "w" and ep / 8 == 5:
			capturable = (file > 0 and board[ep - 9] == "P") or (file < 7 and board[ep - 7] == "P")
		elif turn == "b" and ep / 8 == 2:
			capturable = (file > 0 and board[ep + 7] == "p") or (file < 7 and board[ep + 9] == "p")
		if capturable:
			h ^= ep_keys[file]
	return h
