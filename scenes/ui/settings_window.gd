extends Window
class_name SettingsWindow

## Ori's compact desktop settings window.
##
## The window is a transparent, borderless, always-on-top glass card with:
##   - a custom drag header,
##   - a slim icon sidebar that swaps pages,
##   - a page header (title / description / position),
##   - scrollable setting cards built from the neon kit,
##   - a footer with live save status and a per-page reset.
##
## Public contract (kept from the legacy window so ContextMenuComponent and
## MenuBarService keep working unchanged):
##   setup(target_pet, target_desktop_window)
##   popup() / grab_focus() / size / position
##
## Extending it is intentionally boring: add a PAGE_DEFS entry, add a builder
## method, and (optionally) register controls with _add_slider/_add_toggle/
## _add_select. Refresh code looks controls up by stable string ids instead of
## fragile child indices.

const SIDEBAR_W := 266
const HEADER_H := 84
const PAGE_PAD := 36
const CARD_PAD := 32
const ROW_SEP := 12
const CARD_SEP := 22
const WINDOW_TARGET_SIZE := Vector2i(1200, 800)
const PANEL_SCREEN_FRACTION := 0.84
const SETTINGS_AUDIO_CATEGORIES := [
	AudioCategory.Category.MOVEMENT,
	AudioCategory.Category.INTERACTIONS,
	AudioCategory.Category.UI,
	AudioCategory.Category.MUSIC,
]

## The single place that defines the navigation + page header copy. Adding a
## page is a data change plus one builder method (see _build_pages()).
const PAGE_DEFS := [
	{
		"id": "general",
		"label": "General",
		"title": "General",
		"subtitle": "Motion, desktop presence and startup.",
	},
	{
		"id": "interaction",
		"label": "Interaction",
		"title": "Interaction",
		"subtitle": "Movement and the way your companion responds.",
	},
	{
		"id": "appearance",
		"label": "Appearance",
		"title": "Appearance",
		"subtitle": "A little light, a little moonlight.",
	},
	{
		"id": "help",
		"label": "Help",
		"title": "Help",
		"subtitle": "Quick answers for your desktop companion.",
	},
	{
		"id": "about",
		"label": "About",
		"title": "About Mimori",
		"subtitle": "A little companion for your desktop.",
	},
]

var pet: Pet
var desktop_window: DesktopWindow

## Page id -> ScrollContainer.
var _pages: Dictionary = {}
## Page id -> PAGE_DEFS entry.
var _page_meta: Dictionary = {}
## [{id, button}].
var _nav: Array = []
var _current_page := "general"
var _page_tween: Tween = null

## Stable control ids -> widgets. Refresh never relies on child ordering.
var _sliders: Dictionary = {}
var _slider_ranges: Dictionary = {}
var _toggles: Dictionary = {}
var _selects: Dictionary = {}
var _theme_buttons: Dictionary = {}

## Header / footer widgets.
var _page_holder: Control
var _page_title: Label
var _page_subtitle: Label
var _status_label: Label
var _brand_label: Label
var _sidebar_pet_name: Label
var _sidebar_pet_logo: TextureRect
var _pet_name_input: LineEdit
var _pet_profile_ids: PackedStringArray = PackedStringArray()
var _pet_choice_buttons: Dictionary = {}
var _pet_preview: TextureRect
var _pet_character_name: Label
var _pet_character_description: NeonLabel
var _special_move_hint: NeonLabel
var _special_move_button: NeonButton
var _theme_hint: NeonLabel
var _personality_hint: NeonLabel

## Theme/personality selects show display names but carry ids in parallel arrays.
var _theme_ids: PackedStringArray = PackedStringArray()
var _personality_ids: PackedStringArray = PackedStringArray()
var _personality_cards: Dictionary = {}
var _personality_grid: GridContainer

## "Saved" status fades back to "Auto-saved" after a moment.
var _status_reset_left := 0.0

## Height of the header + page header + footer chrome. Cached after the first
## layout so each page can size the window to its content.
var _chrome_h := 0.0
var _fit_pending := false

## Drag state (this build has no begin_move(), so the header moves the window
## manually through DisplayServer mouse coords).
var _dragging := false
var _drag_offset := Vector2i.ZERO
var _host_screen_rect := Rect2i()
var _host_panel_rect := Rect2i()
var _screen_host_configured := false


static func panel_size_for_screen(usable_rect: Rect2i) -> Vector2i:
	if usable_rect.size.x <= 0 or usable_rect.size.y <= 0:
		return WINDOW_TARGET_SIZE
	return Vector2i(
		mini(WINDOW_TARGET_SIZE.x, maxi(640, floori(usable_rect.size.x * PANEL_SCREEN_FRACTION))),
		mini(WINDOW_TARGET_SIZE.y, maxi(460, floori(usable_rect.size.y * PANEL_SCREEN_FRACTION)))
	)


func _ready() -> void:
	transparent = true
	transparent_bg = true
	borderless = true
	unresizable = true
	mode = Window.MODE_WINDOWED
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	min_size = Vector2i(640, 460)
	size = WINDOW_TARGET_SIZE
	always_on_top = true
	exclusive = false
	transient = false
	close_requested.connect(hide)
	_apply_ui_theme(str(SettingsManager.get_setting("appearance.ui_theme", OriTheme.BRIGHT)), false)
	_build()
	_apply_ui_theme(str(SettingsManager.get_setting("appearance.ui_theme", OriTheme.BRIGHT)), false)
	title = "Settings"
	hide()


## --- Public contract ---------------------------------------------------------

func setup(target_pet: Pet, target_desktop_window: DesktopWindow) -> void:
	pet = target_pet
	desktop_window = target_desktop_window
	_refresh_all_values()
	_set_page(_current_page)


## Shows the window with a pop-in. Native Window.popup() must stay untouched
## (this build treats overrides of it as an error), so the caller uses this
## name.
func open_pet_picker() -> void:
	_current_page = "appearance"
	if pet != null and str(SettingsManager.get_setting("general.pet_id", "")).is_empty():
		SettingsManager.set_setting("general.pet_id", pet.profile_id)
	open_control_center()


func open_control_center() -> void:
	_refresh_all_values()
	_set_page(_current_page)
	show()
	var panel := _panel()
	if panel != null:
		panel.modulate.a = 0.0
	await get_tree().process_frame
	await get_tree().process_frame
	_restore_screen_host_geometry()
	_fit_window_to_page()
	if panel != null:
		panel.pivot_offset = panel.size * 0.5
		Neon.pop_in(panel)
	grab_focus()


