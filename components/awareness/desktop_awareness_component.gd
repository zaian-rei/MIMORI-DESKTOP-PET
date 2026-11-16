extends "res://core/base/pet_component.gd"
class_name DesktopAwarenessComponent

## The pet's single source of truth for environmental information. Every
## future system that needs to know about the desktop, the cursor, the
## ground or screen edges should ask this component instead of querying
## DisplayServer directly.
##
## Responsibility is strict and narrow: collect desktop information, cache
## the per-frame cursor state, provide helper functions and emit environment
## signals. It NEVER moves the pet, chooses behaviors, changes states or
## plays animations. Movement/physics/interaction remain separate.
##
## Configuration lives in DesktopAwarenessSettings (res://data/configs/
## desktop_awareness_settings.tres by default) so all numbers are tunable
## without touching engine code.

const ScreenService := preload("res://services/screen/screen_service.gd")
const DefaultAwarenessSettings := preload("res://data/configs/desktop_awareness_settings.tres")

## Vertical tolerance for is_grounded(): anything within this distance of
## the floor counts as grounded (physics snaps the pet to the floor, so the
## value should match exactly; the epsilon just absorbs rounding).
const GROUND_EPSILON := 0.5

## Linux compositors can leave a small visible gap between the windowed pet
## and the bottom edge even when the usable-screen rectangle is correct.
## Small speed below which the cursor counts as stationary.
const CURSOR_STILL_EPSILON := 0.5

## --- Environment signals ---------------------------------------------------
## Emitted (deduplicated) when meaningful desktop information changes, so
## future systems react without polling every frame.

## The pet moved onto a different monitor (or all monitors vanished).
signal monitor_changed(previous_index: int, new_index: int)

## The usable desktop footprint (union of all monitors) changed size or
## position - e.g. a display was plugged in, unplugged or rearranged.
signal desktop_resized(bounds: Rect2i)

## The pet's OS window moved to a new desktop position.
signal window_moved(position: Vector2)

## The cursor crossed into interaction range of the pet.
signal cursor_entered_range(position: Vector2)

## The cursor crossed out of interaction range of the pet.
signal cursor_exited_range(position: Vector2)

## --- Test/simulation seam --------------------------------------------------
## When not INF, cursor tracking returns this instead of the real OS cursor
## so behavior can be exercised deterministically.
var cursor_override: Vector2 = Vector2.INF

var settings: DesktopAwarenessSettings

## --- Cached per-frame cursor state ----------------------------------------
var _cursor_position: Vector2 = Vector2.ZERO
var _cursor_direction: Vector2 = Vector2.ZERO
var _cursor_delta: Vector2 = Vector2.ZERO
var _cursor_speed: float = 0.0
var _cursor_in_range: bool = false

## --- Cached desktop state (refreshed on the configured interval) -----------
var _refresh_timer: float = 0.0
var _current_monitor_index: int = -1
var _desktop_bounds: Rect2i = Rect2i()
var _window_position: Vector2 = Vector2.ZERO


func on_initialized() -> void:
	settings = pet.definition.desktop_awareness_settings if pet.definition.desktop_awareness_settings != null else DefaultAwarenessSettings
	_cursor_position = _read_cursor_position()
	_refresh_timer = settings.refresh_interval
	_current_monitor_index = get_current_monitor()
	_desktop_bounds = _compute_desktop_bounds()
	_window_position = Vector2(DisplayServer.window_get_position())
	_cursor_in_range = pet.world_position.distance_to(_cursor_position) <= settings.cursor_interaction_radius
	LoggerGlobal.info("DesktopAwarenessComponent initialized.")


## Public retune seam: future settings screens can swap the awareness
## tuning resource without any code change.
func set_settings(new_settings: DesktopAwarenessSettings) -> void:
	if new_settings == null:
		return
	settings = new_settings


func _process(delta: float) -> void:
	if pet == null:
		return
	_tick_desktop_refresh(delta)
	_tick_cursor(delta)


## --- Desktop refresh -------------------------------------------------------

