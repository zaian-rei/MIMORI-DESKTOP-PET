extends "res://core/base/pet_component.gd"
class_name StateMachineComponent

const DefaultAnimationPolishSettings := preload("res://data/configs/animation_polish_settings.tres")

## Central state machine. Every transition in the engine passes through here
## and is validated against AnimationTransitionRules - the single explicit
## transition graph. Managers never flip the sprite or the state directly;
## they submit requests and this component decides whether (and through which
## intermediate states) the request may be honoured.
##
## Responsibilities:
##   - validate a target against the shared graph
##   - insert the shortest legal intermediate path when a request is not
##     directly allowed (Run -> Walk -> Idle, Walk -> Idle -> Happy, ...)
##   - enforce the Walk minimum duration before Run (never Idle -> Run)
##   - expose current / previous / requested / target state for debugging and
##     for managers that must not mistake a planned intermediate for a change
##     of intent
##   - keep the existing priority arbitration: HIGH/CRITICAL requests replace
##     lower ones, equal-priority requests replace the current intent

var current_state: PetState.State = PetState.State.IDLE
var previous_state: PetState.State = PetState.State.IDLE

var _requested_state: PetState.State = PetState.State.IDLE
var _target_state: PetState.State = PetState.State.IDLE

## Pending transition plan. Each step is a dictionary: state, priority,
## bypass. The first step is applied on the next process frame; intermediate
## steps may be held for chain_settle_seconds so the sequence is visible.
var _chain: Array[Dictionary] = []
var _chain_priority: StatePriority.Level = StatePriority.Level.LOW
var _chain_wait: float = 0.0

var _entered_at_seconds: float = 0.0
var _walk_entered_at_seconds: float = 0.0

var settings: AnimationPolishSettings


func on_initialized() -> void:
	settings = pet.definition.animation_polish_settings \
		if pet.definition.animation_polish_settings != null \
		else DefaultAnimationPolishSettings
	_walk_entered_at_seconds = _now()
	_entered_at_seconds = _now()
	LoggerGlobal.info("StateMachine initialized.")


## --- Public request API -----------------------------------------------------

## Submits a state request. If the direct transition is illegal the machine
## plans the shortest legal path and plays the intermediate states. Lower
## priority requests are ignored while a higher-priority plan is in flight.
## `bypass` is reserved for manual/user actions and engine recovery; it skips
## the graph entirely.
func request_state(
	new_state: PetState.State,
	priority: StatePriority.Level = StatePriority.Level.NORMAL,
	bypass: bool = false
) -> void:
	_requested_state = new_state

	if bypass:
		_rebuild_chain([new_state], priority, true)
		return

	## Already heading exactly there: do not rebuild/reset the plan every
	## frame (that would starve the Walk minimum duration gate).
	if new_state == _target_state and not _chain.is_empty():
		return
	if new_state == current_state and _chain.is_empty():
		_target_state = new_state
		return

	var path := AnimationTransitionRules.plan_path(current_state, new_state)
	if path.is_empty():
		LoggerGlobal.debug(
			"Rejected transition %s -> %s." % [
				_state_name(current_state),
				_state_name(new_state),
			]
		)
		return
	if path.size() > 1:
		var max_steps := clampi(int(_effective_settings().max_transition_steps), 1, 8)
		if path.size() > max_steps:
			LoggerGlobal.debug(
				"Rejected transition %s -> %s: path needs %d steps." % [
					_state_name(current_state),
					_state_name(new_state),
					path.size(),
				]
			)
			return

	if not _can_replace_plan(priority):
		return
	_rebuild_chain(path, priority, false)


## Decision-path request from BehaviorController. Validates the transition
## against the behavior's allowed_from before submitting - physics/drag/mood
## keep using request_state() and stay ungated ground truth.
func request_behavior(
	behavior: BehaviorDefinition,
	priority: StatePriority.Level = StatePriority.Level.NORMAL
) -> void:
	if behavior == null:
		return
	if not behavior.allowed_from.is_empty() and current_state not in behavior.allowed_from:
		LoggerGlobal.debug(
			"Rejected behavior %s from %s." % [
				_state_name(behavior.state),
				_state_name(current_state),
			]
		)
		return
	request_state(behavior.state, priority)


