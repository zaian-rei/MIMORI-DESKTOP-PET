extends Node

## Developer Debug Overlay. Devs only - the overlay never runs in a release
## build unless the saved prefs explicitly enable it (see _compute_available).
##
## Design contract:
##   - It ONLY displays. Every subsystem exposes its own lightweight debug
##     interface via get_debug_info() (see PetComponent's default); the
##     manager never reads subsystem internals and never reaches into
##     components beyond that public method and a handful of existing public
##     controls (force_state / request / autonomy_locked / setters).
##   - Near-zero overhead when off: no _process, no string formatting, no UI.
##     The window is created lazily on first show, and the refresh timer runs
##     only while the window is visible.
##   - Prefs (enabled, scale, opacity, refresh rate, hotkey, visible
##     sections, visual-debug toggles) persist through ConfigService.

const DEFAULT_PREFS := {
	"enabled": true,
	"scale": 1.0,
	"opacity": 0.92,
	"refresh_rate": 4.0,
	"hotkey": "F8",
	"visible_sections": {},
	"visual_debug": {
		"ground": false,
		"safe_area": false,
		"cursor": false,
		"arrival_radius": false,
		"screen_bounds": false,
	},
}

const HOTKEY_CHOICES := ["F7", "F8", "F9", "F10", "Ctrl+Shift+D"]
const REFRESH_CHOICES := [2.0, 4.0, 8.0, 16.0, 30.0]

const VISUAL_TOGGLES := [
	{"id": "ground", "label": "Ground"},
	{"id": "safe_area", "label": "Safe Area"},
	{"id": "cursor", "label": "Cursor"},
	{"id": "arrival_radius", "label": "Arrival"},
	{"id": "screen_bounds", "label": "Bounds"},
]

## Ordered data sections. "kind" selects how the data is produced:
##   general    - engine/display snapshot (no pet required)
##   components - pet.get_component() for each provider script, called via
##                its public get_debug_info()
##   autoload   - a method on this manager that reads a global singleton
var SECTION_DEFS := [
	{"id": "general", "title": "General", "kind": "general"},
	{"id": "state_machine", "title": "State Machine", "kind": "components", "providers": [StateMachineComponent]},
	{"id": "animation", "title": "Animation", "kind": "components", "providers": [AnimationTransitionManager, AnimationComponent]},
	{"id": "movement", "title": "Movement", "kind": "components", "providers": [MovementComponent, MovementPolishComponent]},
	{"id": "follow_cursor", "title": "Follow Cursor", "kind": "components", "providers": [FollowCursorComponent]},
	{"id": "behavior_stats", "title": "Behavior Stats", "kind": "components", "providers": [BehaviorStatsComponent]},
	{"id": "utility_ai", "title": "Utility AI", "kind": "components", "providers": [BehaviorDecisionComponent, BehaviorPolishComponent]},
	{"id": "memory", "title": "Memory", "kind": "components", "providers": [BehaviorMemoryComponent]},
	{"id": "personality", "title": "Personality", "kind": "components", "providers": [PersonalityComponent]},
	{"id": "desktop", "title": "Desktop", "kind": "components", "providers": [DesktopAwarenessComponent]},
	{"id": "audio", "title": "Audio", "kind": "autoload", "getter": "_audio_debug"},
	{"id": "save_system", "title": "Save System", "kind": "autoload", "getter": "_save_debug"},
	{"id": "statistics", "title": "Statistics", "kind": "autoload", "getter": "_statistics_debug"},
	{"id": "settings", "title": "Settings", "kind": "autoload", "getter": "_settings_debug"},
	{"id": "theme", "title": "Theme", "kind": "autoload", "getter": "_theme_debug"},
	{"id": "event_bus", "title": "Event Bus", "kind": "autoload", "getter": "_event_bus_debug"},
	{"id": "plugins", "title": "Plugins", "kind": "autoload", "getter": "_plugins_debug"},
]

var _prefs: Dictionary = {}
var _available := false
var _pet: Pet
var _draw_node: DebugDraw

var _window: Window
var _content: VBoxContainer
var _root_box: VBoxContainer
var _timer: Timer

## --- Controls-panel widget handles (built once; data sections rebuild) -----

var _pause_button: Button
var _behavior_option: OptionButton
var _animation_option: OptionButton
var _hotkey_option: OptionButton
var _hotkey_hint: Label
var _scale_slider: HSlider
var _opacity_slider: HSlider
var _refresh_option: OptionButton
var _draw_checks: Dictionary = {}
var _section_checks: Dictionary = {}


