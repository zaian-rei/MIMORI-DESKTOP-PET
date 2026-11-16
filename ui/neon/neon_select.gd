extends Control
class_name NeonSelect

## Neon dropdown field: a glass pill showing the current selection with a
## chevron, opening a styled PopupMenu when clicked. Used for theme,
## personality and startup-behavior pickers in the control centre.

signal item_selected(index: int, value: String)

@export var label: String = ""
@export var accent_color: Color = Neon.accent

var options: PackedStringArray = PackedStringArray()
var selected_index: int = -1

var _hover := 0.0
var _hovered := false
var _popup: PopupMenu = null

const HEIGHT := 30.0
const CHEVRON_W := 22.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(180, HEIGHT * Neon.UI_SCALE)
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func set_options(opts: PackedStringArray) -> void:
	options = opts
	if selected_index >= options.size():
		selected_index = options.size() - 1
	queue_redraw()


func set_selected(index: int) -> void:
	selected_index = clampi(index, -1, options.size() - 1)
	queue_redraw()


func get_selected_value() -> String:
	if selected_index >= 0 and selected_index < options.size():
		return options[selected_index]
	return ""


func _process(delta: float) -> void:
	var target := 1.0 if _hovered else 0.0
	var nh := move_toward(_hover, target, delta * 9.0)
	if nh != _hover:
		_hover = nh
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_open_popup()
			accept_event()


func _open_popup() -> void:
	if options.is_empty():
		return
	_close_popup()

	var popup := PopupMenu.new()
	popup.name = "NeonSelectPopup"
	## Keep the child popup above the transparent full-screen settings host on
	## macOS, Linux and Windows, where child-window stacking differs by platform.
	popup.transient = true
	popup.always_on_top = true
	popup.exclusive = false
	popup.allow_search = true
	for index in options.size():
		popup.add_item(options[index], index)
	if selected_index >= 0:
		popup.set_focused_item(selected_index)
	popup.id_pressed.connect(_on_selected)
	popup.popup_hide.connect(_close_popup)
	_style_popup(popup)

	var parent_window := get_window()
	if parent_window != null:
		parent_window.add_child(popup)
	else:
		add_child(popup)
	_popup = popup

	popup.reset_size()
	var screen := DisplayServer.window_get_current_screen()
	if parent_window != null:
		screen = parent_window.current_screen
	var screen_pos := Vector2i(get_screen_position()) + Vector2i(0, int(size.y) + 4)
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x > 0 and usable.size.y > 0:
		screen_pos.x = clampi(screen_pos.x, usable.position.x + 4, usable.position.x + usable.size.x - popup.size.x - 4)
		screen_pos.y = clampi(screen_pos.y, usable.position.y + 4, usable.position.y + usable.size.y - popup.size.y - 4)
	popup.position = screen_pos
	popup.popup()


func _close_popup() -> void:
	if _popup != null and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _on_selected(index: int) -> void:
	selected_index = index
	queue_redraw()
	var value := get_selected_value()
	item_selected.emit(index, value)


func _style_popup(popup: PopupMenu) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Neon.GLASS_STRONG
	panel.border_color = Neon.PANEL_BORDER
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.shadow_color = Neon.accent.darkened(0.6)
	panel.shadow_size = 8
	popup.add_theme_stylebox_override("panel", panel)

	var hover_sb := StyleBoxFlat.new()
	hover_sb.bg_color = Neon.accent.darkened(0.35)
	hover_sb.set_corner_radius_all(6)
	popup.add_theme_stylebox_override("hover", hover_sb)

	popup.add_theme_font_override("font", Neon.font())
	popup.add_theme_font_size_override("font_size", roundi(13.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	popup.add_theme_color_override("font_color", Neon.TEXT_MAIN)
	popup.add_theme_color_override("font_hover_color", Neon.TEXT_ON)
	popup.add_theme_constant_override("v_separation", 2)
	popup.add_theme_constant_override("h_separation", 4)


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	var radius := minf(Neon.RADIUS_SMALL, full.size.y * 0.5)

	var f := Neon.GLASS.lerp(accent_color, 0.10 * _hover)
	var rim := Neon.PANEL_BORDER
	if _hover > 0.0:
		rim = Neon.RIM.lerp(Neon.PANEL_BORDER, 1.0 - _hover)

	if _hover > 0.01:
		Neon.draw_glow(self, full, radius, rim, 0.5 * _hover)

	Neon.draw_glass_rect(self, full, radius, f, rim)

	var font := Neon.font()
	var fs := roundi(13.0 * Neon.UI_SCALE * Neon.FONT_SCALE)
	var baseline_y := full.position.y + (full.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
	var text := get_selected_value() if selected_index >= 0 else "(none)"
	var text_color := Neon.TEXT_MAIN if selected_index >= 0 else Neon.TEXT_FAINT
	var label_left := 0.0
	if label != "":
		label_left = 12.0 * Neon.UI_SCALE
		draw_string(font, Vector2(15.0 * Neon.UI_SCALE, baseline_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Neon.TEXT_DIM)
		label_left += font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 15.0 * Neon.UI_SCALE

	draw_string(font, Vector2(label_left + 12.0 * Neon.UI_SCALE, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

	## chevron
	var cx := full.size.x - CHEVRON_W * 0.5
	var cy := full.size.y * 0.5
	var chevron_col := Neon.TEXT_DIM.lerp(Neon.accent, _hover)
	var s := 3.0
	var points := PackedVector2Array([
		Vector2(cx - s, cy - s * 0.5),
		Vector2(cx, cy + s * 0.5),
		Vector2(cx + s, cy - s * 0.5),
	])
	draw_polyline(points, chevron_col, 1.5, true)
