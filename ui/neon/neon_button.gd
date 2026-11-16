extends Control
class_name NeonButton

## Custom-drawn "glassy" button: rounded translucent fill, 1px rim, soft glow
## on hover, and a press squash. Supports toggle mode with an accent fill and
## optional leading/trailing glyph. Redraws itself - no Godot theme involved.

signal pressed
signal toggled(state: bool)

enum Indicator { UNDERLINE, LEFT_BAR, NONE }

@export var label: String = ""
@export var glyph: String = ""
@export var toggle_mode: bool = false
@export var accent_color: Color = Neon.accent
@export var content_alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER
@export var indicator: Indicator = Indicator.UNDERLINE
@export var font_size: int = 14

var toggled_state: bool = false

var _hover := 0.0
var _press := 0.0
var _pressing := false
var _hovered := false

const PAD_X := 14.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(96, 36) * Neon.UI_SCALE
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _on_mouse_entered() -> void:
	_hovered = true


func _on_mouse_exited() -> void:
	_hovered = false


func set_label(value: String) -> void:
	label = value
	queue_redraw()


func set_glyph(value: String) -> void:
	glyph = value
	queue_redraw()


func set_toggled(value: bool) -> void:
	toggle_mode = true
	if toggled_state != value:
		toggled_state = value
	queue_redraw()


func _process(delta: float) -> void:
	var target_hover := 1.0 if _hovered else 0.0
	var target_press := 1.0 if _pressing else 0.0
	var nh := move_toward(_hover, target_hover, delta * 6.0)
	var np := move_toward(_press, target_press, delta * 10.0)
	if nh != _hover or np != _press:
		_hover = nh
		_press = np
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _pressing:
				_pressing = true
				queue_redraw()
				accept_event()
			elif not mb.pressed and _pressing:
				_pressing = false
				queue_redraw()
				accept_event()
				if toggle_mode:
					toggled_state = not toggled_state
					toggled.emit(toggled_state)
				pressed.emit()


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, size)
	var radius := minf(Neon.RADIUS_SMALL, full.size.y * 0.5)
	var is_on := toggle_mode and toggled_state

	var f := Neon.GLASS
	if toggle_mode:
		if is_on:
			f = f.lerp(accent_color, 0.28 + 0.18 * _hover)
		else:
			f = f.lerp(accent_color, 0.14 * _hover)
	else:
		f = f.lerp(accent_color, 0.16 * _hover)

	var rim_color := Neon.PANEL_BORDER
	if is_on:
		rim_color = accent_color.lerp(Neon.RIM, 0.45)
	elif _hover > 0.0:
		rim_color = Neon.RIM.lerp(Neon.PANEL_BORDER, 1.0 - _hover)

	var glow := 0.6 * _hover
	if is_on:
		glow = 0.5 + 0.4 * _hover

	if glow > 0.01:
		Neon.draw_glow(self, full, radius, rim_color, glow)

	Neon.draw_glass_rect(self, full, radius, f, rim_color)

	if _press > 0.0:
		Neon.draw_glass_rect(self, full.grow(-1.5 * _press), radius, f.darkened(0.08), rim_color, 1.5)

	_draw_text(full)

	if is_on and indicator != Indicator.NONE:
		var sb := StyleBoxFlat.new()
		sb.bg_color = accent_color
		if indicator == Indicator.LEFT_BAR:
			var bar := Rect2(
				Vector2(full.position.x + 2.0, full.position.y + 8.0),
				Vector2(2.5, maxf(full.size.y - 16.0, 1.0))
			)
			sb.set_corner_radius_all(2)
			draw_style_box(sb, bar)
		else:
			var bar := Rect2(
				Vector2(full.position.x + PAD_X * Neon.UI_SCALE * 0.7, full.position.y + full.size.y - 3.0 * Neon.UI_SCALE),
				Vector2(full.size.x - PAD_X * Neon.UI_SCALE * 1.4, 3.0 * Neon.UI_SCALE)
			)
			sb.corner_radius_bottom_left = int(radius)
			sb.corner_radius_bottom_right = int(radius)
			draw_style_box(sb, bar)


func _draw_text(full: Rect2) -> void:
	var color := Neon.TEXT_MAIN
	if toggle_mode and toggled_state:
		color = Neon.TEXT_ON

	var font := Neon.font()
	var fs := roundi(float(font_size) * Neon.UI_SCALE * Neon.FONT_SCALE)
	var glyph_w := 0.0
	if glyph != "":
		glyph_w = font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0 * Neon.UI_SCALE

	var total_w := glyph_w + font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var start_x := full.position.x + (full.size.x - total_w) * 0.5
	match content_alignment:
		HORIZONTAL_ALIGNMENT_LEFT:
			start_x = full.position.x + PAD_X * Neon.UI_SCALE
		HORIZONTAL_ALIGNMENT_RIGHT:
			start_x = full.position.x + full.size.x - total_w - PAD_X * Neon.UI_SCALE
	## draw_string() takes a baseline, so use font metrics to center the glyph
	## box vertically instead of estimating from font size.
	var baseline_y := full.position.y + (full.size.y + font.get_ascent(fs) - font.get_descent(fs)) * 0.5

	if glyph != "":
		draw_string(font, Vector2(start_x, baseline_y), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		start_x += glyph_w

	draw_string(font, Vector2(start_x, baseline_y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


## Small helper so widgets can be built with a fluent one-liner.
func configured(t: String, g: String = "", acc: Color = Neon.accent) -> NeonButton:
	label = t
	glyph = g
	accent_color = acc
	custom_minimum_size = Vector2(maxf(custom_minimum_size.x, 96.0 * Neon.UI_SCALE), maxf(custom_minimum_size.y, 36.0 * Neon.UI_SCALE))
	return self
