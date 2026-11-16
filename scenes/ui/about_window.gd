extends Window
class_name AboutWindow

## Glass about dialog for the companion: LYRIA brand, version, a short
## descriptor, and an OK button. Transparent borderless window like the
## companion menu - pure neon kit drawing.

const MENU_WIDTH := 360.0

var _root_box: VBoxContainer


func _ready() -> void:
	transparent = true
	borderless = true
	unresizable = true
	always_on_top = true
	exclusive = false
	unfocusable = false
	transient = false
	focus_exited.connect(close_about)
	_build()
	hide()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := NeonPanel.new()
	panel.glass_panel(Neon.GLASS, Neon.RADIUS, 22)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	_root_box = box

	var brand_row := HBoxContainer.new()
	brand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	var brand := NeonLabel.make("LYRIA", NeonLabel.Style.HEADER)
	brand.add_theme_font_size_override("font_size", 30)
	brand_row.add_child(brand)
	box.add_child(brand_row)

	var sub := NeonLabel.make("A NEON COMPANION", NeonLabel.Style.CAPTION)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	box.add_child(_separator())

	var desc := NeonLabel.make(
		"Lyria is a tiny desktop pet that lives on your screen - walking,\n"
		+ "thinking, dozing and dancing through its own little day. Right-click\n"
		+ "your companion to open the menu.",
		NeonLabel.Style.BODY
	)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(MENU_WIDTH - 56.0, 0)
	box.add_child(desc)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)

	var version := NeonLabel.make(_version_string(), NeonLabel.Style.MONO)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(version)

	var ok := NeonButton.new()
	ok.configured("OK", "")
	ok.custom_minimum_size = Vector2(120, 34)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(close_about)
	box.add_child(ok)

	var min_size := box.get_combined_minimum_size()
	min_size.x = maxf(min_size.x, MENU_WIDTH) + 20.0
	min_size.y += 16.0
	size = Vector2i(int(min_size.x), int(min_size.y))
	min_size = size
	root.reset_size()


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Neon.PANEL_BORDER
	line.custom_minimum_size = Vector2(0, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _version_string() -> String:
	var v := Engine.get_version_info()
	var engine_str := "Godot %s" % v.get("string", "4.x")
	return "LYRIA v0.1.0  -  %s" % engine_str


func open_about(screen_pos: Vector2i) -> void:
	if not is_inside_tree():
		return
	position = screen_pos
	_resolve_position()
	show()
	Neon.pop_in(_root_box.get_parent())
	grab_focus()


func close_about() -> void:
	hide()


func _resolve_position() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	position.x = clampi(position.x, usable.position.x + 4, usable.position.x + usable.size.x - size.x - 4)
	position.y = clampi(position.y, usable.position.y + 4, usable.position.y + usable.size.y - size.y - 4)
