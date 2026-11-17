class_name CampaignBoons
extends RefCounted
## Boons: small, balanced, deterministic bonuses chosen between encounters (one of three) that last for the whole run. They are applied to the
## player's fighter STATE right after a duel starts (maximum/current health, stamina pool, stamina costs and regeneration), the same kind of change as a
## lesson's reduced-health handicap. No rule, frame data, balance table or contract changes, and nothing is sent online.
##
## Offers are a pure function of (run seed, node index, boons already taken), so a run can be replayed and tested.

const BOONS := {
	"vitality": {"title": "Vitality", "text": "+15% health.", "health": 0.15},
	"endurance": {"title": "Endurance", "text": "+25% stamina pool.", "stamina": 0.25},
	"efficiency": {"title": "Efficiency", "text": "Stamina costs 15% less.", "cost": 0.85},
	"second_wind": {"title": "Second wind", "text": "Stamina regenerates 30% faster.", "regen": 1.3},
	"iron_will": {"title": "Iron will", "text": "+8% health and +10% stamina.", "health": 0.08, "stamina": 0.10},
}
const MAX_STACK := 2
const OFFER_SIZE := 3


static func ids() -> Array:
	var out: Array = BOONS.keys()
	out.sort()
	return out


static func title(id: String) -> String:
	return String(BOONS.get(id, {}).get("title", id))


static func text(id: String) -> String:
	return String(BOONS.get(id, {}).get("text", ""))


static func stack_of(taken: Array, id: String) -> int:
	var n := 0
	for t in taken:
		if String(t) == id:
			n += 1
	return n


## Three distinct boons that can still be taken (fewer when almost everything is stacked out). Deterministic.
static func offer(run_seed: int, node_index: int, taken: Array) -> Array:
	var pool: Array = []
	for id in ids():
		if stack_of(taken, id) < MAX_STACK:
			pool.append(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, node_index, taken.size()])
	var out: Array = []
	while out.size() < OFFER_SIZE and not pool.is_empty():
		out.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return out


## Applies the taken boons to a started simulation's player fighter. Returns a summary {health_max, stamina_max, cost, regen}.
static func apply(sim: CombatSimulation, taken: Array, player_id: String) -> Dictionary:
	var fighter := sim.fighter_by_id(player_id)
	var health_bonus := 0.0
	var stamina_bonus := 0.0
	var cost := 1.0
	var regen := 1.0
	for id in taken:
		var b: Dictionary = BOONS.get(String(id), {})
		health_bonus += float(b.get("health", 0.0))
		stamina_bonus += float(b.get("stamina", 0.0))
		cost *= float(b.get("cost", 1.0))
		regen *= float(b.get("regen", 1.0))
	if fighter == null:
		return {"health_max": 0, "stamina_max": 0.0, "cost": cost, "regen": regen}
	var old_max := fighter.health.maximum
	fighter.health.maximum = int(round(float(old_max) * (1.0 + health_bonus)))
	fighter.health.current = clampi(fighter.health.current + (fighter.health.maximum - old_max), 1, fighter.health.maximum)
	fighter.stamina.maximum *= 1.0 + stamina_bonus
	fighter.stamina.current = fighter.stamina.maximum
	fighter.stamina.cost_multiplier *= cost
	fighter.stamina.seat_regen *= regen
	return {"health_max": fighter.health.maximum, "stamina_max": fighter.stamina.maximum, "cost": cost, "regen": regen}
