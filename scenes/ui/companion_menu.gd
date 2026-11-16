extends Window
class_name CompanionMenu

## The neon right-click companion menu. Renders as a transparent, borderless
## OS window floating beside the pet: a glass card with the LYRIA brand mark,
## toggle row (Follow Cursor), an Actions group (Happy / Think /
## Dance / Sleep), then Settings / About / Exit. Pure custom drawing via the
## neon kit - no Godot menu theme involved.
##
## Contract: the context menu component drives this window. It calls
## open_menu(screen_pos) and listens to item_pressed(id); the ids mirror the
## legacy ContextMenuComponent ids so the existing dispatch logic keeps working
## unchanged. Toggle rows report their state through the same id press so the
## owner can flip Follow Cursor, then the row is refreshed via
## set_toggle_state().

signal item_pressed(id: int)

const MENU_WIDTH := 236.0
const ROW_H := 34.0

## Ids kept identical to ContextMenuComponent's legacy ids.
const FOLLOW_CURSOR_ID := 85
const FEED_ID := 45
const SETTINGS_ID := 50
const QUIT_ID := 100
const ABOUT_ID := 110

## Action states (spec: Happy / Think / Dance / Sleep) map to pet states.
const ACTIONS := [
	{"id": 20, "label": "Happy", "state": PetState.State.HAPPY},
	{"id": 21, "label": "Think", "state": PetState.State.THINK},
	{"id": 22, "label": "Dance", "state": PetState.State.DANCE},
	{"id": 23, "label": "Sleep", "state": PetState.State.SLEEP},
]

var _root_box: VBoxContainer
var _follow_button: NeonButton


func _ready() -> void:
	transparent = true
	borderless = true
	unresizable = true
	always_on_top = true
	exclusive = false
	unfocusable = false
	transient = false
	focus_exited.connect(close_menu)
	_build()
	## Start off-screen so the never-instantiated menu never flashes.
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := NeonPanel.new()
	panel.glass_panel(Neon.GLASS, Neon.RADIUS, 10)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)
	_root_box = box

	_add_brand()

	## Separator
	box.add_child(_separator())

	## Toggle rows
	_follow_button = _add_row("Follow Cursor", FOLLOW_CURSOR_ID, true)
	box.add_child(_follow_button)

	box.add_child(_separator())

	## Actions group (submenu-style: header + indented items)
	box.add_child(_add_section("Actions"))
	for action in ACTIONS:
		box.add_child(_add_action_row(action))

	box.add_child(_separator())

	## Feed (existing functionality preserved)
	box.add_child(_add_row("Feed", FEED_ID, false))

	box.add_child(_separator())

	box.add_child(_add_row("Settings", SETTINGS_ID, false))
	box.add_child(_add_row("About", ABOUT_ID, false))

	box.add_child(_separator())
	box.add_child(_add_row("Exit", QUIT_ID, false))

	## Size the window from the content.
	var min_size := box.get_combined_minimum_size()
	min_size.x = maxf(min_size.x, MENU_WIDTH) + 20.0
	min_size.y += 16.0
	size = Vector2i(int(min_size.x), int(min_size.y))
	min_size = size

	## Force layout pass so rows measure correctly.
	root.reset_size()


func _add_brand() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 26.0

	var dot := Control.new()
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	dot.draw.connect(func() -> void:
		dot.draw_circle(Vector2(4, 4), 3.0, Neon.OK)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.3, 0.95, 0.7, 0.25)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(1)
		sb.border_color = Neon.OK
		dot.draw_style_box(sb, Rect2(0, 0, 8, 8))
	)

	var title := NeonLabel.make("LYRIA", NeonLabel.Style.HEADER)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)

	var tag := NeonLabel.make("companion", NeonLabel.Style.CAPTION)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	_root_box.add_child(row)


func _add_section(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := NeonLabel.make(text.to_upper(), NeonLabel.Style.CAPTION)
	label.add_theme_color_override("font_color", Neon.TEXT_FAINT)
	row.add_child(label)
	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.custom_minimum_size = Vector2(0, 1)
	row.add_child(line)
	return row


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _add_row(label: String, id: int, is_toggle: bool) -> NeonButton:
	var btn := NeonButton.new()
	btn.configured(label)
	btn.custom_minimum_size = Vector2(0, ROW_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.toggle_mode = is_toggle
	btn.pressed.connect(_on_row_pressed.bind(id, btn))
	if is_toggle:
		btn.toggled.connect(_on_toggle.bind(id, btn))
	return btn


## Action rows are indented under the Actions header; pressing triggers the
## matching manual pet state via the same id dispatch.
func _add_action_row(action: Dictionary) -> NeonButton:
	var btn := NeonButton.new()
	btn.configured(action["label"])
	btn.custom_minimum_size = Vector2(0, ROW_H)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_constant_override("hseparation", 18)
	btn.pressed.connect(_on_row_pressed.bind(int(action["id"]), btn))
	return btn


func _on_row_pressed(id: int, btn: NeonButton) -> void:
	## Toggle rows report through toggled(); plain rows close the menu.
	if btn.toggle_mode:
		return
	item_pressed.emit(id)
	close_menu()


func _on_toggle(state: bool, id: int, _btn: NeonButton) -> void:
	item_pressed.emit(id)
	## Keep the menu open so the user can chain actions.


func set_toggle_state(id: int, state: bool) -> void:
	var btn: NeonButton
	match id:
		FOLLOW_CURSOR_ID:
			btn = _follow_button
		_:
			return
	if btn != null:
		btn.set_toggled(state)


## Opens the menu beside the given desktop cursor position, clamped to the
## usable screen area so it never pops up off-screen.
func open_menu(screen_pos: Vector2i) -> void:
	if not is_inside_tree():
		return
	position = screen_pos - Vector2i(0, 8)
	_resolve_position()
	show()
	Neon.pop_in(_root_box.get_parent())
	grab_focus()


func _resolve_position() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position.x = clampi(position.x, usable.position.x + 4, usable.position.x + usable.size.x - size.x - 4)
	position.y = clampi(position.y, usable.position.y + 4, usable.position.y + usable.size.y - size.y - 4)


func close_menu() -> void:
	hide()