func _panel() -> CanvasItem:
	return get_node_or_null("Root/Panel")


## Hosts the rounded settings card in a transparent, screen-sized window.
## Input outside the card is passed through to the desktop.
func configure_screen_host(screen_rect: Rect2i, panel_rect: Rect2i) -> void:
	_host_screen_rect = screen_rect
	_host_panel_rect = panel_rect
	_screen_host_configured = true
	mode = Window.MODE_WINDOWED
	transparent = true
	transparent_bg = true
	min_size = screen_rect.size
	_restore_screen_host_geometry()


func _restore_screen_host_geometry() -> void:
	if not _screen_host_configured:
		return
	mode = Window.MODE_WINDOWED
	transparent = true
	transparent_bg = true
	size = _host_screen_rect.size
	position = _host_screen_rect.position
	var panel := get_node_or_null("Root/Panel") as Control
	if panel == null:
		return
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(_host_panel_rect.position)
	panel.size = Vector2(_host_panel_rect.size)
	_update_input_region()


func _move_panel_to_host_position(next_position: Vector2i) -> void:
	var panel := get_node_or_null("Root/Panel") as Control
	if panel == null:
		return
	var margin := 12
	var max_x := maxi(margin, int(size.x - panel.size.x) - margin)
	var max_y := maxi(margin, int(size.y - panel.size.y) - margin)
	panel.position = Vector2(
		clampi(next_position.x, margin, max_x),
		clampi(next_position.y, margin, max_y)
	)
	_host_panel_rect.position = Vector2i(panel.position)
	_update_input_region()


func _update_input_region() -> void:
	var panel := get_node_or_null("Root/Panel") as Control
	if panel == null:
		return
	var rect := Rect2(panel.position, panel.size)
	var radius := minf(Neon.RADIUS, minf(rect.size.x, rect.size.y) * 0.5)
	mouse_passthrough_polygon = _rounded_rect_polygon(rect, radius)


