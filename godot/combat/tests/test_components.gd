extends RefCounted
## Unit tests for the reusable components and the attack timeline maths.


static func run(h, _tree: SceneTree) -> void:
	_health(h)
	_stamina(h)
	_attack_definition(h)
	_ability(h)


static func _health(h) -> void:
	h.begin("health: damage, clamp, depletion, threshold")
	var hp := HealthComponent.new()
	hp.setup(80.0)
	var depleted := [0]
	hp.depleted.connect(func(): depleted[0] += 1)
	h.eq(hp.apply_damage(30), 30, "damage removes HP")
	h.eq(hp.current, 50, "HP after 30 damage")
	h.eq(hp.apply_damage(0), 0, "zero damage does nothing")
	h.eq(hp.apply_damage(-5), 0, "negative damage is ignored (cannot heal)")
	h.eq(hp.apply_damage(500), 50, "overkill is clamped to remaining HP")
	h.eq(hp.current, 0, "HP floors at zero")
	h.eq(depleted[0], 1, "depleted fires once")
	h.eq(hp.apply_damage(5), 0, "no damage after defeat")
	h.eq(depleted[0], 1, "depleted does not fire again")
	h.eq(hp.heal(10), 0, "no healing after defeat")

	hp.setup(80.0)
	hp.current = 28
	h.check(hp.at_or_below(0.35), "28/80 is at the 35% threshold")
	hp.current = 29
	h.check(not hp.at_or_below(0.35), "29/80 is above the 35% threshold")
	hp.current = 70
	h.eq(hp.heal(50), 10, "heal is clamped to the maximum")


static func _stamina(h) -> void:
	h.begin("stamina: spend is atomic, delay, regen, exhaustion")
	var st := StaminaComponent.new()
	st.setup(100.0, 0.5, 30)
	h.check(st.spend(40.0), "can spend 40 of 100")
	h.near(st.current, 60.0, 0.0001, "stamina after spend")
	h.check(not st.spend(70.0), "cannot spend more than available")
	h.near(st.current, 60.0, 0.0001, "failed spend changes nothing")
	for _i in 30:
		st.tick(true)
	h.near(st.current, 60.0, 0.0001, "no regeneration during the regen delay")
	st.tick(true)
	h.near(st.current, 60.5, 0.0001, "regeneration resumes after the delay")
	st.tick(false)
	h.near(st.current, 60.5, 0.0001, "regeneration is paused while guarding/sprinting")
	st.regen_multiplier = 2.0
	st.tick(true)
	h.near(st.current, 61.5, 0.0001, "regeneration multiplier applies")

	h.begin("stamina: exhaustion blocks actions until recovered")
	st.setup(100.0, 1.0, 10)
	h.check(not st.drain(500.0), "draining past zero reports depletion")
	h.check(st.exhausted, "reaching zero exhausts the fighter")
	h.check(not st.can_afford(0.1), "nothing can be spent while exhausted")
	h.check(not st.spend(0.1), "spend fails while exhausted")
	for _i in 20:
		st.tick(true)
	h.near(st.current, 0.0, 0.0001, "regeneration waits twice as long after exhaustion")
	for _i in 14:
		st.tick(true)
	h.check(st.exhausted, "still exhausted below 15% of maximum")
	st.tick(true)
	st.tick(true)
	h.check(not st.exhausted, "recovered once above 15% of maximum")
	h.check(st.spend(5.0), "can act again after recovery")
	st.setup(100.0, 1.0, 10)
	h.near(st.lose(130.0), 30.0, 0.0001, "lose() reports the shortfall that could not be paid")
	h.check(st.exhausted, "being driven to zero by a block exhausts too")


