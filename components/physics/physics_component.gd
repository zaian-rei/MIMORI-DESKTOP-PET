extends "res://core/base/pet_component.gd"
class_name PhysicsComponent

const ScreenService := preload("res://services/screen/screen_service.gd")

## Grounded tolerance. The floor can shift by a few hundredths of a pixel
## between animation frames (the sprite's opaque bottom edge changes), so an
## exact `y >= floor` test can report airborne while the pet is visually on the
## ground - which used to swallow jump launches. Matches the awareness
## component's tolerance.
const GROUND_EPSILON := 0.5

## True once the pet left the ground for a jump (or real drop) and is still in
## the air, updated every physics tick so dependents (e.g. FollowCursor) can
## gate actions on the physics-authoritative airborne state instead of the
## render-tick state machine (which lags the physics by up to a frame and caused
## premature give-up evaluation / repeat jumps).
signal jump_launched()

## Emitted the physics frame a self-owned jump arc (a hop, not a drop) lands.
## Used to resolve the follow-cursor give-up exactly once, physics-authoritatively,
## rather than polling a lagging state machine.
signal jump_landed()

var drag_component: DragComponent
var state_machine: StateMachineComponent
var awareness: DesktopAwarenessComponent
var was_on_floor := false

var _jump_pending := false
## Physics-authoritative: true from the launch frame through the landing frame
## of a jump arc. (Drops/falls do NOT set this - only a launched hop.)
var is_jumping := false

## Optional one-shot launch velocity for a cursor-follow jump. The follow
## component derives it from its configurable jump_height and the pet's
## gravity, so the same setting produces the requested peak for every pet.
var _follow_jump_velocity := 0.0

func on_initialized() -> void:
	drag_component = pet.get_component(DragComponent)
	state_machine = pet.get_component(StateMachineComponent)
	awareness = pet.get_component(DesktopAwarenessComponent)
	EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)


func _on_state_changed_event(payload: Dictionary) -> void:
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	# A STATE_CHANGED to JUMP is the state machine's request to launch. The
	# actual launch happens on the next physics frame (if grounded), but we
	# record the request here - it's the single gate for starting an arc.
	_jump_pending = new_state == PetState.State.JUMP


## Called after a visual size or identity change. Keep the visible feet on the
## desktop floor even when the old anchor was airborne or below the new floor.
func snap_to_ground() -> void:
	if awareness == null or drag_component.dragging:
		return
	pet.world_position.y = awareness.floor_position()
	pet.velocity.y = 0.0
	is_jumping = false
	_jump_pending = false
	_follow_jump_velocity = 0.0
	was_on_floor = true
	if state_machine.get_state() in [PetState.State.JUMP, PetState.State.FALL, PetState.State.LAND]:
		state_machine.force_state(PetState.State.IDLE)


## Arms a follow jump with an explicit upward launch velocity (px/s). The
## override is consumed by the next grounded launch and then cleared.
func set_follow_jump_velocity(velocity: float) -> void:
	_follow_jump_velocity = maxf(velocity, 0.0)


func clear_follow_jump_velocity() -> void:
	_follow_jump_velocity = 0.0


## Drops a jump request that has not launched yet. Used when a follow attempt
## is cancelled by a drag, manual animation or special move.
func cancel_pending_jump() -> void:
	_jump_pending = false
	_follow_jump_velocity = 0.0


func _physics_process(delta: float) -> void:
	if pet == null:
		return

	## Follow the pet onto whichever monitor it is currently on so the
	## floor always matches the active screen (also during a drag, so the
	## pet can be dropped on another display).
	ScreenService.update_pet_bounds(pet)

	if drag_component.dragging:
		return

	var floor_y := awareness.floor_position()

	var on_floor := pet.world_position.y >= floor_y - GROUND_EPSILON
	var launched := false

	if _jump_pending:
		_jump_pending = false
		if on_floor:
			var launch_speed := pet.definition.jump_speed * 1.5
			if _follow_jump_velocity > 0.0:
				launch_speed = _follow_jump_velocity
			_follow_jump_velocity = 0.0
			pet.velocity.y = -launch_speed
			launched = true
			is_jumping = true
			jump_launched.emit()
		else:
			## A jump requested mid-air is discarded, including its follow
			## velocity, so it cannot leak into a later launch.
			_follow_jump_velocity = 0.0

	if launched:
		pet.world_position += pet.velocity * delta
		_clamp_horizontal_position()
		was_on_floor = false
		return

	if on_floor:
		pet.world_position.y = floor_y
		pet.velocity.y = 0.0
		pet.world_position.x += pet.velocity.x * delta
		_clamp_horizontal_position()
		if not was_on_floor:
			if is_jumping:
				is_jumping = false
				jump_landed.emit()
				## A follow jump shows the jump clip for the whole arc and
				## settles straight into idle - no FALL/LAND animations.
				state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
			else:
				state_machine.request_state(PetState.State.LAND, StatePriority.Level.NORMAL)
		was_on_floor = true
		return

	pet.velocity.y += pet.definition.gravity * delta
	pet.world_position += pet.velocity * delta
	_clamp_horizontal_position()
	if pet.world_position.y >= floor_y:
		pet.world_position.y = floor_y
		pet.velocity.y = 0.0
		if is_jumping:
			is_jumping = false
			jump_landed.emit()
			## Keep the jump animation through the landing frame and go
			## directly to idle instead of playing FALL/LAND.
			state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
		elif not was_on_floor:
			state_machine.request_state(PetState.State.LAND, StatePriority.Level.NORMAL)
		was_on_floor = true
	else:
		was_on_floor = false
		## While a launched jump owns the arc, hold the JUMP state/clip for
		## both the ascent and the descent. Only real drops use FALL.
		if not is_jumping and pet.velocity.y > 0.0 and state_machine.get_state() != PetState.State.FALL:
			# Drops descend through the FALL animation.
			state_machine.request_state(PetState.State.FALL, StatePriority.Level.NORMAL)


func _clamp_horizontal_position() -> void:
	if awareness == null:
		return
	var clamped_x := awareness.clamp_pet_x_to_safe_area(pet.world_position.x)
	if is_equal_approx(clamped_x, pet.world_position.x):
		return
	var moving_outward := (clamped_x < pet.world_position.x and pet.velocity.x > 0.0) or (clamped_x > pet.world_position.x and pet.velocity.x < 0.0)
	pet.world_position.x = clamped_x
	if moving_outward:
		pet.velocity.x = 0.0