func _can_replace_plan(priority: StatePriority.Level) -> bool:
	if _chain.is_empty():
		return true
	if priority > _chain_priority:
		return true
	## Equal priority = the newest intent wins (walk -> run, run -> walk).
	## Lower priority stays queued behind the stronger request.
	return priority == _chain_priority


func _rebuild_chain(
	path: Array,
	priority: StatePriority.Level,
	bypass: bool
) -> void:
	_chain.clear()
	_chain_priority = priority
	_chain_wait = 0.0
	for i in path.size():
		_chain.append({
			"state": int(path[i]),
			"priority": priority,
			"bypass": bypass,
			"final": i == path.size() - 1,
		})
	if path.is_empty():
		_target_state = current_state
	else:
		_target_state = int(path[path.size() - 1])


## --- Execution --------------------------------------------------------------

func _process(delta: float) -> void:
	if _chain.is_empty():
		return

	_chain_wait -= delta
	if _chain_wait > 0.0:
		return

	var step: Dictionary = _chain[0]
	var next_state: int = int(step["state"])
	var bypass: bool = bool(step["bypass"])

	## The world may have moved since the plan was built (physics, drag,
	## force_state). Re-validate instead of applying a stale step.
	if not AnimationTransitionRules.can_transition(current_state, next_state, bypass):
		var replanned := AnimationTransitionRules.plan_path(current_state, _target_state, bypass)
		if replanned.is_empty():
			_chain.clear()
			_target_state = current_state
			return
		_rebuild_chain(replanned, _chain_priority, bypass)
		return

	## Never promote to Run before Walk has had its minimum time. The plan
	## stays queued, so the pet simply keeps walking until the gate opens.
	if next_state == PetState.State.RUN and current_state == PetState.State.WALK:
		if _now() - _walk_entered_at_seconds < float(_effective_settings().walk_min_duration):
			return

	_chain.pop_front()
	_apply_state(next_state)

	if _chain.is_empty():
		_target_state = next_state
		_chain_wait = 0.0
	else:
		## Hold an intermediate state just long enough to be seen. The final
		## step is never delayed.
		_chain_wait = float(_effective_settings().chain_settle_seconds)


func _apply_state(new_state: PetState.State) -> void:
	if current_state == new_state:
		return

	var was := current_state
	previous_state = current_state
	current_state = new_state
	_entered_at_seconds = _now()
	if new_state == PetState.State.WALK:
		_walk_entered_at_seconds = _entered_at_seconds

	EventBus.emit(EventBus.STATE_CHANGED, {
		"previous_state": was,
		"new_state": current_state,
	})


## Immediately applies a state, clearing any pending plan so a stale
## HIGH-priority request can't swallow the forced transition later.
func force_state(new_state: PetState.State) -> void:
	_chain.clear()
	_chain_wait = 0.0
	_chain_priority = StatePriority.Level.CRITICAL
	_requested_state = new_state
	_target_state = new_state
	_apply_state(new_state)


## --- Queries ----------------------------------------------------------------

func get_state() -> PetState.State:
	return current_state


func get_previous_state() -> PetState.State:
	return previous_state


## The final state the current plan is heading toward. Managers that own an
## activity (BehaviorController) compare against this, not against a transient
## intermediate inserted by the planner.
func get_target_state() -> PetState.State:
	return _target_state


func get_requested_state() -> PetState.State:
	return _requested_state


func get_state_elapsed() -> float:
	return _now() - _entered_at_seconds


func has_pending_transition() -> bool:
	return not _chain.is_empty()


func _effective_settings() -> AnimationPolishSettings:
	return settings if settings != null else DefaultAnimationPolishSettings


func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _state_name(state: int) -> String:
	var keys := PetState.State.keys()
	if state >= 0 and state < keys.size():
		return keys[state]
	return str(state)


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	var queued: Array = []
	for step in _chain:
		queued.append(_state_name(int(step["state"])))
	return {
		"current_state": _state_name(current_state),
		"previous_state": _state_name(previous_state),
		"requested_state": _state_name(_requested_state),
		"target_state": _state_name(_target_state),
		"has_pending_request": not _chain.is_empty(),
		"pending_chain": queued,
		"pending_priority": _chain_priority,
		"state_elapsed": get_state_elapsed(),
		"walk_elapsed": _now() - _walk_entered_at_seconds,
		"walk_min_duration": float(settings.walk_min_duration) if settings != null else 0.0,
	}
