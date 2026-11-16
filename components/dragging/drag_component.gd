extends "res://core/base/pet_component.gd"
class_name DragComponent

## Dragging works on hold: a left press that stays still (or is released
## quickly) is a poke/click, while holding past a short window or moving
## the mouse turns into a drag. Clicks are reported through EventBus
## (PET_CLICKED), so InteractionComponent reacts to pokes without a drag.

const CLICK_HOLD_SECONDS := 0.18
const DRAG_SLOP_PIXELS := 8.0

var state_machine: StateMachineComponent
var dragging: bool = false
var drag_offset: Vector2

var _left_pressed := false
var _press_started_ms := 0
var _press_position := Vector2.ZERO


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	pet.interaction_area.input_event.connect(_on_input_event)


func _process(_delta: float) -> void:
	if not _left_pressed:
		return

	var now_ms := Time.get_ticks_msec()
	var elapsed := float(now_ms - _press_started_ms) / 1000.0
	var moved := Vector2(DisplayServer.mouse_get_position()).distance_to(_press_position)

	if not dragging and (elapsed > CLICK_HOLD_SECONDS or moved > DRAG_SLOP_PIXELS):
		dragging = true
		drag_offset = Vector2(DisplayServer.mouse_get_position()) - pet.world_position
		EventBus.emit(EventBus.PET_DRAGGED)

	if not dragging:
		return

	state_machine.request_state(PetState.State.DRAG, StatePriority.Level.HIGH)
	var new_position := Vector2(DisplayServer.mouse_get_position()) - drag_offset
	pet.world_position = pet.clamp_world_position_to_screen(new_position)
	pet.velocity = Vector2.ZERO


func _on_input_event(
	_viewport,
	event: InputEvent,
	_shape_idx
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_left_pressed = true
				dragging = false
				_press_started_ms = Time.get_ticks_msec()
				_press_position = Vector2(DisplayServer.mouse_get_position())
			else:
				_left_pressed = false
				var was_drag := dragging
				dragging = false
				if was_drag:
					pet.world_position = pet.clamp_world_position_to_screen(pet.world_position)
					state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
					EventBus.emit(EventBus.PET_RELEASED)
				else:
					EventBus.emit(EventBus.PET_CLICKED)
