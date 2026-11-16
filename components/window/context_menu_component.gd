extends "res://core/base/pet_component.gd"
class_name ContextMenuComponent

const SettingsWindowScene := preload("res://scenes/ui/settings_window.tscn")


const MANUAL_ITERATIONS := {
	PetState.State.IDLE: 2,
	PetState.State.WALK: 2,
	PetState.State.RUN: 2,
	PetState.State.JUMP: 1,
	PetState.State.SLEEP: 2,
	PetState.State.DEEP_SLEEP: 2,
	PetState.State.DANCE: 3,
	PetState.State.HAPPY: 3,
	PetState.State.THINK: 3,
}

var manual_override_active: bool = false
var manual_state: PetState.State = PetState.State.IDLE

var state_machine: StateMachineComponent
var _settings_window: SettingsWindow

var _manual_loops := 0
var _manual_iterations := 2
var _manual_first_frame := true

func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	pet.interaction_area.input_event.connect(_on_input_event)
	pet.sprite.frame_changed.connect(_on_sprite_frame_changed)
	EventBus.settings_requested.connect(_open_settings)


func _on_input_event(_viewport, event: InputEvent, _shape_idx) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT and mouse_event.pressed:
			_open_settings()


func _process(_delta: float) -> void:
	if not manual_override_active:
		return
	## Manual menu actions are explicit user commands: they bypass the shared
	## transition graph (the documented exception) so the chosen clip always
	## plays exactly, even from a non-idle state.
	state_machine.request_state(manual_state, StatePriority.Level.HIGH, true)

func _on_sprite_frame_changed() -> void:
	if not manual_override_active:
		return
	if _manual_first_frame:
		_manual_first_frame = false
		return
	if pet.sprite.frame == 0:
		_manual_loops += 1
		if _manual_loops >= _manual_iterations:
			_stop_manual()


func play_action(state: PetState.State) -> void:
	manual_override_active = true
	manual_state = state
	_manual_loops = 0
	_manual_first_frame = true
	_manual_iterations = MANUAL_ITERATIONS.get(state, 2)


## Ends the manual animation: the pet returns to idle and the autonomous
## brain is asked to pick its next behavior right away. force_state clears
## any stale pending request so the release can't be swallowed.
func _stop_manual() -> void:
	manual_override_active = false
	_manual_loops = 0
	state_machine.force_state(PetState.State.IDLE)
	var behavior_controller := pet.get_component(BehaviorController) as BehaviorController
	if behavior_controller != null:
		behavior_controller.kick_decision()


func open_first_run_picker() -> void:
	_open_settings(true)


func _open_settings(show_pet_picker: bool = false) -> void:
	if _settings_window == null:
		_settings_window = SettingsWindowScene.instantiate()
		get_tree().root.add_child(_settings_window)
		_settings_window.setup(pet, pet.desktop_window)

	_position_settings_near_pet()
	if show_pet_picker:
		_settings_window.open_pet_picker()
	else:
		_settings_window.open_control_center()
	_settings_window.grab_focus()


func is_settings_open() -> bool:
	return _settings_window != null and _settings_window.visible


func _position_settings_near_pet() -> void:
	var screen_index := 0
	for i in range(DisplayServer.get_screen_count()):
		var candidate_rect := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if candidate_rect.has_point(Vector2i(pet.world_position)):
			screen_index = i
			break
	var screen_rect := Rect2i(DisplayServer.screen_get_position(screen_index), DisplayServer.screen_get_size(screen_index))
	var usable := pet.screen_bounds
	if usable.size.x <= 0 or usable.size.y <= 0 or not screen_rect.intersects(usable):
		usable = DisplayServer.screen_get_usable_rect(screen_index)
	var settings_size := SettingsWindow.panel_size_for_screen(usable)
	var pet_window_rect := pet.desktop_window.get_window_rect() if pet.desktop_window != null else Rect2i(Vector2i(pet.world_position) - Vector2i(250, 250), Vector2i(500, 500))
	var gap := 16

	var target := Vector2i(
		int(pet.world_position.x) - settings_size.x / 2,
		int(pet_window_rect.position.y) - settings_size.y - gap
	)

	target.x = clampi(target.x, usable.position.x, usable.position.x + usable.size.x - settings_size.x)
	target.y = clampi(target.y, usable.position.y, usable.position.y + usable.size.y - settings_size.y)

	var panel_rect := Rect2i(target - screen_rect.position, settings_size)
	_settings_window.configure_screen_host(screen_rect, panel_rect)
