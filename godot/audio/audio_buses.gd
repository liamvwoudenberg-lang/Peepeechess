extends RefCounted
## Runtime audio bus layout: Master + Music, SFX, UI, Ambience. Idempotent, autoload-free; no .tres edits.
## Also small pitch/volume variation helpers for sound hooks. Presentation only.
const BUSES := ["Music", "SFX", "UI", "Ambience"]

static func ensure_all() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
			if bus_name != "UI":
				AudioServer.add_bus_effect(index, AudioEffectLimiter.new())

static func set_linear(bus_name: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index != -1:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))

## Random pitch around 1.0 (spread 0.06 = +-6 percent) using a caller-owned RNG so it never touches simulation randomness.
static func vary_pitch(rng: RandomNumberGenerator, spread: float = 0.06) -> float:
	return 1.0 + rng.randf_range(-spread, spread)

static func vary_db(rng: RandomNumberGenerator, spread_db: float = 1.5) -> float:
	return rng.randf_range(-spread_db, spread_db)
