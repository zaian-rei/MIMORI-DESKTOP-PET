extends "res://core/base/pet_component.gd"
class_name BehaviorController

## Executes the pet's autonomous life on two channels:
##  1) Behavior execution - consumes the recommendation from
##     BehaviorDecisionComponent (which owns the cadence, eligibility and
##     utility scoring) and starts it. This component never chooses what to
##     do; it only performs the chosen action.
##  2) Mood channel - every 18-35s it has a chance to flash a 2.5s
##     THINK/HAPPY/SAD quirk, weighted by the pet's emotion.
## Kept as the single executor so there is exactly ONE actor submitting
## behavior state transitions. Only submits LOW/NORMAL priority - physics
## (FALL/LAND) and drag/manual (DRAG) stay ground truth and interrupt both.
const REPEAT_BOREDOM_DELTA := 2.0

const MOOD_CHECK_MIN_SECONDS := 18.0
const MOOD_CHECK_MAX_SECONDS := 35.0
const MOOD_DURATION_SECONDS := 2.5

const MOOD_POOL := [
	PetState.State.THINK,
	PetState.State.HAPPY,
	PetState.State.SAD,
]

## States the decision loop must never touch. FALL is transient mid-air and
## JUMP owns its own physics arc, so neither should be interrupted.
## LAND and DRAG are deliberately NOT blocked: LAND happens on the first
## physics frame (blocking it froze the pet in the land animation forever)
## and DRAG's real guard is the `dragging` flag below - the state itself
## lingers for a frame after release.
const BLOCKED_STATES := [
	PetState.State.FALL,
	PetState.State.JUMP,
]

## Reference to the stats owned by BehaviorStatsComponent - the single
## source of truth for the pet's needs. Read only here; every mutation
## goes through stats_component so change signals fire.
var stats: PetStats
var stats_component: BehaviorStatsComponent

var decision_component: BehaviorDecisionComponent
var personality_component: PersonalityComponent
var polish_component: BehaviorPolishComponent

var state_machine: StateMachineComponent
var context_menu: ContextMenuComponent
var drag_component: DragComponent
var movement_component: MovementComponent
var emotion_component: EmotionComponent

## Held by InteractionComponent while it runs a scripted reaction or cursor
## follow. When true the decision brain stands down entirely.
var autonomy_locked: bool = false

var active_behavior: BehaviorDefinition

## Behavior picked by the decision loop but held back by a polish transition
## delay (e.g. a brief pause before sleeping/thinking). While set, the pet
## stays idle until the delay elapses, then this becomes the active behavior.
var _pending_behavior: BehaviorDefinition
var _transition_delay_left: float = 0.0

var _active_time_left: float = 0.0
var _last_behavior_state: int = -1

var _mood_timer: float = 0.0
var _mood_seconds_left: float = 0.0
var _current_mood: PetState.State = PetState.State.IDLE
var _last_moment_state: PetState.State = PetState.State.IDLE
var _signature_move_timer := 0.0
var _signature_animation := ""


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	context_menu = pet.get_component(ContextMenuComponent)
	drag_component = pet.get_component(DragComponent)
	movement_component = pet.get_component(MovementComponent)
	emotion_component = pet.get_component(EmotionComponent)
	stats_component = pet.get_component(BehaviorStatsComponent)
	stats = stats_component.get_stats()
	decision_component = pet.get_component(BehaviorDecisionComponent)
	personality_component = pet.get_component(PersonalityComponent)
	polish_component = pet.get_component(BehaviorPolishComponent)
	_mood_timer = _next_mood_delay()
	_signature_move_timer = _next_signature_delay()
	pet.sprite.animation_finished.connect(_on_sprite_animation_finished)
	EventBus.subscribe(EventBus.MUSIC_STARTED, _on_music_started_event)
	EventBus.subscribe(EventBus.MUSIC_STOPPED, _on_music_stopped_event)

	LoggerGlobal.info("BehaviorController initialized.")


func get_active_behavior() -> BehaviorDefinition:
	return active_behavior


