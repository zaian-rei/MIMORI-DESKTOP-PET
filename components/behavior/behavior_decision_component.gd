extends "res://core/base/pet_component.gd"
class_name BehaviorDecisionComponent

## Pure decision-maker for the pet: watches the internal needs and, on a
## configurable cadence, recommends the single highest-utility VALID
## behavior. It never plays animations, moves the pet, changes physics or
## transitions states - BehaviorController consumes the recommendation and
## executes it. Responsibilities stay separate.
##
## Scoring is modular and data-driven:
##   - Base utility comes from each BehaviorDefinition (base_weight x
##     stat_weights), so new behaviors are added as .tres files with zero
##     decision-loop changes.
##   - A repetition penalty cools down recently-repeated actions so the pet
##     doesn't chain the same behavior over and over.
##   - Extra rules register per-state via register_utility_modifier() and are
##     layered on top, again without editing this loop.
## Selection picks the highest valid score (argmax), not a random roll.

signal decision_made(action: BehaviorDefinition)

## Cadence between decisions. Kept at the previous effective values so the
## pet's rhythm is unchanged - only how the choice is made differs.
const DECISION_MIN_SECONDS := 3.0
const DECISION_MAX_SECONDS := 6.0

## Multiplier applied to a behavior's score per consecutive repeat, so
## WALK/WALK/WALK/WALK decays into something else instead of looping forever.
const REPEAT_DECAY := 0.45

## States the decision maker never evaluates while active (FALL/JUMP own
## their physics arcs; the executor also blocks them via _can_act()).
const BLOCKED_STATES := [
	PetState.State.FALL,
	PetState.State.JUMP,
]

var stats_component: BehaviorStatsComponent
var state_machine: StateMachineComponent
var drag_component: DragComponent
var memory_component: BehaviorMemoryComponent
var personality_component: PersonalityComponent
var polish_component: BehaviorPolishComponent

var decision_timer_remaining: float = 0.0

var selected_action: BehaviorDefinition
var last_chosen_action: PetState.State = PetState.State.IDLE
var last_scores: Dictionary = {}

var _cooldowns: Dictionary = {}
var _consecutive_repeats: Dictionary = {}
var _utility_modifiers: Dictionary = {}


func on_initialized() -> void:
	stats_component = pet.get_component(BehaviorStatsComponent)
	state_machine = pet.get_component(StateMachineComponent)
	drag_component = pet.get_component(DragComponent)
	memory_component = pet.get_component(BehaviorMemoryComponent)
	personality_component = pet.get_component(PersonalityComponent)
	polish_component = pet.get_component(BehaviorPolishComponent)
	decision_timer_remaining = _decision_window()
	if memory_component != null:
		_register_memory_modifiers()
	LoggerGlobal.info("BehaviorDecisionComponent initialized.")


## Ticks the decision timer and, once it elapses, returns the recommended
## behavior (null otherwise). Called every frame by the executor so the
## cadence only advances while the pet is free to act.
func tick(delta: float) -> BehaviorDefinition:
	if not enabled:
		return null
	decision_timer_remaining -= delta
	if decision_timer_remaining > 0.0:
		return null
	decision_timer_remaining = _decision_window()
	return _compute_best_action()


## Forces a decision right now (e.g. music started while the pet was idle).
func request_now() -> BehaviorDefinition:
	decision_timer_remaining = _decision_window()
	return _compute_best_action()


## Clears the timer so the next tick() decides immediately (e.g. after a
## manual animation finishes).
func reset_timer() -> void:
	decision_timer_remaining = 0.0


## Arms a fresh decision window (used when a behavior ends, so the pet
## settles briefly before its next choice).
func arm_timer() -> void:
	decision_timer_remaining = _decision_window()


## Called by the executor when it starts a behavior: records the repeat for
## the repetition penalty and arms the behavior's data-driven cooldown.
func note_behavior_started(behavior: BehaviorDefinition) -> void:
	var current_count := int(_consecutive_repeats.get(behavior.state, 0)) + 1
	for state in _consecutive_repeats:
		_consecutive_repeats[state] = 0
	_consecutive_repeats[behavior.state] = current_count

	if behavior.cooldown_min > 0.0 or behavior.cooldown_max > 0.0:
		_cooldowns[behavior.state] = _now() + randf_range(behavior.cooldown_min, behavior.cooldown_max)


## Registers an extra scoring rule for a state. The callable receives
## (score, behavior, self) and returns the adjusted score. Future behaviors
## register a rule here instead of editing the decision loop.
func register_utility_modifier(state: PetState.State, modifier: Callable) -> void:
	if not _utility_modifiers.has(state):
		_utility_modifiers[state] = []
	_utility_modifiers[state].append(modifier)