func _tick_desktop_refresh(delta: float) -> void:
	_refresh_timer += delta
	if _refresh_timer < settings.refresh_interval:
		return
	_refresh_timer = 0.0

	var monitor := get_current_monitor()
	if monitor != _current_monitor_index:
		var previous := _current_monitor_index
		_current_monitor_index = monitor
		monitor_changed.emit(previous, monitor)

	var bounds := _compute_desktop_bounds()
	if bounds != _desktop_bounds:
		_desktop_bounds = bounds
		desktop_resized.emit(bounds)

	var win_pos := Vector2(DisplayServer.window_get_position())
	if win_pos != _window_position:
		_window_position = win_pos
		window_moved.emit(win_pos)


## --- Cursor tracking -------------------------------------------------------

func _tick_cursor(delta: float) -> void:
	var current := _read_cursor_position()
	_cursor_delta = current - _cursor_position
	_cursor_position = current
	_cursor_speed = _cursor_delta.length() / maxf(delta, 0.001)
	if _cursor_delta.length() > CURSOR_STILL_EPSILON:
		_cursor_direction = _cursor_delta.normalized()
	else:
		_cursor_direction = Vector2.ZERO

	var in_range := pet.world_position.distance_to(_cursor_position) <= settings.cursor_interaction_radius
	if in_range == _cursor_in_range:
		return
	_cursor_in_range = in_range
	if in_range:
		cursor_entered_range.emit(_cursor_position)
	else:
		cursor_exited_range.emit(_cursor_position)


func _read_cursor_position() -> Vector2:
	if cursor_override != Vector2.INF:
		return cursor_override
	return Vector2(DisplayServer.mouse_get_position())


## --- Screen information ----------------------------------------------------

## Usable rect of the monitor the pet is currently on. Falls back to the
## monitor containing the pet's position if screen_bounds isn't set yet.
func get_screen_bounds() -> Rect2i:
	if pet.screen_bounds != Rect2i():
		return pet.screen_bounds
	return screen_bounds_for(pet.world_position)


## Usable rect of whichever monitor currently holds the pet.
func current_screen_bounds() -> Rect2i:
	return pet.screen_bounds


## Visible area of the current monitor (alias of get_screen_bounds()).
func get_visible_screen_area() -> Rect2i:
	return get_screen_bounds()


## Union of every monitor's usable rect - the full desktop footprint.
func get_desktop_bounds() -> Rect2i:
	return _desktop_bounds


func get_window_size() -> Vector2:
	return Vector2(DisplayServer.window_get_size())


func get_window_position() -> Vector2:
	return Vector2(DisplayServer.window_get_position())


func get_screen_center() -> Vector2:
	return Vector2(get_screen_bounds().get_center())


## The four edges of the current monitor as floats.
func get_screen_edges() -> Dictionary:
	var b := get_screen_bounds()
	return {
		"left": float(b.position.x),
		"right": float(b.position.x + b.size.x),
		"top": float(b.position.y),
		"bottom": float(b.position.y + b.size.y),
	}


## Desktop scaling factor of the pet's current monitor (1.0 on standard
## displays, higher on HiDPI). 1.0 when no monitor is available.
func get_desktop_scale() -> float:
	if DisplayServer.get_screen_count() <= 0:
		return 1.0
	return DisplayServer.screen_get_scale()


## --- Cursor information ----------------------------------------------------

## Cached cursor position, updated every frame (cheap, no recalculation).
func get_cursor_position() -> Vector2:
	return _cursor_position


## Cursor position read live from the OS/override. Same value as
## get_cursor_position() but never cached - for consumers that must see the
## freshest value this exact frame.
func cursor_position() -> Vector2:
	return _read_cursor_position()


## Last movement direction as a unit vector (ZERO while stationary).
func get_cursor_direction() -> Vector2:
	return _cursor_direction


## Cursor speed in px/s for the last frame.
func get_cursor_speed() -> float:
	return _cursor_speed


## Cursor displacement (px) over the last frame.
func get_cursor_delta() -> Vector2:
	return _cursor_delta


func get_distance_to_cursor() -> float:
	return pet.world_position.distance_to(_cursor_position)


func get_cursor_distance_horizontal() -> float:
	return absf(_cursor_position.x - pet.world_position.x)