func _rounded_rect_polygon(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [
		rect.position + Vector2(radius, radius),
		Vector2(rect.end.x - radius, rect.position.y + radius),
		rect.end - Vector2(radius, radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
	]
	var start_angles := [PI, -PI * 0.5, 0.0, PI * 0.5]
	const CORNER_STEPS := 8
	for corner_index in range(centers.size()):
		for step in range(CORNER_STEPS + 1):
			var angle: float = start_angles[corner_index] + (PI * 0.5) * float(step) / CORNER_STEPS
			points.append(centers[corner_index] + Vector2(cos(angle), sin(angle)) * radius)
	return points


## --- Build -------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := NeonPanel.new()
	panel.name = "Panel"
	panel.shadow_blur_size = 0
	panel.glass_panel(Neon.GLASS, Neon.RADIUS, 0)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 0)
	panel.add_child(vbox)

	vbox.add_child(_build_header())
	vbox.add_child(_separator())

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	vbox.add_child(body)

	body.add_child(_build_sidebar())
	body.add_child(_vertical_separator())

	var content := VBoxContainer.new()
	content.name = "Content"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	body.add_child(content)

	content.add_child(_build_page_header())
	content.add_child(_separator())

	_page_holder = Control.new()
	_page_holder.name = "PageHolder"
	_page_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(_page_holder)

	content.add_child(_separator())
	content.add_child(_build_footer())

	_build_pages()
	_set_page("general")


func _build_header() -> Control:
	var header := Control.new()
	header.name = "Header"
	header.custom_minimum_size = Vector2(0, HEADER_H)
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_gui_input)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 14)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(hbox)

	var brand_box := VBoxContainer.new()
	brand_box.add_theme_constant_override("separation", 0)
	brand_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(brand_box)

	_brand_label = NeonLabel.make("SETTINGS", NeonLabel.Style.HEADER)
	var brand := _brand_label
	brand.add_theme_font_size_override("font_size", roundi(18.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	brand_box.add_child(brand)

	var caption := NeonLabel.make("PREFERENCES", NeonLabel.Style.CAPTION)
	caption.add_theme_font_size_override("font_size", roundi(9.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	brand_box.add_child(caption)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)

	var esc_hint := NeonLabel.make("ESC", NeonLabel.Style.MONO)
	esc_hint.add_theme_font_size_override("font_size", roundi(9.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	esc_hint.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	esc_hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(esc_hint)

	var close_btn := NeonButton.new()
	close_btn.configured("X", "", Neon.DANGER)
	close_btn.font_size = 12
	close_btn.custom_minimum_size = Vector2(56, 50)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(hide)
	hbox.add_child(close_btn)

	return header


func _build_sidebar() -> Control:
	var sidebar := Control.new()
	sidebar.name = "Sidebar"
	sidebar.custom_minimum_size = Vector2(SIDEBAR_W, 0)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	sidebar.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)

	_sidebar_pet_logo = TextureRect.new()
	_sidebar_pet_logo.texture = load(str(PetRoster.get_profile(PetRoster.DEFAULT_ID).get("portrait", "")))
	_sidebar_pet_logo.custom_minimum_size = Vector2(147, 147)
	_sidebar_pet_logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sidebar_pet_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sidebar_pet_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_sidebar_pet_logo)
	_sidebar_pet_name = NeonLabel.make(str(SettingsManager.get_setting("general.pet_name", "Ori")), NeonLabel.Style.HEADER)
	_sidebar_pet_name.add_theme_font_size_override("font_size", roundi(20.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	_sidebar_pet_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_sidebar_pet_name)
	var caption := NeonLabel.make("Your desktop companion", NeonLabel.Style.CAPTION)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(caption)
	box.add_child(_spacer_row(18))

	for def in PAGE_DEFS:
		_add_nav(box, def["id"], def["label"])

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	box.add_child(_separator())

	var version := NeonLabel.make("v0.1.0", NeonLabel.Style.MONO)
	version.add_theme_font_size_override("font_size", roundi(9.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	version.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	box.add_child(version)

	return sidebar


func _add_nav(parent: VBoxContainer, page_id: String, label: String) -> void:
	var btn := NeonButton.new()
	var glyphs := {
		"general": "⚙",
		"appearance": "◇",
		"interaction": "⌖",
		"help": "?",
		"about": "ⓘ",
	}
	btn.configured(label, str(glyphs.get(page_id, "")))
	btn.content_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.indicator = NeonButton.Indicator.LEFT_BAR
	btn.font_size = 12
	btn.toggle_mode = true
	btn.custom_minimum_size = Vector2(0, 62)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggled.connect(_on_nav_toggled.bind(page_id))
	parent.add_child(btn)
	_nav.append({"id": page_id, "button": btn})


func _on_nav_toggled(pressed: bool, page_id: String) -> void:
	if not pressed:
		## Clicking the already-active page: keep it active.
		for entry in _nav:
			if entry["id"] == _current_page:
				(entry["button"] as NeonButton).set_toggled(true)
		return
	_set_page(page_id)


func _build_page_header() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAGE_PAD)
	margin.add_theme_constant_override("margin_right", PAGE_PAD)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 20)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	margin.add_child(row)

	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 6)
	row.add_child(titles)

	_page_title = NeonLabel.make("", NeonLabel.Style.HEADER)
	_page_title.add_theme_font_size_override("font_size", roundi(18.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	titles.add_child(_page_title)

	_page_subtitle = NeonLabel.make("", NeonLabel.Style.FAINT)
	_page_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(_page_subtitle)

	return margin


func _build_footer() -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAGE_PAD)
	margin.add_theme_constant_override("margin_right", PAGE_PAD)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	margin.add_child(row)

	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 8)
	status_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(status_row)

	var dot := Control.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.draw.connect(func() -> void:
		var glow := Neon.OK
		glow.a = 0.22
		var sb := StyleBoxFlat.new()
		sb.bg_color = glow
		sb.set_corner_radius_all(4)
		dot.draw_style_box(sb, Rect2(0, 0, 8, 8))
		dot.draw_circle(Vector2(4, 4), 2.5, Neon.OK)
	)
	status_row.add_child(dot)

	_status_label = NeonLabel.make("Auto-saved", NeonLabel.Style.CAPTION)
	_status_label.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	status_row.add_child(_status_label)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var exit_button := NeonButton.new()
	exit_button.configured("Exit Mimori", "", Neon.DANGER)
	exit_button.font_size = 13
	exit_button.custom_minimum_size = Vector2(176, 52)
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	exit_button.pressed.connect(_on_quit_application)
	row.add_child(exit_button)

	return margin


func _build_pages() -> void:
	## A data-driven registry keeps page creation out of _build(). Add a page
	## by appending to PAGE_DEFS and adding one builder here.
	var builders := {
		"general": Callable(self, "_build_page_general"),
		"interaction": Callable(self, "_build_page_behavior"),
		"appearance": Callable(self, "_build_page_appearance"),
		"help": Callable(self, "_build_page_help"),
		"about": Callable(self, "_build_page_about"),
	}
	for def in PAGE_DEFS:
		_page_meta[def["id"]] = def
		builders[def["id"]].call()


func _set_page(page_id: String) -> void:
	if not _pages.has(page_id):
		return
	_current_page = page_id

	for entry in _nav:
		(entry["button"] as NeonButton).set_toggled(entry["id"] == page_id)

	var meta: Dictionary = _page_meta.get(page_id, {})
	if _page_title != null:
		_page_title.text = str(meta.get("title", page_id.capitalize()))
	if _page_subtitle != null:
		_page_subtitle.text = str(meta.get("subtitle", ""))

	for id in _pages:
		var page: Control = _pages[id]
		page.visible = id == page_id
		if id == page_id:
			if _page_tween != null and _page_tween.is_valid():
				_page_tween.kill()
			page.modulate.a = 0.0
			_page_tween = create_tween()
			_page_tween.tween_property(page, "modulate:a", 1.0, 0.14)

	if visible:
		_schedule_fit()


## A newly shown page reports a stale minimum size until the containers have
## sorted it, so wait one frame before measuring.
func _schedule_fit() -> void:
	if _fit_pending:
		return
	_fit_pending = true
	await get_tree().process_frame
	_fit_pending = false
	_fit_window_to_page()


## Keeps the window compact: it grows to the current page's content and
## shrinks back when a shorter page is selected. The header/footer chrome is
## cached from the first real layout so resizing never feeds back into itself.
func _fit_window_to_page() -> void:
	## Settings is intentionally kept at its larger window size across pages.
	pass


## --- Page scaffolding --------------------------------------------------------

func _new_page(id: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "Page_%s" % id
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	_style_scroll(scroll)
	_pages[id] = scroll
	_page_holder.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", PAGE_PAD)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", PAGE_PAD)
	margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(margin)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", CARD_SEP)
	margin.add_child(box)
	return box


func _style_scroll(scroll: ScrollContainer) -> void:
	var bar := scroll.get_v_scroll_bar()
	bar.custom_minimum_size = Vector2(6, 0)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)

	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Neon.PANEL_BORDER
	grabber.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("grabber", grabber)

	var active := grabber.duplicate() as StyleBoxFlat
	active.bg_color = Neon.accent
	bar.add_theme_stylebox_override("grabber_highlight", active)
	bar.add_theme_stylebox_override("grabber_pressed", active)


func _add_card(parent: VBoxContainer, title: String) -> VBoxContainer:
	var panel := NeonPanel.new()
	panel.name = "Card"
	panel.glass_panel(Neon.GLASS_STRONG, Neon.RADIUS_SMALL + 2.0, CARD_PAD)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)

	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_theme_constant_override("separation", ROW_SEP)
	panel.add_child(inner)

	if not title.is_empty():
		inner.add_child(_card_title(title))
	return inner


func _card_title(title: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var label := NeonLabel.make(title.to_upper(), NeonLabel.Style.CAPTION)
	label.add_theme_font_size_override("font_size", roundi(10.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	label.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	row.add_child(label)

	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	return row


func _add_hint(parent: VBoxContainer, text: String) -> NeonLabel:
	var hint := NeonLabel.make(text, NeonLabel.Style.FAINT)
	hint.add_theme_font_size_override("font_size", roundi(11.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(hint)
	return hint


func _add_slider(
	parent: VBoxContainer,
	id: String,
	label: String,
	min_value: float,
	max_value: float,
	step: float,
	value: float,
	_suffix: String,
	_float_values: bool,
	handler: Callable
) -> NeonSlider:
	var slider := NeonSlider.new()
	_configure_slider(slider, id, label, min_value, max_value, step, value, handler)
	slider.custom_minimum_size = Vector2(0, 48)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(slider)
	return slider


func _configure_slider(
	slider: NeonSlider,
	id: String,
	label: String,
	actual_min: float,
	actual_max: float,
	actual_step: float,
	actual_value: float,
	handler: Callable
) -> void:
	_slider_ranges[id] = {"min": actual_min, "max": actual_max, "step": actual_step}
	slider.configured(label, 0.0, 100.0, 1.0, _actual_to_slider_percent(id, actual_value, actual_min, actual_max), "", false)
	slider.show_value_text = false
	slider.value_changed.connect(_on_normalized_slider_changed.bind(id, handler))
	_sliders[id] = slider


func _actual_to_slider_percent(id: String, value: float, actual_min: float, actual_max: float) -> float:
	if _is_volume_slider(id):
		if value <= 0.0:
			return clampf((value - actual_min) / -actual_min * 50.0, 0.0, 50.0)
		return clampf(50.0 + value / actual_max * 50.0, 50.0, 100.0)
	if is_equal_approx(actual_min, actual_max):
		return 0.0
	return clampf((value - actual_min) / (actual_max - actual_min) * 100.0, 0.0, 100.0)


func _slider_percent_to_actual(id: String, percent: float, actual_min: float, actual_max: float) -> float:
	var normalized := clampf(percent, 0.0, 100.0)
	if _is_volume_slider(id):
		if normalized <= 50.0:
			return actual_min * (1.0 - normalized / 50.0)
		return actual_max * (normalized - 50.0) / 50.0
	return lerpf(actual_min, actual_max, normalized / 100.0)


func _is_volume_slider(id: String) -> bool:
	return id == "audio.master" or id.begins_with("audio.cat.")


func _on_normalized_slider_changed(percent: float, id: String, handler: Callable) -> void:
	var range: Dictionary = _slider_ranges[id]
	var actual_min := float(range["min"])
	var actual_max := float(range["max"])
	var value := _slider_percent_to_actual(id, percent, actual_min, actual_max)
	var step := float(range["step"])
	if step > 0.0:
		value = clampf(round(value / step) * step, actual_min, actual_max)
	handler.call(value)


func _add_toggle(parent: Container, id: String, label: String, handler: Callable) -> NeonToggle:
	var toggle := NeonToggle.new()
	toggle.label = label
	toggle.custom_minimum_size = Vector2(0, 48)
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(toggle)
	toggle.toggled.connect(handler)
	_toggles[id] = toggle
	return toggle


func _add_select(parent: VBoxContainer, id: String, label: String, handler: Callable) -> NeonSelect:
	var select := NeonSelect.new()
	select.label = label
	select.custom_minimum_size = Vector2(0, 52)
	select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(select)
	select.item_selected.connect(handler)
	_selects[id] = select
	return select


func _add_action(parent: VBoxContainer, label: String, handler: Callable) -> NeonButton:
	var btn := NeonButton.new()
	btn.configured(label)
	btn.content_alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.font_size = 12
	btn.custom_minimum_size = Vector2(0, 52)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn


func _spacer_row(height: float) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


func _separator() -> ColorRect:
	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _vertical_separator() -> ColorRect:
	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.custom_minimum_size = Vector2(1, 0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


## --- Pages -------------------------------------------------------------------

func _build_page_general() -> VBoxContainer:
	var box := _new_page("general")

	var app := _add_card(box, "Your companion")
	_add_hint(app, "A name for your desktop companion.")
	_pet_name_input = LineEdit.new()
	_pet_name_input.placeholder_text = "Ori"
	_pet_name_input.text = str(SettingsManager.get_setting("general.pet_name", "Ori"))
	_pet_name_input.custom_minimum_size = Vector2(0, 48)
	_pet_name_input.add_theme_font_size_override("font_size", roundi(16.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
	_pet_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pet_name_input.add_theme_color_override("font_color", Neon.TEXT_MAIN)
	_pet_name_input.add_theme_color_override("font_placeholder_color", Neon.TEXT_FAINT)
	_pet_name_input.add_theme_font_override("font", Neon.font())
	_pet_name_input.add_theme_stylebox_override("normal", _input_style())
	_pet_name_input.add_theme_stylebox_override("focus", _input_style(true))
	_pet_name_input.text_submitted.connect(_on_pet_name_submitted)
	_pet_name_input.focus_exited.connect(func() -> void: _save_pet_name(_pet_name_input.text))
	app.add_child(_pet_name_input)
	var app_grid := GridContainer.new()
	app_grid.columns = 2
	app_grid.add_theme_constant_override("h_separation", 12)
	app_grid.add_theme_constant_override("v_separation", 8)
	app.add_child(app_grid)
	_add_toggle(app_grid, "general.on_top", "Always on top", _on_always_on_top_toggled)
	_add_toggle(app_grid, "general.login", "Launch at startup", _on_launch_at_login_toggled)

	var sound := _add_card(box, "Sound")
	_add_slider(sound, "audio.master", "Master Volume", -80.0, 24.0, 1.0, AudioManager.get_master_volume_db(), " dB", false, _on_master_volume_changed)
	_add_toggle(sound, "audio.mute", "Mute all sounds", _on_mute_toggled)
	for category in SETTINGS_AUDIO_CATEGORIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var label := NeonLabel.make(AudioCategory.label(category), NeonLabel.Style.BODY)
		label.custom_minimum_size = Vector2(156, 48)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_child(label)
		var slider := NeonSlider.new()
		var slider_id := "audio.cat.%d" % category
		_configure_slider(slider, slider_id, "", -80.0, 24.0, 1.0, AudioManager.get_category_volume(category), _on_category_volume_changed.bind(category))
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(180, 48)
		row.add_child(slider)
		var mute := NeonToggle.new()
		mute.show_mute_icon = true
		mute.tooltip_text = "Mute this sound category"
		mute.custom_minimum_size = Vector2(117, 48)
		mute.toggled.connect(_on_category_mute_toggled.bind(category))
		row.add_child(mute)
		_toggles["audio.mute.%d" % category] = mute
		sound.add_child(row)

	var theme_card := _add_card(box, "Theme")
	_add_hint(theme_card, "Choose a soft daytime palette or a quiet plum night.")
	var theme_row := HBoxContainer.new()
	theme_row.add_theme_constant_override("separation", 12)
	theme_card.add_child(theme_row)
	for theme_entry in [["Bright", OriTheme.BRIGHT], ["Dark", OriTheme.DARK]]:
		var theme_button := NeonButton.new()
		theme_button.configured(theme_entry[0])
		theme_button.toggle_mode = true
		theme_button.accent_color = Neon.accent
		theme_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		theme_button.custom_minimum_size = Vector2(0, 60)
		theme_button.toggled.connect(_on_ui_theme_button_toggled.bind(theme_entry[1]))
		theme_row.add_child(theme_button)
		_theme_buttons[theme_entry[1]] = theme_button

	return box


func _build_page_audio() -> VBoxContainer:
	var box := _new_page("audio")

	var output := _add_card(box, "Output")
	_add_slider(output, "audio.master", "Master Volume", -80.0, 24.0, 1.0, AudioManager.get_master_volume_db(), " dB", false, _on_master_volume_changed)
	_add_toggle(output, "audio.mute", "Mute All", _on_mute_toggled)

	var categories := _add_card(box, "Categories")
	for category in SETTINGS_AUDIO_CATEGORIES:
		_add_slider(
			categories,
			"audio.cat.%d" % category,
			AudioCategory.label(category),
			-80.0,
			24.0,
			1.0,
			AudioManager.get_category_volume(category),
			" dB",
			false,
			_on_category_volume_changed.bind(category)
		)

	return box


func _build_page_behavior() -> VBoxContainer:
	var box := _new_page("interaction")
	var actions := _add_card(box, "Spend a moment with your companion")
	_add_hint(actions, "Choose a quick reaction or spend a little time together.")
	var action_grid := GridContainer.new()
	action_grid.columns = 2
	action_grid.add_theme_constant_override("h_separation", 12)
	action_grid.add_theme_constant_override("v_separation", 10)
	actions.add_child(action_grid)
	_add_interaction_action(action_grid, "Feed Ori", Callable(self, "_on_feed_action"))
	_add_interaction_action(action_grid, "Make Ori happy", Callable(self, "_on_happy_action"))
	_add_interaction_action(action_grid, "Sad / angry", Callable(self, "_on_sad_action"))
	_add_interaction_action(action_grid, "Sleep", Callable(self, "_on_sleep_action"))
	_add_interaction_action(action_grid, "Dance", Callable(self, "_on_dance_action"))
	_add_toggle(action_grid, "general.follow", "Follow cursor", _on_follow_cursor_toggled)

	var signature := _add_card(box, "Signature Move")
	_special_move_hint = _add_hint(signature, "Select a pet to see its special move.")
	_special_move_button = _add_action(signature, "Play a Special Move", _on_play_special_move)

	var presence := _add_card(box, "Movement & presence")
	_add_slider(presence, "general.speed", "Move speed", 100.0, 220.0, 10.0, ConfigService.move_speed, "", false, _on_speed_changed)
	var gravity_value := clampf(ConfigService.gravity, 500.0, 1500.0)
	if not is_equal_approx(gravity_value, ConfigService.gravity):
		_on_gravity_changed(gravity_value)
	_add_slider(presence, "general.gravity", "Gravity", 500.0, 1500.0, 50.0, gravity_value, "", false, _on_gravity_changed)
	var jump_value := clampf(ConfigService.jump_speed, 100.0, 300.0)
	if not is_equal_approx(jump_value, ConfigService.jump_speed):
		_on_jump_changed(jump_value)
	_add_slider(presence, "general.jump", "Jump strength", 100.0, 300.0, 50.0, jump_value, "", false, _on_jump_changed)

	var personality := _add_card(box, "Personality")
	_add_hint(personality, "Choose how your companion behaves. Mimori adapts as soon as you select one.")
	_personality_grid = GridContainer.new()
	_personality_grid.columns = 1
	_personality_grid.add_theme_constant_override("h_separation", 0)
	_personality_grid.add_theme_constant_override("v_separation", 10)
	_personality_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	personality.add_child(_personality_grid)
	_personality_hint = _add_hint(personality, "No personalities found in res://data/personalities/.")
	_personality_hint.visible = false

	return box


func _add_interaction_action(parent: GridContainer, label: String, handler: Callable) -> void:
	var button := NeonButton.new()
	button.configured(label)
	button.font_size = 12
	button.custom_minimum_size = Vector2(0, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	parent.add_child(button)


func _build_page_appearance() -> VBoxContainer:
	var box := _new_page("appearance")
	var character := _add_card(box, "Character")
	var character_row := HBoxContainer.new()
	character_row.add_theme_constant_override("separation", 12)
	character.add_child(character_row)
	_pet_preview = TextureRect.new()
	_pet_preview.custom_minimum_size = Vector2(120, 120)
	_pet_preview.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_pet_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	character_row.add_child(_pet_preview)
	var character_copy := VBoxContainer.new()
	character_copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pet_character_name = NeonLabel.make("Echo", NeonLabel.Style.SECTION)
	character_copy.add_child(_pet_character_name)
	_pet_character_description = _add_hint(character_copy, "")
	character_row.add_child(character_copy)
	_add_hint(character, "Choose a companion. You can switch at any time.")
	_pet_profile_ids = PetRoster.get_all_ids()
	var choices := GridContainer.new()
	choices.columns = 3
	choices.add_theme_constant_override("h_separation", 12)
	choices.add_theme_constant_override("v_separation", 10)
	character.add_child(choices)
	var pet_names := PetRoster.get_names()
	for index in _pet_profile_ids.size():
		var profile_id := _pet_profile_ids[index]
		var choice := NeonButton.new()
		choice.configured(str(pet_names[index]))
		choice.toggle_mode = true
		choice.custom_minimum_size = Vector2(0, 56)
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.pressed.connect(_on_pet_choice_pressed.bind(index))
		choices.add_child(choice)
		_pet_choice_buttons[profile_id] = choice

	var window_card := _add_card(box, "Window")
	_add_slider(window_card, "general.scale", "Pet size", 0.75, 1.25, 0.01, ConfigService.scale, "", false, _on_scale_changed)
	_add_slider(
		window_card,
		"appearance.opacity",
		"Pet Opacity",
		0.35,
		1.0,
		0.01,
		ConfigService.window_opacity,
		"",
		false,
		_on_window_opacity_changed
	)

	return box


func _build_page_about() -> VBoxContainer:
	var box := _new_page("about")
	var intro := _add_card(box, "About Mimori")
	_add_hint(intro, "Mimori is a desktop companion designed to keep a little character close by while you work, browse, or relax.")
	_add_hint(intro, "Five companions are available: Echo the curious machine, Kairo the ninja cat, Lumen the gentle ghost, Miso the playful slime, and Vex the shadow creature.")

	var companions := _add_card(box, "A companion with a life of its own")
	_add_hint(companions, "Each pet has its own movement, moods, sleep, emotions, and signature animations. Rare moves and little reactions help each character feel distinct.")
	_add_hint(companions, "Choose another pet at any time from Appearance. Its personality and settings continue to shape how it behaves.")

	var controls := _add_card(box, "Made to fit your desktop")
	_add_hint(controls, "Mimori uses a transparent desktop window, so the companion can sit over your workspace. Adjust its size, opacity, movement, and sound from Settings.")
	_add_hint(controls, "Settings save automatically. A quiet ambient bed and sound effects play in the background.")

	var version := NeonLabel.make("MIMORI  ·  GODOT %s" % Engine.get_version_info().get("string", "4.x"), NeonLabel.Style.CAPTION)
	version.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	box.add_child(version)
	return box


func _build_page_help() -> VBoxContainer:
	var box := _new_page("help")
	var questions := [
		["How do I change my companion?", "Open Appearance and choose Echo, Kairo, Lumen, Miso, or Vex. The new pet appears right away."],
		["How do I change its personality?", "Open Interaction and select a personality. The selection takes effect immediately and stays selected after restarting."],
		["What does personality change?", "It affects how often your companion moves, thinks, dances, rests, and how quickly it responds."],
		["How do I play a signature move?", "Use Play a Special Move in Interaction. The animation and sound are specific to the selected pet and move."],
		["How do I make my pet follow the cursor?", "Turn on Follow cursor in Interaction. Turn it off there whenever you want."],
		["How do I dance?", "Choose Dance in Interaction to play the pet’s dance reaction."],
		["How do I change movement or jumping?", "Use Move speed, Gravity, and Jump strength in Interaction."],
		["How do I resize or fade my pet?", "Open Appearance and adjust Pet size or Pet Opacity."],
		["How do I keep the pet above other windows?", "Turn Always on top on or off in General."],
		["Where are the volume controls?", "Open General to adjust Master, Movement, Interactions, UI, and Music volume. Mute All silences every sound category."],
		["How can Mimori start with my computer?", "Turn on Launch at startup in General."],
		["How do I close Mimori?", "Choose Exit Mimori at the bottom of the Settings window."],
	]
	for question in questions:
		var answer_card := _add_card(box, str(question[0]))
		_add_hint(answer_card, str(question[1]))
	return box

func _on_feed_action() -> void:
	if pet != null:
		var interaction := pet.get_component(InteractionComponent) as InteractionComponent
		if interaction != null:
			interaction.feed()
	_flash_saved()


func _on_happy_action() -> void:
	_play_pet_action(PetState.State.HAPPY)


func _on_sad_action() -> void:
	_play_pet_action(PetState.State.SAD)


func _on_sleep_action() -> void:
	_play_pet_action(PetState.State.SLEEP)


func _on_dance_action() -> void:
	_play_pet_action(PetState.State.DANCE)


func _play_pet_action(state: PetState.State) -> void:
	if pet != null:
		var controller := pet.get_component(ContextMenuComponent) as ContextMenuComponent
		if controller != null:
			controller.play_action(state)
	_flash_saved()




## --- Value refresh -----------------------------------------------------------

func _refresh_all_values() -> void:
	_refresh_general()
	_refresh_audio()
	_refresh_behavior()
	_refresh_appearance()


func _set_slider(id: String, value: float) -> void:
	var slider := _sliders.get(id) as NeonSlider
	if slider != null:
		var range: Dictionary = _slider_ranges[id]
		slider.set_value_no_signal(_actual_to_slider_percent(id, value, float(range["min"]), float(range["max"])))


func _set_toggle(id: String, value: bool) -> void:
	var toggle := _toggles.get(id) as NeonToggle
	if toggle != null:
		toggle.set_pressed_no_signal(value)


func _refresh_general() -> void:
	_set_toggle("general.on_top", ConfigService.always_on_top)
	_set_toggle("general.login", ConfigService.launch_at_login)

	var follow_on := ConfigService.follow_cursor_enabled
	if pet != null:
		var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
		if follow != null:
			follow_on = follow.is_follow_enabled()
	_set_toggle("general.follow", follow_on)


func _refresh_audio() -> void:
	_set_slider("audio.master", AudioManager.get_master_volume_db())
	_set_toggle("audio.mute", AudioManager.is_muted())
	for category in SETTINGS_AUDIO_CATEGORIES:
		_set_slider("audio.cat.%d" % category, AudioManager.get_category_volume(category))
		_set_toggle("audio.mute.%d" % category, AudioManager.is_category_muted(category))


func _refresh_behavior() -> void:
	_refresh_special_move_hint()

	var installed := PersonalityCatalog.get_all()
	_personality_ids = PackedStringArray()
	for defn in installed:
		_personality_ids.append(defn.id)
	_rebuild_personality_cards(installed)

	var current_id := ""
	if pet != null:
		var component := pet.get_component(PersonalityComponent) as PersonalityComponent
		if component != null:
			current_id = component.get_personality_id()
	if current_id.is_empty():
		current_id = ConfigService.personality_id
	for personality_id in _personality_cards:
		(_personality_cards[personality_id] as NeonButton).set_toggled(personality_id == current_id)

	if _personality_hint != null:
		_personality_hint.visible = installed.is_empty()


func _rebuild_personality_cards(personalities: Array[PersonalityDefinition]) -> void:
	if _personality_grid == null:
		return
	for child in _personality_grid.get_children():
		child.queue_free()
	_personality_cards.clear()
	for definition in personalities:
		var button := NeonButton.new()
		button.configured(definition.display_name)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, 72)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.font_size = 18
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_personality_card_pressed.bind(definition.id))
		_personality_grid.add_child(button)
		_personality_cards[definition.id] = button


func _on_personality_card_pressed(personality_id: String) -> void:
	var index := _personality_ids.find(personality_id)
	if index < 0:
		return
	_on_personality_selected(index, personality_id)
	for id in _personality_cards:
		(_personality_cards[id] as NeonButton).set_toggled(id == personality_id)


func _refresh_appearance() -> void:
	_set_slider("general.scale", ConfigService.scale)
	_set_slider("appearance.opacity", ConfigService.window_opacity)
	var active_id := str(SettingsManager.get_setting("general.pet_id", PetRoster.DEFAULT_ID))
	if pet != null:
		active_id = pet.profile_id
	for profile_id in _pet_choice_buttons:
		(_pet_choice_buttons[profile_id] as NeonButton).set_toggled(profile_id == active_id)
	_refresh_pet_preview(active_id)


func _refresh_pet_preview(profile_id: String) -> void:
	var profile := PetRoster.get_profile(profile_id)
	if profile.is_empty():
		return
	var portrait := load(str(profile["portrait"])) as Texture2D
	if _pet_preview != null:
		_pet_preview.texture = portrait
	if _sidebar_pet_logo != null:
		_sidebar_pet_logo.texture = portrait
	if _pet_character_name != null:
		_pet_character_name.text = str(profile["name"])
	if _pet_character_description != null:
		_pet_character_description.text = str(profile.get("description", "A little companion for your desktop."))


func _on_pet_selected(index: int, _value: String) -> void:
	if index < 0 or index >= _pet_profile_ids.size():
		return
	var profile_id := _pet_profile_ids[index]
	if pet != null and pet.profile_id != profile_id:
		pet.set_profile(profile_id)
	SettingsManager.set_setting("general.pet_id", profile_id)
	_refresh_pet_preview(profile_id)
	_refresh_special_move_hint()
	_flash_saved()
	_refresh_appearance()
	_refresh_behavior()


func _on_pet_choice_pressed(index: int) -> void:
	if index < 0 or index >= _pet_profile_ids.size():
		return
	var names := PetRoster.get_names()
	_on_pet_selected(index, names[index])


func _refresh_special_move_hint() -> void:
	if _special_move_hint == null:
		return
	if pet == null:
		_special_move_hint.text = "No companion is active."
		return
	var moves := PetRoster.get_special_animations(pet.profile_id, pet.sprite.sprite_frames)
	if _special_move_button != null:
		var pet_name := str(PetRoster.get_profile(pet.profile_id).get("name", pet.profile_id.capitalize()))
		_special_move_button.set_label("Play %s's Special Move" % pet_name if not moves.is_empty() else "No Special Move Available")
	if moves.is_empty():
		_special_move_hint.text = "%s has no special move animation available yet." % str(PetRoster.get_profile(pet.profile_id).get("name", pet.profile_id.capitalize()))
		return
	var move_names := PackedStringArray()
	for move in moves:
		move_names.append(str(move["name"]))
	_special_move_hint.text = "%s: %s. Plays once." % [str(PetRoster.get_profile(pet.profile_id).get("name", pet.profile_id.capitalize())), ", ".join(move_names)]


func _on_play_special_move() -> void:
	if pet == null:
		_flash_status("No companion is active", Neon.DANGER)
		return
	var controller := pet.get_component(BehaviorController) as BehaviorController
	if controller != null and controller.play_special_move():
		_flash_status("Special move!", Neon.OK)
	else:
		_flash_status("Pet is busy; try again in a moment", Neon.DANGER)


## --- Header drag -------------------------------------------------------------

func _on_header_gui_input(event: InputEvent) -> void:
	var panel := get_node_or_null("Root/Panel") as Control
	if panel == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if _dragging:
				var panel_screen_origin := position + Vector2i(panel.position)
				_drag_offset = DisplayServer.mouse_get_position() - panel_screen_origin
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var panel_screen_origin := DisplayServer.mouse_get_position() - _drag_offset
		_move_panel_to_host_position(panel_screen_origin - position)
		get_viewport().set_input_as_handled()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


func _input_style(focused: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Neon.GLASS_STRONG
	style.border_color = Neon.accent if focused else Neon.PANEL_BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _apply_ui_theme(theme_id: String, persist: bool = true) -> void:
	OriTheme.apply(theme_id)
	Neon.apply_ori_palette(OriTheme.is_dark())
	transparent = true
	if persist and SettingsManager.has_setting("appearance.ui_theme"):
		SettingsManager.set_setting("appearance.ui_theme", OriTheme.mode)
	for id in _theme_buttons:
		var button := _theme_buttons[id] as NeonButton
		if button != null:
			button.accent_color = Neon.accent
			button.set_toggled(id == OriTheme.mode)
	if is_inside_tree():
		_refresh_theme_tree(self)
		_restore_screen_host_geometry()
		call_deferred("_restore_screen_host_geometry")
		var root_panel := _panel()
		if root_panel != null:
			root_panel.queue_redraw()
	if _status_label != null and persist:
		_flash_saved()


func _refresh_theme_tree(node: Node) -> void:
	if node is NeonLabel:
		(node as NeonLabel)._apply_style()
	elif node is NeonPanel:
		var panel := node as NeonPanel
		panel.tint = Neon.GLASS_STRONG if panel.name.begins_with("Card") else Neon.GLASS
		panel.rim = Neon.PANEL_BORDER
		panel._apply_style()
	elif node is NeonButton:
		(node as NeonButton).accent_color = Neon.accent
	elif node is NeonSlider:
		(node as NeonSlider).accent_color = Neon.accent
	elif node is NeonToggle:
		(node as NeonToggle).accent_color = Neon.accent
	elif node is LineEdit:
		var edit := node as LineEdit
		edit.add_theme_color_override("font_color", Neon.TEXT_MAIN)
		edit.add_theme_color_override("font_placeholder_color", Neon.TEXT_FAINT)
		edit.add_theme_font_size_override("font_size", roundi(16.0 * Neon.UI_SCALE * Neon.FONT_SCALE))
		edit.add_theme_font_override("font", Neon.font())
		edit.add_theme_stylebox_override("normal", _input_style())
		edit.add_theme_stylebox_override("focus", _input_style(true))
	elif node is ColorRect:
		var rect := node as ColorRect
		rect.color = Neon.PANEL_BORDER
	for child in node.get_children():
		_refresh_theme_tree(child)


func _on_pet_name_submitted(value: String) -> void:
	_save_pet_name(value)
	get_viewport().gui_release_focus()


func _save_pet_name(value: String) -> void:
	var clean := value.strip_edges()
	clean = clean if not clean.is_empty() else "Ori"
	SettingsManager.set_setting("general.pet_name", clean)
	if _sidebar_pet_name != null:
		_sidebar_pet_name.text = clean
	if _pet_name_input != null and _pet_name_input.text != clean:
		_pet_name_input.text = clean
	title = "Settings"
	_flash_saved()




func _on_ui_theme_button_toggled(pressed: bool, theme_id: String) -> void:
	if pressed:
		_apply_ui_theme(theme_id)




func _on_category_mute_toggled(pressed: bool, category: int) -> void:
	AudioManager.set_category_muted(category, pressed)
	_flash_saved()


## --- Handlers (live apply + persist) ----------------------------------------

func _on_scale_changed(value: float) -> void:
	value = clampf(value, 0.75, 1.25)
	var physics: PhysicsComponent = null
	if pet != null:
		physics = pet.get_component(PhysicsComponent) as PhysicsComponent
	ConfigService.scale = value
	if pet != null:
		pet.definition.scale = value
		if pet.visual != null:
			pet.visual.scale = Vector2(value, value)
		if physics != null:
			physics.snap_to_ground()
		pet.center_in_window()
	_flash_saved()


func _on_scale_percent_changed(value: float) -> void:
	_on_scale_changed(value / 100.0)


func _on_speed_changed(value: float) -> void:
	ConfigService.move_speed = value
	if pet != null:
		pet.definition.move_speed = value
	_flash_saved()


func _on_gravity_changed(value: float) -> void:
	ConfigService.gravity = value
	if pet != null:
		pet.definition.gravity = value
	_flash_saved()


func _on_jump_changed(value: float) -> void:
	ConfigService.jump_speed = value
	if pet != null:
		pet.definition.jump_speed = value
	_flash_saved()


func _on_always_on_top_toggled(pressed: bool) -> void:
	if desktop_window != null:
		desktop_window.apply_always_on_top(pressed)
	else:
		ConfigService.always_on_top = pressed
	_flash_saved()


func _on_launch_at_login_toggled(pressed: bool) -> void:
	ConfigService.set_launch_at_login(pressed)
	_flash_saved()


func _on_follow_cursor_toggled(pressed: bool) -> void:
	var follow: FollowCursorComponent = null
	if pet != null:
		follow = pet.get_component(FollowCursorComponent) as FollowCursorComponent
	if follow != null:
		follow.set_follow_enabled(pressed)
	else:
		ConfigService.set_follow_cursor_enabled(pressed)
	_flash_saved()


func _on_follow_tuning_changed(value: float, key: String) -> void:
	var saved_value: Variant = roundi(value) if key == "follow_cursor.max_jumps" else value
	SettingsManager.set_setting(key, saved_value)
	if pet != null:
		var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
		if follow != null:
			follow.reload_tuning_from_settings()
	_flash_saved()


func _on_master_volume_changed(value: float) -> void:
	AudioManager.set_master_volume_db(value)
	_flash_saved()


func _on_mute_toggled(pressed: bool) -> void:
	AudioManager.set_muted(pressed)
	_flash_saved()


func _on_category_volume_changed(value: float, category: int) -> void:
	AudioManager.set_category_volume(category, value)
	_flash_saved()



func _on_personality_selected(index: int, _value: String) -> void:
	if index < 0 or index >= _personality_ids.size():
		return
	var id := _personality_ids[index]
	var component: PersonalityComponent = null
	if pet != null:
		component = pet.get_component(PersonalityComponent) as PersonalityComponent
	if component != null:
		component.set_personality_by_id(id)
	else:
		ConfigService.set_personality_id(id)
	_flash_saved()


func _on_theme_selected(index: int, _value: String) -> void:
	if index < 0 or index >= _theme_ids.size():
		return
	_apply_theme(_theme_ids[index])


func _apply_theme(theme_id: String) -> void:
	if not ThemeManager.load_theme(theme_id):
		_flash_status("Theme unavailable", Neon.DANGER)
		return
	var theme := ThemeManager.get_theme(theme_id)
	if theme == null:
		_flash_status("Theme unavailable", Neon.DANGER)
		return
	if pet != null:
		if theme.sprite_pack != null:
			pet.definition.sprite_pack = theme.sprite_pack
		if theme.audio_pack != null:
			pet.definition.audio_pack = theme.audio_pack
		if not theme.default_personality_id.is_empty():
			pet.definition.default_personality_id = theme.default_personality_id
		pet._apply_sprite_pack()
	ConfigService.set_theme_id(theme_id)
	_flash_saved()


func _on_window_opacity_changed(value: float) -> void:
	if desktop_window != null:
		desktop_window.apply_window_opacity(value)
	else:
		ConfigService.window_opacity = value
		if pet != null and pet.visual != null:
			pet.visual.modulate.a = value
	_flash_saved()


func _on_opacity_percent_changed(value: float) -> void:
	_on_window_opacity_changed(value / 100.0)


func _on_quit_application() -> void:
	get_tree().quit()


## --- Page reset --------------------------------------------------------------

func _on_reset_page() -> void:
	match _current_page:
		"general":
			_reset_general()
		"interaction":
			_reset_behavior()
		"appearance":
			_reset_appearance()
	_refresh_all_values()
	_flash_status("Page reset")


func _reset_general() -> void:
	_save_pet_name("Ori")
	_emit_toggle("general.on_top", true)
	_emit_toggle("general.login", false)
	_emit_slider("audio.master", 0.0)
	_emit_toggle("audio.mute", false)
	for category in SETTINGS_AUDIO_CATEGORIES:
		_emit_slider("audio.cat.%d" % category, 0.0)
		_emit_toggle("audio.mute.%d" % category, false)


func _reset_behavior() -> void:
	_emit_toggle("general.follow", false)
	var default_id := PersonalityCatalog.get_default_id()
	var index := _personality_ids.find(default_id)
	if index >= 0:
		_on_personality_selected(index, "")


func _reset_appearance() -> void:
	_apply_ui_theme(OriTheme.BRIGHT)
	_emit_slider("general.scale", 1.0)
	_emit_slider("appearance.opacity", 1.0)


func _emit_slider(id: String, value: float) -> void:
	var slider := _sliders.get(id) as NeonSlider
	if slider != null:
		var range: Dictionary = _slider_ranges[id]
		var percent := _actual_to_slider_percent(id, value, float(range["min"]), float(range["max"]))
		slider.set_value(percent)


func _emit_toggle(id: String, value: bool) -> void:
	var toggle := _toggles.get(id) as NeonToggle
	if toggle != null:
		toggle.set_pressed(value)


## --- Maintenance actions -----------------------------------------------------

func _on_reset_session() -> void:
	StatisticsManager.reset_session()
	_flash_status("Session stats reset")


func _on_open_saves() -> void:
	var dir := ProjectSettings.globalize_path("user://")
	if DirAccess.open("user://") != null:
		OS.shell_open(dir)
		_flash_status("Opened saves folder")
	else:
		_flash_status("Saves folder unavailable", Neon.DANGER)


func _on_save_settings() -> void:
	SettingsManager.save_settings()
	if pet != null:
		ConfigService.save_data(pet.world_position)
	_flash_status("Saved now")


## --- Status ------------------------------------------------------------------

func _flash_saved() -> void:
	_flash_status("Saved")


func _flash_status(text: String, color: Color = Neon.OK) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", color)
	_status_reset_left = 1.4


func _process(delta: float) -> void:
	if _status_reset_left <= 0.0:
		return
	_status_reset_left -= delta
	if _status_reset_left <= 0.0 and _status_label != null:
		_status_label.text = "Auto-saved"
		_status_label.add_theme_color_override("font_color", Neon.TEXT_FAINT)
