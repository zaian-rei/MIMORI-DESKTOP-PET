extends "res://core/base/pet_component.gd"
class_name BehaviorPolishComponent

const DefaultPolishSettings := preload("res://data/configs/behavior_polish_settings.tres")

## Makes the pet's behavior FEEL natural without making the AI smarter.
## BehaviorDecisionComponent still owns eligibility, cadence and selection;
## this component only supplies temporary modifiers and timing variation that
## the decision loop and executor layer on top:
##   - Behavior fatigue: repeating a behavior raises its fatigue, which
##     temporarily lowers its utility via the decision loop's registered
##     utility-modifier extension point. Fatigue recovers over time, so no
##     behavior is ever permanently disabled.
##   - Decision interval: configurable min/max bounds with random variation.
##   - Duration variation: behavior durations get a random jitter (and idle
##     occasionally runs noticeably longer for natural pacing).
##   - Transition delays: certain behaviors (sleep, think) settle into a brief
##     idle pause first.
## It never moves the pet, plays animations, changes states or picks
## behaviors - strict data/state provider, same contract as Personality and
## BehaviorMemory.

const MAX_FATIGUE := 3.0

var settings: BehaviorPolishSettings

var decision_component: BehaviorDecisionComponent
var memory_component: BehaviorMemoryComponent

## PetState.State -> current fatigue (0..MAX_FATIGUE).
var _fatigue: Dictionary = {}


func on_initialized() -> void:
	decision_component = pet.get_component(BehaviorDecisionComponent)
	memory_component = pet.get_component(BehaviorMemoryComponent)
	settings = pet.definition.polish_settings if pet.definition.polish_settings != null else DefaultPolishSettings
	if memory_component != null:
		EventBus.subscribe(EventBus.BEHAVIOR_SELECTED, _on_behavior_selected_event)
	if decision_component != null:
		_register_fatigue_modifiers()
	LoggerGlobal.info("BehaviorPolishComponent initialized.")


## Public retune seam: future settings screens can swap the polish tuning
## resource without any code change.
func set_settings(new_settings: BehaviorPolishSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings


## Resolves the active settings. Safe before on_initialized has run (the
## decision loop's very first decision window is armed during its own
## initialization, which precedes this component's).
func _effective_settings() -> BehaviorPolishSettings:
	return settings if settings != null else DefaultPolishSettings


func _process(delta: float) -> void:
	if pet == null or not enabled:
		return
	var active := _effective_settings()
	for state in _fatigue:
		var level := float(_fatigue[state])
		if level > 0.0:
			_fatigue[state] = maxf(
				level - active.fatigue_recovery_per_second * delta,
				0.0
			)


## --- Fatigue ----------------------------------------------------------------

## Registers the fatigue penalty for every behavior the memory component
## records, through the decision loop's existing extension point. The callable
## receives (score, behavior, decision_component) and returns the scaled score.
func _register_fatigue_modifiers() -> void:
	for state in BehaviorMemoryComponent.RECORDED_STATES:
		decision_component.register_utility_modifier(state, _fatigue_modifier)


func _on_behavior_selected_event(payload: Dictionary) -> void:
	var state: PetState.State = payload.get("state", PetState.State.IDLE)
	_fatigue[state] = minf(
		float(_fatigue.get(state, 0.0)) + _effective_settings().fatigue_per_action,
		MAX_FATIGUE
	)


## Utility multiplier the fatigue currently applies to a state.
func get_current_penalty(state: PetState.State) -> float:
	var level := float(_fatigue.get(state, 0.0))
	if level <= 0.0:
		return 1.0
	return 1.0 - _effective_settings().fatigue_strength * clampf(level, 0.0, 1.0)


func _fatigue_modifier(score: float, behavior: BehaviorDefinition, _decision) -> float:
	return score * get_current_penalty(behavior.state)


## --- Timing variation -------------------------------------------------------

## Configurable decision-interval bounds for the decision loop. The control
## centre edits these live through SettingsManager; the polish .tres values
## remain the built-in defaults.
func get_decision_min() -> float:
	return float(SettingsManager.get_setting("behavior.decision_interval_min", _effective_settings().decision_min_seconds))


func get_decision_max() -> float:
	return float(SettingsManager.get_setting("behavior.decision_interval_max", _effective_settings().decision_max_seconds))


## Random duration multiplier for a behavior: +/-duration_variation jitter,
## plus a chance for idle to run noticeably longer (natural pacing).
func get_duration_factor(state: PetState.State) -> float:
	var active := _effective_settings()
	var factor := 1.0 + randf_range(-active.duration_variation, active.duration_variation)
	if state == PetState.State.IDLE and randf() < active.idle_extension_chance:
		factor *= active.idle_extension_factor
	return maxf(factor, 0.1)


## Random transition delay (seconds) before a behavior starts; 0.0 when the
## state has no configured delay.
func get_transition_delay(state: PetState.State) -> float:
	var active := _effective_settings()
	if active.delayed_states.is_empty() or state not in active.delayed_states:
		return 0.0
	return randf_range(active.transition_delay_min, active.transition_delay_max)


## --- Moments ----------------------------------------------------------------

## Duration of one idle moment (seconds).
func get_moment_duration() -> float:
	return maxf(_effective_settings().moment_duration_seconds, 0.1)


## Probability multiplier applied to the per-profile moment chance.
func get_moment_probability_scale() -> float:
	return _effective_settings().moment_probability_scale


## Multiplier applied to the per-profile gap between moment opportunities.
func get_moment_gap_scale() -> float:
	return _effective_settings().moment_gap_scale


## --- Debug support ----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var penalties := {}
	for state in _fatigue:
		penalties[state] = get_current_penalty(state)
	var active := _effective_settings()
	return {
		"fatigue": _fatigue.duplicate(),
		"penalties": penalties,
		"decision_interval": [active.decision_min_seconds, active.decision_max_seconds],
		"duration_variation": active.duration_variation,
		"recent_history": memory_component.get_recent_actions() if memory_component != null else [],
		"adjusted_utility_scores": decision_component.get_current_scores() if decision_component != null else {},
	}
