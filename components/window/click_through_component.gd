extends "res://core/base/pet_component.gd"
class_name ClickThroughComponent


func on_initialized() -> void:
	if pet.click_polygon == null:
		return
	set_process(true)


## The passthrough region must match where the pet's body actually renders.
## The pet is only centered in its window AFTER components initialize
## (bootstrap -> DesktopWindow.track -> center_in_window), so computing this
## once in on_initialized would put the region off by the window center and
## let every real click pass through the window. Recompute each frame (cheap)
## and only push to the OS when the region changes (re-centering, resize,
## scale changes).
func _process(_delta: float) -> void:
	_apply_passthrough()


var _last_region := PackedVector2Array()
var _last_scale_factor := -1.0
var _last_pet_position := Vector2.INF
var _last_window_size := Vector2i.ZERO
var click_through := false
var _applied_click_through := false


func set_click_through(enabled: bool) -> void:
	click_through = enabled
	_last_region = PackedVector2Array()
	_last_scale_factor = -1.0
	_last_pet_position = Vector2.INF
	_last_window_size = Vector2i.ZERO
	_apply_passthrough()


func _apply_passthrough() -> void:
	if pet.click_polygon == null:
		return
	if click_through:
		if not _applied_click_through:
			DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
			_applied_click_through = true
		return
	_applied_click_through = false
	var scale_factor := pet.get_scale_factor()
	var window_size := DisplayServer.window_get_size()
	if is_equal_approx(scale_factor, _last_scale_factor) and pet.position == _last_pet_position and window_size == _last_window_size:
		return
	var region := PackedVector2Array()
	for point in pet.click_polygon.polygon:
		region.append(pet.click_polygon.to_global(point * scale_factor))
	if region == _last_region:
		_last_scale_factor = scale_factor
		_last_pet_position = pet.position
		_last_window_size = window_size
		return
	_last_region = region
	_last_scale_factor = scale_factor
	_last_pet_position = pet.position
	_last_window_size = window_size
	DisplayServer.window_set_mouse_passthrough(region)
