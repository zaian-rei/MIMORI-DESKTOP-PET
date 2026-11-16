extends Resource
class_name BehaviorDefinition

## Pure data for one pet behavior. New behaviors = new .tres files in
## res://data/behaviors/ - no engine code changes (Open/Closed).

enum Category { LOOP, TRANSITION, ONESHOT }

@export var state: PetState.State = PetState.State.IDLE
@export var category: Category = Category.LOOP
@export var animation_name: String = ""
@export var base_weight: float = 10.0

## False = the behavior is never picked by the autonomous brain. Only manual
## triggers (context menu, music playback) can start it. The animation name
## is still resolved through the catalog so those triggers keep working.
@export var autonomous: bool = true

@export var duration_min: float = 3.0
@export var duration_max: float = 8.0

@export var cooldown_min: float = 0.0
@export var cooldown_max: float = 0.0

@export var allowed_from: Array = []

## PetStats.Stat -> minimum value required (behavior ineligible below it).
@export var stat_gates: Dictionary = {}

## PetStats.Stat -> maximum value allowed (behavior ineligible above it).
@export var stat_maxes: Dictionary = {}

## PetStats.Stat -> coefficient. Score multiplier = 1 + sum(coefficient * stat/50).
@export var stat_weights: Dictionary = {}

## PetStats.Stat -> per-second change applied while this behavior is active.
@export var stat_effects: Dictionary = {}


func passes_gates(stats: PetStats) -> bool:
	for stat in stat_gates:
		if stats.get_value(stat) < float(stat_gates[stat]):
			return false
	for stat in stat_maxes:
		if stats.get_value(stat) > float(stat_maxes[stat]):
			return false
	return true


func weight_for(stats: PetStats) -> float:
	var multiplier := 1.0
	for stat in stat_weights:
		multiplier += float(stat_weights[stat]) * (stats.get_value(stat) / 50.0)
	return base_weight * maxf(multiplier, 0.05)