func _ready() -> void:
	_apply_prefs()
	_available = _compute_available()
	set_process_unhandled_input(_available)
	LoggerGlobal.info(
		"DebugOverlayManager initialized (%s)." % ("available" if _available else "unavailable")
	)


## Bootstrap hands the pet over after instantiating it. Sets up the visual
## debug layer and shows the overlay on startup when the pref says so.
func register_pet(pet: Pet) -> void:
	_pet = pet
	if not _available:
		return
	_setup_draw_node()
	if bool(_prefs.get("enabled", false)):
		_show()


## --- Release gating ---------------------------------------------------------

## In debug/editor builds the overlay is always available. In release builds
## it stays inert unless the persisted pref explicitly enables it.
func _compute_available() -> bool:
	return OS.is_debug_build() or bool(_prefs.get("enabled", false))


## --- Prefs ------------------------------------------------------------------

func _apply_prefs() -> void:
	_prefs = DEFAULT_PREFS.duplicate(true)
	var saved: Dictionary = ConfigService.debug_overlay if ConfigService != null else {}
	if typeof(saved) != TYPE_DICTIONARY or saved.is_empty():
		return
	for key in saved:
		if typeof(_prefs.get(key, null)) == TYPE_DICTIONARY:
			var merged: Dictionary = _prefs[key].duplicate(true)
			var incoming: Dictionary = saved[key]
			if typeof(incoming) == TYPE_DICTIONARY:
				for sub in incoming:
					merged[sub] = incoming[sub]
			_prefs[key] = merged
		else:
			_prefs[key] = saved[key]


func _save_prefs() -> void:
	if ConfigService != null:
		ConfigService.set_debug_overlay(_prefs.duplicate(true))


func _section_visible(id: String) -> bool:
	var visible: Dictionary = _prefs.get("visible_sections", {})
	if visible.is_empty():
		return true
	return bool(visible.get(id, true))


## --- Input (hotkey) ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not _available:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var combo := str(_prefs.get("hotkey", "F8"))
	var key_part := combo
	var need_ctrl := false
	var need_shift := false
	if combo.begins_with("Ctrl+Shift+"):
		need_ctrl = true
		need_shift = true
		key_part = combo.trim_prefix("Ctrl+Shift+")
	elif combo.begins_with("Ctrl+"):
		need_ctrl = true
		key_part = combo.trim_prefix("Ctrl+")
	var code := OS.find_keycode_from_string(key_part)
	if event.keycode == code and event.ctrl_pressed == need_ctrl and event.shift_pressed == need_shift:
		toggle()
		get_viewport().set_input_as_handled()


## --- Show / hide ------------------------------------------------------------

func toggle() -> void:
	if is_enabled():
		_hide()
	else:
		_show()


## Explicit setter for UI controls. Unlike toggle(), this is idempotent and
## safe to call from a settings checkbox: the requested state always wins,
## even when the window's visibility and the persisted preference disagree.
func set_enabled(value: bool) -> void:
	if value:
		_show()
	else:
		_hide()


func is_enabled() -> bool:
	return _window != null and _window.visible


func _show() -> void:
	_ensure_window()
	if not bool(_prefs.get("enabled", false)):
		_prefs["enabled"] = true
		_save_prefs()
	_start_refresh_timer()
	_refresh()
	call_deferred("_apply_show")


## Runs after the window is actually added to the tree (deferred, since the
## manager's first show may happen while bootstrap's _ready is still running).
func _apply_show() -> void:
	if _window == null:
		return
	if _window.is_inside_tree():
		_window.show()
		_window.grab_focus()
	_refresh()


func _hide() -> void:
	_stop_refresh_timer()
	if _window != null:
		_window.hide()
	if bool(_prefs.get("enabled", false)):
		_prefs["enabled"] = false
		_save_prefs()


## --- Window / UI construction -----------------------------------------------

func _ensure_window() -> void:
	if _window != null:
		return
	var scale := clampf(_prefs.get("scale", 1.0), 0.5, 3.0)
	var base_size := Vector2i(480, 720)

	_window = Window.new()
	_window.title = "Debug Overlay"
	_window.min_size = Vector2i(base_size * scale)
	_window.size = base_size * scale
	_window.always_on_top = true
	_window.close_requested.connect(_hide)
	_window.content_scale_factor = scale
	## Deferred: the first show can happen while bootstrap's _ready is still
	## running, and the root viewport refuses add_child() mid-setup.
	get_tree().root.add_child.call_deferred(_window)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.07, 0.08, 0.10, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_window.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_window.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.name = "RootBox"
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)
	_root_box = root_box

	root_box.add_child(_build_controls())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_box.add_child(scroll)

	_content = VBoxContainer.new()
	_content.name = "Sections"
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_content)

	root_box.modulate = Color(1.0, 1.0, 1.0, clampf(_prefs.get("opacity", 0.92), 0.2, 1.0))
	_root_box = root_box


