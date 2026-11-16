extends Label
class_name NeonLabel

## Pre-styled text label (section header / body / caption) using the neon type
## ramp. Just a Label with the right font, size and colour pre-applied.

enum Style { HEADER, SECTION, BODY, CAPTION, MONO, FAINT }

var style_kind: int = Style.BODY


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func make(text: String, kind: int = Style.BODY) -> NeonLabel:
	var l := NeonLabel.new()
	l.style_kind = kind
	l.text = text
	l._apply_style()
	return l


func configured(text_s: String, kind: int = Style.BODY) -> NeonLabel:
	text = text_s
	style_kind = kind
	_apply_style()
	return self


func _apply_style() -> void:
	match style_kind:
		Style.HEADER:
			add_theme_font_override("font", Neon.display_font())
			add_theme_font_size_override("font_size", roundi(22.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.TEXT_MAIN)
		Style.SECTION:
			add_theme_font_override("font", Neon.font())
			add_theme_font_size_override("font_size", roundi(15.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.CYAN)
		Style.CAPTION:
			add_theme_font_override("font", Neon.font())
			add_theme_font_size_override("font_size", roundi(11.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.TEXT_DIM)
		Style.MONO:
			add_theme_font_override("font", Neon.mono_font())
			add_theme_font_size_override("font_size", roundi(12.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.TEXT_MAIN)
		Style.FAINT:
			add_theme_font_override("font", Neon.font())
			add_theme_font_size_override("font_size", roundi(12.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.TEXT_FAINT)
		_:
			add_theme_font_override("font", Neon.font())
			add_theme_font_size_override("font_size", roundi(14.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
			add_theme_color_override("font_color", Neon.TEXT_MAIN)