func get_cursor_distance_vertical() -> float:
	return absf(_cursor_position.y - pet.world_position.y)


func is_cursor_above_pet() -> bool:
	return _cursor_position.y < pet.world_position.y


func is_cursor_below_pet() -> bool:
	return _cursor_position.y > pet.world_position.y


func is_cursor_in_interaction_range() -> bool:
	return _cursor_in_range


## --- Ground information ----------------------------------------------------

## The gap between the usable screen bottom and the floor the pet stands on.
## The awareness settings floor_offset takes priority when non-zero; the
## default (0.0) defers to PetDefinition.floor_offset, keeping the existing
## landing behavior exactly as it was.
func get_floor_offset() -> float:
	if settings.floor_offset > 0.0:
		return settings.floor_offset
	return pet.definition.floor_offset


## World-y anchor for the pet's center, adjusted so the lowest visible
## sprite point rests on the configured desktop floor at every size.
func floor_position() -> float:
	var bounds := pet.screen_bounds
	if bounds == Rect2i():
		bounds = ScreenService.usable_rect_containing(pet.world_position)
	if bounds == Rect2i():
		## Pet is between monitors (e.g. dragged into a display gap): anchor
		## to the nearest screen instead of leaving it floating in place.
		bounds = ScreenService.nearest_screen_rect(pet.world_position)
	if bounds == Rect2i():
		return pet.world_position.y
	var floor_edge := float(bounds.position.y + bounds.size.y) - get_floor_offset()
	return floor_edge - pet.get_sprite_bottom_extent()


## The ground the pet stands on (x follows the pet).
func get_ground_position() -> Vector2:
	return Vector2(pet.world_position.x, get_ground_y())


func get_ground_y() -> float:
	return floor_position()


func get_distance_to_ground() -> float:
	return maxf(get_ground_y() - pet.world_position.y, 0.0)


func is_grounded() -> bool:
	return pet.world_position.y >= get_ground_y() - GROUND_EPSILON


## A ground position clamped into the safe walking area - where the pet
## could safely be dropped/landed without going off-screen.
func get_safe_landing_position() -> Vector2:
	var area := get_safe_walking_area()
	var x := clampf(pet.world_position.x, area.position.x, area.position.x + area.size.x)
	return Vector2(x, get_ground_y())


## The horizontal limits of the ground plus the floor y, as a dictionary.
func get_ground_limits() -> Dictionary:
	var area := get_safe_walking_area()
	return {
		"left": area.position.x,
		"right": area.position.x + area.size.x,
		"ground_y": get_ground_y(),
	}


## --- Edge information ------------------------------------------------------

func get_left_edge() -> float:
	return float(get_screen_bounds().position.x)


func get_right_edge() -> float:
	var b := get_screen_bounds()
	return float(b.position.x + b.size.x)


func get_top_edge() -> float:
	return float(get_screen_bounds().position.y)


func get_bottom_edge() -> float:
	var b := get_screen_bounds()
	return float(b.position.y + b.size.y)


func get_distance_to_left_edge() -> float:
	return maxf(pet.world_position.x - get_left_edge(), 0.0)


func get_distance_to_right_edge() -> float:
	return maxf(get_right_edge() - pet.world_position.x, 0.0)


func is_near_left_edge() -> bool:
	return get_distance_to_left_edge() <= settings.edge_padding


func is_near_right_edge() -> bool:
	return get_distance_to_right_edge() <= settings.edge_padding


func is_near_any_edge() -> bool:
	return is_near_left_edge() or is_near_right_edge()


## The x-range the pet may walk on the current monitor without risk: the
## usable rect inset by the pet's rendered half-width (the body must stay
## on-screen) plus the safe_walking_margin on each side. Vertical range is
## left full-height so future window-climbing/dock features can use it.
func get_safe_walking_area() -> Rect2:
	var b := get_screen_bounds()
	var margin := settings.safe_walking_margin + pet.get_half_width()
	return Rect2(
		Vector2(b.position.x + margin, b.position.y),
		Vector2(maxf(b.size.x - 2.0 * margin, 0.0), b.size.y)
	)