## Brief, non-restarting reaction when cursor-follow reaches the pointer.
## The caller controls the probability; this method picks the reaction.
func play_cursor_reaction(probability: float = 1.0) -> bool:
	if randf() >= clampf(probability, 0.0, 1.0):
		return false
	if drag_component.dragging or context_menu.manual_override_active or not _signature_animation.is_empty():
		return false
	var current := state_machine.get_state()
	if current in [PetState.State.FALL, PetState.State.LAND, PetState.State.DRAG, PetState.State.DEEP_SLEEP, PetState.State.JUMP]:
		return false
	var specials := PetRoster.get_special_animations(pet.profile_id, pet.sprite.sprite_frames)
	if not specials.is_empty() and randf() < 0.18:
		return play_special_move()
	var reaction := PetState.State.HAPPY if randf() < 0.5 else PetState.State.THINK
	_current_mood = reaction
	_mood_seconds_left = randf_range(1.8, 3.0)
	pet.velocity.x = 0.0
	state_machine.force_state(reaction)
	var reaction_duration := _mood_seconds_left
	get_tree().create_timer(reaction_duration).timeout.connect(
		func() -> void:
			if state_machine != null and state_machine.get_state() == reaction:
				state_machine.force_state(PetState.State.IDLE)
	)
	return true


## Ask the decision system to reconsider right away (e.g. after a manual
## animation finishes) instead of waiting out its timer.
func kick_decision() -> void:
	decision_component.reset_timer()


## Apply a newly selected personality immediately when the pet can act.
## Busy states keep their current animation, then use the new modifiers on the
## next free behavior decision.
func apply_personality_change() -> void:
	if decision_component == null:
		return
	_cancel_pending()
	decision_component.reset_timer()
	_mood_timer = _next_mood_delay()
	if not _can_act():
		return
	active_behavior = null
	_active_time_left = 0.0
	_mood_seconds_left = 0.0
	if state_machine.get_state() != PetState.State.IDLE:
		state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)


func _process(delta: float) -> void:
	if pet == null:
		return

	if active_behavior != null:
		## Compare against the plan's final state, not a transient intermediate
		## the transition graph inserted (Run -> Walk -> ...). Otherwise the
		## executor would abandon a behaviour the moment it starts walking.
		if state_machine.get_target_state() != active_behavior.state:
			_active_behavior_ended()
		else:
			_apply_active_effects(delta)
			_active_time_left -= delta
			if _active_time_left <= 0.0:
				_active_behavior_ended()

	_tick_mood(delta)
	_tick_signature_move(delta)

	if not _can_act():
		_cancel_pending()
		return

	## A behavior is waiting out its transition delay: hold idle until the
	## pause elapses (a mood quirk steals the slot and cancels the pending).
	if _pending_behavior != null:
		if _is_mood_active():
			_cancel_pending()
			return
		_transition_delay_left -= delta
		if _transition_delay_left <= 0.0:
			var pending := _pending_behavior
			_pending_behavior = null
			_start_behavior(pending)
		return

	if _is_mood_active():
		return

	var action := decision_component.tick(delta)
	if action != null and active_behavior == null:
		_begin_behavior(action)


func _active_behavior_ended() -> void:
	active_behavior = null
	## Settle into idle and let the decision timer count down so the pet
	## pauses between activities instead of hopping straight into the next
	## animation. Mood quirks run on their own timer and are left alone.
	if not _is_mood_active() and _can_act():
		state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
	decision_component.arm_timer()


## Starts a behavior, optionally after a polish transition delay (a brief
## idle pause before sleeping/thinking). Delays are short enough to feel
## natural; without one this is identical to the original direct start.
func _begin_behavior(behavior: BehaviorDefinition) -> void:
	var delay := 0.0
	if polish_component != null:
		delay = polish_component.get_transition_delay(behavior.state)
	if delay > 0.0:
		_pending_behavior = behavior
		_transition_delay_left = delay
		if state_machine.get_state() != PetState.State.IDLE:
			state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
		return
	_start_behavior(behavior)


func _cancel_pending() -> void:
	_pending_behavior = null
	_transition_delay_left = 0.0


