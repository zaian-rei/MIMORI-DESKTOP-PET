extends RefCounted
class_name ScreenService

## Small screen-query helpers so the pet can roam across multiple
## monitors. Everything is computed from DisplayServer at runtime instead
## of the old single-screen snapshot in Bootstrap, so the floor and walk
## boundaries always match the monitor the pet is currently on.

## Returns the usable rect of the screen containing `point`, or the current
## window's screen as a fallback (empty Rect2i if no screen exists at all).
static func usable_rect_containing(point: Vector2) -> Rect2i:
	var int_point := Vector2i(point)
	for screen in DisplayServer.get_screen_count():
		var rect := DisplayServer.screen_get_usable_rect(screen)
		if rect.has_point(int_point):
			return rect
	var current := DisplayServer.window_get_current_screen()
	if current >= 0:
		return DisplayServer.screen_get_usable_rect(current)
	return Rect2i()


## Index of the monitor whose usable area contains `point`, or -1 if the
## point is on no monitor (e.g. a gap between displays).
static func screen_index_containing(point: Vector2) -> int:
	var int_point := Vector2i(point)
	for screen in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(screen).has_point(int_point):
			return screen
	return -1


## True if `point` lies inside any monitor's usable area. Used at walk
## boundaries: if the point just past the edge is on another screen, the
## pet is allowed to keep walking across instead of bouncing.
static func is_point_on_any_screen(point: Vector2) -> bool:
	return screen_index_containing(point) >= 0


## Usable rect of the nearest screen by distance to `point` (used when the
## point is in a gap between monitors). Empty Rect2i if no screens exist.
static func nearest_screen_rect(point: Vector2) -> Rect2i:
	var count := DisplayServer.get_screen_count()
	if count <= 0:
		return Rect2i()
	var best := 0
	var best_dist := INF
	for screen in count:
		var rect := DisplayServer.screen_get_usable_rect(screen)
		var dist := Vector2(rect.get_center()).distance_to(point)
		if dist < best_dist:
			best_dist = dist
			best = screen
	return DisplayServer.screen_get_usable_rect(best)


## Keeps the pet's screen_bounds in sync with whichever monitor it is on.
static func update_pet_bounds(pet: Pet) -> void:
	var rect := usable_rect_containing(pet.world_position)
	if rect != Rect2i():
		pet.screen_bounds = rect
