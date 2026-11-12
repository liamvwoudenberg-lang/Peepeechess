extends RefCounted
## battle-royal-v1 PLAYABLE integration (the King's last stand in the app): the ruleset toggle and its persistence, the local flow
## end to end with the real BattleRoyalMatch + real CombatSimulation duels (CombatAI and scripted knockouts), the pit presentation of a
## multi-duel sequence (one descent, an interlude per duel, one climb; interruption at every point; node leaks), the banner / HUD
## texts, the computer opponent, and a full sequence through the real CombatArena inside the pit world.
##
## Everything is deterministic: the pit and the flow are stepped explicitly (world.auto_advance = false, flow.advance(dt)).
## Outcomes that decide assertions are scripted (damage applied to the REAL simulation), never left to a balance-dependent AI;
## the CombatAI-driven scenario only asserts consistency (carried state, board after) for either outcome.

const Main := preload("res://app/main.tscn")
const Application := preload("res://ui/application.tscn")
const Royal := preload("res://chess/battle_royal_match.gd")
const BattleMatch := preload("res://chess/battle_match.gd")
const Flow := preload("res://app/battle_flow.gd")
const Interaction := preload("res://boards/board_interaction.gd")
const Rules := preload("res://chess/chess_engine.gd")
const AppSettings := preload("res://ui/application_settings.gd")
const W := preload("res://world/world_constants.gd")
const BACK_RANK := "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"   # Ra8# next: ONE checker (mate by a quiet move)
const BOTH := "R3k3/3p1p2/8/8/8/8/8/4R1K1 b - - 0 1"        # a loaded mate: Re1 and Ra8 check (two checkers, Re1 first by square)
const THREE := "R5k1/5ppp/5N1N/8/8/8/8/6K1 b - - 0 1"       # three checkers: Nf6, Nh6 (3 each, by square) then Ra8 (5)
const DT := 1.0 / 60.0


static func run(h, tree: SceneTree) -> void:
	RoyalOption.persist = false  # the suites below never write the player's real preference file
	_texts(h)
	await _toggle_and_persistence(h, tree)
	await _local_flow(h, tree)
	await _pit_sequences(h, tree)
	await _app_world(h, tree)
	await _computer_opponent(h, tree)
	await _end_to_end(h, tree)
	RoyalOption.persist = true


# ---- test doubles -----------------------------------------------------------------------------------------------------------
## Stands in for BattleCombatAdapter but runs a REAL CombatSimulation, exactly like the real adapter reports the King's state.
class SimAdapter extends Node:
	signal arena_ready
	signal snapshot_received(snapshot: Dictionary)
	signal result_received(result: Dictionary)
	signal failed(message: String)
	var request: Dictionary = {}
	var options: Dictionary = {}
	var sim: CombatSimulation = null
	var live := false
	var loads := 0
	var starts := 0
	var stops := 0
	var pending_load := false
	var load_fails := false
	var started_options: Array = []

	func available() -> bool:
		return true

	func check_request(_request: Dictionary, _options: Dictionary = {}) -> Dictionary:
		return {"ok": true}

	func has_live_arena() -> bool:
		return live

	func begin_load(value: Dictionary, _host: Node, opts: Dictionary = {}) -> Dictionary:
		loads += 1
		request = value.duplicate(true)
		options = opts.duplicate(true)
		if load_fails:
			return {"ok": false, "error": "Fixture load failure."}
		pending_load = true
		return {"ok": true}

	## The test acts as the asynchronous scene load finishing.
	func finish_load() -> void:
		if pending_load:
			pending_load = false
			live = true
			arena_ready.emit()

	func start(value: Dictionary, opts: Dictionary = {}) -> Dictionary:
		starts += 1
		request = value.duplicate(true)
		options = opts.duplicate(true)
		started_options.append(options.duplicate(true))
		_drop_sim()
		sim = CombatSimulation.new()
		add_child(sim)
		return sim.start(request, options)

	func stop() -> void:
		stops += 1
		live = false
		pending_load = false
		_drop_sim()

	func fighter_state(player_id: String) -> Dictionary:
		return sim.fighter_state(player_id) if sim != null else {}

	func _drop_sim() -> void:
		if sim != null:
			sim.stop()
			if sim.get_parent() != null:
				sim.get_parent().remove_child(sim)
			sim.queue_free()
			sim = null

	## Plays the started duel to its end on the REAL simulation. `plan`: {"king_damage": int, "kill_king": bool, "kill_checker": bool}
	## (applied through the real health component before the first tick) or {"ai": {"king": cfg, "checker": cfg}} (CombatAI duel).
	## Returns the BattleResult the simulation produced.
	func play(plan: Dictionary) -> Dictionary:
		var king: FighterController = sim.attacker()
		var checker: FighterController = sim.defender()
		var bots: Array = []
		if plan.has("ai"):
			var seed_value := int(request["seed"])
			var index := 0
			for fighter in [king, checker]:
				var cfg: Dictionary = plan["ai"]["king"] if fighter == king else plan["ai"]["checker"]
				var other: FighterController = checker if fighter == king else king
				var builder := CombatInputBuilder.new(request["matchId"], request["battleId"], fighter.player_id)
				bots.append(CombatAI.new(builder, fighter.stats, other.stats, seed_value * 2 + 1 + index, float(cfg["skill"]), String(cfg["style"])))
				index += 1
		else:
			if int(plan.get("king_damage", 0)) > 0:
				king.health.apply_damage(int(plan["king_damage"]))
			if plan.get("kill_king", false):
				king.health.apply_damage(100000)
			if plan.get("kill_checker", false):
				checker.health.apply_damage(100000)
		var ticks := 0
		while sim.is_running() and ticks < 7000:
			if not bots.is_empty():
				var snap := sim.snapshot(false)
				for bot in bots:
					sim.submit_input(bot.think(snap))
			sim.step_tick()
			ticks += 1
		return sim.result.duplicate(true)


static func _rig(fen: String, host_parent: Node) -> Array:
	var game := Royal.new()
	var adapter := SimAdapter.new()
	var flow := Flow.new()
	var host := Node.new()
	host_parent.add_child(host)
	host_parent.add_child(adapter)
	host_parent.add_child(flow)
	flow.set_process(false)
	flow.setup(game, adapter, host)
	return [game, adapter, flow, host]


static func _drop_rig(parts: Array) -> void:
	parts[2].dispose()
	for node in [parts[2], parts[1], parts[3]]:
		node.queue_free()


## Banner -> loading -> countdown -> (the real simulation plays `plan`) -> result -> aftermath -> board / next banner, through BattleFlow.
static func _fight(h, parts: Array, plan: Dictionary, label: String) -> Dictionary:
	var adapter: SimAdapter = parts[1]
	var flow: BattleFlow = parts[2]
	flow.advance(Flow.ROYAL_BANNER_SECONDS + 0.1)
	h.eq(flow.phase, "loading", label + ": the royal duel starts after its banner")
	adapter.finish_load() if adapter.pending_load else null
	h.eq(flow.phase, "countdown", label + ": countdown")
	var result: Dictionary = adapter.play(plan)
	adapter.result_received.emit(result)
	h.eq(flow.phase, "aftermath", label + ": the validated result is shown")
	flow.advance(2.1)
	return result


# ---- 1. texts ----------------------------------------------------------------------------------------------------------------
static func _texts(h) -> void:
	h.begin("royal flow: banner / HUD / result texts")
	h.eq(RoyalPresenter.banner_title(1, 3), "KING'S LAST STAND - duel 2 of 3", "banner title is 1-based")
	h.eq(RoyalPresenter.hud_context(0, 2), "LAST STAND\nDUEL 1/2", "HUD context line")
	h.check(RoyalPresenter.sequence_text({"outcome": "king_survived", "duels": [1, 2]}).contains("2 duels won"), "survival text counts the duels")
	h.check(RoyalPresenter.sequence_text({"outcome": "king_fell", "duels": [1, 2]}).contains("duel 2"), "defeat text names the duel")
	h.check(RoyalOption.EXPLANATION.contains("checkmate") and RoyalOption.EXPLANATION.length() < 400, "the rule is explained in one short paragraph")
	var hud := CombatHud.new()
	h.eq(hud.context_text(), "", "no context by default")
	hud.free()


