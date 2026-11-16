extends "res://core/base/pet_component.gd"
class_name AnimationTransitionManager

const DefaultAnimationPolishSettings := preload("res://data/configs/animation_polish_settings.tres")

## Owns the transition mechanics between AnimationComponent (which decides
## WHAT to play per state) and AnimationController (the low-level executor
## that flips the sprite):
##   - Priorities: a higher-priority request always interrupts the current
##     animation; equal/lower requests wait behind its protection window.
##   - Safe interruption: transition and one-shot animations are protected for
##     a configurable window so they complete before being cut off. DRAG holds
##     its animation for its whole duration - nothing lower can sneak in while
##     the pet is being carried.
##   - Transition queue: deferred requests are held (bounded) and played in
##     priority order once the current animation's protection expires.
##   - Duplicate protection: re-requesting the animation already playing does
##     not restart it, unless the state opts into restarts.
##   - Anti-thrash: equal/lower-priority flapping right after a switch is
##     swallowed, so gait/brain toggles never make the sprite flicker.
##   - Loop/one-shot/transition classification comes from
##     BehaviorDefinition.Category first, then from the settings data.
##   - State sync recovery: reconciles the sprite with the state machine's
##     expected animation so the two never drift apart.
## It never changes states and never picks behaviors - that stays in the state
## machine and the behavior systems.

enum AnimationCategory { LOOP, TRANSITION, ONESHOT }

var settings: AnimationPolishSettings

var sprite: AnimatedSprite2D
var controller: AnimationController
var state_machine: StateMachineComponent

var _current_state: int = PetState.State.IDLE
var _current_animation: String = "idle"
var _current_priority: int = 10
var _current_category: int = AnimationCategory.LOOP
var _played_at_ms: int = 0
var _protected_until_ms: int = 0
var _queue: Array = []
var _transition_count: int = 0
var _last_transition: Dictionary = {}


func on_initialized() -> void:
	sprite = pet.sprite
	controller = pet.get_component(AnimationController)
	state_machine = pet.get_component(StateMachineComponent)
	settings = pet.definition.animation_polish_settings if pet.definition.animation_polish_settings != null else DefaultAnimationPolishSettings
	LoggerGlobal.info("AnimationTransitionManager initialized.")


