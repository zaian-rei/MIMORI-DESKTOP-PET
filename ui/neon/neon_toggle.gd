extends Control
class_name NeonToggle

## Modern toggle switch: a pill track with a sliding knob, cyan glow when on,
## animated transitions and immediate visual feedback. No Godot checkbox.

signal toggled(state: bool)

@export var label: String = ""
@export var accent_color: Color = Neon.accent
@export var show_mute_icon: bool = false

var button_pressed: bool = false

var _knob_anim := 0.0
var _hover := 0.0
var _hovered := false

const TRACK_W := 46.0
const TRACK_H := 26.0
const KNOB_R := 20.0
const ANIM_SPEED := 9.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(TRACK_W, TRACK_H) * Neon.UI_SCALE
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func set_pressed(value: bool) -> void:
	if button_pressed != value:
		button_pressed = value
		toggled.emit(button_pressed)
	queue_redraw()


func set_pressed_no_signal(value: bool) -> void:
	if button_pressed != value:
		button_pressed = value
	queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if button_pressed else 0.0
	var nk := move_toward(_knob_anim, target, delta * ANIM_SPEED)
	var tgt_hover := 1.0 if _hovered else 0.0
	var nh := move_toward(_hover, tgt_hover, delta * 6.0)
	if nk != _knob_anim or nh != _hover:
		_knob_anim = nk
		_hover = nh
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			set_pressed(not button_pressed)
			accept_event()


func _draw() -> void:
	var track_w := TRACK_W * Neon.UI_SCALE
	var track_h := TRACK_H * Neon.UI_SCALE
	var knob_r := KNOB_R * Neon.UI_SCALE
	var track := Rect2(Vector2(0, (size.y - track_h) * 0.5), Vector2(track_w, track_h))
	var radius := track_h * 0.5

	var base := Neon.TRACK
	if button_pressed:
		base = accent_color.darkened(0.15)
		Neon.draw_glow(self, track, radius, accent_color, 0.6 + 0.3 * _hover)
	else:
		base = base.lerp(Neon.TRACK_GLASS, 0.5)

	Neon.draw_glass_rect(self, track, radius, base, Neon.PANEL_BORDER, 1.0)

	## knob
	var knob_x := lerpf(knob_r / 2.0, track_w - knob_r / 2.0, _knob_anim)
	var knob_pos := Vector2(track.position.x + knob_x, track.position.y + track_h * 0.5)
	var knob_col := Neon.TEXT_MAIN if button_pressed else Neon.TEXT_DIM
	draw_circle(knob_pos, knob_r / 2.0 + Neon.UI_SCALE, Neon.GLASS_STRONG)
	draw_circle(knob_pos, knob_r / 2.0, knob_col)

	## on-state mini indicator dot
	if button_pressed:
		draw_circle(track.position + Vector2(track_w * 0.5, track_h * 0.5), 3.0 * Neon.UI_SCALE, accent_color)

	if show_mute_icon:
		_draw_mute_icon(track, track_h, button_pressed)

	## label to the right
	if label != "":
		var label_x := track.position.x + track_w + 10.0 * Neon.UI_SCALE
		var fs := roundi(14.0 * Neon.UI_SCALE * Neon.FONT_SCALE)
		var color := Neon.TEXT_MAIN if button_pressed else Neon.TEXT_DIM
		var font := Neon.font()
		var y := track.position.y + (track_h + font.get_ascent(fs) - font.get_descent(fs)) * 0.5
		draw_string(font, Vector2(label_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _draw_mute_icon(track: Rect2, track_h: float, active: bool) -> void:
	var scale := Neon.UI_SCALE
	var icon_size := 18.0 * scale
	var origin := Vector2(track.position.x + track.size.x + 12.0 * scale, track.position.y + (track_h - icon_size) * 0.5)
	var color := accent_color if active else Neon.TEXT_DIM
	var speaker := PackedVector2Array([
		origin + Vector2(0, 6) * scale,
		origin + Vector2(5, 6) * scale,
		origin + Vector2(11, 1) * scale,
		origin + Vector2(11, 17) * scale,
		origin + Vector2(5, 12) * scale,
		origin + Vector2(0, 12) * scale,
	])
	draw_colored_polygon(speaker, color)
	var x_start := origin + Vector2(15, 5) * scale
	var x_end := origin + Vector2(21, 13) * scale
	draw_line(x_start, x_end, color, 2.0 * scale, true)
	draw_line(origin + Vector2(21, 5) * scale, origin + Vector2(15, 13) * scale, color, 2.0 * scale, true)