# ---- 2. toggle + persistence -----------------------------------------------------------------------------------------------
static func _toggle_and_persistence(h, tree: SceneTree) -> void:
	h.begin("royal flow: ruleset toggle (default off, persisted, New game dialog, Play page, launch)")
	# Persistence in its own file (the suite runs in a throw-away user:// by scripts/test-royal.mjs; the file is removed again).
	var path := ProjectSettings.globalize_path(RoyalOption.PATH)
	var saved_persist: bool = RoyalOption.persist
	RoyalOption.persist = true
	if FileAccess.file_exists(RoyalOption.PATH):
		DirAccess.remove_absolute(path)
	RoyalOption.reset_cache()
	h.check(not RoyalOption.load_choice(), "the default is OFF")
	RoyalOption.save_choice(true)
	RoyalOption.reset_cache()
	h.check(RoyalOption.load_choice(), "an ON choice survives a restart (reloaded from disk)")
	RoyalOption.save_choice(false)
	RoyalOption.reset_cache()
	h.check(not RoyalOption.load_choice(), "an OFF choice is persisted as well")
	RoyalOption.save_choice(true)  # the New game dialog below must start from the persisted ON
	RoyalOption.reset_cache()
	RoyalOption.persist = saved_persist
	# New game dialog (local Battle + computer opponent glue).
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app.set_world_mode(false)
	h.check(app.opponent.find_royal_toggle() == null, "Classic game: the New game dialog has no ruleset toggle")
	app._switch_mode(1)
	h.check(not app.game is Royal, "Battle C0 is the default Battle ruleset")
	app.opponent.royal_state["royal"] = RoyalOption.load_choice()
	app.opponent.prepare_new_dialog()
	var toggle: Button = app.opponent.find_royal_toggle()
	h.check(toggle != null and toggle.button_pressed and "ON" in toggle.text, "Battle game: the dialog shows the toggle with the persisted choice")
	h.check(app.opponent.royal_explanation().length() > 40, "the rule explanation is shown in the dialog")
	toggle.pressed.emit()
	await tree.process_frame
	h.check(not bool(app.opponent.royal_state["royal"]) and not (app.opponent.find_royal_toggle().button_pressed), "pressing the toggle turns it off")
	app.opponent.find_royal_toggle().pressed.emit()
	await tree.process_frame
	h.check(bool(app.opponent.royal_state["royal"]), "and on again")
	app._start_game()
	h.check(app.game is Royal and app.mode_label.text == "BATTLE · LAST STAND", "Start game with the toggle ON creates a BattleRoyalMatch")
	h.check(is_instance_valid(app.royal_presenter) and app.battle_flow != null, "the royal presenter and the flow exist")
	app.opponent.royal_state["royal"] = false
	app._start_game()
	h.check(app.game is BattleChessMatch and not app.game is Royal, "Start game with the toggle OFF returns to the standard Battle match")
	h.check(not is_instance_valid(app.royal_presenter), "no royal presenter for the standard ruleset")
	# Computer opponent: the toggle works together with it.
	app.opponent.royal_state["royal"] = true
	app.opponent.selection = {"kind": "computer", "level": 2, "color": "w"}
	app.opponent.prepare_new_dialog()
	h.check(app.opponent.find_royal_toggle() != null, "the toggle is offered next to the computer opponent options")
	app._start_game()
	h.check(app.game is Royal and app.opponent.computer.active and app.opponent.computer.human_color == "w", "royal game against the computer (you play White)")
	h.check(app.battle_adapter.computer_seat.get("color", "") == "b", "the computer fights Black's duels (the human fights White's)")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame
	# Launch from the Play page: Settings.launch.royal -> main creates the royal match.
	AppSettings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false, "royal": true}
	app = Main.instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	h.check(app.game is Royal, "a Play-page launch with royal=true opens King's last stand")
	app.queue_free()
	await tree.process_frame
	AppSettings.launch = {"mode": "battle", "initialMs": 0, "incrementMs": 0, "view3d": false}
	app = Main.instantiate()
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	h.check(app.game is BattleChessMatch and not app.game is Royal, "a launch without the flag opens the standard Battle ruleset")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame
	# Play page.
	AppSettings.launch = {}
	RoyalOption.save_choice(false)
	var page = Application.instantiate()
	tree.root.add_child(page)
	await tree.process_frame
	await tree.process_frame
	page.selected_mode = "classic"
	page.navigate("play")
	h.check(page.find_child("RoyalToggle", true, false) == null, "Play page, Classic: no toggle")
	page.selected_mode = "battle"
	page.online = true
	page.navigate("play")
	h.check(page.find_child("RoyalToggle", true, false) == null, "Play page, Battle online: no toggle (the online protocol cannot carry it yet)")
	page.online = false
	page.navigate("play")
	var page_toggle: Button = page.find_child("RoyalToggle", true, false)
	h.check(page_toggle != null and not page_toggle.button_pressed, "Play page, local Battle: toggle shown, default OFF")
	h.check(page.find_child("RoyalExplanation", true, false) != null, "Play page: one explanatory paragraph")
	h.check(not page.launch_data().has("royal"), "OFF: the launch data carries no flag")
	page_toggle.pressed.emit()
	await tree.process_frame
	await tree.process_frame
	h.check(bool(page.ruleset.royal) and RoyalOption.load_choice(), "pressing it turns it ON and remembers it")
	h.check(page.launch_data().get("royal", false) and page.launch_data().mode == "battle", "ON: the launch data requests King's last stand")
	page.opponent.kind = "computer"
	page.navigate("play")
	h.check(page.find_child("RoyalToggle", true, false) != null and page.launch_data().get("royal", false) and page.launch_data().opponent.kind == "computer", "Computer opponent keeps the toggle and the flag")
	page.selected_mode = "classic"
	h.check(not page.launch_data().has("royal"), "Classic never carries the flag, even when the preference is ON")
	page.queue_free()
	await tree.process_frame
	await tree.process_frame
	RoyalOption.save_choice(false)
	RoyalOption.reset_cache()
	RoyalOption.persist = saved_persist
	if FileAccess.file_exists(RoyalOption.PATH):
		DirAccess.remove_absolute(path)
	AppSettings.launch = {}


