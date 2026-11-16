extends RefCounted
class_name Neon

const UI_SCALE := 1.6
const FONT_SCALE := 1.495

## ----------------------------------------------------------------
## LYRIA DESIGN SYSTEM
##
## A small frozen palette + type ramp for the whole companion UI. Every
## custom-drawn neon control reaches its brushes and fonts from here, so the
## settings control-centre, the right-click menu and future panels all speak
## the same visual language. Chrome is dark translucent glass with a thin
## cyan rim, purple/blue accents and restrained glow.
## ----------------------------------------------------------------

## ---- Palette ---------------------------------------------------------------

static var accent := Color(0.16, 0.82, 1.0)          # electric cyan (default)
static var accent_secondary := Color(0.62, 0.45, 1.0) # purple
static var accent_blue := Color(0.30, 0.56, 1.0)   # helper blue

static var CYAN := Color(0.16, 0.82, 1.0)
static var PURPLE := Color(0.62, 0.45, 1.0)
static var BLUE := Color(0.30, 0.56, 1.0)

static var BG_DEEP := Color(0.025, 0.04, 0.065)
static var GLASS := Color(0.07, 0.095, 0.15, 0.98)
static var GLASS_STRONG := Color(0.10, 0.13, 0.20, 1.0)
static var PANEL_BORDER := Color(0.30, 0.72, 1.0, 0.35)
static var RIM := Color(0.45, 0.86, 1.0, 0.55)

static var TEXT_MAIN := Color(0.92, 0.96, 1.0)
static var TEXT_DIM := Color(0.58, 0.66, 0.80)
static var TEXT_FAINT := Color(0.40, 0.47, 0.60)
static var TEXT_ON := Color(0.025, 0.10, 0.16)
static var DANGER := Color(1.0, 0.36, 0.44)
static var OK := Color(0.30, 0.95, 0.70)

static var RADIUS := 48.0
static var RADIUS_SMALL := 20.0
static var TRACK := Color(0.16, 0.22, 0.33, 0.9)
static var TRACK_GLASS := Color(0.18, 0.25, 0.38, 0.55)


static func apply_ori_palette(dark: bool) -> void:
	var rose := Color("#E7A0B5") if dark else Color("#C86B86")
	var plum := Color("#241A22") if dark else Color("#3F2537")
	var panel := Color("#33232E") if dark else Color("#FDF2F3")
	var panel_strong := Color("#3D2A37") if dark else Color("#FFF9F8")
	var border := Color("#5A3E4D") if dark else Color("#E8CDD4")
	accent = rose
	accent_secondary = Color("#C3B2E0") if dark else Color("#B5A4D6")
	accent_blue = accent_secondary
	CYAN = rose
	PURPLE = accent_secondary
	BLUE = accent_secondary
	BG_DEEP = plum
	GLASS = panel
	GLASS_STRONG = panel_strong
	PANEL_BORDER = border
	RIM = Color("#7A5367") if dark else Color("#D8A8B8")
	TEXT_MAIN = Color("#F6EDF1") if dark else plum
	TEXT_DIM = Color("#CBB6C4") if dark else Color("#6F5063")
	TEXT_FAINT = Color("#9C8494") if dark else Color("#9B8090")
	TEXT_ON = plum if dark else Color("#FFF9F8")
	DANGER = Color("#E08095") if dark else Color("#C0506A")
	OK = Color("#8FC7A6") if dark else Color("#6F9E80")
	TRACK = Color("#4A3340") if dark else Color("#EAD7DD")
	TRACK_GLASS = Color("#3D2A37") if dark else Color("#F5E4E9")

## ---- type ramp ------------------------------------------------------------
static var _pixel_font: FontFile = null
static var _fallback_font: SystemFont = null


static func font() -> Font:
	if _pixel_font == null:
		_pixel_font = load("res://assets/fonts/VT323-Regular.ttf") as FontFile
		if _pixel_font != null:
			_pixel_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	if _pixel_font != null:
		return _pixel_font
	if _fallback_font == null:
		_fallback_font = _build_font(["SF Pro Display", "Segoe UI", "Roboto", "Noto Sans"])
	return _fallback_font


static func display_font() -> Font:
	return font()


static func mono_font() -> Font:
	return font()


static func _build_font(names: Array, monospace := false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(names)
	f.allow_system_fallback = true
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	return f


## ---- geometry / drawing helpers --------------------------------------------

## Draws a soft outer glow around `rect` by expanding translucent rims.
static func draw_glow(carrier: CanvasItem, rect: Rect2, radius: float, color: Color, strength: float = 1.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(radius))
	for i in range(3, 0, -1):
		var pad := i * 2.0 * strength
		sb.bg_color.a = color.a * 0.12 * (3.0 - float(i)) / 3.0
		sb.set_border_width_all(0)
		carrier.draw_style_box(sb, rect.grow(pad + i * strength))


## Draw a filled rounded rectangle with a 1px rim (soft inner accent).
static func draw_glass_rect(
	carrier: CanvasItem,
	rect: Rect2,
	radius: float,
	fill: Color,
	rim: Color = PANEL_BORDER,
	rim_width: float = 1.0
) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = rim
	sb.set_border_width_all(int(rim_width))
	sb.set_corner_radius_all(int(radius))
	carrier.draw_style_box(sb, rect)
	## top sheen - a hairline lighter edge that sells the "glass" look.
	var sheen := StyleBoxFlat.new()
	sheen.bg_color = Color(1.0, 1.0, 1.0, 0.06)
	sheen.set_corner_radius_all(int(radius))
	var inner := rect.grow(-1.0 - rim_width)
	carrier.draw_style_box(sheen, Rect2(inner.position, Vector2(inner.size.x, 2.0)))


## Fade + scale-in a CanvasItem (used for panel & menu entrances).
static func pop_in(node: CanvasItem, duration: float = 0.22) -> void:
	node.modulate = Color(1, 1, 1, 0)
	var target: Vector2 = node.scale
	node.scale = target * 0.94
	var tw := node.create_tween()
	tw.set_parallel(true)
	tw.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(node, "scale", target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().set_parallel(false).tween_callback(node.queue_redraw)


