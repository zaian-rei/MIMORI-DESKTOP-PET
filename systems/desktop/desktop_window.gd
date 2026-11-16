extends Node
class_name DesktopWindow

## The window's size is derived from the pet's rendered size - the largest
## sprite frame across every animation, scaled by the pet's current scale,
## plus a safety padding. There is no fixed window size: pets and themes
## with different art automatically get a correctly-fitting window, and
## changing the pet scale resizes the window immediately.
const WINDOW_PADDING := 16.0
const MIN_WINDOW_SIZE := 128
const MAX_WINDOW_SIZE := 5120

const ALWAYS_ON_TOP_REASSERT_INTERVAL_SECONDS := 0.5
const POSITION_AUTOSAVE_INTERVAL_SECONDS := 15.0
const POSITION_AUTOSAVE_THRESHOLD := 24.0
const ACTIVE_MAX_FPS := 30
const RESTING_MAX_FPS := 15
const ACTIVE_PHYSICS_TICKS := 60
const RESTING_PHYSICS_TICKS := 30
const ScreenService := preload("res://services/screen/screen_service.gd")

var tracked_pet: Pet
var _last_saved_position := Vector2.INF


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and tracked_pet != null:
		ConfigService.save_data(tracked_pet.world_position)


func configure_small_window() -> void:
	var window := get_window()
	window.borderless = true
	window.always_on_top = ConfigService.always_on_top
	window.transparent = true
	window.unresizable = true

	_start_always_on_top_watchdog()


## The engine's Window class has no opacity property in this build, so pet
## transparency is applied to the sprite node's modulate alpha (the window
## itself is transparent, which yields the same visual result).
func apply_window_opacity(value: float) -> void:
	var clamped := clampf(value, 0.35, 1.0)
	ConfigService.window_opacity = clamped
	if tracked_pet != null and tracked_pet.visual != null:
		tracked_pet.visual.modulate.a = clamped


func track(pet: Pet) -> void:
	tracked_pet = pet
	_last_saved_position = pet.world_position
	_start_position_autosave()
	_follow_pet()


func apply_always_on_top(value: bool) -> void:
	ConfigService.always_on_top = value
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, value)


func _process(_delta: float) -> void:
	_update_power_profile()
	_follow_pet()


## Most of the time the pet is resting and its sprite animates at 8 FPS.
## Match the engine budget to that state, then restore the smoother budget for
## walking, jumping, dragging, and settings interactions.
func _update_power_profile() -> void:
	if tracked_pet == null:
		return
	var state_machine := tracked_pet.get_component(StateMachineComponent) as StateMachineComponent
	var state := state_machine.get_state() if state_machine != null else PetState.State.IDLE
	var drag := tracked_pet.get_component(DragComponent) as DragComponent
	var context := tracked_pet.get_component(ContextMenuComponent) as ContextMenuComponent
	var active := (
		state in [PetState.State.WALK, PetState.State.RUN, PetState.State.JUMP, PetState.State.FALL, PetState.State.LAND, PetState.State.DRAG]
		or (drag != null and drag.dragging)
		or (context != null and context.is_settings_open())
		or absf(tracked_pet.velocity.x) > 1.0
		or absf(tracked_pet.velocity.y) > 1.0
	)
	var target_fps := ACTIVE_MAX_FPS if active else RESTING_MAX_FPS
	var target_physics_ticks := ACTIVE_PHYSICS_TICKS if active else RESTING_PHYSICS_TICKS
	if Engine.max_fps != target_fps:
		Engine.max_fps = target_fps
	if Engine.physics_ticks_per_second != target_physics_ticks:
		Engine.physics_ticks_per_second = target_physics_ticks


func _follow_pet() -> void:
	if tracked_pet == null:
		return

	_update_window_size()
	var window := get_window()
	var next_position := Vector2i(tracked_pet.world_position) - window.size / 2
	var screen_rect := tracked_pet.screen_bounds
	if screen_rect == Rect2i():
		screen_rect = ScreenService.usable_rect_containing(tracked_pet.world_position)
	## Keep the transparent host window inside the active desktop horizontally.
	## Physics also clamps the visible sprite footprint; this is a final guard
	## against the operating-system window itself sliding off a screen edge.
	if screen_rect != Rect2i() and window.size.x <= screen_rect.size.x:
		var max_x := screen_rect.position.x + screen_rect.size.x - window.size.x
		var clamped_x := clampi(next_position.x, screen_rect.position.x, max_x)
		if clamped_x != next_position.x:
			next_position.x = clamped_x
			tracked_pet.world_position.x = float(clamped_x + window.size.x / 2)
	## Desktop window managers constrain ordinary windows to the usable work
	## area at the taskbar/panel. Keep the pet window inside that area too, then
	## place the pet node at its true desktop coordinate within the window. Near
	## the floor this shifts the transparent window padding above the pet rather
	## than allowing the OS to push the visible feet upward.
	if screen_rect != Rect2i() and window.size.y <= screen_rect.size.y:
		var max_y := screen_rect.position.y + screen_rect.size.y - window.size.y
		next_position.y = mini(next_position.y, max_y)
	## Setting the native window position every frame is expensive on Windows
	## and Linux compositors, even when the pet is idle. Skip the OS call unless
	## its actual position needs to change.
	if window.position != next_position:
		window.position = next_position
	var actual_position := Vector2(window.position)
	var local_pet_position := tracked_pet.world_position - actual_position
	if tracked_pet.position != local_pet_position:
		tracked_pet.position = local_pet_position


## Recomputes the window size from the pet's current rendered footprint.
## Runs every frame (cheap: the sprite-frame scan is cached by Godot and the
## result only changes when art or scale changes) so a scale slider or theme
## swap resizes the window instantly.
func _update_window_size() -> void:
	var rendered := tracked_pet.get_rendered_size()
	var target := Vector2i(
		int(rendered.x + WINDOW_PADDING * 2.0),
		int(rendered.y + WINDOW_PADDING * 2.0)
	)
	target.x = clampi(target.x, MIN_WINDOW_SIZE, MAX_WINDOW_SIZE)
	target.y = clampi(target.y, MIN_WINDOW_SIZE, MAX_WINDOW_SIZE)
	if target != get_window().size:
		get_window().size = target


## The OS window is centered on the pet's world position; this is the full
## window footprint in absolute desktop coordinates.
func get_window_rect() -> Rect2i:
	if tracked_pet == null:
		return Rect2i()
	var size := get_window().size
	return Rect2i(Vector2i(tracked_pet.world_position) - size / 2, size)


func _start_position_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = POSITION_AUTOSAVE_INTERVAL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_autosave_position)
	add_child(timer)


func _autosave_position() -> void:
	if tracked_pet == null:
		return
	if tracked_pet.world_position.distance_to(_last_saved_position) < POSITION_AUTOSAVE_THRESHOLD:
		return
	_last_saved_position = tracked_pet.world_position
	ConfigService.save_data(tracked_pet.world_position)


func _start_always_on_top_watchdog() -> void:
	var timer := Timer.new()
	timer.wait_time = ALWAYS_ON_TOP_REASSERT_INTERVAL_SECONDS
	timer.autostart = true
	timer.timeout.connect(_reassert_always_on_top)
	add_child(timer)


func _reassert_always_on_top() -> void:
	if not ConfigService.always_on_top:
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
