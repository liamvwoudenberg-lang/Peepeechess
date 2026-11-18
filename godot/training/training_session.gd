class_name TrainingSession
extends RefCounted
## One run of a lesson on the REAL combat engine (CombatSimulation, the same rules, frame data and balance as a Battle Chess duel).
## The player is seat "player-white", the opponent "player-black".
##
## Headless / scripted use (tests, tools):
##   var session := TrainingSession.new(lesson, {"level": "hard", "seed": 7})
##   await session.start(get_tree())
##   session.skip_countdown()
##   session.player.move = Vector2(1, 0)          # TrainingSession.Player: the player's held controls, edges via session.player.press("light")
##   session.step()                                # one 60 Hz tick: player packet + opponent packet + sim step + tracker update
##   session.tracker.lesson_completed.connect(...)
## UI use: the UI drives a normal CombatArena with `lesson_request()` and attaches `ObjectiveTracker.new(arena.sim, "player-white", lesson)`
## itself; this class then only supplies the request, the opponent and the handicaps (`apply_handicaps(sim)`).
##
## `finish(progress)` returns {completed, rating, seconds, stats} and records the attempt in a ProgressStore.

class Player:
	extends RefCounted
	var builder: CombatInputBuilder
	var move := Vector2.ZERO
	var yaw := 0.0
	var lock := true
	var sprint := false
	var block := false
	var auto_face := true      # face the opponent each tick (lock-on); set false to steer `yaw` yourself

	func press(action: String) -> void:
		builder.press(action)

const PLAYER_ID := "player-white"
const OPPONENT_ID := "player-black"
const MAX_TICKS := 6000

var lesson: Dictionary
var options: Dictionary
var level: String = "normal"
var seed_value: int = 1
var sim: CombatSimulation
var tracker: ObjectiveTracker
var player := Player.new()
var opponent: TrainingOpponent
var request: Dictionary
var ticks: int = 0


func _init(p_lesson: Dictionary, p_options: Dictionary = {}) -> void:
	lesson = p_lesson
	options = p_options
	level = String(options.get("level", lesson.get("difficulty", "normal")))
	seed_value = int(options.get("seed", 1))


## The BattleRequest of this lesson (schema-valid; player = white).
func lesson_request() -> Dictionary:
	var player_attacks := String(lesson.get("attacker", "player")) == "player"
	var req := FighterRoster.build_request(String(lesson["player_role"]), String(lesson["opponent_role"]), "w" if player_attacks else "b",
			"training-%s-%d" % [String(lesson["id"]), seed_value], seed_value, 0)
	if lesson.has("duration_seconds"):
		req["durationTicks"] = clampi(int(float(lesson["duration_seconds"]) * 60.0), 600, 5400)
	return req


## Lesson handicaps applied to a started simulation (state, not rules): a reduced starting HP for "limited health" lessons.
func apply_handicaps(target_sim: CombatSimulation) -> void:
	var fraction := float(lesson.get("constraints", {}).get("player_hp_fraction", 1.0))
	if fraction < 1.0:
		var me := target_sim.fighter_by_id(PLAYER_ID)
		me.health.current = maxi(1, int(ceil(float(me.health.maximum) * fraction)))


func start(tree: SceneTree) -> bool:
	stop()
	request = lesson_request()
	sim = CombatSimulation.new()
	tree.root.add_child(sim)
	var reply: Dictionary = sim.start(request, {"allow_experimental_roles": true, "duel_rules": false})   # practice teaches the documented mechanics: no defender head start, no Resolve
	if not reply["ok"]:
		sim.get_parent().remove_child(sim)
		sim.queue_free()
		sim = null
		return false
	await tree.physics_frame
	apply_handicaps(sim)
	player = Player.new()
	player.builder = CombatInputBuilder.new(request["matchId"], request["battleId"], PLAYER_ID)
	var opp_builder := CombatInputBuilder.new(request["matchId"], request["battleId"], OPPONENT_ID)
	opponent = TrainingOpponent.new(String(lesson.get("behaviour", "idle")), level, opp_builder, FighterRoster.stats_for(String(lesson["opponent_role"])),
			FighterRoster.stats_for(String(lesson["player_role"])), seed_value * 2 + 2)
	tracker = ObjectiveTracker.new(sim, PLAYER_ID, lesson)
	ticks = 0
	return true


func is_running() -> bool:
	return sim != null and sim.is_running()


## Steps the 180-tick countdown with neutral inputs so the next step() is the first live tick.
func skip_countdown() -> void:
	var guard := 0
	while sim != null and sim.phase == CombatSimulation.Phase.COUNTDOWN and guard < 400:
		_tick(false)
		guard += 1


## One simulation tick. The opponent decides from the snapshot taken BEFORE this tick's player input (it never sees what the player is
## about to do) and its packet is submitted together with the player's.
func step() -> void:
	_tick(true)


func _tick(use_player: bool) -> void:
	if sim == null or not sim.is_running():
		return
	var snapshot := sim.snapshot(false)
	var yaw := player.yaw
	if player.auto_face:
		var me := sim.fighter_by_id(PLAYER_ID)
		var other := sim.fighter_by_id(OPPONENT_ID)
		var to := other.global_position - me.global_position
		to.y = 0.0
		yaw = CombatConstants.yaw_of(to) if to.length() > 0.01 else me.yaw
	var packet: Dictionary
	if use_player:
		packet = player.builder.build(player.move.x, player.move.y, yaw, player.lock, player.sprint, player.block)
	else:
		packet = player.builder.build(0.0, 0.0, yaw, true, false, false)
	sim.submit_input(packet)
	sim.submit_input(opponent.packet(snapshot))
	sim.step_tick()
	ticks += 1
	tracker.update()


## Runs until the lesson is completed, failed or the fight ends, calling `think` (Callable(session)) before every tick. For scripted tests.
func run(think: Callable, max_ticks: int = MAX_TICKS) -> void:
	var guard := 0
	while is_running() and not tracker.finished and not tracker.failed and guard < max_ticks:
		think.call(self)
		step()
		guard += 1


## Final summary and (optionally) the progress record: {completed, failed, rating, seconds, stats, fail_reason}.
func finish(progress: ProgressStore = null) -> Dictionary:
	var stats := tracker.summary()
	var rating := tracker.rating()
	if progress != null:
		progress.record_attempt(String(lesson["id"]), tracker.finished, rating, float(stats["seconds"]))
	return {"completed": tracker.finished, "failed": tracker.failed, "rating": rating, "seconds": stats["seconds"], "stats": stats,
			"fail_reason": tracker.fail_reason}


func stop() -> void:
	if sim != null and is_instance_valid(sim):
		sim.stop()
		if sim.get_parent() != null:
			sim.get_parent().remove_child(sim)
		sim.queue_free()
	sim = null