func _build_controls() -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.17, 1.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	## Header row
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "Pet Debug"
	title.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	header.add_child(title)
	_hotkey_hint = Label.new()
	_hotkey_hint.text = "Hotkey: %s" % _prefs.get("hotkey", "F8")
	header.add_child(_hotkey_hint)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	_pause_button = Button.new()
	_pause_button.text = "Pause AI"
	_pause_button.toggle_mode = true
	_pause_button.toggled.connect(_on_pause_toggled)
	header.add_child(_pause_button)
	var reload_button := Button.new()
	reload_button.text = "Reload Settings"
	reload_button.pressed.connect(_reload_settings)
	header.add_child(reload_button)
	var close_button := Button.new()
	close_button.text = "Hide"
	close_button.pressed.connect(_hide)
	header.add_child(close_button)
	vbox.add_child(header)

	## Force behavior / animation row
	var force_row := HBoxContainer.new()
	force_row.add_theme_constant_override("separation", 6)
	var force_label := Label.new()
	force_label.text = "Force:"
	force_row.add_child(force_label)
	_behavior_option = OptionButton.new()
	for state in PetState.State.values():
		_behavior_option.add_item(PetState.State.keys()[state], state)
	force_row.add_child(_behavior_option)
	var force_behavior_button := Button.new()
	force_behavior_button.text = "Behavior"
	force_behavior_button.pressed.connect(_force_behavior)
	force_row.add_child(force_behavior_button)
	_animation_option = OptionButton.new()
	_animation_option.add_item("(auto)", 0)
	force_row.add_child(_animation_option)
	var force_animation_button := Button.new()
	force_animation_button.text = "Animation"
	force_animation_button.pressed.connect(_force_animation)
	force_row.add_child(force_animation_button)
	var reset_stats_button := Button.new()
	reset_stats_button.text = "Reset Stats"
	reset_stats_button.pressed.connect(_reset_stats)
	force_row.add_child(reset_stats_button)
	var reset_memory_button := Button.new()
	reset_memory_button.text = "Reset Memory"
	reset_memory_button.pressed.connect(_reset_memory)
	force_row.add_child(reset_memory_button)
	vbox.add_child(force_row)

	## Statistics reset row
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 6)
	var stats_label := Label.new()
	stats_label.text = "Stats:"
	stats_row.add_child(stats_label)
	var reset_session_button := Button.new()
	reset_session_button.text = "Reset Session"
	reset_session_button.pressed.connect(_reset_session_stats)
	stats_row.add_child(reset_session_button)
	var reset_lifetime_button := Button.new()
	reset_lifetime_button.text = "Reset Lifetime"
	reset_lifetime_button.pressed.connect(_reset_lifetime_stats)
	stats_row.add_child(reset_lifetime_button)
	vbox.add_child(stats_row)

	## Visual debug toggles
	var visual_row := HBoxContainer.new()
	visual_row.add_theme_constant_override("separation", 6)
	var visual_label := Label.new()
	visual_label.text = "Visual:"
	visual_row.add_child(visual_label)
	var visual_prefs: Dictionary = _prefs.get("visual_debug", {})
	for toggle in VISUAL_TOGGLES:
		var check := CheckBox.new()
		check.text = toggle["label"]
		check.button_pressed = bool(visual_prefs.get(toggle["id"], false))
		check.toggled.connect(_on_draw_toggle.bind(toggle["id"]))
		_draw_checks[toggle["id"]] = check
		visual_row.add_child(check)
	vbox.add_child(visual_row)

	## Scale / opacity / refresh
	var tune_row := HBoxContainer.new()
	tune_row.add_theme_constant_override("separation", 6)
	var scale_label := Label.new()
	scale_label.text = "Scale"
	tune_row.add_child(scale_label)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = 0.6
	_scale_slider.max_value = 2.0
	_scale_slider.step = 0.05
	_scale_slider.custom_minimum_size = Vector2(90, 0)
	_scale_slider.value = _prefs.get("scale", 1.0)
	_scale_slider.value_changed.connect(_on_scale_changed)
	tune_row.add_child(_scale_slider)
	var opacity_label := Label.new()
	opacity_label.text = "Opacity"
	tune_row.add_child(opacity_label)
	_opacity_slider = HSlider.new()
	_opacity_slider.min_value = 0.25
	_opacity_slider.max_value = 1.0
	_opacity_slider.step = 0.05
	_opacity_slider.custom_minimum_size = Vector2(90, 0)
	_opacity_slider.value = _prefs.get("opacity", 0.92)
	_opacity_slider.value_changed.connect(_on_opacity_changed)
	tune_row.add_child(_opacity_slider)
	var refresh_label := Label.new()
	refresh_label.text = "Refresh"
	tune_row.add_child(refresh_label)
	_refresh_option = OptionButton.new()
	for hz in REFRESH_CHOICES:
		_refresh_option.add_item("%d Hz" % int(hz))
	_refresh_option.select(REFRESH_CHOICES.find(_prefs.get("refresh_rate", 4.0)))
	_refresh_option.item_selected.connect(_on_refresh_changed)
	tune_row.add_child(_refresh_option)
	_hotkey_option = OptionButton.new()
	for combo in HOTKEY_CHOICES:
		_hotkey_option.add_item(combo)
	var hotkey_index := HOTKEY_CHOICES.find(str(_prefs.get("hotkey", "F8")))
	_hotkey_option.select(maxi(hotkey_index, 0))
	_hotkey_option.item_selected.connect(_on_hotkey_changed)
	tune_row.add_child(_hotkey_option)
	vbox.add_child(tune_row)

	## Section visibility toggles
	var sections_row := HBoxContainer.new()
	sections_row.add_theme_constant_override("separation", 6)
	var sections_label := Label.new()
	sections_label.text = "Sections:"
	sections_row.add_child(sections_label)
	var flow := FlowContainer.new()
	flow.custom_minimum_size = Vector2(0, 0)
	for def in SECTION_DEFS:
		var check := CheckBox.new()
		check.text = def["title"]
		check.button_pressed = _section_visible(def["id"])
		check.toggled.connect(_on_section_toggled.bind(def["id"]))
		_section_checks[def["id"]] = check
		flow.add_child(check)
	sections_row.add_child(flow)
	vbox.add_child(sections_row)

	return panel