## Clamps `point` horizontally so the pet's full body stays inside its
## current screen (the rendered half-width is included in the margin). Used
## by cursor-follow so the pet never stops with its body past the edge.
func clamp_to_safe_area(point: Vector2) -> Vector2:
	var area := get_safe_walking_area()
	if area.size.x <= 0.0:
		var bounds := get_screen_bounds()
		if bounds == Rect2i():
			return point
		return Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, point.y)
	return Vector2(
		clampf(point.x, area.position.x, area.position.x + area.size.x),
		point.y
	)


## --- Multi-monitor information ---------------------------------------------

## Monitor the pet is currently on, with a nearest-screen fallback when it
## sits in a display gap. -1 only when there are no monitors at all.
func get_current_monitor() -> int:
	var containing := which_monitor(pet.world_position)
	if containing >= 0:
		return containing
	return _nearest_monitor(pet.world_position)


func get_monitor_containing_pet() -> int:
	return get_current_monitor()


## Monitor containing `point` (or -1 if in a gap / no monitors).
func get_monitor_containing(point: Vector2) -> int:
	return which_monitor(point)


## Index of the monitor containing `point`, or -1.
func which_monitor(point: Vector2) -> int:
	return ScreenService.screen_index_containing(point)


func get_available_monitors() -> Array[int]:
	var monitors: Array[int] = []
	for i in DisplayServer.get_screen_count():
		monitors.append(i)
	return monitors


## Usable rect of a monitor. -1 = the pet's current monitor.
func get_monitor_bounds(index: int = -1) -> Rect2i:
	if index == -1:
		index = get_current_monitor()
	if index < 0 or index >= DisplayServer.get_screen_count():
		return Rect2i()
	return DisplayServer.screen_get_usable_rect(index)


## Position (top-left) of a monitor's usable rect. -1 = current monitor.
func get_monitor_position(index: int = -1) -> Vector2:
	return Vector2(get_monitor_bounds(index).position)


## Size of a monitor's usable rect. -1 = current monitor.
func get_monitor_size(index: int = -1) -> Vector2:
	return Vector2(get_monitor_bounds(index).size)


func monitor_count() -> int:
	return DisplayServer.get_screen_count()


func can_move_to_monitor(index: int) -> bool:
	return index >= 0 and index < DisplayServer.get_screen_count()


## --- Safe movement helpers -------------------------------------------------

## True when walking left is possible: not at the edge, or another monitor
## sits just beyond the edge to walk onto.
func can_move_left() -> bool:
	if not is_near_left_edge():
		return true
	var b := get_screen_bounds()
	var beyond := Vector2(b.position.x - settings.edge_padding, pet.world_position.y)
	return ScreenService.is_point_on_any_screen(beyond)


## True when walking right is possible: not at the edge, or another monitor
## sits just beyond the edge to walk onto.
func can_move_right() -> bool:
	if not is_near_right_edge():
		return true
	var b := get_screen_bounds()
	var beyond := Vector2(b.position.x + b.size.x + settings.edge_padding, pet.world_position.y)
	return ScreenService.is_point_on_any_screen(beyond)


## True when `point` lies on any monitor's usable area.
func is_destination_inside_desktop(point: Vector2) -> bool:
	return ScreenService.is_point_on_any_screen(point)


## Clamps `point` into the union of all monitors (no-op with no monitors).
func clamp_position_to_desktop(point: Vector2) -> Vector2:
	var b := get_desktop_bounds()
	if b == Rect2i():
		return point
	return Vector2(
		clampf(point.x, b.position.x, b.position.x + b.size.x),
		clampf(point.y, b.position.y, b.position.y + b.size.y)
	)


## Clamps `point` horizontally into the current safe walking area.
func get_nearest_safe_position(point: Vector2) -> Vector2:
	var area := get_safe_walking_area()
	return Vector2(
		clampf(point.x, area.position.x, area.position.x + area.size.x),
		point.y
	)


## Clamps `point` into the safe walking area and places it on the ground.
func get_nearest_floor_position(point: Vector2) -> Vector2:
	var safe := get_nearest_safe_position(point)
	return Vector2(safe.x, get_ground_y())


