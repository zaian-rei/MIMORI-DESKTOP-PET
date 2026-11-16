extends Node2D
class_name DebugDraw

## Visual-debug helpers drawn inside the pet's own window, in pet-local
## coordinates (window center == pet origin == pet.world_position). Every
## toggle is off by default, and the node only processes/redraws while at
## least one helper is enabled - zero cost otherwise.

var pet: Pet
var awareness: DesktopAwarenessComponent
var follow_component: FollowCursorComponent

var show_ground := false
var show_safe_area := false
var show_cursor := false
var show_arrival_radius := false
var show_screen_bounds := false

const COLOR_GROUND := Color(0.25, 0.9, 0.3, 0.9)
const COLOR_SAFE_AREA := Color(0.95, 0.9, 0.2, 0.5)
const COLOR_CURSOR := Color(0.95, 0.3, 0.25, 0.9)
const COLOR_ARRIVAL := Color(0.25, 0.7, 0.95, 0.9)
const COLOR_BOUNDS := Color(1.0, 1.0, 1.0, 0.6)


func setup(target_pet: Pet) -> void:
	pet = target_pet
	if pet != null:
		awareness = pet.get_component(DesktopAwarenessComponent)
		follow_component = pet.get_component(FollowCursorComponent)
	_refresh_activity()


## Re-applies options and turns the node's processing on/off so an
## all-disabled overlay costs nothing.
func set_options(options: Dictionary) -> void:
	show_ground = bool(options.get("ground", false))
	show_safe_area = bool(options.get("safe_area", false))
	show_cursor = bool(options.get("cursor", false))
	show_arrival_radius = bool(options.get("arrival_radius", false))
	show_screen_bounds = bool(options.get("screen_bounds", false))
	_refresh_activity()
	queue_redraw()


func is_active() -> bool:
	return visible


func _refresh_activity() -> void:
	var active := show_ground or show_safe_area or show_cursor or show_arrival_radius or show_screen_bounds
	set_process(active)
	visible = active


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if pet == null:
		return

	var origin := pet.world_position
	var half := pet.get_rendered_size() * 0.5 + Vector2(DesktopWindow.WINDOW_PADDING, DesktopWindow.WINDOW_PADDING)

	if show_screen_bounds and pet.screen_bounds != Rect2i():
		_draw_world_rect(pet.screen_bounds, COLOR_BOUNDS, origin)

	if show_ground and awareness != null:
		var gy := awareness.get_ground_y() - origin.y
		draw_line(Vector2(-half.x, gy), Vector2(half.x, gy), COLOR_GROUND, 1.0)

	if show_safe_area and awareness != null:
		var area := awareness.get_safe_walking_area()
		_draw_world_rect(Rect2(area.position - origin, area.size), COLOR_SAFE_AREA, origin, true)

	if show_cursor and awareness != null:
		var cursor_local := awareness.get_cursor_position() - origin
		draw_line(Vector2.ZERO, cursor_local, COLOR_CURSOR, 1.0)
		draw_circle(cursor_local, 4.0, COLOR_CURSOR)
		draw_arc(Vector2.ZERO, awareness.settings.cursor_interaction_radius, 0.0, TAU, 48, Color(0.95, 0.3, 0.25, 0.35), 1.0)

	if show_arrival_radius and follow_component != null:
		var settings := follow_component.settings
		if settings != null:
			draw_arc(Vector2.ZERO, settings.stop_distance, 0.0, TAU, 48, COLOR_ARRIVAL, 1.0)
			draw_arc(Vector2.ZERO, settings.sprint_distance, 0.0, TAU, 48, Color(0.25, 0.7, 0.95, 0.35), 1.0)


func _draw_world_rect(world_rect: Rect2, color: Color, origin: Vector2, filled: bool = false) -> void:
	var local := Rect2(world_rect.position - origin, world_rect.size)
	draw_rect(local, color, filled)