# ---- 3. the local flow end to end: real BattleRoyalMatch + BattleFlow + real CombatSimulation duels ------------------------------
static func _local_flow(h, tree: SceneTree) -> void:
	# One checker, the King wins (scripted knockout after 60 damage): carried HP asserted, the checker leaves the board.
	h.begin("royal flow: 1 checker, King wins")
	var parts := _rig(BACK_RANK, tree.root)
	var game: Royal = parts[0]
	var adapter: SimAdapter = parts[1]
	var flow: BattleFlow = parts[2]
	var events: Array = []
	flow.sequence_started.connect(func(info): events.append(["start", info.attackers.size()]))
	flow.duel_started.connect(func(i, n, hp): events.append(["duel", i, n, hp]))
	flow.duel_finished.connect(func(i, n, summary): events.append(["done", i, n, summary.kingEnd.hp, summary.kingSurvived]))
	flow.sequence_finished.connect(func(summary): events.append(["end", summary.outcome]))
	game.new_game(0, 0, BACK_RANK)
	h.check(game.play("a1", "a8").ok and game.royal_active() and flow.is_royal_duel(), "the mating move opens the sequence")
	var king_max := int(game.royal_request().king.stats.maxHp)
	var result := await _fight(h, parts, {"king_damage": 60, "kill_checker": true}, "1 checker")
	h.eq(result.outcome, "attacker", "the King won the real duel")
	h.eq(adapter.started_options[0].initial_hp, king_max, "duel 1 starts with a full King")
	h.eq(game.royal_log[0].duels[0].kingEnd.hp, king_max - 60, "the real simulation ended 60 HP down")
	h.eq(events, [["start", 1], ["duel", 0, 1, king_max], ["done", 0, 1, king_max - 60, true], ["end", "king_survived"]], "events: start, duel, done(carried HP), end")
	h.check(not game.royal_active() and game.engine.result.is_empty() and game.engine.turn == "b", "play continues with the mated side to move")
	h.check(game.engine.board[Rules.index("a8")] == "", "the checking rook was removed")
	h.check(game.royal_log.size() == 1 and game.royal_log[0].outcome == "king_survived" and game.royal_log[0].kingEnd.hp == king_max - 60, "the chronicle records the sequence and the King's end state")
	h.eq(adapter.loads, 1, "one scene load")
	_drop_rig(parts)

	# Two checkers, the King wins both: carried HP / stamina / cooldown from the REAL simulation into duel 2.
	h.begin("royal flow: 2 checkers, King wins both, carried state asserted at each duel")
	parts = _rig(BOTH, tree.root)
	game = parts[0]
	adapter = parts[1]
	flow = parts[2]
	events.clear()
	flow.duel_started.connect(func(i, n, hp): events.append(["duel", i, n, hp]))
	flow.duel_finished.connect(func(i, n, summary): events.append(["done", i, n, summary.kingEnd.hp, summary.kingEnd.stamina, summary.kingEnd.cooldownTicks]))
	game.new_game(0, 0, BOTH)
	h.check(game.royal_active() and game.royal_progress().duelCount == 2 and game.royal_progress().remaining.size() == 2, "a loaded mate opens a two-duel sequence")
	king_max = int(game.royal_request().king.stats.maxHp)
	result = await _fight(h, parts, {"king_damage": 40, "kill_checker": true}, "duel 1")
	h.eq(flow.phase, "preview", "duel 1 -> banner of duel 2 (no board in between)")
	var progress: Dictionary = game.royal_progress()
	h.eq(progress.duelIndex, 1, "duel 2 is next")
	h.eq(progress.king.hp, king_max - 40, "the King's carried HP is 40 down")
	h.check(progress.king.stamina <= float(game.royal_request().king.stats.maxStamina), "carried stamina never exceeds the maximum")
	var carried: Dictionary = progress.king.duplicate()
	result = await _fight(h, parts, {"king_damage": 50, "kill_checker": true}, "duel 2")
	h.eq(adapter.started_options[1].initial_hp, king_max - 40, "duel 2 started from the carried HP")
	h.eq(adapter.started_options[1].initial_stamina, carried.stamina, "duel 2 started from the carried stamina")
	h.eq(adapter.started_options[1].initial_cooldown, carried.cooldownTicks, "duel 2 started from the carried ability cooldown")
	h.eq(events.filter(func(e): return e[0] == "duel").map(func(e): return e[3]), [king_max, king_max - 40], "duel_started reports the carried HP (full, then 40 down)")
	h.eq(events.filter(func(e): return e[0] == "done").map(func(e): return e[3]), [king_max - 40, king_max - 90], "duel_finished reports the King's end HP of each duel")
	h.check(game.engine.result.is_empty() and not game.royal_active() and game.engine.turn == "b", "King won both: the game continues")
	h.check(game.engine.board[Rules.index("a8")] == "" and game.engine.board[Rules.index("e1")] == "", "both checkers were removed")
	h.eq(adapter.loads, 2, "without the pit world every duel loads its own arena (the reuse path is exercised in the world tests)")
	_drop_rig(parts)

	# The King loses the first duel: checkmate, board untouched, the second checker never fights.
	h.begin("royal flow: King loses the first duel")
	parts = _rig(BOTH, tree.root)
	game = parts[0]
	adapter = parts[1]
	flow = parts[2]
	game.new_game(0, 0, BOTH)
	var fen_before: String = game.engine.fen()
	result = await _fight(h, parts, {"kill_king": true}, "lost duel")
	h.eq(result.outcome, "defender", "the real simulation: the checker won")
	h.check(game.engine.result == "1-0" and game.engine.reason == "Checkmate" and game.engine.fen() == fen_before, "the match ends as checkmate for White; the board is untouched")
	h.eq(adapter.starts, 1, "the second checker never fought")
	h.eq(game.royal_log[0].outcome, "king_fell", "chronicle: king_fell")
	_drop_rig(parts)

	# Three checkers, the King wins the first and loses the second (loses in the MIDDLE): the third never fights.
	h.begin("royal flow: 3 checkers, King wins duel 1 and loses duel 2")
	parts = _rig(THREE, tree.root)
	game = parts[0]
	adapter = parts[1]
	flow = parts[2]
	game.new_game(0, 0, THREE)
	h.check(game.royal_active() and game.royal_progress().duelCount == 3, "three checkers: Nf6, Nh6, Ra8")
	var order: Array = game.royal_request().attackers.map(func(a): return a.role + a.square)
	h.eq(order, ["nf6", "nh6", "ra8"], "fighting order: value, then square")
	fen_before = game.engine.fen()
	king_max = int(game.royal_request().king.stats.maxHp)
	await _fight(h, parts, {"king_damage": 30, "kill_checker": true}, "duel 1")
	h.eq(game.royal_progress().king.hp, king_max - 30, "duel 2 starts 30 down")
	result = await _fight(h, parts, {"kill_king": true}, "duel 2")
	h.eq(result.outcome, "defender", "the King fell in the middle of the sequence")
	h.check(game.engine.result == "1-0" and game.engine.fen() == fen_before, "checkmate; the board is untouched (the knight the King beat is still there)")
	h.eq(adapter.starts, 2, "the third duel never started")
	h.eq(game.royal_log[0].duels.size(), 2, "two duels in the chronicle")
	_drop_rig(parts)

	# CombatAI duels (outcome-agnostic): whatever happens, the carried state and the board are consistent.
	h.begin("royal flow: CombatAI-driven sequence is consistent (either outcome)")
	parts = _rig(BOTH, tree.root)
	game = parts[0]
	adapter = parts[1]
	flow = parts[2]
	game.new_game(0, 0, BOTH)
	fen_before = game.engine.fen()
	var plan := {"ai": {"king": {"style": "duelist", "skill": 0.9}, "checker": {"style": "balanced", "skill": 0.5}}}
	var previous_hp := int(game.royal_request().king.stats.maxHp)
	var duels_played := 0
	while game.royal_active() and duels_played < 3:
		h.eq(game.royal_progress().king.hp, previous_hp, "AI duel %d starts from the carried HP" % (duels_played + 1))
		result = await _fight(h, parts, plan, "AI duel %d" % (duels_played + 1))
		duels_played += 1
		var summary: Dictionary = game.royal_log.back().duels.back() if not game.royal_log.is_empty() else {}
		if game.royal_active():
			previous_hp = int(game.royal_progress().king.hp)
			h.check(previous_hp > 0 and previous_hp <= int(game.royal_request().king.stats.maxHp), "carried HP in range")
	var outcome: String = game.royal_log[0].outcome
	h.check(outcome in ["king_survived", "king_fell"], "the sequence ended with a defined outcome (%s)" % outcome)
	if outcome == "king_fell":
		h.check(game.engine.result == "1-0" and game.engine.fen() == fen_before, "King fell: checkmate, board untouched")
	else:
		h.check(game.engine.board[Rules.index("a8")] == "" and game.engine.board[Rules.index("e1")] == "", "King survived: both checkers removed")
	h.eq(game.royal_log[0].duels.size(), duels_played, "every fought duel is in the chronicle")
	_drop_rig(parts)
	await tree.process_frame
	await tree.process_frame


# ---- 4. the pit presentation of a multi-duel sequence ----------------------------------------------------------------------------
const WorldTests := preload("res://combat/tests/test_world.gd")
const PHASES := ["IDLE", "CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "INTERLUDE"]

class Authority extends RefCounted:
	var state := {"hp": 160, "stamina": 100.0, "cooldownTicks": 0}
	func fighter_state(_player_id: String) -> Dictionary:
		return state


static func _royal_fixture(tree: SceneTree, fen: String) -> Dictionary:
	var holder := Control.new()
	holder.size = Vector2(800, 600)
	tree.root.add_child(holder)
	var game := Royal.new()
	var authority := Authority.new()
	game.bind_combat_authority(authority)
	game.new_game(0, 0, fen)
	var interaction := Interaction.new(game)
	var board := ChessBoard3D.new()
	board.size = Vector2(800, 600)
	holder.add_child(board)
	board.setup(game, interaction)
	board.animation_enabled = false
	var world: BattleWorld = board.world
	world.auto_advance = false
	world.pit.require_arena = false
	await tree.process_frame
	return {"holder": holder, "game": game, "interaction": interaction, "board": board, "world": world, "authority": authority}


## The match-level commit of the pending duel (what BattleFlow + the combat authority do): the King wins or loses with `end` left.
static func _commit(game: Royal, authority: Authority, king_wins: bool, end: Dictionary) -> Dictionary:
	var pending: Dictionary = game.pending_request()
	authority.state = end
	var side := "attacker" if king_wins else "defender"
	var result := {"schemaVersion": 1, "matchId": game.match_id, "battleId": pending.battleId, "expectedRevision": game.revision, "resolvedTick": pending.startTick + 181, "winnerPlayerId": pending[side].playerId, "outcome": side, "reason": "knockout", "attackerHp": end.hp, "defenderHp": 0 if king_wins else 50}
	var accepted: Dictionary = game.accept_result(result, authority)
	return game.commit_battle() if accepted.ok else accepted


## Starts the presentation of the sequence the match has just opened (duel 1).
static func _start_pit(h, fx: Dictionary, label: String) -> bool:
	var game: Royal = fx["game"]
	var pit: PitSequence = fx["world"].pit
	var ok_seq: bool = pit.begin_sequence(game.royal_request(), int(game.royal_progress().duelIndex))
	var ok_begin: bool = pit.begin(game.pending_request())
	return h.check(ok_seq and ok_begin, label + ": sequence + first duel started")


## Presents the result of the duel that is on screen: result to the pit, the committed outcome to the match at the same moment
## the bridge does (duel_cleared for a non-final King win, return_ready after the climb).
static func _play_duel(h, fx: Dictionary, king_wins: bool, end: Dictionary, label: String) -> void:
	var world: BattleWorld = fx["world"]
	var pit: PitSequence = world.pit
	h.check(WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2), label + ": combat reached")
	pit.present_result({"outcome": "attacker" if king_wins else "defender"})