## --- Refresh ----------------------------------------------------------------

func _start_refresh_timer() -> void:
	if _timer == null:
		_timer = Timer.new()
		add_child(_timer)
		_timer.timeout.connect(_refresh)
	_timer.wait_time = 1.0 / clampf(_prefs.get("refresh_rate", 4.0), 0.5, 60.0)
	_timer.start()


func _stop_refresh_timer() -> void:
	if _timer != null:
		_timer.stop()


func _refresh() -> void:
	if _content == null or _window == null or not _window.visible:
		return
	for child in _content.get_children():
		_content.remove_child(child)
		child.free()
	for def in SECTION_DEFS:
		if not _section_visible(def["id"]):
			continue
		_content.add_child(_build_section(def["title"], _section_data(def)))
	_update_controls_state()


## --- Section data -----------------------------------------------------------

func _section_data(def: Dictionary) -> Dictionary:
	match def["kind"]:
		"general":
			return _general_data()
		"components":
			return _components_data(def["providers"])
		"autoload":
			return call(def["getter"])
	return {}


func _general_data() -> Dictionary:
	var fps := Engine.get_frames_per_second()
	var version := Engine.get_version_info()
	var build_type := "Release"
	if OS.has_feature("editor"):
		build_type = "Editor"
	elif OS.is_debug_build():
		build_type = "Debug"
	return {
		"fps": fps,
		"frame_time_ms": 1000.0 / maxf(fps, 0.001),
		"engine_version": version.get("string", ""),
		"build_type": build_type,
		"os": OS.get_name(),
		"overlay_available": _available,
		"monitor": DisplayServer.window_get_current_screen(),
		"window_position": DisplayServer.window_get_position(),
		"window_size": DisplayServer.window_get_size(),
		"desktop_scale": DisplayServer.screen_get_scale(),
	}


func _components_data(providers: Array) -> Dictionary:
	if _pet == null:
		return {"pet": "not registered"}
	var out := {}
	for script in providers:
		var component := _pet.get_component(script)
		if component == null:
			out[script.resource_path.get_file()] = "missing"
		elif component.has_method("get_debug_info"):
			out[script.resource_path.get_file()] = component.get_debug_info()
	return out


