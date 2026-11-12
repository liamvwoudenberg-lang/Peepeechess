class_name ComputerOpponent
extends Node
## Plays one side of a ClassicMatch / BattleChessMatch against the human.
##
## It only uses the match's public API (`game.play`, `undo`, `resign`, `claim_draw`, `agree_draw`) exactly like a
## UI would, so every rule, clock and Battle-flow check still applies. Search runs off the main thread
## (ChessAIJob); `cancel_search()` is called whenever the position can change under it (new game, undo, resign,
## game end, leaving the screen).
##
## Behaviour
## - Moves after a short, seeded "natural" delay that shortens with the animation-speed setting and waits for
##   `animation_busy` (optional Callable returning true while the board animates).
## - Clock: spends about 1/30 of the remaining time (+ half the increment), at most the level's time budget.
## - Promotion: the search picks it; knight under-promotion only if it clearly beats the queen.
## - Draw offers: accepts when it is clearly worse (<= -90 cp) or in a long, level position; declines otherwise.
##   It claims a threefold / fifty-move draw (Classic) when its own evaluation is not better than +20 cp.
## - Resigns (Classic only, level >= 3) after three consecutive moves at <= -1100 cp past move 30.
## - Battle Chess: a capture it plays goes through the normal Battle flow. In the duel it controls its fighter with
##   CombatAI (`computer_seat` handed to the combat adapter; skill/style come from the level).
signal thinking_changed(thinking: bool)
signal message(text: String)
signal moved(from: String, to: String)
const DRAW_ACCEPT_CP = -90
const RESIGN_CP = -1100
var game
var adapter: Node
var active = false
var level = 3
var ai_color = "b"
var human_color = "w"
var ai: ChessAI
var base_delay_ms = 650
var think_scale = 1.0
var animation_busy: Callable = Callable()
var last_score = 0
var last_result: Dictionary = {}
var rng = RandomNumberGenerator.new()
var force_slice = false
var _job: ChessAIJob
var _search_fen = ""
var _ready_move: Dictionary = {}
var _turn_started_ms = 0
var _delay_ms = 0
var _undoing = false
var _hopeless = 0
var _games = 0

func _init() -> void:
	set_process(false)

## Attach to a match (and, for Battle Chess, the combat adapter). Safe to call again when the match is replaced.
func bind(match_game, combat_adapter: Node = null) -> void:
	cancel_search()
	if game != null and game.changed.is_connected(_on_changed):
		game.changed.disconnect(_on_changed)
	game = match_game
	adapter = combat_adapter
	if game != null:
		game.changed.connect(_on_changed)
	_sync_combat_seat()
	if active:
		_consider()

## Start a computer game. options: level (1-6), color ("w" | "b" | "random"), seed (int).
func begin(options: Dictionary) -> void:
	cancel_search()
	level = clampi(int(options.get("level", 3)), ChessAI.MIN_LEVEL, ChessAI.MAX_LEVEL)
	_games += 1
	var seed_value = int(options.get("seed", Time.get_ticks_usec() + _games))
	rng.seed = seed_value
	var color = str(options.get("color", "random"))
	if color not in ["w", "b"]:
		color = "w" if rng.randi() % 2 == 0 else "b"
	human_color = color
	ai_color = "b" if color == "w" else "w"
	ai = ChessAI.new(level, seed_value)
	ai.time_scale = think_scale * (0.6 if OS.has_feature("mobile") else 1.0)
	active = true
	_hopeless = 0
	last_score = 0
	_sync_combat_seat()
	message.emit("Computer · level %d (%s) · you play %s" % [level, ChessAI.level_name(level), "White" if human_color == "w" else "Black"])
	_consider()

## Back to ordinary two-player play.
func end() -> void:
	cancel_search()
	active = false
	_sync_combat_seat()

func dispose() -> void:
	cancel_search()
	if game != null and game.changed.is_connected(_on_changed):
		game.changed.disconnect(_on_changed)
	game = null
	adapter = null
	active = false

func _exit_tree() -> void:
	cancel_search()

func _sync_combat_seat() -> void:
	if adapter == null or not is_instance_valid(adapter) or not "computer_seat" in adapter:
		return
	if active and game is BattleChessMatch:
		var profile = ChessAI.combat_profile(level)
		adapter.computer_seat = {"color": ai_color, "seat": {"type": "ai", "skill": profile.skill, "style": profile.style, "attacker_style": profile.attack_style}}
	else:
		adapter.computer_seat = {}

func is_thinking() -> bool:
	return active and (_job != null and _job.is_running() or not _ready_move.is_empty())

func cancel_search() -> void:
	var was_busy = _job != null or not _ready_move.is_empty() or _search_fen != ""
	if _job != null:
		_job.cancel()
		_job = null
	_ready_move = {}
	_search_fen = ""
	set_process(false)
	if was_busy:
		thinking_changed.emit(false)

func _on_changed() -> void:
	if _undoing or not active:
		return
	if _search_fen != "" and game.engine.fen() != _search_fen:
		cancel_search()  # the position moved on (undo, new game, loaded FEN): the old search is stale
	_consider()