static func _free_fx(fx: Dictionary, tree: SceneTree) -> void:
	fx["interaction"].dispose()
	fx["holder"].queue_free()
	await tree.process_frame


static func _pit_sequences(h, tree: SceneTree) -> void:
	# --- A: two duels, the King wins both: ONE descent, an interlude, ONE climb; the King returns to its own square.
	var fx: Dictionary = await _royal_fixture(tree, BOTH)
	var world: BattleWorld = fx["world"]
	var pit: PitSequence = world.pit
	var game: Royal = fx["game"]
	var authority: Authority = fx["authority"]
	h.begin("royal pit: two duels, King wins both (one descent, interlude, one climb)")
	var phases: Array = []
	var signals := {"cleared": [], "ended": 0, "combat_started": 0, "drop_started": 0, "finished": 0}
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	pit.duel_cleared.connect(func(i: int): signals["cleared"].append(i))
	pit.sequence_ended.connect(func(): signals["ended"] += 1)
	pit.combat_started.connect(func(): signals["combat_started"] += 1)
	pit.drop_started.connect(func(): signals["drop_started"] += 1)
	pit.finished.connect(func(): signals["finished"] += 1)
	var king_node: Node3D = fx["board"].pieces["b-k-e8"]
	var checker_nodes: Array = [fx["board"].pieces["w-r-e1"], fx["board"].pieces["w-r-a8"]]
	h.check(game.royal_active() and game.pending_request().defender.pieceId == "w-r-e1", "the loaded mate opens duel 1 against Re1")
	_start_pit(h, fx, "A")
	h.check(pit.sequence_active() and pit.sequence_total() == 2 and pit.sequence_index() == 0, "the pit tracks duel 1 of 2")
	_play_duel(h, fx, true, {}, "A duel 1")
	h.check(WorldTests._run_to(world, PitSequence.Phase.INTERLUDE, 0.0), "A: duel 1 resolves into the INTERLUDE (no climb)")
	h.eq(signals["cleared"], [0], "duel_cleared(0) was emitted")
	h.check(world.shifted and world.trapdoor.is_open() and world.chamber.visible, "A: the pit stays in the chamber: board lifted, trapdoor open")
	h.eq(world.rig.state, CameraRig.State.COMBAT_VICTORY, "A: the camera stays below")
	h.check(not pit.is_idle() and fx["board"].sync_hold, "A: the chess board stays held while the sequence runs")
	WorldTests._step(world, 1.0)
	h.eq(pit.phase, PitSequence.Phase.INTERLUDE, "A: the interlude holds until the next duel is armed")
	var carried := {"hp": 100, "stamina": 55.5, "cooldownTicks": 220}
	h.check(_commit(game, authority, true, carried).ok and game.pending_request().defender.pieceId == "w-r-a8", "A: duel 1 committed at the match, duel 2 prepared")
	h.check(pit.next_duel(game.pending_request()), "A: next_duel accepted in the INTERLUDE")
	h.check(not checker_nodes[1].visible, "A: the next checker has stepped into the pit (its board mesh is hidden)")
	h.check(pit.sequence_index() == 1, "A: the pit moved to duel 2")
	h.check(not pit.next_duel(game.pending_request()), "A: next_duel is refused while the step-in runs")
	h.check(WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.1), "A: duel 2 reaches COMBAT again")
	h.eq(world.rig.state, CameraRig.State.COMBAT_THIRD_PERSON, "A: third-person camera for duel 2")
	h.eq(signals["combat_started"], 2, "A: combat_started twice (once per duel)")
	h.eq(signals["drop_started"], 1, "A: ONE descent for the whole sequence")
	pit.return_ready.connect(func(): _commit(game, authority, true, {"hp": 60, "stamina": 20.0, "cooldownTicks": 100}))
	pit.present_result({"outcome": "attacker"})
	h.check(WorldTests._run_to(world, PitSequence.Phase.IDLE, 0.0), "A: the sequence completes")
	WorldTests._step(world, 0.3)
	h.eq(phases, ["CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "INTERLUDE", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "IDLE"], "A: phase order of a two-duel sequence")
	h.eq(signals["ended"], 1, "A: sequence_ended once")
	h.eq(signals["finished"], 1, "A: finished once")
	h.check(not game.royal_active() and game.engine.result.is_empty(), "A: the match committed the sequence (King survived, play continues)")
	await tree.process_frame
	WorldTests._world_is_chess(h, fx, "A: after the sequence")
	h.check((king_node.position - Interaction.world_position(Rules.index("e8"))).length() < 0.02, "A: the King is back on ITS OWN square (e8)")
	h.check(not is_instance_valid(checker_nodes[0]) or not checker_nodes[0].is_inside_tree() or not checker_nodes[0].visible, "A: the removed checkers are gone from the board")
	h.eq(fx["board"].pieces.size(), game.chess_state().pieces.size(), "A: mesh registry equals the committed position")
	h.check(game.engine.board[Rules.index("a8")] == "" and game.engine.board[Rules.index("e1")] == "", "A: both checking rooks left the position")
	await _free_fx(fx, tree)

	# --- B: the King wins duel 1 and loses duel 2: the winning checker climbs, then every piece is where the (untouched) board has it.
	fx = await _royal_fixture(tree, BOTH)
	world = fx["world"]
	pit = world.pit
	game = fx["game"]
	authority = fx["authority"]
	h.begin("royal pit: the King loses the last duel (the winning checker climbs out; the board is untouched)")
	phases = []
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	_start_pit(h, fx, "B")
	var fen_before: String = game.engine.fen()
	_play_duel(h, fx, true, {}, "B duel 1")
	WorldTests._run_to(world, PitSequence.Phase.INTERLUDE, 0.0)
	_commit(game, authority, true, {"hp": 20, "stamina": 5.0, "cooldownTicks": 50})
	h.check(pit.next_duel(game.pending_request()), "B: next_duel")
	WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.1)
	pit.return_ready.connect(func(): _commit(game, authority, false, {"hp": 0, "stamina": 0.0, "cooldownTicks": 0}))
	pit.present_result({"outcome": "defender"})
	h.check(WorldTests._run_to(world, PitSequence.Phase.IDLE, 0.0), "B: completes")
	WorldTests._step(world, 0.3)
	h.eq(phases.slice(phases.size() - 4), ["RESOLVE", "CLIMB", "RETURN", "IDLE"], "B: a lost last duel climbs the winner out")
	h.check(game.engine.result == "1-0" and game.engine.fen() == fen_before, "B: checkmate stands, board untouched")
	await tree.process_frame
	WorldTests._world_is_chess(h, fx, "B: after the sequence")
	await _free_fx(fx, tree)

	# --- C: the King loses duel 1: no interlude at all.
	fx = await _royal_fixture(tree, BOTH)
	world = fx["world"]
	pit = world.pit
	game = fx["game"]
	authority = fx["authority"]
	h.begin("royal pit: the King loses duel 1 (no interlude, no second duel)")
	phases = []
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	_start_pit(h, fx, "C")
	_play_duel(h, fx, false, {}, "C")
	pit.return_ready.connect(func(): _commit(game, authority, false, {"hp": 0, "stamina": 0.0, "cooldownTicks": 0}))
	h.check(WorldTests._run_to(world, PitSequence.Phase.IDLE, 0.0), "C: completes")
	WorldTests._step(world, 0.3)
	h.check(not "INTERLUDE" in phases and phases.count("CLIMB") == 1, "C: no INTERLUDE, one CLIMB")
	h.eq(game.engine.result, "1-0", "C: checkmate")
	await tree.process_frame
	WorldTests._world_is_chess(h, fx, "C: after the sequence")
	await _free_fx(fx, tree)

	await _pit_interruptions(h, tree)
	await _pit_leaks(h, tree)


## Interruption at every point of a two-duel sequence: the world is a consistent top-down chess world again, nothing is left over.
static func _pit_interruptions(h, tree: SceneTree) -> void:
	var points := [
		["CAPTURE_FOCUS", PitSequence.Phase.CAPTURE_FOCUS, 0.3, 0],
		["TRAPDOOR_OPEN", PitSequence.Phase.TRAPDOOR_OPEN, 0.3, 0],
		["DROP (falling)", PitSequence.Phase.DROP, 0.4, 0],
		["DROP (landed)", PitSequence.Phase.DROP, 1.5, 0],
		["COMBAT duel 1", PitSequence.Phase.COMBAT, 0.4, 0],
		["RESOLVE duel 1", PitSequence.Phase.RESOLVE, 0.9, 0],
		["INTERLUDE (holding)", PitSequence.Phase.INTERLUDE, 0.5, 1],
		["INTERLUDE (step-in)", PitSequence.Phase.INTERLUDE, 0.3, 2],
		["COMBAT duel 2", PitSequence.Phase.COMBAT, 0.4, 2],
		["RESOLVE duel 2", PitSequence.Phase.RESOLVE, 0.9, 3],
		["CLIMB (ladder)", PitSequence.Phase.CLIMB, 1.0, 3],
		["CLIMB (top)", PitSequence.Phase.CLIMB, 4.2, 3],
		["RETURN (morph)", PitSequence.Phase.RETURN, 0.2, 3],
		["RETURN (camera)", PitSequence.Phase.RETURN, 1.2, 3],
	]
	h.begin("royal pit: interruption at every point of a two-duel sequence")
	for entry in points:
		var label: String = "interrupt at " + entry[0]
		var stage: int = entry[3]   # 0 = duel 1 only, 1 = duel 1 won + interlude, 2 = duel 2 armed, 3 = duel 2 won (final)
		var fx: Dictionary = await _royal_fixture(tree, BOTH)
		var world: BattleWorld = fx["world"]
		var pit: PitSequence = world.pit
		var game: Royal = fx["game"]
		var authority: Authority = fx["authority"]
		# Warm up the lazily built props, then take the node and geometry baseline.
		_start_pit(h, fx, label)
		WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.1)
		pit.abort("warm-up")
		WorldTests._step(world, 0.6)
		await tree.process_frame
		var nodes: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
		var geometry: Dictionary = WorldTests._snapshot_board(fx["board"])
		var counters := {"aborted": 0, "ended": 0}
		pit.aborted.connect(func(_reason: String): counters["aborted"] += 1)
		pit.sequence_ended.connect(func(): counters["ended"] += 1)
		var fen: String = game.engine.fen()
		var reached := false
		_start_pit(h, fx, label)
		if stage == 0:
			if entry[1] == PitSequence.Phase.RESOLVE:
				WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2)
				pit.present_result({"outcome": "attacker"})
			reached = WorldTests._run_to(world, entry[1], entry[2])
		else:
			WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2)
			pit.present_result({"outcome": "attacker"})
			reached = WorldTests._run_to(world, PitSequence.Phase.INTERLUDE, 0.0)
		h.check(reached, label + ": target phase reached")
		if stage >= 1:
			if stage == 1:
				WorldTests._step(world, entry[2])
			else:
				h.check(_commit(game, authority, true, {"hp": 90, "stamina": 40.0, "cooldownTicks": 10}).ok and pit.next_duel(game.pending_request()), label + ": duel 2 armed")
				if stage == 2:
					if entry[1] == PitSequence.Phase.INTERLUDE:
						WorldTests._step(world, entry[2])
					else:
						reached = WorldTests._run_to(world, entry[1], entry[2])
				else:
					WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2)
					pit.present_result({"outcome": "attacker"})
					reached = WorldTests._run_to(world, entry[1], entry[2])
		h.eq(pit.phase, entry[1], label + ": presenting the intended phase")
		pit.abort("test")
		h.eq(counters["aborted"], 1, label + ": aborted signal")
		h.eq(counters["ended"], 1, label + ": sequence_ended")
		h.check(not pit.sequence_active() and pit.is_idle(), label + ": no sequence state left")
		WorldTests._step(world, 0.6)
		await tree.process_frame
		WorldTests._world_is_chess(h, fx, label)
		h.check(not world.rig.is_transitioning() and world.rig.state == world.rig.chess_view and world.rig.camera.position.distance_to(world.rig.pose_for(world.rig.chess_view)["p"]) < 0.01, label + ": camera back in the chess view")
		if stage <= 1:
			h.eq(game.engine.fen(), fen, label + ": chess position untouched")
		h.eq(Performance.get_monitor(Performance.OBJECT_NODE_COUNT), nodes, label + ": no orphan nodes")
		h.check(WorldTests._snapshot_board(fx["board"]) == geometry, label + ": board geometry identical to before")
		# An interrupted duel is re-armed by the flow: the very next presentation starts at the match's current duel.
		var progress: Dictionary = game.royal_progress()
		h.check(pit.begin_sequence(game.royal_request(), int(progress.duelIndex)) and pit.begin(game.pending_request()), label + ": the pending duel can be presented again right away")
		h.eq(pit.sequence_index(), int(progress.duelIndex), label + ": at the match's duel index")
		pit.abort("cleanup")
		WorldTests._step(world, 0.6)
		await tree.process_frame
		await _free_fx(fx, tree)