func _audio_debug() -> Dictionary:
	if AudioManager == null:
		return {"audio_manager": "unavailable"}
	return AudioManager.get_debug_info()


func _save_debug() -> Dictionary:
	if ConfigService == null:
		return {"config_service": "unavailable"}
	return ConfigService.get_debug_info()


func _statistics_debug() -> Dictionary:
	if StatisticsManager == null:
		return {"statistics_manager": "unavailable"}
	return StatisticsManager.get_debug_info()


func _settings_debug() -> Dictionary:
	if SettingsManager == null:
		return {"settings_manager": "unavailable"}
	return SettingsManager.get_debug_info()


func _theme_debug() -> Dictionary:
	if ThemeManager == null:
		return {"theme_manager": "unavailable"}
	return ThemeManager.get_debug_info()


func _event_bus_debug() -> Dictionary:
	if EventBus == null:
		return {"event_bus": "unavailable"}
	return EventBus.get_debug_info()


func _plugins_debug() -> Dictionary:
	if PluginManager == null:
		return {"plugin_manager": "unavailable"}
	return PluginManager.get_debug_info()


## --- Section rendering ------------------------------------------------------

func _build_section(title: String, data: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.17, 1.0)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	title_label.add_theme_font_size_override("font_size", 15)
	vbox.add_child(title_label)

	_add_data_rows(vbox, data, 0)
	return panel


func _add_data_rows(parent: VBoxContainer, data: Dictionary, indent: int) -> void:
	for key in data:
		var value = data[key]
		if value is Dictionary:
			_add_row(parent, str(key), "", indent, true)
			_add_data_rows(parent, value, indent + 1)
		else:
			_add_row(parent, str(key), _format_value(value), indent, false)


func _add_row(parent: VBoxContainer, key: String, value: String, indent: int, is_header: bool) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var key_label := Label.new()
	key_label.text = "  ".repeat(indent) + key
	key_label.custom_minimum_size = Vector2(170, 0)
	key_label.add_theme_font_size_override("font_size", 13)
	if is_header:
		key_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
	row.add_child(key_label)

	var value_label := Label.new()
	value_label.text = value
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.add_theme_font_size_override("font_size", 13)
	row.add_child(value_label)

	parent.add_child(row)


