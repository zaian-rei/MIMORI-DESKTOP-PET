extends RefCounted
class_name PetStats

## Pet stats that drift over time and gate/weight autonomous behavior.
## Stored in data, ticks each frame, and is consumed by BehaviorController
## via BehaviorDefinition.passes_gates() / weight_for().
##
## Each stat is described by one STAT_DEFINITIONS entry carrying its own
## min/max/default and passive drift. Adding a future stat (Trust, Stress,
## Hunger, ...) means adding an enum value and a matching definition here;
## no other system needs to change. Mutations never touch this class
## directly from outside - go through BehaviorStatsComponent so change
## signals fire.

enum Stat {
	ENERGY,
	HAPPINESS,
	CURIOSITY,
	BOREDOM,
	SLEEPINESS,
}

const STAT_NAMES := {
	Stat.ENERGY: &"energy",
	Stat.HAPPINESS: &"happiness",
	Stat.CURIOSITY: &"curiosity",
	Stat.BOREDOM: &"boredom",
	Stat.SLEEPINESS: &"sleepiness",
}

## Definition applied to any stat without its own entry (shouldn't happen in
## practice; kept so a bad enum value degrades safely instead of erroring).
const _BASE_DEFINITION := {"min": 0.0, "max": 100.0, "default": 50.0, "drift": 0.0}

## Per-stat bounds, starting value and passive per-second drift.
##   min/max   - the stat is always clamped to this range
##   default   - the value a fresh pet starts with (and the fallback for
##               missing entries in a partial save)
##   drift     - passive per-second change applied in tick(). Behavior
##               effects (the behavior .tres stat_effects) are layered on
##               top of this by BehaviorController while a behavior runs.
const STAT_DEFINITIONS := {
	Stat.ENERGY: {"min": 0.0, "max": 100.0, "default": 50.0, "drift": -0.08},
	Stat.HAPPINESS: {"min": 0.0, "max": 100.0, "default": 50.0, "drift": -0.01},
	Stat.CURIOSITY: {"min": 0.0, "max": 100.0, "default": 50.0, "drift": 0.0},
	Stat.BOREDOM: {"min": 0.0, "max": 100.0, "default": 50.0, "drift": 0.15},
	Stat.SLEEPINESS: {"min": 0.0, "max": 100.0, "default": 50.0, "drift": 0.18},
}

var _values: Dictionary = {}


func _init() -> void:
	for stat in Stat.values():
		_values[stat] = get_default(stat)


func get_value(stat: int) -> float:
	return _values.get(stat, get_default(stat))


func get_name(stat: int) -> StringName:
	return STAT_NAMES.get(stat, &"unknown")


func get_min(stat: int) -> float:
	return _definition(stat).get("min", _BASE_DEFINITION["min"])


func get_max(stat: int) -> float:
	return _definition(stat).get("max", _BASE_DEFINITION["max"])


func get_default(stat: int) -> float:
	return _definition(stat).get("default", _BASE_DEFINITION["default"])


func get_drift(stat: int) -> float:
	return _definition(stat).get("drift", _BASE_DEFINITION["drift"])


func _definition(stat: int) -> Dictionary:
	return STAT_DEFINITIONS.get(stat, _BASE_DEFINITION)


func add(stat: int, amount: float) -> void:
	_values[stat] = clampf(
		_values.get(stat, get_default(stat)) + amount,
		get_min(stat),
		get_max(stat)
	)


func set_value(stat: int, value: float) -> void:
	_values[stat] = clampf(value, get_min(stat), get_max(stat))


## Applies each stat's passive drift. Behavior effects are NOT applied here;
## they are layered on by BehaviorController while a behavior is active.
## Optional drift_scales (Stat -> multiplier) lets the personality system bias
## how fast individual needs grow without changing base definitions.
func tick(delta: float, drift_scales: Dictionary = {}) -> void:
	for stat in STAT_DEFINITIONS:
		var scale := 1.0
		if drift_scales.has(stat):
			scale = float(drift_scales[stat])
		_values[stat] = clampf(
			_values.get(stat, get_default(stat)) + float(STAT_DEFINITIONS[stat]["drift"]) * delta * scale,
			get_min(stat),
			get_max(stat)
		)


## Applies Stat -> per-second change from an active behavior.
func apply_effects(effects: Dictionary, delta: float) -> void:
	for stat in effects:
		add(stat, float(effects[stat]) * delta)


func to_dict() -> Dictionary:
	var out := {}
	for stat in Stat.values():
		out[STAT_NAMES[stat]] = _values[stat]
	return out


## Restores stats from a to_dict() snapshot (session persistence). Missing
## keys are left untouched so partial saves degrade gracefully.
func from_dict(data: Dictionary) -> void:
	for stat in Stat.values():
		var key: StringName = STAT_NAMES[stat]
		if data.has(key):
			set_value(stat, float(data[key]))
