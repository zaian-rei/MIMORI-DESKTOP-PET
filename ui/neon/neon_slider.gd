extends Control
class_name NeonSlider

## Modern neon slider: glowing track, cyan→purple gradient fill, a glowing
## handle, drag + arrow-key support, and a live value readout on the right
## (percent by default). Pure custom drawing - no Godot theme involved.

signal value_changed(value: float)

@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var step: float = 1.0
@export var show_value_text: bool = true
@export var value_suffix: String = "%"
@export var label: String = ""
@export var accent_color: Color = Neon.accent
@export var is_float: bool = false

var value: float = 0.0

var _drag := false
var _hover := 0.0
var _hovered := false

const TRACK := 8.0
const HANDLE_R := 9.0
const VALUE_W := 26.0
const VALUE_GAP := 12.0
const LABEL_W := 110.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(220, 30) * Neon.UI_SCALE
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func configured(l: String, mn: float, mx: float, st: float, init: float, suffix: String = "%", float_vals: bool = false) -> NeonSlider:
	label = l
	min_value = mn
	max_value = mx
	step = st
	value = clampf(init, mn, mx)
	value_suffix = suffix
	is_float = float_vals
	return self


func set_value(new_value: float, emit: bool = true) -> void:
	value = clampf(new_value, min_value, max_value)
	if emit:
		value_changed.emit(value)
	queue_redraw()


func set_value_no_signal(new_value: float) -> void:
	value = clampf(new_value, min_value, max_value)
	queue_redraw()


func get_value() -> float:
	return value


func _process(delta: float) -> void:
	var target := 1.0 if _hovered else 0.0
	var nh := move_toward(_hover, target, delta * 9.0)
	if nh != _hover:
		_hover = nh
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				grab_focus()
				_update_from_mouse(mb.position.x)
				accept_event()
			else:
				_drag = false
				accept_event()
	elif event is InputEventMouseMotion and _drag:
		_update_from_mouse(event.position.x)
		accept_event()
	elif event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and not _drag:
			if key.keycode == KEY_LEFT or key.keycode == KEY_DOWN:
				set_value(value - _snap_step())
				accept_event()
			elif key.keycode == KEY_RIGHT or key.keycode == KEY_UP:
				set_value(value + _snap_step())
				accept_event()


func _draw() -> void:
	var track_h := TRACK * Neon.UI_SCALE
	var handle_r := HANDLE_R * Neon.UI_SCALE
	var left := LABEL_W * Neon.UI_SCALE if label != "" else 10.0 * Neon.UI_SCALE
	var value_w := _value_width()
	var track_w := maxf(size.x - left - value_w, 1.0)
	var track_y := size.y * 0.5 - track_h * 0.5
	var track := Rect2(Vector2(left, track_y), Vector2(track_w, track_h))

	Neon.draw_glass_rect(self, track, track_h * 0.5, Neon.TRACK, Neon.PANEL_BORDER, Neon.UI_SCALE)

	var ratio := 0.0 if max_value <= min_value else clampf((value - min_value) / (max_value - min_value), 0.0, 1.0)
	if ratio > 0.0:
		var fill_col := accent_color.lerp(Neon.PURPLE, ratio)
		Neon.draw_glass_rect(self, Rect2(track.position, Vector2(track_w * ratio, track_h)), track_h * 0.5, fill_col, fill_col, 0.0)

	if label != "":
		var fs := roundi(13.0 * Neon.UI_SCALE * Neon.FONT_SCALE)
		var font := Neon.font()
		var baseline_y := (size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		draw_string(font, Vector2(0.0, baseline_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Neon.TEXT_DIM)

	var handle_x := track.position.x + track_w * ratio
	var handle_y := size.y * 0.5
	Neon.draw_glow(self, Rect2(Vector2(handle_x - handle_r * 2, handle_y - handle_r), Vector2(handle_r * 4, handle_r * 2)), handle_r, accent_color, 0.35 + 0.5 * _hover)
	draw_circle(Vector2(handle_x, handle_y), handle_r, Neon.GLASS_STRONG)
	draw_circle(Vector2(handle_x, handle_y), handle_r * 0.55, accent_color)
	draw_circle(Vector2(handle_x, handle_y), handle_r * 0.2, Neon.TEXT_ON)

	if show_value_text:
		var font := Neon.mono_font()
		var text := _format_value()
		var value_font_size := roundi(15.0 * Neon.UI_SCALE * Neon.FONT_SCALE)
		var text_w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size).x
		var text_color := Neon.TEXT_MAIN if _drag or _hover > 0.5 else Neon.TEXT_DIM
		var baseline_y := (size.y + font.get_ascent(value_font_size) - font.get_descent(value_font_size)) * 0.5
		draw_string(font, Vector2(size.x - text_w, baseline_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size, text_color)


## Width reserved for the live value readout. Measured from the current text
## so long suffixes ("1800 px/s²") never run under the slider handle.
func _value_width() -> float:
	if not show_value_text:
		return 0.0
	var value_font_size := roundi(15.0 * Neon.UI_SCALE * Neon.FONT_SCALE)
	var text_w := Neon.mono_font().get_string_size(_format_value(), HORIZONTAL_ALIGNMENT_LEFT, -1, value_font_size).x
	return maxf(VALUE_W * Neon.UI_SCALE, text_w + VALUE_GAP * Neon.UI_SCALE)


func _format_value() -> String:
	if is_float:
		return "%.1f%s" % [value, value_suffix]
	return "%d%s" % [roundi(value), value_suffix]


func _snap_step() -> float:
	return maxf(step, 0.01)


func _update_from_mouse(x: float) -> void:
	var left := LABEL_W * Neon.UI_SCALE if label != "" else 10.0 * Neon.UI_SCALE
	var track_w := maxf(size.x - left - _value_width(), 1.0)
	var ratio := clampf((x - left) / track_w, 0.0, 1.0)
	var raw := min_value + ratio * (max_value - min_value)
	if step > 0.0:
		raw = round(raw / step) * step
		raw = clampf(raw, min_value, max_value)
	set_value(raw)


func left_margin_width() -> float:
	return LABEL_W * Neon.UI_SCALE if label != "" else 10.0 * Neon.UI_SCALE