## Memory-backed scoring rules: BehaviorMemoryComponent only supplies data,
## the actual score adjustments live here in the decision loop's extension
## point. Kept mild so the pet's existing rhythm stays dominant.
func _register_memory_modifiers() -> void:
	register_utility_modifier(PetState.State.WALK, _walk_repetition_modifier)
	register_utility_modifier(PetState.State.THINK, _think_novelty_modifier)


## Walking 3+ times inside a minute reads as overuse; cool the urge down on
## top of the per-repeat decay. Only bites when the pet would otherwise
## trudge back and forth non-stop.
func _walk_repetition_modifier(score: float, _behavior: BehaviorDefinition, _self) -> float:
	var repeats := memory_component.count_recent_occurrences(PetState.State.WALK, 60.0)
	if repeats >= 3:
		score *= pow(0.6, repeats - 2)
	return score


## The pet hasn't thought in a while: nudge thinking back up. The curiosity
## gate in think.tres still governs eligibility - this only lifts scoring.
func _think_novelty_modifier(score: float, _behavior: BehaviorDefinition, _self) -> float:
	if memory_component.time_since_last(PetState.State.THINK) > 120.0:
		score *= 1.5
	return score


func _compute_best_action() -> BehaviorDefinition:
	var now := _now()
	var best: BehaviorDefinition = null
	var best_score := -INF
	last_scores = {}

	for behavior in BehaviorCatalog.get_all():
		if not _is_eligible(behavior, now):
			continue
		var score := _score(behavior)
		last_scores[behavior.state] = score
		if score > best_score:
			best_score = score
			best = behavior

	if best != null:
		selected_action = best
		last_chosen_action = best.state
		decision_made.emit(best)
	return best


func _is_eligible(behavior: BehaviorDefinition, now: float) -> bool:
	if state_machine.get_state() in BLOCKED_STATES:
		return false
	if drag_component.dragging:
		return false
	## Dance is the one manual/music-only behavior: the autonomous brain only
	## considers it while music is playing.
	var music_dance := MusicService.is_playing() and behavior.state == PetState.State.DANCE
	if not behavior.autonomous and not music_dance:
		return false
	if not behavior.passes_gates(stats_component.get_stats()):
		return false
	var current := state_machine.get_state()
	if not behavior.allowed_from.is_empty() and current not in behavior.allowed_from:
		return false
	if _cooldowns.has(behavior.state) and now < _cooldowns[behavior.state] and not music_dance:
		return false
	return true


func _score(behavior: BehaviorDefinition) -> float:
	var score := behavior.weight_for(stats_component.get_stats())
	if personality_component != null:
		score *= personality_component.get_utility_multiplier_for(behavior.state)
	var repeats := int(_consecutive_repeats.get(behavior.state, 0))
	if repeats > 0:
		score *= pow(REPEAT_DECAY, repeats)
	for modifier in _utility_modifiers.get(behavior.state, []):
		score = modifier.call(score, behavior, self)
	return score


## Random decision window length. The base bounds come from the polish system
## (configurable, falls back to the constants), then the personality's
## decision delay scales the result. Both take effect on the very next window.
func _decision_window() -> float:
	var min_s := DECISION_MIN_SECONDS
	var max_s := DECISION_MAX_SECONDS
	if polish_component != null:
		min_s = polish_component.get_decision_min()
		max_s = polish_component.get_decision_max()
	if max_s < min_s:
		var mid := (min_s + max_s) * 0.5
		min_s = mid
		max_s = mid
	var window := randf_range(min_s, max_s)
	if personality_component != null:
		window *= personality_component.get_decision_delay_modifier()
	return window


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## --- Debug support ----------------------------------------------------------

## Utility scores from the most recent decision pass (keyed by state).
func get_current_scores() -> Dictionary:
	return last_scores


func get_selected_action() -> BehaviorDefinition:
	return selected_action


func get_last_chosen_action() -> PetState.State:
	return last_chosen_action


func get_decision_timer_remaining() -> float:
	return decision_timer_remaining


## Fraction of the decision window left (0..1), for a debug progress bar.
func get_decision_timer_ratio() -> float:
	return clampf(decision_timer_remaining / DECISION_MAX_SECONDS, 0.0, 1.0)


func get_debug_info() -> Dictionary:
	return {
		"timer_remaining": decision_timer_remaining,
		"timer_ratio": get_decision_timer_ratio(),
		"selected_action": selected_action.state if selected_action != null else -1,
		"last_chosen_action": last_chosen_action,
		"scores": last_scores,
	}
