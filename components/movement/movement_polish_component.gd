extends "res://core/base/pet_component.gd"
class_name MovementPolishComponent

const DefaultMovementPolishSettings := preload("res://data/configs/movement_polish_settings.tres")

## Makes the pet move with weight and intention. MovementComponent stays the
## sole executor of pet.velocity.x and NaturalGait the gait planner; this
## component only PROVIDES the tuning and transient state those systems layer
## on top (same contract as BehaviorPolishComponent / PersonalityComponent):
##   - Motion smoothing: walk/run acceleration & deceleration profiles.
##   - Turn smoothing: gentle turn deceleration + flowing edge turns.
##   - Arrival smoothing: speed ramp tuned by arrival distance/radius/settle.
##   - Edge smoothing: cruise speed ramps down near a screen edge (asked of
##     DesktopAwarenessComponent, never hardcoded).
##   - Jump anticipation: brief pause before leaving the ground.
##   - Landing recovery: a beat after landing before resuming full speed.
##   - Follow-cursor smoothing: facing deadzone + stop/start hysteresis.
## It never moves the pet, never changes states and never picks behaviors.

## Emitted when a jump anticipation pause finishes - the jump owner (Follow
## Cursor) may then actually launch.
signal jump_anticipation_finished

## Emitted when the post-landing recovery beat ends.
signal landing_recovery_finished

var settings: MovementPolishSettings

var movement_component: MovementComponent
var awareness: DesktopAwarenessComponent
var state_machine: StateMachineComponent
var follow_component: FollowCursorComponent

## Last WALK/RUN state seen, so acceleration profiles stay consistent while a
## jump (which has its own state) keeps the momentum of what it was doing.
var _last_move_state: int = PetState.State.WALK

var _jump_anticipation_left := 0.0
var _landing_recovery_left := 0.0


func on_initialized() -> void:
	movement_component = pet.get_component(MovementComponent)
	awareness = pet.get_component(DesktopAwarenessComponent)
	state_machine = pet.get_component(StateMachineComponent)
	follow_component = pet.get_component(FollowCursorComponent)
	settings = pet.definition.movement_polish_settings if pet.definition.movement_polish_settings != null else DefaultMovementPolishSettings
	if state_machine != null:
		EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)
	LoggerGlobal.info("MovementPolishComponent initialized.")