static func _attack_definition(h) -> void:
	h.begin("attack definition: windows derive from FighterStats ticks")
	var pawn := FighterRoster.stats_for("p")
	var l1 := AttackLibrary.light("p", 0)
	h.eq(l1.total_ticks(pawn), 24, "pawn light 1 lasts lightTicks (24)")
	var window := l1.active_window(24)
	h.eq(window, Vector2i(7, 12), "pawn light 1 active window [7,12)")
	h.eq(l1.phase_at(6, 24), AttackDefinition.Phase.STARTUP, "tick 6 is startup")
	h.eq(l1.phase_at(7, 24), AttackDefinition.Phase.ACTIVE, "tick 7 is the first active tick")
	h.eq(l1.phase_at(11, 24), AttackDefinition.Phase.ACTIVE, "tick 11 is the last active tick")
	h.eq(l1.phase_at(12, 24), AttackDefinition.Phase.RECOVERY, "tick 12 is recovery")
	h.eq(l1.cancel_tick(24), 17, "chain/cancel opens at tick 17")
	h.eq(AttackLibrary.light("p", 2).total_ticks(pawn), 32, "finisher is 1.35x longer")
	h.eq(AttackLibrary.heavy("p").total_ticks(pawn), 53, "pawn heavy lasts heavyTicks (53)")
	h.eq(l1.total_ticks(pawn, 1.3), 19, "Last Stand attack speed shortens a light attack to 19")
	var knight := FighterRoster.stats_for("n")
	h.eq(AttackLibrary.light("n", 0).total_ticks(knight), 32, "knight light lasts 32 ticks")
	h.eq(AttackLibrary.ability_attack("n", "lunging-strike").total_ticks(knight), 72, "lunge is an absolute 72 ticks")
	h.check(AttackLibrary.light("n", 0).total_ticks(knight) > l1.total_ticks(pawn), "knight swings slower than the pawn")

	h.begin("attack definition: stats drive timing (balance is data, not code)")
	var slow := pawn.duplicate()
	slow["lightTicks"] = 36
	h.eq(l1.total_ticks(slow), 36, "a different lightTicks stat changes the timeline")
	h.eq(l1.active_window(36), Vector2i(11, 18), "...and rescales the hit window")

	h.begin("attack definition: forward motion covers the authored distance")
	var travelled := 0.0
	for t in 24:
		travelled += l1.forward_speed(t, 24) * CombatConstants.DT
	h.near(travelled, 0.35, 0.05, "pawn light 1 lunges about 0.35 m")
	var lunge := AttackLibrary.ability_attack("n", "lunging-strike")
	travelled = 0.0
	for t in 72:
		travelled += lunge.forward_speed(t, 72) * CombatConstants.DT
	h.near(travelled, 4.2, 0.2, "Lunging Strike covers about 4.2 m")

	h.begin("hitbox geometry: sector reach, arc and target radius")
	var o := Vector3.ZERO
	h.check(HitboxController.in_sector(o, 0.0, 1.95, 36.0, Vector3(0, 0, 1.9), 0.38), "target dead ahead in reach")
	h.check(HitboxController.in_sector(o, 0.0, 1.95, 36.0, Vector3(0, 0, 2.3), 0.38), "reach is measured to the hurtbox edge")
	h.check(not HitboxController.in_sector(o, 0.0, 1.95, 36.0, Vector3(0, 0, 2.5), 0.38), "beyond reach + radius misses")
	h.check(not HitboxController.in_sector(o, 0.0, 1.95, 36.0, Vector3(0, 0, -1.0), 0.38), "target behind misses")
	h.check(not HitboxController.in_sector(o, 0.0, 1.95, 36.0, Vector3(1.5, 0, 1.0), 0.38), "56 deg off-axis misses a 36 deg thrust")
	h.check(HitboxController.in_sector(o, 0.0, 1.95, 100.0, Vector3(1.5, 0, 1.0), 0.38), "...but a 100 deg sweep reaches it")
	h.check(HitboxController.in_sector(o, PI, 1.95, 36.0, Vector3(0, 0, -1.9), 0.38), "facing yaw=pi hits toward -Z")


static func _ability(h) -> void:
	h.begin("ability: Last Stand gating, cooldown and buff")
	var health := HealthComponent.new()
	health.setup(80.0)
	var stamina := StaminaComponent.new()
	stamina.setup(120.0, 0.45, 36)
	var ability := AbilityComponent.new()
	h.check(not ability.setup("royal-fury", 840), "unimplemented ability ids are refused")
	h.check(ability.setup("last-stand", 900), "last-stand is implemented")
	var verdict: Dictionary = ability.check(health, stamina)
	h.eq(verdict["reason"], "condition", "Last Stand needs HP at or below 35%")
	health.current = 28
	verdict = ability.check(health, stamina)
	h.check(verdict["ok"], "Last Stand available at 28/80")
	stamina.lose(500.0)
	h.check(ability.check(health, stamina)["ok"], "Last Stand is free: usable even while exhausted")
	ability.commit()
	h.eq(ability.cooldown_remaining, 900, "cooldown comes from FighterStats.cooldownTicks")
	h.eq(ability.check(health, stamina)["reason"], "cooldown", "cannot recast during cooldown")
	h.near(ability.move_mult(), 1.3, 0.0001, "buff raises movement 30%")
	h.near(ability.attack_speed_mult(), 1.3, 0.0001, "buff raises attack speed 30%")
	for _i in 300:
		ability.tick()
	h.near(ability.move_mult(), 1.0, 0.0001, "buff lasts 300 ticks (5 s)")
	h.eq(ability.cooldown_remaining, 600, "cooldown keeps running after the buff ends")
	for _i in 600:
		ability.tick()
	h.check(ability.check(health, stamina)["ok"], "available again when the cooldown has elapsed")

	h.begin("ability: Lunging Strike needs stamina")
	var knight_ability := AbilityComponent.new()
	h.check(knight_ability.setup("lunging-strike", 540), "lunging-strike is implemented")
	h.check(knight_ability.is_attack_ability(), "Lunging Strike is an attack ability")
	h.near(knight_ability.stamina_cost(), 28.0, 0.0001, "Lunging Strike costs 28 stamina")
	var poor := StaminaComponent.new()
	poor.setup(110.0, 0.4, 40)
	poor.current = 20.0
	health.setup(125.0)
	h.eq(knight_ability.check(health, poor)["reason"], "stamina", "refused without enough stamina")
