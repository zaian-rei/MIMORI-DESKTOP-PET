extends "res://core/base/pet_component.gd"
class_name FollowCursorComponent

const DefaultFollowCursorSettings := preload("res://data/configs/follow_cursor_settings.tres")

## IDLE -> NOTICE -> RUN/WALK -> JUMP -> RESTING -> IDLE.
## RESTING is a latch: while the cursor stays inside the detection radius the
## pet will neither chase again nor attempt another jump. Only a real exit
## followed by a new entry re-arms the system.
enum FollowPhase { IDLE, NOTICE, RUN, WALK, JUMP, RESTING }

## States whose vertical arc or drag ownership must never be interrupted by
## cursor following. JUMP/FALL/LAND belong to the follow jump while phase is
## JUMP; the component waits for the physics-authoritative landing instead of
## submitting a competing state.
const ARC_STATES := [
	PetState.State.JUMP,
	PetState.State.FALL,
	PetState.State.LAND,
	PetState.State.DRAG,
]

## The persisted preference. Held here and mirrored through ConfigService so
## the toggle survives restarts. Distinct from the base `enabled` flag.
var follow_enabled: bool = false

var state_machine: StateMachineComponent
var movement_component: MovementComponent
var drag_component: DragComponent
var behavior_controller: BehaviorController
var context_menu: ContextMenuComponent
var awareness: DesktopAwarenessComponent
var polish_component: MovementPolishComponent
var physics: PhysicsComponent

var settings: FollowCursorSettings

var _phase := FollowPhase.IDLE
var _notice_left := 0.0

## Exactly one jump attempt per radius entry. These flags make the single
## attempt observable and prevent a second one if the launch or landing event
## is delayed by a frame.
var _overhead_jump_count := 0
var _jump_attempt_pending := false
var _jump_launched := false
var _jump_launch_wait_left := 0.0
var _follow_jump_active := false

## Direction the follow jump committed to at launch. The pet keeps this
## heading through JUMP -> FALL -> LAND instead of chasing a moving cursor.
var _jump_direction := 1


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	movement_component = pet.get_component(MovementComponent)
	drag_component = pet.get_component(DragComponent)
	behavior_controller = pet.get_component(BehaviorController)
	context_menu = pet.get_component(ContextMenuComponent)
	awareness = pet.get_component(DesktopAwarenessComponent)
	polish_component = pet.get_component(MovementPolishComponent)
	physics = pet.get_component(PhysicsComponent)
	settings = pet.definition.follow_cursor_settings if pet.definition.follow_cursor_settings != null else DefaultFollowCursorSettings
	settings = settings.duplicate(true) as FollowCursorSettings
	reload_tuning_from_settings()
	if not bool(SettingsManager.get_setting("follow_cursor.follow_default_migrated", false)):
		ConfigService.set_follow_cursor_enabled(true)
		SettingsManager.set_setting("follow_cursor.follow_default_migrated", true)
	follow_enabled = ConfigService.follow_cursor_enabled
	if physics != null:
		physics.jump_landed.connect(_on_jump_landed)
		physics.jump_launched.connect(_on_jump_launched)
	LoggerGlobal.info("FollowCursorComponent initialized.")


