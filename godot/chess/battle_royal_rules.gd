class_name BattleRoyalRules
extends "res://chess/battle_rules.gd"
## battle-royal-v1: the C0 / battle-checkmate-v1 rules plus "the king's last stand".
##
## Everything about legality is inherited unchanged (kings never initiate or receive capture duels, both capture
## outcomes must leave the mover's king safe, same draw accounting). The ONE difference is the terminal rule: a
## position that C0 adjudicates as checkmate does not end the match yet. It becomes `mate_pending` (the frozen
## position, the mated colour and the ordered mating group) and the match layer runs the duel sequence described in
## docs/architecture/BATTLE_ROYAL_V1.md. This class only owns the chess facts: who is in the mating group, what the
## board looks like after the king wins every duel, and how the match ends when it does not.
const RULESET_ID = "battle-royal-v1"
## Material value used to order the mating group (ascending). Knight and bishop tie; the square breaks the tie.
const VALUES = {"p": 1, "n": 3, "b": 3, "r": 5, "q": 9}

## {} or {"mated": "w"|"b", "kingSquare": int, "fen": String, "group": [{"square": int, "role": String, "color": String}]}.
## Set instead of `result` when the side to move is checkmated; the match clears it through one of the resolve_* calls.
var mate_pending: Dictionary = {}
## One summary per finished last stand (kept for the custom chronicle; the match appends).
var last_stands: Array = []
var _resolving_last_stand = false

## True if the piece on `from` (any colour) geometrically attacks the square `target` on the current board.
func piece_attacks(from: int, target: int) -> bool:
	var piece: String = board[from]
	if piece.is_empty() or from == target:
		return false
	var dx = target % 8 - from % 8
	var dy = target / 8 - from / 8
	match piece.to_lower():
		"p":
			return dy == (1 if side(piece) == "w" else -1) and absi(dx) == 1
		"n":
			return (absi(dx) == 1 and absi(dy) == 2) or (absi(dx) == 2 and absi(dy) == 1)
		"k":
			return maxi(absi(dx), absi(dy)) == 1
		"b":
			return absi(dx) == absi(dy) and _line_clear(from, target)
		"r":
			return (dx == 0 or dy == 0) and _line_clear(from, target)
		"q":
			return (dx == 0 or dy == 0 or absi(dx) == absi(dy)) and _line_clear(from, target)
	return false

func _line_clear(from: int, target: int) -> bool:
	var step_x = signi(target % 8 - from % 8)
	var step_y = signi(target / 8 - from / 8)
	var x = from % 8 + step_x
	var y = from / 8 + step_y
	while y * 8 + x != target:
		if not board[y * 8 + x].is_empty():
			return false
		x += step_x
		y += step_y
	return true

## Squares (ascending index) of every `by` piece that directly attacks `target`.
func attackers_of(target: int, by: String) -> Array:
	var out: Array = []
	for at in range(64):
		if side(board[at]) == by and piece_attacks(at, target):
			out.append(at)
	return out

## The mating group of the side to move: the opponent's pieces that give check on the CURRENT board (all direct
## checkers; both on a double check), ordered by ascending material value, then by square index (a1, b1 .. h8).
## Pieces that merely cover escape squares or block are never included. Empty if the side to move is not in check.
func mating_group() -> Array:
	var king_at = board.find("K" if turn == "w" else "k")
	if king_at < 0:
		return []
	var group: Array = []
	for at in attackers_of(king_at, opposite(turn)):
		var role: String = board[at].to_lower()
		group.append({"square": at, "role": role, "color": side(board[at])})
	group.sort_custom(func(a, b): return VALUES.get(a.role, 99) < VALUES.get(b.role, 99) or (VALUES.get(a.role, 99) == VALUES.get(b.role, 99) and a.square < b.square))
	return group

func _adjudicate() -> void:
	mate_pending = {}
	if not _resolving_last_stand and legal_moves().is_empty() and in_check():
		var group = mating_group()
		if not group.is_empty():
			mate_pending = {"mated": turn, "kingSquare": board.find("K" if turn == "w" else "k"), "fen": fen(), "group": group}
			return
		# No direct checker cannot happen at checkmate; if it ever did, fall back to the Classic/C0 mate below.
	super._adjudicate()

## All duels were won by the king. Removes the whole mating group, then re-adjudicates the new position with the
## SAME side to move (no ply is consumed). A second sequence is never started from this call: if the king is still
## checkmated by remaining pieces, checkmate stands. Returns the engine's own verdict (result may stay empty).
func resolve_king_survived(squares: Array) -> void:
	for at in squares:
		board[at] = ""
	ep = -1
	halfmove = 0
	castling = _castling_on_board()
	keys.clear()
	keys.append(position_key())
	_resolving_last_stand = true
	_adjudicate()
	_resolving_last_stand = false
	mate_pending = {}

## The king lost a duel (or the sequence could not be fought): checkmate for the other side.
func resolve_king_fell(why: String = "Checkmate") -> void:
	var mated: String = mate_pending.get("mated", turn)
	mate_pending = {}
	result = "0-1" if mated == "w" else "1-0"
	reason = why

func _castling_on_board() -> String:
	var rights = ""
	for right in "KQkq":
		if right not in castling:
			continue
		var white = right == right.to_upper()
		var king_at = 4 if white else 60
		var rook_at = {"K": 7, "Q": 0, "k": 63, "q": 56}[right]
		if board[king_at] == ("K" if white else "k") and board[rook_at] == ("R" if white else "r"):
			rights += right
	return rights

func pgn() -> String:
	var chronicle = JSON.parse_string(super.pgn())
	chronicle["rulesetId"] = RULESET_ID
	chronicle["lastStands"] = last_stands.duplicate(true)
	return JSON.stringify(chronicle, "  ", true, true)