## Public retune seam: future settings screens can swap the animation polish
## tuning resource without any code change.
func set_settings(new_settings: AnimationPolishSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings


## Safe before on_initialized has run.
func _effective_settings() -> AnimationPolishSettings:
	return settings if settings != null else DefaultAnimationPolishSettings


## --- Request entry point (called by AnimationComponent) ---------------------

func request(state: PetState.State, animation_name: String) -> void:
	if sprite == null or animation_name == "":
		return
	var active := _effective_settings()
	var priority := active.get_priority(state)
	var now := Time.get_ticks_msec()

	if _current_animation == animation_name:
		if active.is_restart_allowed(state):
			_play(state, animation_name, priority, _classify(state), now)
		elif priority > _current_priority:
			## A higher-priority holder of the same animation (e.g. DRAG over
			## IDLE) adopts the floor so lower tiers can't sneak in underneath
			## it. No replay needed - the sprite already shows it.
			_current_state = state
			_current_priority = priority
			_current_category = _classify(state)
			_queue.clear()
		return

	## Safe interruption: DRAG holds its animation for as long as it is being
	## carried; anything lower waits.
	if _is_dragging() and priority < _current_priority:
		return

	if _is_protected(now) and priority < _current_priority:
		_queue_request(state, animation_name, priority)
		return

	## Anti-thrash: swallow equal/lower flapping within the dwell window.
	if now - _played_at_ms < int(active.minimum_dwell_time * 1000.0) and priority <= _current_priority:
		return

	_play(state, animation_name, priority, _classify(state), now)


## Plays a resolved direct clip and records it as the active animation so
## reconcile() does not immediately replace a pet's special move. `priority`
## is checked against the transition permissions: a drag or a protected
## higher-priority animation rejects the request instead of being overridden.
func play_external(
	animation_name: String,
	priority: int = AnimationTransitionRules.SPECIAL_PRIORITY
) -> bool:
	if sprite == null or controller == null or sprite.sprite_frames == null:
		return false
	if not sprite.sprite_frames.has_animation(animation_name):
		return false
	var now := Time.get_ticks_msec()
	## Permission gate: the transition manager is the single authority for
	## what may own the sprite. Behaviour systems never force a clip past it.
	if _is_dragging() and priority < AnimationTransitionRules.get_priority(PetState.State.DRAG):
		return false
	if _is_protected(now) and priority < _current_priority:
		return false
	var state: PetState.State = state_machine.get_state() if state_machine != null else PetState.State.IDLE
	var expected := PetRoster.resolve_animation(
		pet.profile_id,
		BehaviorCatalog.get_animation_for_state(state),
		sprite.sprite_frames
	)
	var category := _classify(state) if animation_name == expected else AnimationCategory.ONESHOT
	var protection := _protection_seconds(category)
	## A pet-specific special move is non-interruptible for its whole clip, so
	## lower-priority reactions queue behind it instead of cutting it off.
	if animation_name != expected:
		protection = maxf(protection, _clip_duration_seconds(animation_name))
	controller.play(sprite, animation_name, protection, true, true)
	_queue.clear()
	_current_state = state
	_current_animation = animation_name
	_current_priority = priority
	_current_category = category
	_played_at_ms = now
	_protected_until_ms = now + int(protection * 1000.0)
	_transition_count += 1
	_last_transition = {
		"state": state,
		"animation": animation_name,
		"priority": _current_priority,
		"category": AnimationCategory.keys()[category],
		"at_ms": now,
		"protected_until_ms": _protected_until_ms,
	}
	return sprite.animation == animation_name


## How long the given state's animation resists equal/lower-priority
## interruption (AnimationComponent uses it for the LAND settle timing).
func get_protection_seconds(state: PetState.State) -> float:
	return _protection_seconds(_classify(state))


## Full playback time of a non-looping clip. Used to keep special moves
## non-interruptible for their actual length instead of a generic window.
func _clip_duration_seconds(animation_name: String) -> float:
	if sprite == null or sprite.sprite_frames == null:
		return 0.0
	if not sprite.sprite_frames.has_animation(animation_name):
		return 0.0
	if sprite.sprite_frames.get_animation_loop(animation_name):
		return 0.0
	var speed := maxf(sprite.sprite_frames.get_animation_speed(animation_name), 0.01)
	var frames := maxi(sprite.sprite_frames.get_frame_count(animation_name), 1)
	return float(frames) / speed


func _process(_delta: float) -> void:
	if pet == null or not enabled:
		return
	var now := Time.get_ticks_msec()
	if not _queue.is_empty() and not _is_protected(now) and not _is_dragging():
		_play_queued(now)
	reconcile()


## --- Transition queue -------------------------------------------------------

func _queue_request(state: PetState.State, animation_name: String, priority: int) -> void:
	for entry in _queue:
		if entry.animation == animation_name:
			return
	var active := _effective_settings()
	if _queue.size() >= active.max_queue_length:
		var lowest_index := 0
		for i in range(1, _queue.size()):
			if _queue[i].priority < _queue[lowest_index].priority:
				lowest_index = i
		if priority <= _queue[lowest_index].priority:
			return
		_queue.remove_at(lowest_index)
	_queue.append({
		"state": state,
		"animation": animation_name,
		"priority": priority,
		"category": _classify(state),
	})


func _play_queued(now: int) -> void:
	var next := _pop_highest_priority()
	if next.is_empty():
		return
	_play(next.state, next.animation, next.priority, next.category, now)


func _pop_highest_priority() -> Dictionary:
	if _queue.is_empty():
		return {}
	var best: Dictionary = _queue[0]
	var best_index := 0
	for i in range(1, _queue.size()):
		if _queue[i].priority > best.priority:
			best = _queue[i]
			best_index = i
	_queue.remove_at(best_index)
	return best


## The animation that would play next from the queue (highest priority), or ""
## when the queue is empty. Used for debug and verification.
func get_next_queued_animation() -> String:
	if _queue.is_empty():
		return ""
	var best: Dictionary = _queue[0]
	for i in range(1, _queue.size()):
		if _queue[i].priority > best.priority:
			best = _queue[i]
	return best.animation


## --- Execution --------------------------------------------------------------

func _play(state: PetState.State, animation_name: String, priority: int, category: int, now: int) -> void:
	if controller == null:
		return
	var protection := _protection_seconds(category)
	controller.play(
		sprite,
		animation_name,
		protection,
		_is_protected(now),
		_current_animation == animation_name
	)
	## An interrupt supersedes every deferred request waiting behind the old
	## animation - the world moved on, so the queue is stale.
	if priority > _current_priority:
		_queue.clear()
	_current_state = state
	_current_animation = animation_name
	_current_priority = priority
	_current_category = category
	_played_at_ms = now
	_protected_until_ms = now + int(protection * 1000.0)
	_transition_count += 1
	_last_transition = {
		"state": state,
		"animation": animation_name,
		"priority": priority,
		"category": AnimationCategory.keys()[category],
		"at_ms": now,
		"protected_until_ms": _protected_until_ms,
	}


func _protection_seconds(category: int) -> float:
	var active := _effective_settings()
	match category:
		AnimationCategory.TRANSITION:
			return active.transition_protection_seconds
		AnimationCategory.ONESHOT:
			return active.one_shot_protection_seconds
		_:
			return 0.0


func _is_protected(now: int) -> bool:
	return now < _protected_until_ms


## True while the state machine says the pet is being carried (the manager
## consults it, never changes it). DRAG keeps its animation for its whole
## duration regardless of protection windows.
func _is_dragging() -> bool:
	return state_machine != null and state_machine.get_state() == PetState.State.DRAG


## --- Classification ---------------------------------------------------------

func _classify(state: PetState.State) -> int:
	var active := _effective_settings()
	var behavior := BehaviorCatalog.get_behavior_for_state(state)
	if behavior != null and behavior.category != BehaviorDefinition.Category.LOOP:
		match behavior.category:
			BehaviorDefinition.Category.TRANSITION:
				return AnimationCategory.TRANSITION
			BehaviorDefinition.Category.ONESHOT:
				return AnimationCategory.ONESHOT
	if state in active.transition_states:
		return AnimationCategory.TRANSITION
	if state in active.one_shot_states:
		return AnimationCategory.ONESHOT
	return AnimationCategory.LOOP


## --- State sync recovery ----------------------------------------------------

## Safety net: if the sprite is showing something the manager did not last
## play (external interference), re-apply the state machine's expected
## animation so the two never drift apart. No-op in normal operation - the
## manager is the only thing that plays the sprite, so it stays in lockstep
## with its own bookkeeping.
func reconcile() -> void:
	if state_machine == null or sprite == null:
		return
	if sprite.animation == _current_animation:
		return
	var now := Time.get_ticks_msec()
	if _is_protected(now):
		return
	var sm_state := state_machine.get_state()
	## BehaviorCatalog stores canonical clip names ("walk", "jump", etc.),
	## while each companion's SpriteFrames uses profile-prefixed names such as
	## "ori walk". Reconcile must compare/play the resolved companion clip;
	## otherwise it can fall back to an unrelated generic animation after the
	## transition dwell expires.
	var expected := PetRoster.resolve_animation(
		pet.profile_id,
		BehaviorCatalog.get_animation_for_state(sm_state),
		sprite.sprite_frames
	)
	if expected == "":
		return
	_play(sm_state, expected, _effective_settings().get_priority(sm_state), _classify(sm_state), now)


## --- Debug support ----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var now := Time.get_ticks_msec()
	var queued: Array = []
	for entry in _queue:
		queued.append("%s(%s)" % [entry.animation, _state_name(entry.state)])
	return {
		"current_animation": _current_animation,
		"current_state": _state_name(_current_state),
		"current_priority": _current_priority,
		"current_category": AnimationCategory.keys()[_current_category],
		"protected_left_ms": maxi(_protected_until_ms - now, 0),
		"dwell_left_ms": maxi(int(_effective_settings().minimum_dwell_time * 1000.0) - (now - _played_at_ms), 0),
		"queue": queued,
		"queue_length": _queue.size(),
		"max_queue_length": _effective_settings().max_queue_length,
		"transition_count": _transition_count,
		"last_transition": _last_transition,
	}


func _state_name(state: int) -> String:
	var keys := PetState.State.keys()
	if state >= 0 and state < keys.size():
		return keys[state]
	return str(state)