func _start_behavior(behavior: BehaviorDefinition) -> void:
	## Ground movement always begins through Walk: a Run decision taken while
	## the pet is not already moving becomes a Walk. Once the walk minimum
	## duration has elapsed the planner may promote the intent to Run.
	if behavior.state == PetState.State.RUN \
			and state_machine.get_state() not in [PetState.State.WALK, PetState.State.RUN]:
		var walk_behavior := BehaviorCatalog.get_behavior_for_state(PetState.State.WALK)
		if walk_behavior != null:
			behavior = walk_behavior

	## Some profiles have no sad clip. Keep the shared behavior catalog, but route their
	## autonomous sad action to a supported thoughtful expression.
	if behavior.state == PetState.State.SAD and not PetRoster.has_native_animation(pet.profile_id, "sad", pet.sprite.sprite_frames):
		behavior = BehaviorCatalog.get_behavior_for_state(PetState.State.THINK)
		if behavior == null:
			return

	## Repeating the same action makes the pet more bored, nudging the
	## utility scoring toward something different next time.
	if behavior.state == _last_behavior_state:
		stats_component.add(PetStats.Stat.BOREDOM, REPEAT_BOREDOM_DELTA)
	_last_behavior_state = behavior.state

	## Give walking a fresh heading so consecutive walks don't trudge the
	## same way; MovementComponent's edge-bounce corrects dead ends.
	if behavior.state == PetState.State.WALK or behavior.state == PetState.State.RUN:
		movement_component.direction = 1 if randf() < 0.5 else -1

	active_behavior = behavior
	_active_time_left = randf_range(behavior.duration_min, behavior.duration_max)
	if personality_component != null:
		_active_time_left *= personality_component.get_duration_modifier_for(behavior.state)
	if polish_component != null:
		_active_time_left *= polish_component.get_duration_factor(behavior.state)
	decision_component.note_behavior_started(behavior)

	var priority := _priority_for(behavior.state)
	state_machine.request_behavior(behavior, priority)
	LoggerGlobal.debug("Behavior started: %s" % PetState.State.keys()[behavior.state])


func _tick_mood(delta: float) -> void:
	## Sleep owns the pet completely: random mood quirks would cancel the
	## active sleep behavior (the state change ends it), so they stand down
	## for the whole nap.
	if state_machine.get_state() == PetState.State.SLEEP or state_machine.get_state() == PetState.State.DEEP_SLEEP:
		_mood_timer = _next_mood_delay()
		return
	if _mood_seconds_left > 0.0:
		_mood_seconds_left -= delta
		if _can_act():
			state_machine.request_state(_current_mood, StatePriority.Level.NORMAL)
		if _mood_seconds_left <= 0.0:
			_mood_timer = _next_mood_delay()
		return

	_mood_timer -= delta
	if _mood_timer <= 0.0:
		_mood_timer = _next_mood_delay()
		## Moments are idle-only and never stack on top of another active
		## behavior. Cursor following locks autonomy, so it is excluded too.
		if active_behavior == null and _can_act() and randf() <= _moment_chance():
			_start_mood()


func _start_mood() -> void:
	_current_mood = _pick_mood()
	_last_moment_state = _current_mood
	_mood_seconds_left = _moment_duration()
	pet.velocity = Vector2.ZERO
	## The state machine routes Walk/Run through Idle first, so a moment can
	## never hard-cut movement animation.
	state_machine.request_state(_current_mood, StatePriority.Level.NORMAL)
	LoggerGlobal.debug("Mood started: %s" % PetState.State.keys()[_current_mood])


## Picks the mood quirk weighted by the pet's current emotion, so the
## visible expression usually matches how it's feeling. The previous moment
## is excluded when another option exists - moments never repeat back to back.
func _pick_mood() -> PetState.State:
	var weights := {
		PetState.State.THINK: 1.0,
		PetState.State.HAPPY: 1.0,
	}
	if PetRoster.has_native_animation(pet.profile_id, "sad", pet.sprite.sprite_frames):
		weights[PetState.State.SAD] = 1.0
	if weights.size() > 1:
		weights.erase(_last_moment_state)
	match emotion_component.get_emotion():
		EmotionComponent.Emotion.HAPPY, EmotionComponent.Emotion.EXCITED:
			weights[PetState.State.HAPPY] = 4.0
		EmotionComponent.Emotion.SAD:
			if weights.has(PetState.State.SAD):
				weights[PetState.State.SAD] = 4.0
			else:
				weights[PetState.State.THINK] = 3.0
		EmotionComponent.Emotion.SLEEPY, EmotionComponent.Emotion.BORED:
			weights[PetState.State.THINK] = 3.0
		_:
			pass
	var total := 0.0
	for weight in weights.values():
		total += weight
	var roll := randf() * total
	for state in weights:
		roll -= weights[state]
		if roll <= 0.0:
			return state
	return MOOD_POOL.pick_random()