## Three whole sequences back to back leak no nodes and leave the geometry alone.
static func _pit_leaks(h, tree: SceneTree) -> void:
	var fx: Dictionary = await _royal_fixture(tree, BOTH)
	var world: BattleWorld = fx["world"]
	var pit: PitSequence = world.pit
	var game: Royal = fx["game"]
	var authority: Authority = fx["authority"]
	h.begin("royal pit: three whole sequences leak no nodes")
	var counts: Array = []
	var world_counts: Array = []
	var geometry: Dictionary = {}
	for round in 3:
		game.new_game(0, 0, BOTH)
		await tree.process_frame
		_start_pit(h, fx, "round %d" % (round + 1))
		WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2)
		pit.present_result({"outcome": "attacker"})
		WorldTests._run_to(world, PitSequence.Phase.INTERLUDE, 0.0)
		_commit(game, authority, true, {"hp": 100, "stamina": 50.0, "cooldownTicks": 30})
		pit.next_duel(game.pending_request())
		WorldTests._run_to(world, PitSequence.Phase.COMBAT, 0.2)
		var commit_final := func(): _commit(game, authority, true, {"hp": 70, "stamina": 20.0, "cooldownTicks": 30})
		pit.return_ready.connect(commit_final)
		pit.present_result({"outcome": "attacker"})
		h.check(WorldTests._run_to(world, PitSequence.Phase.IDLE, 0.0), "sequence %d completes" % (round + 1))
		pit.return_ready.disconnect(commit_final)
		WorldTests._step(world, 0.3)
		await tree.process_frame
		await tree.process_frame
		if round == 0:
			geometry = WorldTests._snapshot_board(fx["board"])
		counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		world_counts.append(WorldTests._count(world))
		h.check(WorldTests._snapshot_board(fx["board"]) == geometry, "sequence %d: tile and slab transforms unchanged" % (round + 1))
	h.eq(counts[1], counts[0], "global node count stable after sequence 2")
	h.eq(counts[2], counts[0], "global node count stable after sequence 3")
	h.eq(world_counts[2], world_counts[0], "world subtree size stable")
	h.eq(fx["board"].tiles.size(), 64, "all 64 tiles still present")
	await _free_fx(fx, tree)


# ---- 5. the real application screen: BattleFlow + WorldBattleBridge + PitSequence + RoyalPresenter ---------------------------------
static func _boot(tree: SceneTree, fen: String) -> Dictionary:
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app._switch_mode(1, true)
	var adapter := SimAdapter.new()
	app._configure_battle_flow(adapter)
	app.battle_flow.set_process(false)
	app.board_3d.animation_enabled = false
	var world: BattleWorld = app.board_3d.world
	world.auto_advance = false
	app.game.new_game(0, 0, fen)   # a loaded mate opens the sequence at once
	await tree.process_frame
	return {"app": app, "adapter": adapter, "world": world, "game": app.game, "board": app.board_3d}


