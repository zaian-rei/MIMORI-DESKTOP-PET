extends PanelContainer
class_name NeonPanel

## Frosted-glass card container used for settings sections, the menu frame,
## and any chrome container. Draws a translucent rounded panel with a thin
## rim and a subtle top sheen; children sit inside with comfortable padding.
## Extends PanelContainer so the panel stylebox drives layout + draw.

@export var tint: Color = Neon.GLASS
@export var radius: float = Neon.RADIUS
@export var rim: Color = Neon.PANEL_BORDER
@export var shadow_blur_size: int = 8

var pad := 18


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_style()


func glass_panel(t: Color = Neon.GLASS, r: float = Neon.RADIUS, padding: int = 18) -> NeonPanel:
	tint = t
	radius = r
	pad = padding
	_apply_style()
	return self


func set_tint(t: Color) -> void:
	tint = t
	_apply_style()


func set_pad(p: int) -> void:
	pad = p
	_apply_style()


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.border_color = rim
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(radius))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	sb.shadow_color = Neon.accent.darkened(0.62)
	sb.shadow_size = shadow_blur_size
	sb.anti_aliasing = true
	add_theme_stylebox_override("panel", sb)