## Music started: make the pet dance right away instead of waiting out the
## decision timer.
func _on_music_started_event(_payload: Dictionary) -> void:
	if active_behavior == null and not _is_mood_active() and _can_act():
		var action := decision_component.request_now()
		if action != null:
			_start_behavior(action)


## Music stopped: cut the dance and hand back to normal autonomous life.
func _on_music_stopped_event(_payload: Dictionary) -> void:
	if state_machine.get_state() == PetState.State.DANCE:
		state_machine.force_state(PetState.State.IDLE)
		active_behavior = null
		kick_decision()


func _is_mood_active() -> bool:
	return _mood_seconds_left > 0.0


## Rare signature moves are selected only from clips that exist for this pet.
## They play once during an otherwise quiet idle moment, then return to idle.
func _tick_signature_move(delta: float) -> void:
	if not _signature_animation.is_empty():
		if state_machine.get_state() != PetState.State.IDLE or _is_user_busy():
			_signature_animation = ""
			_signature_move_timer = _next_signature_delay()
			if state_machine.get_state() == PetState.State.IDLE:
				var animation := pet.get_component(AnimationComponent) as AnimationComponent
				if animation != null:
					animation.play("idle", AnimationTransitionRules.get_priority(PetState.State.IDLE))
		return

	_signature_move_timer -= delta
	if _signature_move_timer > 0.0:
		return
	_signature_move_timer = _next_signature_delay()
	if state_machine.get_state() != PetState.State.IDLE or active_behavior != null or _is_mood_active() or not _can_act():
		return
	if randf() > PetRoster.special_chance(pet.profile_id):
		return
	var moves := PetRoster.get_special_animations(pet.profile_id, pet.sprite.sprite_frames)
	if moves.is_empty():
		return
	var move: Dictionary = moves.pick_random()
	_signature_animation = str(move["animation"])
	var animation := pet.get_component(AnimationComponent) as AnimationComponent
	if animation != null:
		animation.play(_signature_animation)
	if pet.sprite.animation == _signature_animation:
		_play_signature_sound(str(move.get("sound_event", "")))
	if pet.sprite.animation != _signature_animation:
		_signature_animation = ""


func _on_sprite_animation_finished() -> void:
	if _signature_animation.is_empty() or pet.sprite.animation != _signature_animation:
		return
	_signature_animation = ""
	_signature_move_timer = _next_signature_delay()
	if state_machine.get_state() == PetState.State.IDLE and not _is_user_busy():
		var animation := pet.get_component(AnimationComponent) as AnimationComponent
		if animation != null:
			animation.play("idle", AnimationTransitionRules.get_priority(PetState.State.IDLE))


func _is_user_busy() -> bool:
	return (context_menu != null and context_menu.manual_override_active) or (drag_component != null and drag_component.dragging) or autonomy_locked


func is_signature_move_playing() -> bool:
	return not _signature_animation.is_empty()


## Settings can request a pet-specific signature move on demand. Autonomous
## moves still use the idle-only timer; manual requests gently settle the pet
## first, but never cut off a drag or an active jump arc.
func play_special_move() -> bool:
	if drag_component.dragging or context_menu.manual_override_active:
		return false
	var moves := PetRoster.get_special_animations(pet.profile_id, pet.sprite.sprite_frames)
	if moves.is_empty():
		return false
	## A manual request may replace the pet's entry animation or another special
	## animation; the button should not be disabled just because one is playing.
	_signature_animation = ""
	_cancel_pending()
	active_behavior = null
	_active_time_left = 0.0
	_mood_seconds_left = 0.0
	var physics := pet.get_component(PhysicsComponent) as PhysicsComponent
	if physics != null and state_machine.get_state() in [PetState.State.JUMP, PetState.State.FALL, PetState.State.LAND]:
		physics.snap_to_ground()
	pet.velocity = Vector2.ZERO
	state_machine.force_state(PetState.State.IDLE)
	var move: Dictionary = moves.pick_random()
	_signature_animation = str(move["animation"])
	_signature_move_timer = _next_signature_delay()
	var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
	if follow != null:
		follow.pause_for_signature_move()
	var animation := pet.get_component(AnimationComponent) as AnimationComponent
	if animation == null:
		_signature_animation = ""
		return false
	animation.play(_signature_animation)
	var accepted := pet.sprite.animation == _signature_animation
	if accepted:
		_play_signature_sound(str(move.get("sound_event", "")))
	if not accepted:
		_signature_animation = ""
	return accepted