func _format_value(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_FLOAT:
			return "%.3f" % value
		TYPE_INT:
			return str(value)
		TYPE_VECTOR2:
			return "(%.1f, %.1f)" % [value.x, value.y]
		TYPE_VECTOR2I:
			return "(%d, %d)" % [value.x, value.y]
		TYPE_RECT2:
			return "(pos %.1f,%.1f size %.1fx%.1f)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_RECT2I:
			return "(pos %d,%d size %dx%d)" % [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_COLOR:
			return value.to_html(false)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			var parts: Array[String] = []
			for item in value:
				parts.append(str(item))
			return ", ".join(parts)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value)
		TYPE_OBJECT:
			if value is Resource and value.resource_path != "":
				return value.resource_path
			if value != null:
				return value.get_class()
			return "null"
		TYPE_NIL:
			return "null"
		_:
			return str(value)


## --- Controls actions -------------------------------------------------------

func _update_controls_state() -> void:
	if _pet == null:
		return
	if _animation_option != null and _animation_option.item_count == 1 \
			and _pet.sprite != null and _pet.sprite.sprite_frames != null:
		for name in _pet.sprite.sprite_frames.get_animation_names():
			_animation_option.add_item(name)
	if _pause_button != null:
		var controller := _pet.get_component(BehaviorController)
		var locked: bool = controller.autonomy_locked if controller != null else false
		_pause_button.set_pressed_no_signal(locked)
		_pause_button.text = "Resume AI" if locked else "Pause AI"


func _on_pause_toggled(pressed: bool) -> void:
	var controller := _pet.get_component(BehaviorController) if _pet != null else null
	if controller != null:
		controller.autonomy_locked = pressed
	if pressed and _pet != null:
		_pet.get_component(StateMachineComponent).force_state(PetState.State.IDLE)
	_pause_button.text = "Resume AI" if pressed else "Pause AI"


func _force_behavior() -> void:
	if _pet == null or _behavior_option == null:
		return
	var state := _behavior_option.get_item_id(_behavior_option.selected)
	if state < 0:
		return
	_pet.get_component(StateMachineComponent).force_state(state)


func _force_animation() -> void:
	if _pet == null or _animation_option == null:
		return
	var name := _animation_option.get_item_text(_animation_option.selected)
	if name == "" or name == "(auto)":
		return
	var manager := _pet.get_component(AnimationTransitionManager)
	if manager != null:
		manager.request(_pet.get_component(StateMachineComponent).get_state(), name)


func _reset_stats() -> void:
	if _pet == null:
		return
	var stats := _pet.get_component(BehaviorStatsComponent)
	if stats == null:
		return
	for stat in PetStats.Stat.values():
		stats.set_value(stat, stats.get_stat_default(stat))
	LoggerGlobal.info("DebugOverlay: stats reset to defaults.")


func _reset_memory() -> void:
	if _pet == null:
		return
	var memory := _pet.get_component(BehaviorMemoryComponent)
	if memory == null:
		return
	memory.reset_session_memory()
	LoggerGlobal.info("DebugOverlay: memory reset.")


func _reset_session_stats() -> void:
	if StatisticsManager == null:
		return
	StatisticsManager.reset_session()
	LoggerGlobal.info("DebugOverlay: statistics session reset.")


func _reset_lifetime_stats() -> void:
	if StatisticsManager == null:
		return
	StatisticsManager.reset_lifetime()
	LoggerGlobal.info("DebugOverlay: statistics lifetime reset.")


func _reload_settings() -> void:
	if _pet == null:
		return
	ConfigService.load_data()
	_pet.definition.move_speed = ConfigService.move_speed
	_pet.definition.gravity = ConfigService.gravity
	_pet.definition.jump_speed = ConfigService.jump_speed
	_pet.definition.scale = ConfigService.scale
	_pet.visual.scale = Vector2(ConfigService.scale, ConfigService.scale)
	var desktop_window := _pet.desktop_window
	if desktop_window != null:
		desktop_window.apply_always_on_top(ConfigService.always_on_top)
	var follow := _pet.get_component(FollowCursorComponent)
	if follow != null:
		follow.set_follow_enabled(ConfigService.follow_cursor_enabled)
	var personality := _pet.get_component(PersonalityComponent)
	if personality != null and ConfigService.personality_id != "":
		personality.set_personality_by_id(ConfigService.personality_id)
	AudioManager.set_master_volume_db(ConfigService.master_volume_db)
	AudioManager.set_muted(ConfigService.muted)
	for category in AudioCategory.all():
		AudioManager.set_category_volume(category, ConfigService.get_category_volume(category))
	LoggerGlobal.info("DebugOverlay: settings reloaded from save.")


func _on_draw_toggle(pressed: bool, toggle_id: String) -> void:
	var visual: Dictionary = _prefs.get("visual_debug", {})
	visual[toggle_id] = pressed
	_prefs["visual_debug"] = visual
	_save_prefs()
	if _draw_node != null:
		_draw_node.set_options(visual)


func _on_section_toggled(pressed: bool, section_id: String) -> void:
	var visible: Dictionary = _prefs.get("visible_sections", {})
	visible[section_id] = pressed
	_prefs["visible_sections"] = visible
	_save_prefs()
	_refresh()


func _on_scale_changed(value: float) -> void:
	_prefs["scale"] = value
	_save_prefs()
	if _window != null:
		_window.content_scale_factor = clampf(value, 0.5, 3.0)


func _on_opacity_changed(value: float) -> void:
	_prefs["opacity"] = value
	_save_prefs()
	if _root_box != null:
		_root_box.modulate = Color(1.0, 1.0, 1.0, clampf(value, 0.2, 1.0))


func _on_refresh_changed(index: int) -> void:
	if index < 0 or index >= REFRESH_CHOICES.size():
		return
	_prefs["refresh_rate"] = REFRESH_CHOICES[index]
	_save_prefs()
	_start_refresh_timer()


func _on_hotkey_changed(index: int) -> void:
	if index < 0 or index >= HOTKEY_CHOICES.size():
		return
	_prefs["hotkey"] = HOTKEY_CHOICES[index]
	_save_prefs()
	if _hotkey_hint != null:
		_hotkey_hint.text = "Hotkey: %s" % HOTKEY_CHOICES[index]


## --- Visual debug draw layer ------------------------------------------------

func _setup_draw_node() -> void:
	if _draw_node != null:
		return
	_draw_node = DebugDraw.new()
	_pet.add_child(_draw_node)
	_draw_node.setup(_pet)
	var visual: Dictionary = _prefs.get("visual_debug", {})
	if not visual.is_empty():
		_draw_node.set_options(visual)
