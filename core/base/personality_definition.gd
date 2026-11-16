extends Resource
class_name PersonalityDefinition

## Pure data for one pet personality. A personality biases HOW the pet
## behaves by tuning the utility decision system, behavior durations and the
## stat economy - it never moves the pet, plays animations or picks behaviors
## itself. New personalities = new .tres files in res://data/personalities/
## with zero engine code changes (Open/Closed), the same pattern as
## BehaviorDefinition.

@export var id: String = ""
@export var display_name: String = ""
@export var description: String = ""

## --- Decision bias (utility multipliers) ------------------------------------
## Multiplicative modifiers on a behavior's utility score in
## BehaviorDecisionComponent. >1 makes the behavior more likely, <1 less.

## "Movement frequency": how often the pet walks/runs.
@export var movement_frequency: float = 1.0

## "Thinking frequency": how often the pet thinks.
@export var thinking_frequency: float = 1.0

## "Dance chance": how eagerly the pet dances when music plays.
@export var dance_chance: float = 1.0

## "Sleep preference": how eager the pet is to sleep (and deep sleep).
@export var sleep_preference: float = 1.0

## "Idle preference": how willing the pet is to just stand around.
@export var idle_preference: float = 1.0

## --- Execution tuning --------------------------------------------------------

## "Idle duration": scales how long an idle lasts.
@export var idle_duration_modifier: float = 1.0

## "Walk distance": scales how long/far a walk (or run) leg lasts.
@export var walk_distance_modifier: float = 1.0

## "Decision delay": scales the gap between behavior decisions. <1 reacts
## quicker to its needs, >1 is more deliberate.
@export var decision_delay_modifier: float = 1.0

## "Movement speed": reserved for the movement/polish layers; exposed via
## PersonalityComponent for future systems. Never applied here.
@export var movement_speed_modifier: float = 1.0

## "Reaction speed": reserved for the follow-cursor/interaction layers;
## exposed via PersonalityComponent for future systems. Never applied here.
@export var reaction_speed_modifier: float = 1.0

## --- Stat economy ------------------------------------------------------------
## Multipliers applied to every per-second stat change (behavior stat
## effects and passive drift) in BehaviorStatsComponent.

@export var curiosity_modifier: float = 1.0
@export var energy_consumption_modifier: float = 1.0
@export var boredom_growth_modifier: float = 1.0
@export var happiness_modifier: float = 1.0

## Extended per-state utility multipliers (PetState.State -> float). Override
## the semantic fields above and let future personalities bias ANY behavior
## state - including new ones - without touching engine code.
@export var extra_state_multipliers: Dictionary = {}


## Multiplier for a behavior's utility score. extra_state_multipliers win
## when present; otherwise the semantic fields map to their states.
func utility_multiplier_for(state: PetState.State) -> float:
	if extra_state_multipliers.has(state):
		return maxf(float(extra_state_multipliers[state]), 0.0)
	match state:
		PetState.State.WALK, PetState.State.RUN:
			return maxf(movement_frequency, 0.0)
		PetState.State.THINK:
			return maxf(thinking_frequency, 0.0)
		PetState.State.DANCE:
			return maxf(dance_chance, 0.0)
		PetState.State.SLEEP, PetState.State.DEEP_SLEEP:
			return maxf(sleep_preference, 0.0)
		PetState.State.IDLE:
			return maxf(idle_preference, 0.0)
	return 1.0


## Multiplier for how long a behavior runs. IDLE scales by idle duration,
## WALK/RUN by walk distance; everything else is unaffected.
func duration_modifier_for(state: PetState.State) -> float:
	match state:
		PetState.State.IDLE:
			return maxf(idle_duration_modifier, 0.1)
		PetState.State.WALK, PetState.State.RUN:
			return maxf(walk_distance_modifier, 0.1)
	return 1.0


## Multiplier for every per-second stat change of `stat` (behavior effects
## and passive drift). Unlisted stats pass through unchanged.
func stat_scale_for(stat: PetStats.Stat) -> float:
	match stat:
		PetStats.Stat.ENERGY:
			return energy_consumption_modifier
		PetStats.Stat.CURIOSITY:
			return curiosity_modifier
		PetStats.Stat.BOREDOM:
			return boredom_growth_modifier
		PetStats.Stat.HAPPINESS:
			return happiness_modifier
	return 1.0


## All named modifiers as one dict, for debug overlays / settings screens.
func get_modifier_summary() -> Dictionary:
	return {
		"movement_frequency": movement_frequency,
		"thinking_frequency": thinking_frequency,
		"dance_chance": dance_chance,
		"sleep_preference": sleep_preference,
		"idle_preference": idle_preference,
		"idle_duration_modifier": idle_duration_modifier,
		"walk_distance_modifier": walk_distance_modifier,
		"decision_delay_modifier": decision_delay_modifier,
		"movement_speed_modifier": movement_speed_modifier,
		"reaction_speed_modifier": reaction_speed_modifier,
		"curiosity_modifier": curiosity_modifier,
		"energy_consumption_modifier": energy_consumption_modifier,
		"boredom_growth_modifier": boredom_growth_modifier,
		"happiness_modifier": happiness_modifier,
		"extra_state_multipliers": extra_state_multipliers,
	}