func play_startup_intro() -> void:
	var intro := PetRoster.get_startup_animation(pet.profile_id, pet.sprite.sprite_frames)
	if intro.is_empty():
		return
	_signature_animation = intro
	_signature_move_timer = _next_signature_delay()
	var animation := pet.get_component(AnimationComponent) as AnimationComponent
	if animation != null:
		animation.play(intro)
	if pet.sprite.animation == intro:
		var move := _get_special_for_animation(intro)
		if not move.is_empty():
			_play_signature_sound(str(move.get("sound_event", "")))
	if pet.sprite.animation != intro:
		_signature_animation = ""


func _get_special_for_animation(animation_name: String) -> Dictionary:
	for move in PetRoster.get_special_animations(pet.profile_id, pet.sprite.sprite_frames):
		if str(move.get("animation", "")) == animation_name:
			return move
	return {}


func _play_signature_sound(event_id: String) -> void:
	if not event_id.is_empty():
		AudioManager.play_event(StringName(event_id))


func reset_signature_moves() -> void:
	_signature_animation = ""
	_signature_move_timer = _next_signature_delay()


func _next_signature_delay() -> float:
	var wait_range := PetRoster.special_wait_range(pet.profile_id) if pet != null else Vector2(60.0, 110.0)
	return randf_range(wait_range.x, wait_range.y)


func _next_mood_delay() -> float:
	var wait_range := PetRoster.mood_wait_range(pet.profile_id) if pet != null else Vector2(MOOD_CHECK_MIN_SECONDS, MOOD_CHECK_MAX_SECONDS)
	var gap_scale := 1.0
	if polish_component != null:
		gap_scale = polish_component.get_moment_gap_scale()
	if personality_component != null:
		gap_scale /= personality_component.get_reaction_speed_modifier()
	return randf_range(wait_range.x, wait_range.y) * gap_scale


## Randomised per-profile moment chance, scaled by the global polish setting.
func _moment_chance() -> float:
	var chance := PetRoster.mood_chance(pet.profile_id) if pet != null else 0.35
	if polish_component != null:
		chance *= polish_component.get_moment_probability_scale()
	return clampf(chance, 0.0, 1.0)


func _moment_duration() -> float:
	if polish_component != null:
		return polish_component.get_moment_duration()
	return MOOD_DURATION_SECONDS


func _priority_for(state: PetState.State) -> StatePriority.Level:
	match state:
		PetState.State.IDLE, PetState.State.THINK, PetState.State.HAPPY, PetState.State.SAD:
			return StatePriority.Level.LOW
		_:
			return StatePriority.Level.NORMAL


func _apply_active_effects(delta: float) -> void:
	if active_behavior == null or active_behavior.stat_effects.is_empty():
		return
	stats_component.apply_effects(active_behavior.stat_effects, delta)


func _can_act() -> bool:
	if not _signature_animation.is_empty():
		return false
	if context_menu.manual_override_active:
		return false
	if drag_component.dragging:
		return false
	if autonomy_locked:
		return false
	if state_machine.get_state() in BLOCKED_STATES:
		return false
	return true


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"active_behavior": PetState.State.keys()[active_behavior.state] if active_behavior != null else "none",
		"active_time_left": _active_time_left,
		"pending_behavior": PetState.State.keys()[_pending_behavior.state] if _pending_behavior != null else "none",
		"transition_delay_left": _transition_delay_left,
		"mood": PetState.State.keys()[_current_mood] if _is_mood_active() else "none",
		"mood_seconds_left": _mood_seconds_left,
		"autonomy_locked": autonomy_locked,
		"manual_override_active": context_menu.manual_override_active if context_menu != null else false,
		"last_behavior_state": PetState.State.keys()[_last_behavior_state] if _last_behavior_state >= 0 and _last_behavior_state < PetState.State.keys().size() else "none",
	}