func _consider() -> void:
	if not active or game == null:
		return
	if not game.engine.result.is_empty() or game.paused:
		cancel_search()
		return
	if game is BattleChessMatch and game.phase != "board":
		return
	if game.engine.turn != ai_color:
		if _search_fen != "":
			cancel_search()
		return
	if _search_fen != "":
		return  # already thinking about this exact position
	if _try_claim_draw():
		return
	_search_fen = game.engine.fen()
	_turn_started_ms = Time.get_ticks_msec()
	var scale = BoardTheme.anim_scale()
	_delay_ms = int(base_delay_ms * (0.2 if scale == 0.0 else (0.6 if scale < 1.0 else 1.0)) * rng.randf_range(0.75, 1.3))
	_job = ChessAIJob.new()
	_job.start(game.engine, ai, {"time_ms": _time_budget_ms()}, force_slice)
	set_process(true)
	thinking_changed.emit(true)

func _time_budget_ms() -> int:
	var budget = int(ChessAI.LEVELS[level].time_ms * ai.time_scale)
	if game.timed and game.started:
		var left: int = game.remaining[ai_color]
		var allowance = int(left / 30.0 + game.increment_ms * 0.5)
		if left < 5000:
			allowance = mini(allowance, 120)
		budget = clampi(allowance, 40, budget)
	return budget

func _process(_delta: float) -> void:
	if _job == null:
		if not _ready_move.is_empty():
			_try_play()
		return
	if _job.poll():
		var result: Dictionary = _job.result
		_job = null
		if result.is_empty() or not result.get("ok", false):
			cancel_search()
			return
		last_result = result
		last_score = result.score
		_ready_move = result
		_try_play()

func _try_play() -> void:
	if Time.get_ticks_msec() - _turn_started_ms < _delay_ms:
		return
	if animation_busy.is_valid() and animation_busy.call():
		return
	var result = _ready_move
	_ready_move = {}
	var fen = _search_fen
	_search_fen = ""
	set_process(false)
	thinking_changed.emit(false)
	if game.engine.fen() != fen or game.engine.turn != ai_color or not game.engine.result.is_empty():
		_consider()
		return
	if _should_resign(result):
		message.emit("Computer resigns.")
		game.resign()
		return
	var outcome = game.play(result.from, result.to, result.promotion if result.promotion != "" else "q")
	if not outcome.ok:
		# Defensive: the search used the engine's own legal moves, so this should not happen. Fall back to any legal move.
		for m in game.engine.legal_moves():
			outcome = game.play(ClassicChess.square(m.from), ClassicChess.square(m.to), m.promotion if m.promotion != "" else "q")
			if outcome.ok:
				break
	if outcome.ok:
		moved.emit(result.from, result.to)

func _should_resign(result: Dictionary) -> bool:
	if game is BattleChessMatch or level < 3 or game.engine.history.size() < 30:
		return false
	_hopeless = _hopeless + 1 if result.score <= RESIGN_CP else 0
	return _hopeless >= 3

func _try_claim_draw() -> bool:
	if game is BattleChessMatch or game.engine.claimable_draws().is_empty():
		return false
	if ChessAI.static_eval(game.engine) > 20 and last_score > 20:
		return false
	var kind: String = game.engine.claimable_draws()[0]
	if game.claim_draw(kind):
		message.emit("Computer claims a draw · " + kind)
		return true
	return false

# ---- user actions routed through the computer -------------------------------------------------

## Take back the human's last move (and the computer's reply): two plies on the human's turn, one while the
## computer is still thinking. Returns false when nothing can be taken back.
func undo() -> bool:
	if not active:
		return game.undo()
	if not game.allow_undo or game.engine.history.is_empty():
		return false
	cancel_search()
	_undoing = true
	var taken = 0
	while taken < 2 and not game.engine.history.is_empty():
		if not game.undo():
			break
		taken += 1
		if game.engine.turn == human_color:
			break
	_undoing = false
	if game.engine.turn != human_color:
		# Could not reach a human turn (for example the computer opened the game): keep the game consistent.
		_consider()
	return taken > 0

## The human resigns. Works on either side's turn and while the computer is thinking.
func human_resign() -> void:
	cancel_search()
	var last_stand = game.has_method("royal_active") and game.royal_active()  # king's last stand (battle-royal-v1) sequence running
	if game.engine.result.is_empty():
		game.poll_clock()
		if game is BattleChessMatch and game.phase == "aftermath" and not last_stand:
			game.commit_battle()
		if game.engine.result.is_empty():
			game.engine.result = "0-1" if human_color == "w" else "1-0"
			game.engine.reason = "Resignation"
	if last_stand:
		game.abandon_pending()  # the human forfeits, whichever side is mated: the sequence is dropped without inventing an outcome
	elif game is BattleChessMatch and game.phase != "board":
		game.cancel_pending()
	else:
		game.changed.emit()

## The human offers a draw. Returns {accepted, text}; applies the draw when accepted.
func respond_to_draw_offer() -> Dictionary:
	var score = last_score if last_score != 0 else ChessAI.static_eval(game.engine) * (1 if game.engine.turn == ai_color else -1)
	var ply = game.engine.history.size()
	var accept = score <= DRAW_ACCEPT_CP or (ply >= 80 and absi(score) <= 25)
	if accept:
		game.agree_draw()
		return {"accepted": true, "text": "Computer accepts the draw."}
	return {"accepted": false, "text": "Computer declines the draw offer."}

func status_text() -> String:
	return "Computer thinking…" if is_thinking() else ""
