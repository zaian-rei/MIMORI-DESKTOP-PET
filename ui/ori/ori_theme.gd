extends RefCounted
class_name OriTheme

## The Ori settings design system: a small, frozen two-theme palette
## (Bright / Dark) plus the drawing helpers every Ori widget shares.
##
## Theme switching is global for the settings UI: call apply("bright") or
## apply("dark"), then ask every node in the "ori_theme" group to refresh.
## Widgets read the static colours below at draw time, so a refresh is enough
## to repaint the whole interface immediately.

const BRIGHT := "bright"
const DARK := "dark"

static var mode: String = BRIGHT

## --- Bright mode defaults ---------------------------------------------------
static var bg := Color("#FBF5F3")
static var bg_soft := Color("#F6E9EC")
static var panel := Color("#FDF2F3")
static var panel_strong := Color("#FFF9F8")
static var panel_soft := Color("#F5E4E9")
static var border := Color("#E8CDD4")
static var border_strong := Color("#D8A8B8")
static var accent := Color("#C86B86")
static var accent_soft := Color("#E7A9BC")
static var lavender := Color("#B5A4D6")
static var text := Color("#3F2537")
static var text_dim := Color("#6F5063")
static var text_faint := Color("#9B8090")
static var on_accent := Color("#FFF9F8")
static var track := Color("#EAD7DD")
static var danger := Color("#C0506A")
static var ok := Color("#6F9E80")
static var shadow := Color(0.35, 0.18, 0.25, 0.13)
static var sheen := Color(1, 1, 1, 0.55)


static func is_dark() -> bool:
	return mode == DARK


static func apply(theme_id: String) -> void:
	mode = DARK if theme_id == DARK else BRIGHT
	if mode == DARK:
		bg = Color("#241A22")
		bg_soft = Color("#2B1F29")
		panel = Color("#33232E")
		panel_strong = Color("#3D2A37")
		panel_soft = Color("#2C1F28")
		border = Color("#5A3E4D")
		border_strong = Color("#7A5367")
		accent = Color("#E7A0B5")
		accent_soft = Color("#C97C96")
		lavender = Color("#C3B2E0")
		text = Color("#F6EDF1")
		text_dim = Color("#CBB6C4")
		text_faint = Color("#9C8494")
		on_accent = Color("#2A1A24")
		track = Color("#4A3340")
		danger = Color("#E08095")
		ok = Color("#8FC7A6")
		shadow = Color(0, 0, 0, 0.38)
		sheen = Color(1, 1, 1, 0.08)
	else:
		bg = Color("#FBF5F3")
		bg_soft = Color("#F6E9EC")
		panel = Color("#FDF2F3")
		panel_strong = Color("#FFF9F8")
		panel_soft = Color("#F5E4E9")
		border = Color("#E8CDD4")
		border_strong = Color("#D8A8B8")
		accent = Color("#C86B86")
		accent_soft = Color("#E7A9BC")
		lavender = Color("#B5A4D6")
		text = Color("#3F2537")
		text_dim = Color("#6F5063")
		text_faint = Color("#9B8090")
		on_accent = Color("#FFF9F8")
		track = Color("#EAD7DD")
		danger = Color("#C0506A")
		ok = Color("#6F9E80")
		shadow = Color(0.35, 0.18, 0.25, 0.13)
		sheen = Color(1, 1, 1, 0.55)


## --- Drawing helpers --------------------------------------------------------

## Soft, layered shadow behind a rounded panel.
static func draw_shadow(carrier: CanvasItem, rect: Rect2, radius: float, strength: float = 1.0) -> void:
	if strength <= 0.0:
		return
	for i in range(4, 0, -1):
		var pad := float(i) * 2.0 * strength
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(shadow.r, shadow.g, shadow.b, shadow.a * 0.16 * (5.0 - float(i)) / 4.0)
		sb.set_corner_radius_all(int(radius + pad))
		carrier.draw_style_box(sb, rect.grow(pad))


static func draw_round_rect(
	carrier: CanvasItem,
	rect: Rect2,
	radius: float,
	fill: Color,
	border_color: Color = Color.TRANSPARENT,
	border_width: float = 0.0
) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	if border_width > 0.0:
		sb.border_color = border_color
		sb.set_border_width_all(int(border_width))
	sb.set_corner_radius_all(int(radius))
	carrier.draw_style_box(sb, rect)


static func draw_panel(
	carrier: CanvasItem,
	rect: Rect2,
	radius: float,
	fill: Color,
	border_color: Color,
	shadow_strength: float = 0.0,
	border_width: float = 1.0
) -> void:
	if shadow_strength > 0.0:
		draw_shadow(carrier, rect, radius, shadow_strength)
	draw_round_rect(carrier, rect, radius, fill, border_color, border_width)


## A soft circular wash used for the celestial background.
static func draw_soft_circle(carrier: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	for i in range(7, 0, -1):
		var t := float(i) / 7.0
		var c := Color(color.r, color.g, color.b, color.a * 0.18 * (1.0 - t + 0.15))
		carrier.draw_circle(center, radius * t, c)


## A small four-point sparkle. `s` is the outer radius.
static func draw_sparkle(carrier: CanvasItem, center: Vector2, s: float, color: Color) -> void:
	var inner := s * 0.22
	var points := PackedVector2Array([
		center + Vector2(0, -s),
		center + Vector2(inner, -inner),
		center + Vector2(s, 0),
		center + Vector2(inner, inner),
		center + Vector2(0, s),
		center + Vector2(-inner, inner),
		center + Vector2(-s, 0),
		center + Vector2(-inner, -inner),
	])
	carrier.draw_colored_polygon(points, color)


## A crescent moon, drawn as an accent circle with a panel-coloured bite.
static func draw_crescent(carrier: CanvasItem, center: Vector2, radius: float, color: Color, bite_color: Color) -> void:
	carrier.draw_circle(center, radius, color)
	carrier.draw_circle(center + Vector2(radius * 0.42, -radius * 0.16), radius * 0.86, bite_color)


## Fade + scale-in used when the settings window opens.
static func pop_in(node: CanvasItem, duration: float = 0.22) -> void:
	node.modulate = Color(1, 1, 1, 0)
	var target: Vector2 = node.scale
	node.scale = target * 0.96
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