## Public retune seam: future settings screens can swap the movement polish
## tuning resource without any code change.
func set_settings(new_settings: MovementPolishSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings


## Safe before on_initialized has run (MovementComponent queries profiles
## during its own initialization).
func _effective_settings() -> MovementPolishSettings:
	return settings if settings != null else DefaultMovementPolishSettings


func _physics_process(delta: float) -> void:
	if pet == null or not enabled:
		return
	_tick_jump_anticipation(delta)
	_tick_landing_recovery(delta)


## --- Acceleration / deceleration profiles -----------------------------------

## Acceleration (px/s^2) for the given state. JUMP (and any non-walk state)
## inherits the profile of the last WALK/RUN the pet was doing.
func get_acceleration(state: int) -> float:
	var active := _effective_settings()
	match state:
		PetState.State.RUN:
			return active.run_acceleration
		PetState.State.WALK:
			return active.walk_acceleration
		_:
			return active.run_acceleration if _last_move_state == PetState.State.RUN else active.walk_acceleration


## Deceleration (px/s^2) for the given state; same inheritance rule.
func get_deceleration(state: int) -> float:
	var active := _effective_settings()
	match state:
		PetState.State.RUN:
			return active.run_deceleration
		PetState.State.WALK:
			return active.walk_deceleration
		_:
			return active.run_deceleration if _last_move_state == PetState.State.RUN else active.walk_deceleration


## Gentler acceleration right after a landing, so the pet collects itself
## before resuming speed instead of bolting.
func get_recovery_acceleration() -> float:
	return _effective_settings().landing_recovery_acceleration


## --- Turn smoothing ---------------------------------------------------------

func get_turn_deceleration() -> float:
	return _effective_settings().turn_deceleration


func get_max_turn_speed() -> float:
	return _effective_settings().max_turn_speed


## --- Arrival smoothing ------------------------------------------------------

func get_arrival_slowdown_distance() -> float:
	return _effective_settings().arrival_slowdown_distance


func get_arrival_deceleration() -> float:
	return _effective_settings().arrival_deceleration


func get_arrival_radius() -> float:
	return _effective_settings().arrival_radius


func get_arrival_settle_delay() -> float:
	return _effective_settings().arrival_settle_delay


## --- Edge behavior ----------------------------------------------------------

## Scales the cruise speed as the pet nears the edge it is heading toward:
## 1.0 far away, ramping down to edge_slowdown_min_speed at the edge, so the
## pet slows naturally instead of stopping abruptly (respects
## DesktopAwarenessComponent for edge distances).
func get_edge_slowdown_factor() -> float:
	if awareness == null:
		return 1.0
	var active := _effective_settings()
	if active.edge_slowdown_distance <= 0.0:
		return 1.0
	var distance_to_edge: float
	if movement_component.direction > 0:
		distance_to_edge = awareness.get_distance_to_right_edge()
	else:
		distance_to_edge = awareness.get_distance_to_left_edge()
	var closeness := clampf(1.0 - distance_to_edge / active.edge_slowdown_distance, 0.0, 1.0)
	if closeness <= 0.0:
		return 1.0
	return lerpf(1.0, active.edge_slowdown_min_speed, closeness)


## --- Jump anticipation ------------------------------------------------------

func get_jump_anticipation_time() -> float:
	return _effective_settings().jump_anticipation_time


## Starts the anticipation pause. Returns true when the caller should HOLD
## (the jump_anticipation_finished signal will fire later); false when no
## anticipation is configured and the jump may launch immediately.
func begin_jump_anticipation() -> bool:
	if _effective_settings().jump_anticipation_time <= 0.0:
		return false
	if _jump_anticipation_left <= 0.0:
		_jump_anticipation_left = _effective_settings().jump_anticipation_time
	return true


func cancel_jump_anticipation() -> void:
	_jump_anticipation_left = 0.0


func is_jump_anticipation_active() -> bool:
	return _jump_anticipation_left > 0.0


func get_jump_anticipation_left() -> float:
	return _jump_anticipation_left


## --- Landing recovery -------------------------------------------------------

func get_landing_recovery_time() -> float:
	return _effective_settings().landing_recovery_time


func is_landing_recovering() -> bool:
	return _landing_recovery_left > 0.0


func get_landing_recovery_left() -> float:
	return _landing_recovery_left


## --- Follow cursor smoothing ------------------------------------------------

func get_follow_cursor_deadzone() -> float:
	return _effective_settings().follow_cursor_deadzone


func get_follow_cursor_hysteresis() -> float:
	return _effective_settings().follow_cursor_hysteresis


## --- Internals --------------------------------------------------------------

func _on_state_changed_event(payload: Dictionary) -> void:
	var previous: PetState.State = payload.get("previous_state", PetState.State.IDLE)
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	if new_state == PetState.State.WALK or new_state == PetState.State.RUN:
		_last_move_state = new_state
	## A jump landing settles straight to IDLE (physics), a real drop lands in
	## LAND. Both start the recovery beat before the pet resumes full speed.
	if new_state == PetState.State.LAND:
		_start_landing_recovery()
	elif previous == PetState.State.JUMP and new_state == PetState.State.IDLE:
		_start_landing_recovery()


func _start_landing_recovery() -> void:
	_landing_recovery_left = _effective_settings().landing_recovery_time


func _tick_jump_anticipation(delta: float) -> void:
	if _jump_anticipation_left <= 0.0:
		return
	_jump_anticipation_left -= delta
	if _jump_anticipation_left <= 0.0:
		_jump_anticipation_left = 0.0
		jump_anticipation_finished.emit()


func _tick_landing_recovery(delta: float) -> void:
	if _landing_recovery_left <= 0.0:
		return
	_landing_recovery_left -= delta
	if _landing_recovery_left <= 0.0:
		_landing_recovery_left = 0.0
		landing_recovery_finished.emit()


## --- Debug support ----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var phase_name := ""
	if movement_component != null and movement_component.gait != null:
		phase_name = NaturalGait.Phase.keys()[movement_component.gait.phase]
	var state := state_machine.get_state() if state_machine != null else PetState.State.IDLE
	var jump_cooldown := 0.0
	if follow_component != null:
		jump_cooldown = float(follow_component.get_debug_info().get("jump_cooldown_left", 0.0))
	var target_speed := 0.0
	if movement_component != null and movement_component.gait != null:
		target_speed = movement_component.gait.cruise_speed
	return {
		"current_speed": movement_component.get_current_speed() if movement_component != null else 0.0,
		"target_speed": target_speed,
		"acceleration": get_acceleration(state),
		"deceleration": get_deceleration(state),
		"arrival_radius": get_arrival_radius(),
		"arrival_slowdown_distance": get_arrival_slowdown_distance(),
		"turn_state": movement_component.get_acceleration_state() if movement_component != null else "stopped",
		"movement_phase": phase_name,
		"edge_slowdown_factor": get_edge_slowdown_factor(),
		"jump_anticipation_left": _jump_anticipation_left,
		"jump_cooldown": jump_cooldown,
		"landing_recovery_left": _landing_recovery_left,
		"landing_recovery_time": get_landing_recovery_time(),
		"follow_deadzone": get_follow_cursor_deadzone(),
		"follow_hysteresis": get_follow_cursor_hysteresis(),
	}