## One simulated frame of everything the engine would tick: the asynchronous scene load finishing, the flow clock, the world clock.
static func _pump(ctx: Dictionary, seconds: float, until: Callable = Callable()) -> bool:
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	var adapter: SimAdapter = ctx["adapter"]
	for _i in int(ceil(seconds / DT)):
		if until.is_valid() and until.call():
			return true
		adapter.finish_load()
		if is_instance_valid(app.battle_flow):
			app.battle_flow.advance(DT)
		world.advance(DT)
	return until.is_valid() and until.call()


static func _until_combat(ctx: Dictionary) -> bool:
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	return _pump(ctx, 40.0, func(): return world.pit.phase == PitSequence.Phase.COMBAT and app.battle_flow.phase == "countdown")


## Waits for the duel's COMBAT, lets the REAL simulation decide it by `plan`, and delivers the validated result.
static func _app_duel(h, ctx: Dictionary, plan: Dictionary, label: String) -> Dictionary:
	h.check(_until_combat(ctx), label + ": the pit reached COMBAT with the flow in countdown")
	var adapter: SimAdapter = ctx["adapter"]
	var result: Dictionary = adapter.play(plan)
	adapter.result_received.emit(result)
	return result


static func _app_world(h, tree: SceneTree) -> void:
	# --- the whole sequence through the app: banner, one descent, interlude, carried state, one climb, board back.
	var ctx: Dictionary = await _boot(tree, BOTH)
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	var pit: PitSequence = world.pit
	var adapter: SimAdapter = ctx["adapter"]
	var game: Royal = ctx["game"]
	var flow: BattleFlow = app.battle_flow
	h.begin("royal app: a two-duel sequence through BattleFlow + bridge + pit + presenter")
	var phases: Array = []
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	var banner: PanelContainer = app.royal_presenter.banner
	var king_max := int(game.royal_request().king.stats.maxHp)
	h.check(flow.phase == "preview" and flow.is_royal_duel() and banner.visible, "the loaded mate shows the banner, not the capture preview")
	h.check(not app.battle_card.visible and not app.fight_button.visible and not app.battle_cancel.visible, "no capture preview card / start / cancel for a mandatory duel")
	h.eq(banner.find_child("Title", true, false).text, "KING'S LAST STAND - duel 1 of 2", "banner title (duel 1)")
	h.check("King faces" in banner.find_child("Subtitle", true, false).text or "King faces" in banner.find_child("Subtitle", true, false).text.replace("The Black ", "").replace("The White ", ""), "banner names the matchup")
	var hp_bar = banner.find_child("KingHp", true, false)
	h.check(hp_bar.value == float(king_max) and hp_bar.text == "%d / %d" % [king_max, king_max] and hp_bar.ratio() == 1.0, "duel 1 banner: a full King")
	h.check(pit.is_idle(), "the board is still on screen during the banner")
	# banner (1.5 s) -> the bridge starts the sequence
	h.check(_pump(ctx, 2.0, func(): return not pit.is_idle()), "after the banner the descent begins by itself")
	h.check(pit.sequence_active() and pit.sequence_total() == 2 and pit.sequence_index() == 0, "the pit presents duel 1 of 2")
	h.check(not banner.visible, "the banner is gone once the duel starts")
	var result1: Dictionary = _app_duel(h, ctx, {"king_damage": 60, "kill_checker": true}, "duel 1")
	h.eq(result1.outcome, "attacker", "the real simulation: the King won duel 1")
	h.check(_pump(ctx, 10.0, func(): return pit.phase == PitSequence.Phase.INTERLUDE and flow.phase == "preview"), "RESOLVE ends in the INTERLUDE and the flow shows the next banner")
	h.check(world.shifted and world.trapdoor.is_open() and flow.is_royal_duel() and banner.visible, "still in the chamber; banner up")
	h.eq(banner.find_child("Title", true, false).text, "KING'S LAST STAND - duel 2 of 2", "banner title (duel 2)")
	hp_bar = banner.find_child("KingHp", true, false)
	var stamina_bar = banner.find_child("KingStamina", true, false)
	var cooldown_bar = banner.find_child("KingCooldown", true, false)
	h.check(hp_bar.value == float(king_max - 60) and hp_bar.text == "%d / %d" % [king_max - 60, king_max], "duel 2 banner: HP bar shows the carried HP (%d)" % (king_max - 60))
	h.check(hp_bar.ratio() < 1.0 and absf(hp_bar.ratio() - float(king_max - 60) / float(king_max)) < 0.001, "the HP bar starts at the carried fraction, not full")
	h.check(stamina_bar.value == float(game.royal_progress().king.stamina) and cooldown_bar.text != "", "stamina and cooldown are shown as carried")
	h.check("Carried over" in banner.find_child("Hint", true, false).text, "the banner says the state carries over")
	h.check(game.royal_progress().king.hp == king_max - 60, "the carried HP comes from the match (trusted simulation), not from the UI")
	h.eq(adapter.loads, 1, "only one scene load so far")
	h.check(_pump(ctx, 2.0, func(): return pit.phase == PitSequence.Phase.INTERLUDE and flow.phase == "countdown" and adapter.starts == 2), "after the banner the arena restarts in place (no scene reload)")
	h.eq(adapter.loads, 1, "still ONE scene load: the arena is reused for duel 2")
	h.eq(adapter.started_options[1].initial_hp, king_max - 60, "duel 2 started from the carried HP")
	h.check(not banner.visible, "banner hidden for the fight")
	var result2: Dictionary = _app_duel(h, ctx, {"king_damage": 20, "kill_checker": true}, "duel 2")
	h.eq(result2.outcome, "attacker", "the King won duel 2")
	h.check(_pump(ctx, 30.0, func(): return pit.is_idle() and flow.phase == "board"), "the climb and the return complete")
	await tree.process_frame
	h.eq(phases, ["CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "INTERLUDE", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "IDLE"], "app: one descent, one interlude, one climb")
	h.check(game.engine.result.is_empty() and not game.royal_active() and game.engine.turn == "b", "the match continues (King won everything)")
	h.check(app.interaction.enabled, "board input is back")
	WorldTests._world_is_chess(h, ctx, "app: after the sequence")
	h.eq(game.royal_log[0].duels.size(), 2, "app: both duels are in the chronicle")
	h.check(not app.battle_overlay.visible or not banner.visible, "app: no banner left behind")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	# --- the King falls in duel 2: defeat, result note, board untouched.
	ctx = await _boot(tree, BOTH)
	app = ctx["app"]
	world = ctx["world"]
	pit = world.pit
	adapter = ctx["adapter"]
	game = ctx["game"]
	flow = app.battle_flow
	h.begin("royal app: the King falls in duel 2 (defeat, result note, board untouched)")
	var fen_before: String = game.engine.fen()
	_pump(ctx, 2.0, func(): return not pit.is_idle())
	_app_duel(h, ctx, {"king_damage": 30, "kill_checker": true}, "duel 1")
	_pump(ctx, 10.0, func(): return flow.phase == "preview" and pit.phase == PitSequence.Phase.INTERLUDE)
	_pump(ctx, 2.0, func(): return flow.phase == "countdown" and adapter.starts == 2)
	var lost: Dictionary = _app_duel(h, ctx, {"kill_king": true}, "duel 2")
	h.eq(lost.outcome, "defender", "the real simulation: the checker won duel 2")
	h.check(_pump(ctx, 30.0, func(): return pit.is_idle() and flow.phase == "board"), "the winner climbs out and the board returns")
	await tree.process_frame
	await tree.process_frame
	h.check(game.engine.result == "1-0" and game.engine.reason == "Checkmate" and game.engine.fen() == fen_before, "checkmate for White; the board is untouched")
	WorldTests._world_is_chess(h, ctx, "app: after the defeat")
	var note: String = app.royal_presenter.result_note()
	h.check("fell in duel 2 of 2" in note and "Rook" in note and "checkmate stands" in note and "won 1 duel" in note, "result note explains the last stand: " + note)
	var dialog: Node = null
	for child in app.get_children():
		if child is AcceptDialog:
			dialog = child
	h.check(dialog != null and dialog.find_child("ResultNote", true, false) != null and "King's last stand" in dialog.find_child("ResultNote", true, false).text, "the result screen carries the King's last stand explanation")
	h.check(not app.battle_overlay.visible or not app.royal_presenter.banner.visible, "no banner after the match")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	await _app_interruptions(h, tree)


## Interruptions through the real flow, at points before / between / during duels.
static func _app_interruptions(h, tree: SceneTree) -> void:
	h.begin("royal app: resign / failure / exit at any point leaves a consistent board")
	# 1. Resign during the first descent.
	var ctx: Dictionary = await _boot(tree, BOTH)
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	var pit: PitSequence = world.pit
	var adapter: SimAdapter = ctx["adapter"]
	var game: Royal = ctx["game"]
	var flow: BattleFlow = app.battle_flow
	_pump(ctx, 8.0, func(): return pit.phase == PitSequence.Phase.DROP)
	h.eq(pit.phase, PitSequence.Phase.DROP, "1: falling into the pit")
	app.opponent.resign()  # the acting side (the mated one) resigns
	await tree.process_frame
	_pump(ctx, 1.0)
	h.check(game.engine.result == "1-0" and game.engine.reason == "Resignation" and not game.royal_active() and flow.phase == "board" and pit.is_idle(), "1: resign in the descent: the match is over, the sequence dropped, the pit idle")
	WorldTests._world_is_chess(h, ctx, "1: after resigning in the descent")
	h.eq(game.royal_log[0].outcome, "abandoned", "1: chronicle: abandoned (no invented result)")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	# 2. Resign in the interlude banner (duel 1 won, duel 2 pending).
	ctx = await _boot(tree, BOTH)
	app = ctx["app"]
	world = ctx["world"]
	pit = world.pit
	adapter = ctx["adapter"]
	game = ctx["game"]
	flow = app.battle_flow
	_pump(ctx, 2.0, func(): return not pit.is_idle())
	_app_duel(h, ctx, {"king_damage": 10, "kill_checker": true}, "2: duel 1")
	_pump(ctx, 10.0, func(): return flow.phase == "preview" and pit.phase == PitSequence.Phase.INTERLUDE)
	h.check(pit.phase == PitSequence.Phase.INTERLUDE and flow.phase == "preview", "2: in the interlude with the banner up")
	game.resign()
	await tree.process_frame
	_pump(ctx, 1.0)
	h.check(game.engine.result != "" and flow.phase == "board" and pit.is_idle() and not app.royal_presenter.banner.visible, "2: resign in the interlude: result set, pit idle, banner gone")
	WorldTests._world_is_chess(h, ctx, "2: after resigning in the interlude")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	# 3. The combat authority fails (disconnect) in duel 2: the duel is re-armed from its start state and presented again from the pit.
	ctx = await _boot(tree, BOTH)
	app = ctx["app"]
	world = ctx["world"]
	pit = world.pit
	adapter = ctx["adapter"]
	game = ctx["game"]
	flow = app.battle_flow
	var king_max := int(game.royal_request().king.stats.maxHp)
	_pump(ctx, 2.0, func(): return not pit.is_idle())
	_app_duel(h, ctx, {"king_damage": 50, "kill_checker": true}, "3: duel 1")
	_pump(ctx, 10.0, func(): return flow.phase == "preview" and pit.phase == PitSequence.Phase.INTERLUDE)
	_pump(ctx, 2.0, func(): return flow.phase == "countdown" and adapter.starts == 2)
	adapter.failed.emit("simulated disconnect")
	await tree.process_frame
	h.check(pit.is_idle() and game.royal_active() and flow.phase == "preview" and flow.is_royal_duel(), "3: the failure aborted the presentation; the match re-armed duel 2")
	WorldTests._world_is_chess(h, ctx, "3: after the failure")
	h.eq(game.royal_progress().king.hp, king_max - 50, "3: the King's carried HP survived the failure")
	h.check(_pump(ctx, 2.5, func(): return not pit.is_idle() and flow.phase in ["loading", "countdown"]), "3: after the banner a fresh descent starts")
	h.eq(pit.sequence_index(), 1, "3: the pit presents duel 2 of 2 (index 1)")
	var again: Dictionary = _app_duel(h, ctx, {"king_damage": 10, "kill_checker": true}, "3: duel 2 (retry)")
	h.eq(again.outcome, "attacker", "3: the retried duel is fought")
	h.check(_pump(ctx, 40.0, func(): return pit.is_idle() and flow.phase == "board"), "3: the retried sequence completes")
	await tree.process_frame
	h.check(game.engine.result.is_empty() and not game.royal_active(), "3: the King survived after the retry")
	WorldTests._world_is_chess(h, ctx, "3: after the retried sequence")
	h.eq(adapter.started_options[2].initial_hp, king_max - 50, "3: the retried duel started from the same carried HP")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	# 4. Leaving the screen (exit) in the middle of the sequence: no leaked nodes / no error output.
	var before: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	ctx = await _boot(tree, BOTH)
	app = ctx["app"]
	pit = ctx["world"].pit
	_pump(ctx, 2.0, func(): return not pit.is_idle())
	_app_duel(h, ctx, {"king_damage": 10, "kill_checker": true}, "4: duel 1")
	_pump(ctx, 10.0, func(): return ctx["app"].battle_flow.phase == "preview" and pit.phase == PitSequence.Phase.INTERLUDE)
	app.queue_free()
	for _i in 4:
		await tree.process_frame
	h.check(true, "4: the screen was freed in the interlude without errors")
	h.check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= before + 2, "4: no leaked nodes after exit (%d -> %d)" % [before, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])


# ---- 6. the computer opponent ------------------------------------------------------------------------------------------------------
static func _computer_opponent(h, tree: SceneTree) -> void:
	h.begin("royal computer: the chess AI mates, the sequence opens, the human can resign")
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app._switch_mode(1, true)
	app.board_3d.animation_enabled = false
	app.board_3d.world.auto_advance = false
	app.game.new_game(0, 0, BACK_RANK)   # White (the computer) mates with Ra8
	app.opponent.computer.force_slice = true
	app.opponent.computer.base_delay_ms = 0
	app.opponent.start_computer({"kind": "computer", "level": 4, "color": "b"})   # the human plays Black
	var computer: ComputerOpponent = app.opponent.computer
	h.check(computer.active and computer.ai_color == "w" and computer.human_color == "b", "the computer plays White, the human Black")
	h.eq(app.battle_adapter.computer_seat.get("color", ""), "w", "the combat adapter: White's fighters are controlled by the computer (CombatAI), Black's by the human")
	h.check(app.battle_adapter.computer_seat.seat.type == "ai" and app.battle_adapter.computer_seat.seat.attacker_style != "", "the computer seat carries the level's CombatAI skill / styles")
	var deadline := Time.get_ticks_msec() + 20000
	while not app.game.royal_active() and Time.get_ticks_msec() < deadline:
		await tree.process_frame
	h.check(app.game.royal_active(), "the chess AI found the mate and the last stand opened")
	h.check(app.game.pending_request().attacker.role == "k" and app.game.pending_request().attacker.color == "b", "the mated (human) King is the attacker of the duel")
	h.check(app.battle_flow.phase == "preview" and app.battle_flow.is_royal_duel(), "the banner is up")
	h.check(not computer.is_thinking(), "the computer does not think during the sequence")
	app.opponent.resign()   # the human resigns mid-sequence
	await tree.process_frame
	await tree.process_frame
	h.check(app.game.engine.result == "1-0" and app.game.engine.reason == "Resignation" and not app.game.royal_active() and app.battle_flow.phase == "board", "the human's resignation ends the match (White wins), the sequence is dropped")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame


# ---- 7. real arena, real adapter, computer seats --------------------------------------------------------------------------------------
static func _boot_real(tree: SceneTree, fen: String, computer: Dictionary) -> Dictionary:
	var app = Main.instantiate()
	tree.root.size = Vector2i(1200, 800)
	tree.root.add_child(app)
	await tree.process_frame
	await tree.process_frame
	app._switch_mode(1, true)
	app.board_3d.animation_enabled = false
	var world: BattleWorld = app.board_3d.world
	world.auto_advance = false
	app.battle_flow.set_process(false)
	app.game.new_game(0, 0, fen)
	app.opponent.start_computer(computer)
	await tree.process_frame
	return {"app": app, "adapter": app.battle_adapter, "world": world, "game": app.game, "board": app.board_3d}


static func _frames(ctx: Dictionary, tree: SceneTree, max_frames: int, until: Callable) -> bool:
	for _i in max_frames:
		if until.call():
			return true
		if is_instance_valid(ctx["app"].battle_flow):
			ctx["app"].battle_flow.advance(DT)
		ctx["world"].advance(DT)
		await tree.process_frame
	return until.call()


## Waits until the REAL arena runs the pending duel (it counts down while the pit still descends), applies `plan` to the real
## simulation and waits until the pit has reached COMBAT and left it again (the real CombatSimulation produces the result by itself;
## the pit stores a result that arrives early and resolves it on arrival in COMBAT).
static func _real_duel(h, tree: SceneTree, ctx: Dictionary, plan: Dictionary, label: String) -> Dictionary:
	var world: BattleWorld = ctx["world"]
	var adapter = ctx["adapter"]
	var game: Royal = ctx["game"]
	var wanted: String = game.pending_request().battleId
	var running: bool = await _frames(ctx, tree, 3000, func(): return is_instance_valid(adapter.arena) and adapter.arena.sim.is_running() and adapter.arena.sim.request.get("battleId", "") == wanted and adapter.arena.hud != null and adapter.arena.hud.context_text() != "")
	h.check(running, label + ": the real arena runs the duel")
	if not running:
		return {}
	var arena: CombatArena = adapter.arena
	var info := {"arena": arena, "hp_start": arena.sim.attacker().health.current, "hud_context": arena.hud.context_text(), "seats": arena.seats.duplicate(true), "king_ratio": arena.sim.attacker().health.ratio(), "attacker_role": arena.sim.attacker().role, "request": arena.sim.request.duplicate(true)}
	if int(plan.get("king_damage", 0)) > 0:
		arena.sim.attacker().health.apply_damage(int(plan["king_damage"]))
	if plan.get("kill_king", false):
		arena.sim.attacker().health.apply_damage(100000)
	if plan.get("kill_checker", false):
		arena.sim.defender().health.apply_damage(100000)
	var reached: bool = await _frames(ctx, tree, 3000, func(): return world.pit.phase == PitSequence.Phase.COMBAT or world.pit.phase == PitSequence.Phase.RESOLVE)
	h.check(reached, label + ": the pit reached the fight")
	info["follow_ok"] = is_instance_valid(world.rig.follow) and not arena.cameras.is_empty() and world.rig.follow == arena.cameras[0].camera
	var left: bool = await _frames(ctx, tree, 3000, func(): return world.pit.phase not in [PitSequence.Phase.COMBAT, PitSequence.Phase.DROP])
	h.check(left, label + ": the real simulation decided the duel")
	return info


static func _end_to_end(h, tree: SceneTree) -> void:
	var saved_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 600   # one logical 60 Hz tick per physics frame: keeps the real fights short
	# --- the computer fights the CHECKERS (White), the human the King (Black): two duels, King wins both.
	var ctx: Dictionary = await _boot_real(tree, BOTH, {"kind": "computer", "level": 3, "color": "b"})
	var app = ctx["app"]
	var world: BattleWorld = ctx["world"]
	var pit: PitSequence = world.pit
	var adapter = ctx["adapter"]
	var game: Royal = ctx["game"]
	var flow: BattleFlow = app.battle_flow
	h.begin("royal e2e: two duels through the real arena (human King vs computer checkers)")
	var phases: Array = []
	pit.phase_changed.connect(func(p: int): phases.append(PHASES[p]))
	var king_max := int(game.royal_request().king.stats.maxHp)
	var nodes_before: int = Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var first: Dictionary = await _real_duel(h, tree, ctx, {"king_damage": 40, "kill_checker": true}, "e2e duel 1")
	var arena: CombatArena = first["arena"]
	h.eq(first["attacker_role"], "k", "e2e: the King fights as the attacker")
	h.eq(first["hp_start"], king_max, "e2e: duel 1 starts with a full King")
	h.eq(first["hud_context"], "LAST STAND\nDUEL 1/2", "e2e: the combat HUD shows 'duel 1/2'")
	h.check(first["follow_ok"], "e2e: the pit camera follows the arena's camera")
	var seats: Dictionary = first["seats"]
	var king_id: String = first["request"].attacker.playerId
	var checker_id: String = first["request"].defender.playerId
	h.check(seats[checker_id].type == "ai" and seats[king_id].type == "human", "e2e: the computer controls the checker's side (White), the human the King")
	h.eq(seats[king_id].scheme, InputAssignment.shared().scheme_for_color("w"), "e2e: the human always uses seat 1's controls")
	await _frames(ctx, tree, 3000, func(): return pit.phase == PitSequence.Phase.INTERLUDE and flow.phase == "preview")
	h.check(pit.phase == PitSequence.Phase.INTERLUDE and flow.phase == "preview", "e2e: duel 1 resolved into the interlude")
	h.check(is_instance_valid(arena) and adapter.arena == arena and arena.is_inside_tree(), "e2e: the arena stays mounted between duels")
	h.check(arena.hud != null and not arena.hud.visible, "e2e: the old HUD / result panel is hidden during the banner")
	var banner: PanelContainer = app.royal_presenter.banner
	h.check(banner.visible and banner.find_child("KingHp", true, false).value == float(king_max - 40), "e2e: the banner shows the King's carried HP (%d)" % (king_max - 40))
	var second: Dictionary = await _real_duel(h, tree, ctx, {"kill_checker": true}, "e2e duel 2")
	h.check(second["arena"] == arena, "e2e: duel 2 runs in the SAME arena node (no scene reload)")
	h.eq(second["hp_start"], king_max - 40, "e2e: the real duel 2 starts from the carried HP in the real simulation")
	h.check(absf(second["king_ratio"] - float(king_max - 40) / float(king_max)) < 0.001, "e2e: the King's HP bar starts at the carried fraction")
	h.eq(second["hud_context"], "LAST STAND\nDUEL 2/2", "e2e: the combat HUD shows 'duel 2/2'")
	h.check(second["follow_ok"], "e2e: the camera follows the restarted arena")
	h.check(await _frames(ctx, tree, 4000, func(): return pit.is_idle() and flow.phase == "board"), "e2e: climb, return, board")
	await tree.process_frame
	await tree.process_frame
	h.eq(phases, ["CAPTURE_FOCUS", "TRAPDOOR_OPEN", "DROP", "COMBAT", "RESOLVE", "INTERLUDE", "COMBAT", "RESOLVE", "CLIMB", "RETURN", "IDLE"], "e2e: one descent for the whole sequence")
	h.check(game.engine.result.is_empty() and not game.royal_active() and game.engine.board[Rules.index("a8")] == "" and game.engine.board[Rules.index("e1")] == "", "e2e: King won both duels, the checkers are gone, play continues")
	h.eq(world.chamber.arena_mount.get_child_count(), 0, "e2e: the arena is removed after the sequence")
	WorldTests._world_is_chess(h, ctx, "e2e: after the sequence")
	h.check(app.interaction.enabled, "e2e: board input is back")
	h.eq(game.royal_log[0].duels[1].kingEnd.hp, king_max - 40, "e2e: the chronicle's duel 2 ends with the carried HP (nothing taken)")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame

	# --- the computer plays the KING (Black, attacker style), the human the checker: the King falls (defeat presentation).
	ctx = await _boot_real(tree, BACK_RANK, {"kind": "computer", "level": 3, "color": "w"})
	app = ctx["app"]
	world = ctx["world"]
	pit = world.pit
	adapter = ctx["adapter"]
	game = ctx["game"]
	flow = app.battle_flow
	h.begin("royal e2e: the King (computer) falls to the human's checker (defeat)")
	h.check(game.play("a1", "a8").ok and game.royal_active(), "e2e: the human's Ra8 mates")
	var fell: Dictionary = await _real_duel(h, tree, ctx, {"kill_king": true}, "e2e defeat")
	var fell_seats: Dictionary = fell["seats"]
	var fell_king: String = fell["request"].attacker.playerId
	var fell_checker: String = fell["request"].defender.playerId
	h.check(fell_seats[fell_king].type == "ai" and fell_seats[fell_checker].type == "human", "e2e: the computer controls the King (Black), the human the checker")
	h.check(fell_seats[fell_king].style == adapter.computer_seat.seat.attacker_style, "e2e: the King uses the level's attacking CombatAI style")
	h.check(await _frames(ctx, tree, 4000, func(): return pit.is_idle() and flow.phase == "board"), "e2e: the checker climbs out and the board returns")
	await tree.process_frame
	await tree.process_frame
	h.check(game.engine.result == "1-0" and game.engine.reason == "Checkmate" and not game.royal_active(), "e2e: the King fell: checkmate for White")
	WorldTests._world_is_chess(h, ctx, "e2e: after the defeat")
	h.eq(world.chamber.arena_mount.get_child_count(), 0, "e2e: the arena is gone")
	app.queue_free()
	await tree.process_frame
	await tree.process_frame
	h.check(Performance.get_monitor(Performance.OBJECT_NODE_COUNT) <= nodes_before + 4, "e2e: no node leak over both runs (%d -> %d)" % [nodes_before, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	Engine.physics_ticks_per_second = saved_rate