## Public retune seam: future settings screens can swap the follow tuning
## resource without any code change.
func set_settings(new_settings: FollowCursorSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings.duplicate(true) as FollowCursorSettings


## Reload persisted cursor behavior tuning after the Settings page changes it.
func reload_tuning_from_settings() -> void:
	if settings == null:
		settings = DefaultFollowCursorSettings.duplicate(true) as FollowCursorSettings
	settings.detection_radius = float(SettingsManager.get_setting("follow_cursor.detection_radius", settings.detection_radius))
	settings.stop_distance = float(SettingsManager.get_setting("follow_cursor.stop_distance", settings.stop_distance))
	settings.sprint_distance = float(SettingsManager.get_setting("follow_cursor.sprint_distance", settings.sprint_distance))
	settings.walk_speed = float(SettingsManager.get_setting("follow_cursor.walk_speed", settings.walk_speed))
	settings.run_speed = float(SettingsManager.get_setting("follow_cursor.run_speed", settings.run_speed))
	settings.jump_height = float(SettingsManager.get_setting("follow_cursor.jump_height", settings.jump_height))
	settings.reaction_probability = float(SettingsManager.get_setting("follow_cursor.reaction_probability", settings.reaction_probability))


## Toggles Follow Cursor Mode. Persists the preference through ConfigService
## so it survives restarts. Disabling stands the follow down immediately.
func set_follow_enabled(value: bool) -> void:
	if follow_enabled == value:
		return
	follow_enabled = value
	ConfigService.set_follow_cursor_enabled(value)
	EventBus.emit(EventBus.CURSOR_FOLLOW_ENABLED if value else EventBus.CURSOR_FOLLOW_DISABLED)
	if not value:
		_cancel_jump_attempt()
		_set_phase(FollowPhase.IDLE)
		_release_follow()
	LoggerGlobal.debug("Follow cursor %s." % ("on" if value else "off"))


func is_follow_enabled() -> bool:
	return follow_enabled


## Current state-machine phase. Exposed for tests/debug and for systems that
## need to know whether the pet is actively chasing (e.g. the debug overlay).
func get_phase() -> FollowPhase:
	return _phase


func get_phase_name() -> String:
	return FollowPhase.keys()[_phase]


func is_resting() -> bool:
	return _phase == FollowPhase.RESTING


func get_speed_for_state(state: PetState.State) -> float:
	return settings.run_speed if state == PetState.State.RUN else settings.walk_speed


func is_follow_jump_active() -> bool:
	return _follow_jump_active


## A signature move takes priority over the follow system. Following stands
## down for the duration; it does not fight the move or restack animations.
func pause_for_signature_move() -> void:
	_cancel_jump_attempt()
	if _cursor_inside_radius():
		_set_phase(FollowPhase.RESTING)
	else:
		_set_phase(FollowPhase.IDLE)
	_release_follow()


func _physics_process(delta: float) -> void:
	if pet == null:
		return

	if not follow_enabled or not enabled:
		if _phase != FollowPhase.IDLE or movement_component.following_cursor:
			_cancel_jump_attempt()
			_set_phase(FollowPhase.IDLE)
			_release_follow(false)
		return

	var cursor := awareness.cursor_position()
	var distance := pet.world_position.distance_to(cursor)
	if distance > settings.detection_radius:
		_on_cursor_left_radius()
		return

	## RESTING is the post-jump / post-arrival latch. Nothing below this branch
	## is allowed to restart the chase while the cursor is still inside the
	## detection radius.
	if _phase == FollowPhase.RESTING:
		return

	if _phase == FollowPhase.JUMP:
		_tick_jump(delta)
		return

	## Dragging, manual control, external fall/land and an external jump own
	## the pet completely; latch until the cursor leaves so following cannot
	## immediately start fighting them again.
	if _is_hard_interrupted():
		_interrupt_episode()
		return

	## A one-shot special move must not be overridden, but it is temporary:
	## pause (without latching) and resume after it finishes.
	if _is_soft_interrupted():
		_pause_episode()
		return

	## Follow mode wakes the pet instead of yielding to sleepiness. Cursor
	## following is a direct user interaction, so it takes precedence over a
	## nap while the pointer is inside the detection radius.
	if state_machine.get_state() == PetState.State.SLEEP \
			or state_machine.get_state() == PetState.State.DEEP_SLEEP:
		state_machine.force_state(PetState.State.IDLE)

	match _phase:
		FollowPhase.IDLE:
			## Do not restart an episode every frame while the cursor is
			## already within the stopping distance. An overhead cursor is
			## still allowed to trigger its single jump.
			if _horizontal_distance(cursor) <= settings.stop_distance and not _should_jump(cursor):
				return
			_begin_notice(cursor)
		FollowPhase.NOTICE:
			_tick_notice(delta, cursor)
		FollowPhase.RUN, FollowPhase.WALK:
			_tick_chase(cursor)


func _begin_notice(cursor: Vector2) -> void:
	_set_phase(FollowPhase.NOTICE)
	_notice_left = maxf(settings.notice_duration, 0.0)
	_overhead_jump_count = 0
	_jump_attempt_pending = false
	_jump_launched = false
	_follow_jump_active = false
	_engage_follow()
	_update_facing(cursor)
	if state_machine.get_state() not in ARC_STATES:
		state_machine.request_state(PetState.State.THINK, StatePriority.Level.NORMAL)


func _tick_notice(delta: float, cursor: Vector2) -> void:
	_update_facing(cursor)
	_notice_left -= delta
	if _notice_left > 0.0:
		return

	if _should_jump(cursor):
		_begin_jump(cursor)
		return
	_choose_move_phase(_horizontal_distance(cursor), true)


func _tick_chase(cursor: Vector2) -> void:
	_update_facing(cursor)

	## The overhead jump is deliberately not checked while chasing: replacing
	## a walk/run mid-stride made the pet look like it was walking and jumping
	## at the same time. The pet first arrives, settles to IDLE, then the
	## NOTICE phase performs the single hop.
	var horizontal := _horizontal_distance(cursor)
	if horizontal <= settings.stop_distance:
		_arrive_at_cursor()
		return

	if not awareness.can_move_toward(cursor):
		_arrive_at_cursor()
		return

	_choose_move_phase(horizontal, false)


## Keeps the movement state and speed in sync with the cursor distance. The
## hysteresis band is deliberately wider than the raw switch point so the pet
## eases from RUN to WALK (and back) without animation flicker.
func _choose_move_phase(horizontal_distance: float, fresh: bool) -> void:
	var hysteresis := settings.stopping_hysteresis
	if polish_component != null:
		hysteresis = maxf(hysteresis, polish_component.get_follow_cursor_hysteresis())

	var should_run := horizontal_distance > settings.sprint_distance
	if not fresh:
		if _phase == FollowPhase.RUN:
			should_run = horizontal_distance > settings.sprint_distance - hysteresis
		elif _phase == FollowPhase.WALK:
			should_run = horizontal_distance > settings.sprint_distance + hysteresis

	if should_run:
		_set_phase(FollowPhase.RUN)
		if state_machine.get_state() != PetState.State.RUN:
			state_machine.request_state(PetState.State.RUN, StatePriority.Level.NORMAL)
	else:
		_set_phase(FollowPhase.WALK)
		if state_machine.get_state() != PetState.State.WALK:
			state_machine.request_state(PetState.State.WALK, StatePriority.Level.NORMAL)


## Only a settled, grounded pet may jump. The horizontal reach check keeps
## far-away overhead cursors as normal run/walk targets; the chase never
## jumps mid-stride, so the pet first stops at the cursor and the NOTICE
## phase then performs the single hop. A cursor directly overhead satisfies
## the horizontal reach check at any height, so the pet never gets stuck
## walking in place beneath it.
func _should_jump(cursor: Vector2) -> bool:
	if settings.max_jumps_per_attempt <= 0:
		return false
	if _overhead_jump_count >= settings.max_jumps_per_attempt:
		return false
	if physics != null and physics.is_jumping:
		return false
	if awareness != null and not awareness.is_grounded():
		return false
	var pos := pet.world_position
	if cursor.y > pos.y - settings.jump_height_above:
		return false
	var horizontal := absf(cursor.x - pos.x)
	var distance := pos.distance_to(cursor)
	return distance <= settings.jump_trigger_radius or horizontal <= settings.jump_distance


func _begin_jump(cursor: Vector2) -> void:
	_set_phase(FollowPhase.JUMP)
	_overhead_jump_count += 1
	_jump_attempt_pending = true
	_jump_launched = false
	_jump_launch_wait_left = 0.75
	_follow_jump_active = true

	var pos := pet.world_position
	_jump_direction = 1 if cursor.x >= pos.x else -1
	movement_component.direction = _jump_direction
	pet.sprite.flip_h = _jump_direction < 0

	## The height is data, not a fixed multiplier: derive the launch velocity
	## from this pet's gravity so jump_height is the actual peak in pixels.
	if physics != null:
		physics.set_follow_jump_velocity(_velocity_for_height(settings.jump_height))
	state_machine.request_state(PetState.State.JUMP, StatePriority.Level.NORMAL)


func _tick_jump(delta: float) -> void:
	## Dragging, manual control and non-interruptible specials win over the
	## follow jump. Cancel the rest of the attempt instead of fighting them.
	if _must_abort_jump():
		_cancel_jump_attempt()
		_enter_resting()
		return

	if physics != null and physics.is_jumping:
		_jump_launched = true
		_jump_launch_wait_left = 0.0
		return

	## The landing signal normally resolves the jump. The state check is a
	## safety net for a missed frame; it never starts a second attempt.
	if _jump_launched:
		var state := state_machine.get_state()
		if state == PetState.State.LAND or state == PetState.State.IDLE:
			_finish_jump()
			return

	_jump_launch_wait_left -= delta
	if _jump_launch_wait_left <= 0.0:
		## The request was rejected (for example the pet was not grounded
		## when the state applied). A follow jump is one-shot: rest instead of
		## retrying while the cursor remains inside the radius.
		_cancel_jump_attempt()
		_enter_resting()


## Called by PhysicsComponent on the physics frame a follow jump lands.
func _on_jump_landed() -> void:
	if not _jump_attempt_pending:
		return
	_finish_jump(true)


func _on_jump_launched() -> void:
	if not _jump_attempt_pending:
		return
	_jump_launched = true
	_jump_launch_wait_left = 0.0


## The jump is over: stop steering immediately, hand movement back, and latch
## RESTING. The jump clip owns the whole arc (no FALL/LAND clips); physics
## settles the pet straight into IDLE on landing.
func _finish_jump(from_landing: bool = false) -> void:
	_jump_attempt_pending = false
	_follow_jump_active = false
	_jump_launched = false
	_jump_launch_wait_left = 0.0
	if physics != null:
		physics.clear_follow_jump_velocity()
	_set_phase(FollowPhase.RESTING)
	_release_follow(false)

	## If the launch request was swallowed before an arc started there is no
	## landing transition to settle, so return to idle explicitly. A real
	## landing is handled by physics (Jump -> Idle).
	if not from_landing and state_machine.get_state() == PetState.State.JUMP and (physics == null or not physics.is_jumping):
		state_machine.force_state(PetState.State.IDLE)


## Reached the cursor without jumping. This completes the approach just like a
## jump completes: latch RESTING so the pet neither chases nor retries while
## the pointer remains inside the detection radius. Only a real exit followed
## by a new entry re-arms the system.
func _arrive_at_cursor() -> void:
	_enter_resting()


## Post-jump latch. The pet stays here while the cursor remains inside the
## detection radius, even if it is still overhead or nearby.
func _enter_resting() -> void:
	_cancel_jump_attempt()
	_set_phase(FollowPhase.RESTING)
	_release_follow()


## A drag, manual animation or fall/land owned by someone else interrupted the
## episode. If the pet was already chasing, latch until the cursor leaves the
## detection radius so following cannot immediately fight the other system.
## A transient block before the chase started (e.g. the startup landing) just
## leaves the machine idle, ready to notice the cursor once the block clears.
func _interrupt_episode() -> void:
	_cancel_jump_attempt()
	var was_chasing := _phase != FollowPhase.IDLE
	_set_phase(FollowPhase.RESTING if was_chasing else FollowPhase.IDLE)
	_release_follow(false)


## A temporary, non-interruptible animation (signature move, startup intro)
## paused the episode. Do not latch: once the move finishes a cursor still
## inside the radius may be noticed and followed again.
func _pause_episode() -> void:
	_cancel_jump_attempt()
	_set_phase(FollowPhase.IDLE)
	_release_follow(false)


func _on_cursor_left_radius() -> void:
	## Never cut a jump arc short: let Jump -> Fall -> Land finish. The next
	## frame after landing sees the cursor outside and clears RESTING.
	if _phase == FollowPhase.JUMP:
		return
	_overhead_jump_count = 0
	_set_phase(FollowPhase.IDLE)
	_release_follow()


func _is_hard_interrupted() -> bool:
	if drag_component != null and drag_component.dragging:
		return true
	if context_menu != null and context_menu.manual_override_active:
		return true
	var state := state_machine.get_state()
	if state == PetState.State.DRAG:
		return true
	## A fall/land not owned by the follow jump is physics ground truth.
	if state in [PetState.State.FALL, PetState.State.LAND]:
		return true
	## A jump submitted by another system also owns its arc.
	if state == PetState.State.JUMP and not _jump_attempt_pending:
		return true
	return false


func _is_soft_interrupted() -> bool:
	return behavior_controller != null and behavior_controller.is_signature_move_playing()


func _must_abort_jump() -> bool:
	if drag_component != null and drag_component.dragging:
		return true
	if context_menu != null and context_menu.manual_override_active:
		return true
	if behavior_controller != null and behavior_controller.is_signature_move_playing():
		return true
	if state_machine.get_state() == PetState.State.DEEP_SLEEP:
		return true
	return false


func _update_facing(cursor: Vector2) -> void:
	var dx := cursor.x - pet.world_position.x
	var deadband := settings.heading_deadband
	if polish_component != null:
		deadband = maxf(deadband, polish_component.get_follow_cursor_deadzone())
	if absf(dx) > deadband:
		movement_component.direction = 1 if dx > 0.0 else -1


func _horizontal_distance(cursor: Vector2) -> float:
	var target := awareness.clamp_to_safe_area(cursor)
	return absf(target.x - pet.world_position.x)


func _cursor_inside_radius() -> bool:
	if awareness == null:
		return false
	return pet.world_position.distance_to(awareness.cursor_position()) <= settings.detection_radius


func _velocity_for_height(height: float) -> float:
	var gravity := maxf(pet.definition.gravity, 1.0)
	return sqrt(2.0 * gravity * maxf(height, 0.0))


func _set_phase(next_phase: FollowPhase) -> void:
	_phase = next_phase


## Takes over movement steering: locks the brain out (so it can't fight the
## chase) and flips the MovementComponent override. Idempotent per frame.
func _engage_follow() -> void:
	if movement_component.following_cursor:
		return
	movement_component.set_following_cursor(true)
	if behavior_controller != null:
		behavior_controller.autonomy_locked = true


## Hands control back to natural life: releases the autonomy lock and the
## MovementComponent override, settles a leftover walk to idle, and asks the
## brain to reconsider. Does not touch the follow phase or jump flags.
func _release_follow(kick_behavior: bool = true) -> void:
	if movement_component == null:
		return
	var was_following := movement_component.following_cursor
	if was_following:
		movement_component.set_following_cursor(false)
	if behavior_controller != null:
		behavior_controller.autonomy_locked = false
	if state_machine.get_state() == PetState.State.WALK or state_machine.get_state() == PetState.State.RUN:
		state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
	if kick_behavior and was_following and behavior_controller != null:
		behavior_controller.kick_decision()


func _cancel_jump_attempt() -> void:
	_jump_attempt_pending = false
	_follow_jump_active = false
	_jump_launched = false
	_jump_launch_wait_left = 0.0
	if physics != null:
		physics.cancel_pending_jump()
	## A JUMP state that never became a physics arc must not leave the pet
	## stuck in a jump animation. Never override an active drag/special.
	if state_machine.get_state() == PetState.State.JUMP \
			and (physics == null or not physics.is_jumping) \
			and (drag_component == null or not drag_component.dragging) \
			and (context_menu == null or not context_menu.manual_override_active) \
			and (behavior_controller == null or not behavior_controller.is_signature_move_playing()):
		state_machine.force_state(PetState.State.IDLE)


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	var cursor_distance := 0.0
	if awareness != null:
		cursor_distance = pet.world_position.distance_to(awareness.cursor_position())
	return {
		"enabled": follow_enabled,
		"engaged": movement_component != null and movement_component.following_cursor,
		"phase": get_phase_name(),
		"resting": _phase == FollowPhase.RESTING,
		"cursor_distance": cursor_distance,
		"inside_radius": cursor_distance <= settings.detection_radius,
		"jump_attempt_pending": _jump_attempt_pending,
		"jump_launched": _jump_launched,
		"follow_jump_active": _follow_jump_active,
		"overhead_jumps_used": _overhead_jump_count,
		"jump_height": settings.jump_height,
		"jump_cooldown_left": 0.0,
	}
