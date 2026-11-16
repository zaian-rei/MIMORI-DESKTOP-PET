extends "res://core/base/pet_component.gd"
class_name MovementComponent

const ScreenService := preload("res://services/screen/screen_service.gd")
const DefaultMovementSettings := preload("res://data/configs/movement_settings.tres")


var direction: int = 1

var state_machine: StateMachineComponent
var drag_component: DragComponent
var context_menu: ContextMenuComponent
var behavior_controller: BehaviorController
var personality_component: PersonalityComponent
var polish_component: MovementPolishComponent

var settings: MovementSettings
var gait: NaturalGait

var following_cursor: bool = false

var _gait_active := false
var _walk_duration := 0.0
var _idle_duration := 0.0


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	drag_component = pet.get_component(DragComponent)
	context_menu = pet.get_component(ContextMenuComponent)
	behavior_controller = pet.get_component(BehaviorController)
	personality_component = pet.get_component(PersonalityComponent)
	polish_component = pet.get_component(MovementPolishComponent)
	settings = pet.definition.movement_settings if pet.definition.movement_settings != null else DefaultMovementSettings
	gait = NaturalGait.new(settings)
	LoggerGlobal.info("MovementComponent initialized.")


## Public retune seam: future settings screens can swap the gait tuning
## resource without any code change.
func set_settings(new_settings: MovementSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings
	gait.settings = new_settings


## Lets cursor-follow override natural movement. When following, walking is
## smooth and responsive; the leg/pause/hesitation behavior stands down.
func set_following_cursor(value: bool) -> void:
	following_cursor = value
	if value:
		_gait_active = false


func _physics_process(delta: float) -> void:
	if pet == null:
		return

	var current_state := state_machine.get_state()
	var profiles := _movement_profiles(current_state)

	## Manual WALK/RUN still move the pet (the menu plays the animation AND
	## walks); every other manual animation plays in place.
	if context_menu.manual_override_active:
		_gait_active = false
		if context_menu.manual_state == PetState.State.WALK:
			pet.velocity.x = gait.direct(direction, pet.definition.move_speed, delta, profiles)
		elif context_menu.manual_state == PetState.State.RUN:
			pet.velocity.x = gait.direct(
				direction, pet.definition.move_speed * pet.definition.run_speed_multiplier, delta, profiles
			)
		else:
			pet.velocity.x = gait.stop(delta, profiles)
	elif drag_component.dragging:
		## A drag owns the pet's position entirely; movement stands down.
		_gait_active = false
		gait.hard_stop()
		pet.velocity.x = 0.0
	elif behavior_controller == null:
		_gait_active = false
		pet.velocity.x = gait.direct(direction, pet.definition.move_speed, delta, profiles)
		state_machine.request_state(PetState.State.WALK, StatePriority.Level.LOW)
	elif current_state == PetState.State.WALK or current_state == PetState.State.RUN:
		_run_walk_state(delta, current_state, profiles)
	elif current_state == PetState.State.JUMP or current_state == PetState.State.FALL:
		_gait_active = false
		var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
		if follow != null and follow.is_follow_jump_active():
			## Hold the horizontal momentum captured at launch. Driving the
			## walk gait here made the pet accelerate to walking speed in the
			## air, which read as "jumping while walking". A jump from a stop
			## is therefore a clean vertical hop.
			pass
		elif current_state == PetState.State.JUMP and not following_cursor:
			## A natural/manual hop can retain its heading and ease forward.
			pet.velocity.x = gait.direct(direction, pet.definition.move_speed, delta, profiles)
		else:
			pet.velocity.x = gait.stop(delta, profiles)
	else:
		## Not moving (idle/mood/sleep/land): ease any leftover speed to zero
		## so a walk ends with a natural glide instead of a snap.
		_gait_active = false
		pet.velocity.x = gait.stop(delta, profiles)

	pet.sprite.flip_h = direction < 0

	_tick_durations(delta, current_state)


## Movement Polish profiles for the current context. When no polish component
## is present an empty dict is passed and the gait behaves exactly as before.
func _movement_profiles(state: int) -> Dictionary:
	var p := polish_component
	if p == null:
		return {}
	var accel := p.get_recovery_acceleration() if p.is_landing_recovering() else p.get_acceleration(state)
	return {
		"accel": accel,
		"decel": p.get_deceleration(state),
		"turn_decel": p.get_turn_deceleration(),
		"max_turn_speed": p.get_max_turn_speed(),
		"arrival_slowdown_distance": p.get_arrival_slowdown_distance(),
		"arrival_decel": p.get_arrival_deceleration(),
		"arrival_radius": p.get_arrival_radius(),
		"arrival_settle_delay": p.get_arrival_settle_delay(),
	}


func _run_walk_state(delta: float, current_state: int, profiles: Dictionary) -> void:
	var base_speed := pet.definition.move_speed
	if current_state == PetState.State.RUN:
		base_speed *= pet.definition.run_speed_multiplier

	## Cursor-follow steers the pet directly: responsive, no gait behavior.
	if following_cursor:
		_gait_active = false
		var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
		if follow != null:
			base_speed = follow.get_speed_for_state(current_state)
	if personality_component != null:
		base_speed *= personality_component.get_movement_speed_modifier()
	if following_cursor:
		pet.velocity.x = gait.direct(direction, base_speed, delta, profiles)
		return

	## Near a screen edge the cruise speed ramps down (Movement Polish), so
	## the pet slows naturally instead of stopping suddenly at the boundary.
	var edge_factor := 1.0
	if polish_component != null:
		edge_factor = polish_component.get_edge_slowdown_factor()
	base_speed *= edge_factor

	if not _gait_active:
		gait.start_walk(direction, base_speed)
	_gait_active = true

	pet.velocity.x = gait.update(delta, base_speed, _at_left_edge(), _at_right_edge(), profiles)
	direction = gait.direction


## Tracks how long the pet has been walking vs resting, for debug and for
## the natural pacing feel.
func _tick_durations(delta: float, current_state: int) -> void:
	var is_walking := (current_state == PetState.State.WALK or current_state == PetState.State.RUN) and not following_cursor
	if is_walking:
		_walk_duration += delta
		_idle_duration = 0.0
		return
	_walk_duration = 0.0
	if current_state == PetState.State.IDLE:
		_idle_duration += delta
	else:
		_idle_duration = 0.0


## True when the pet is up against a screen edge with nothing beyond it.
## The gait planner uses this to ease to a stop and turn instead of walking
## into the void; if another monitor is just past the boundary the pet keeps
## walking and crosses onto it (bounds follow via ScreenService). The pet's
## rendered half-width (not a fixed margin) is what must stay on-screen, so
## a scaled-up pet turns before its body would leave the desktop.
func _at_left_edge() -> bool:
	var awareness := pet.get_component(DesktopAwarenessComponent) as DesktopAwarenessComponent
	if awareness == null:
		return false
	var area := awareness.get_safe_walking_area()
	return area.size.x > 0.0 and pet.world_position.x <= area.position.x + 1.0


func _at_right_edge() -> bool:
	var awareness := pet.get_component(DesktopAwarenessComponent) as DesktopAwarenessComponent
	if awareness == null:
		return false
	var area := awareness.get_safe_walking_area()
	return area.size.x > 0.0 and pet.world_position.x >= area.position.x + area.size.x - 1.0


## --- Debug support ---------------------------------------------------------

## Current horizontal speed magnitude (px/s).
func get_current_speed() -> float:
	return gait.speed


## Distance left in the current leg (px).
func get_remaining_distance() -> float:
	return maxf(gait.leg_distance - gait.leg_traveled, 0.0)


## Where the current leg is heading to (absolute desktop coords). When the
## pet isn't walking this is its current position.
func get_current_destination() -> Vector2:
	if not _gait_active:
		return pet.world_position
	return Vector2(
		pet.world_position.x + gait.direction * get_remaining_distance(),
		pet.world_position.y
	)


## Seconds spent walking in the current WALK/RUN stretch.
func get_walk_duration() -> float:
	return _walk_duration


## Seconds spent idle in the current IDLE stretch.
func get_idle_duration() -> float:
	return _idle_duration


## What the gait is doing right now (accelerating/cruising/decelerating...).
func get_acceleration_state() -> String:
	match gait.phase:
		NaturalGait.Phase.MOVE:
			if absf(gait.speed - gait.cruise_speed) < 1.0:
				return "cruising"
			return "accelerating" if gait.speed < gait.cruise_speed else "decelerating"
		NaturalGait.Phase.DECEL:
			return "decelerating"
		NaturalGait.Phase.HESITATE:
			return "hesitating"
		NaturalGait.Phase.PAUSE:
			return "paused"
		NaturalGait.Phase.TURN:
			return "turning"
		_:
			return "stopped"


## High-level movement status for the debug overlay.
func get_movement_status() -> String:
	if drag_component.dragging:
		return "dragging"
	if context_menu.manual_override_active:
		return "manual"
	if following_cursor:
		return "following_cursor"
	var state := state_machine.get_state()
	if state == PetState.State.WALK or state == PetState.State.RUN:
		match gait.phase:
			NaturalGait.Phase.HESITATE:
				return "hesitating"
			NaturalGait.Phase.MOVE:
				return "walking"
			NaturalGait.Phase.DECEL:
				return "stopping"
			NaturalGait.Phase.PAUSE:
				return "pausing"
			NaturalGait.Phase.TURN:
				return "turning"
			_:
				return "walking"
	return "idle"


func get_debug_info() -> Dictionary:
	return {
		"status": get_movement_status(),
		"acceleration_state": get_acceleration_state(),
		"current_speed": get_current_speed(),
		"destination": get_current_destination(),
		"remaining_distance": get_remaining_distance(),
		"walk_duration": _walk_duration,
		"idle_duration": _idle_duration,
		"direction": direction,
	}