## Distance from `point` to the closest edge of the current monitor.
func get_distance_to_nearest_edge(point: Vector2) -> float:
	var b := get_screen_bounds()
	var left := absf(point.x - b.position.x)
	var right := absf(point.x - (b.position.x + b.size.x))
	var top := absf(point.y - b.position.y)
	var bottom := absf(point.y - (b.position.y + b.size.y))
	return minf(minf(left, right), minf(top, bottom))


## True when the pet may stand at `point` (inside its monitor or on an
## adjacent monitor reachable by walking).
func can_move_toward(point: Vector2) -> bool:
	## Some platforms / headless environments can report a zero-sized monitor
	## rect during early startup. With no reliable bounds, don't freeze the pet
	## in place; the normal screen clamp resumes as soon as bounds are known.
	if pet.screen_bounds == Rect2i():
		return true
	if pet.screen_bounds.has_point(Vector2i(point)):
		return true
	return ScreenService.is_point_on_any_screen(point)


## Keeps the moving anchor inside the safe horizontal area. The margin covers
## the sprite's widest frame plus the transparent DesktopWindow padding, so
## the window cannot slide off the side while the pet walks.
func clamp_pet_x_to_safe_area(x: float) -> float:
	var bounds := get_screen_bounds()
	if bounds == Rect2i():
		return x
	var area := get_safe_walking_area()
	if area.size.x <= 0.0:
		return float(bounds.position.x) + float(bounds.size.x) * 0.5
	return clampf(x, area.position.x, area.position.x + area.size.x)


## Nearest edge name of the current monitor's usable rect: "left",
## "right", "top" or "bottom".
func nearest_edge(point: Vector2) -> StringName:
	var bounds := pet.screen_bounds
	var left := absf(point.x - bounds.position.x)
	var right := absf(point.x - (bounds.position.x + bounds.size.x))
	var top := absf(point.y - bounds.position.y)
	var bottom := absf(point.y - (bounds.position.y + bounds.size.y))
	var min_dist := minf(minf(left, right), minf(top, bottom))
	if min_dist == left:
		return &"left"
	if min_dist == right:
		return &"right"
	if min_dist == top:
		return &"top"
	return &"bottom"


func screen_bounds_for(point: Vector2) -> Rect2i:
	return ScreenService.usable_rect_containing(point)


## --- Internals -------------------------------------------------------------

func _compute_desktop_bounds() -> Rect2i:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return Rect2i()
	var left := INF
	var top := INF
	var right := -INF
	var bottom := -INF
	for i in count:
		var rect := DisplayServer.screen_get_usable_rect(i)
		left = minf(left, rect.position.x)
		top = minf(top, rect.position.y)
		right = maxf(right, rect.position.x + rect.size.x)
		bottom = maxf(bottom, rect.position.y + rect.size.y)
	return Rect2i(int(left), int(top), int(right - left), int(bottom - top))


func _nearest_monitor(point: Vector2) -> int:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return -1
	var best := -1
	var best_dist := INF
	for i in count:
		var rect := DisplayServer.screen_get_usable_rect(i)
		var dist := Vector2(rect.get_center()).distance_to(point)
		if dist < best_dist:
			best_dist = dist
			best = i
	return best


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"monitor": get_current_monitor(),
		"monitor_count": monitor_count(),
		"desktop_bounds": get_desktop_bounds(),
		"screen_bounds": get_screen_bounds(),
		"window_size": get_window_size(),
		"window_position": get_window_position(),
		"desktop_scale": get_desktop_scale(),
		"cursor_position": get_cursor_position(),
		"cursor_direction": get_cursor_direction(),
		"cursor_speed": get_cursor_speed(),
		"distance_to_cursor": get_distance_to_cursor(),
		"cursor_in_interaction_range": is_cursor_in_interaction_range(),
		"ground_y": get_ground_y(),
		"grounded": is_grounded(),
		"distance_to_ground": get_distance_to_ground(),
		"distance_to_left_edge": get_distance_to_left_edge(),
		"distance_to_right_edge": get_distance_to_right_edge(),
		"near_left_edge": is_near_left_edge(),
		"near_right_edge": is_near_right_edge(),
		"safe_walking_area": get_safe_walking_area(),
	}
