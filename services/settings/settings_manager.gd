extends Node

## Centralized Settings Manager - single source of truth for all configurable
## engine values. Every system reads settings from here rather than storing
## duplicated configuration.
##
## Design contract:
##   - ONLY stores, validates, loads, saves settings and emits change events.
##   - NEVER moves the pet, plays audio, chooses behaviors, or controls animations.
##   - Future systems register their own settings without modifying this manager.
##   - All changes emit SETTING_CHANGED via EventBus for live updates.

const SAVE_PATH := "user://settings.json"

## --- Setting Definition ------------------------------------------------------

class SettingDef:
	var key: String
	var category: String
	var type: int  # TYPE_FLOAT, TYPE_INT, TYPE_BOOL, TYPE_STRING
	var default_value: Variant
	var current_value: Variant
	var min_value: Variant  # null = no min
	var max_value: Variant  # null = no max
	var description: String

	func _init(p_key: String, p_category: String, p_type: int, p_default: Variant,
			p_min: Variant = null, p_max: Variant = null, p_desc: String = "") -> void:
		key = p_key
		category = p_category
		type = p_type
		default_value = p_default
		current_value = p_default
		min_value = p_min
		max_value = p_max
		description = p_desc

	func validate(value: Variant) -> bool:
		if typeof(value) != type:
			return false
		if min_value != null and value < min_value:
			return false
		if max_value != null and value > max_value:
			return false
		return true

	func clone() -> SettingDef:
		var d := SettingDef.new(key, category, type, default_value, min_value, max_value, description)
		d.current_value = current_value
		return d


## --- Internal State ----------------------------------------------------------

var _settings: Dictionary = {}  # key -> SettingDef
var _categories: Dictionary = {}  # category_name -> Array[String] keys
var _dirty: bool = false
var _validation_errors: Array[Dictionary] = []


## --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	_register_defaults()
	_load_settings()
	LoggerGlobal.info("SettingsManager initialized (%d settings)." % _settings.size())


## --- Registration API --------------------------------------------------------

## Register a new setting. Safe to call multiple times (idempotent).
func register_setting(key: String, category: String, type: int, default_value: Variant,
		min_value: Variant = null, max_value: Variant = null, description: String = "") -> void:
	if _settings.has(key):
		return
	var def := SettingDef.new(key, category, type, default_value, min_value, max_value, description)
	_settings[key] = def
	if not _categories.has(category):
		_categories[category] = []
	_categories[category].append(key)


## --- Get/Set API -------------------------------------------------------------

## Get a setting value by key. Returns default if not found.
func get_setting(key: String, default: Variant = null) -> Variant:
	if _settings.has(key):
		return _settings[key].current_value
	return default


## Set a setting value. Validates before applying. Returns true on success.
func set_setting(key: String, value: Variant) -> bool:
	if not _settings.has(key):
		LoggerGlobal.warn("SettingsManager: unknown setting '%s'." % key)
		return false

	var def: SettingDef = _settings[key]
	if not def.validate(value):
		_record_validation_error(key, value, def)
		return false

	var old_value: Variant = def.current_value
	def.current_value = value
	_dirty = true

	if old_value != value:
		_emit_setting_changed(key, old_value, value)
		_auto_save()

	return true


## Check if a setting exists.
func has_setting(key: String) -> bool:
	return _settings.has(key)


## Get the default value for a setting.
func get_default(key: String) -> Variant:
	if _settings.has(key):
		return _settings[key].default_value
	return null


## --- Reset API ---------------------------------------------------------------

## Reset a single setting to its default.
func reset_setting(key: String) -> void:
	if _settings.has(key):
		var def: SettingDef = _settings[key]
		var old_value: Variant = def.current_value
		def.current_value = def.default_value
		_dirty = true
		if old_value != def.default_value:
			_emit_setting_changed(key, old_value, def.default_value)
			EventBus.emit(EventBus.SETTINGS_CATEGORY_RESET, {"category": def.category, "key": key})
			_auto_save()


## Reset all settings in a category to defaults.
func reset_category(category: String) -> void:
	if not _categories.has(category):
		return
	for key in _categories[category]:
		var def: SettingDef = _settings[key]
		var old_value: Variant = def.current_value
		def.current_value = def.default_value
		if old_value != def.default_value:
			_emit_setting_changed(key, old_value, def.default_value)
	_dirty = true
	EventBus.emit(EventBus.SETTINGS_CATEGORY_RESET, {"category": category})
	_auto_save()


## Reset all settings to defaults.
func reset_all() -> void:
	for key in _settings:
		var def: SettingDef = _settings[key]
		var old_value: Variant = def.current_value
		def.current_value = def.default_value
		if old_value != def.default_value:
			_emit_setting_changed(key, old_value, def.default_value)
	_dirty = true
	EventBus.emit(EventBus.SETTINGS_CATEGORY_RESET, {"category": "all"})
	_auto_save()


## --- Category API ------------------------------------------------------------

## Get all keys in a category.
func get_category_keys(category: String) -> Array:
	return _categories.get(category, [])


## Get all category names.
func get_categories() -> Array:
	return _categories.keys()


## --- Validation API ----------------------------------------------------------

## Get all validation errors since last clear.
func get_validation_errors() -> Array:
	return _validation_errors.duplicate()


## Clear validation errors.
func clear_validation_errors() -> void:
	_validation_errors.clear()


## --- Dirty State API ---------------------------------------------------------

## Check if there are unsaved changes.
func is_dirty() -> bool:
	return _dirty


## Mark settings as saved.
func mark_clean() -> void:
	_dirty = false


## --- Persistence API ---------------------------------------------------------

## Load settings from disk (called automatically at startup).
func _load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		LoggerGlobal.warn("SettingsManager: could not parse settings file.")
		return

	if not parsed.has("settings"):
		return

	var data: Dictionary = parsed["settings"]
	for key in data:
		if _settings.has(key):
			var def: SettingDef = _settings[key]
			var value: Variant = data[key]
			# Type coercion for legacy values
			if def.type == TYPE_FLOAT and typeof(value) == TYPE_INT:
				value = float(value)
			elif def.type == TYPE_INT and typeof(value) == TYPE_FLOAT:
				value = int(value)
			elif def.type == TYPE_BOOL and typeof(value) == TYPE_INT:
				value = value != 0
			## Keep older saved pet sizes when they fall within the new range; clamp
			## only this slider's historic out-of-range values to its new limits.
			if key == "general.pet_scale" and typeof(value) in [TYPE_FLOAT, TYPE_INT]:
				value = clampf(float(value), 0.75, 1.25)
			if def.validate(value):
				def.current_value = value

	_dirty = false
	EventBus.emit(EventBus.SETTINGS_LOADED)


## Save settings to disk.
func save_settings() -> void:
	var data := {}
	for key in _settings:
		data[key] = _settings[key].current_value

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		LoggerGlobal.error("SettingsManager: could not write settings file.")
		return
	file.store_string(JSON.stringify({"settings": data}, "\t"))
	file.close()

	_dirty = false
	EventBus.emit(EventBus.SETTINGS_SAVED)


## Auto-save if dirty (throttled).
var _auto_save_timer: float = 0.0
const AUTO_SAVE_DELAY := 0.5

func _auto_save() -> void:
	_auto_save_timer = AUTO_SAVE_DELAY


func _process(delta: float) -> void:
	if _auto_save_timer > 0.0:
		_auto_save_timer -= delta
		if _auto_save_timer <= 0.0:
			_auto_save_timer = 0.0
			if _dirty:
				save_settings()


## --- EventBus Integration ----------------------------------------------------

func _emit_setting_changed(key: String, old_value: Variant, new_value: Variant) -> void:
	var def: SettingDef = _settings[key]
	EventBus.emit(EventBus.SETTING_CHANGED, {
		"key": key,
		"category": def.category,
		"old_value": old_value,
		"new_value": new_value,
	})


## --- Validation Errors -------------------------------------------------------

func _record_validation_error(key: String, value: Variant, def: SettingDef) -> void:
	var error := {
		"key": key,
		"value": value,
		"expected_type": def.type,
		"min": def.min_value,
		"max": def.max_value,
		"time": Time.get_ticks_msec(),
	}
	_validation_errors.append(error)
	if _validation_errors.size() > 50:
		_validation_errors.pop_front()
	LoggerGlobal.warn("SettingsManager: validation failed for '%s' = %s" % [key, str(value)])


## --- Default Settings Registration -------------------------------------------

func _register_defaults() -> void:
	# General
	register_setting("general.pet_scale", "general", TYPE_FLOAT, 1.0, 0.75, 1.25, "Pet render scale")
	register_setting("general.pet_name", "general", TYPE_STRING, "Ori", null, null, "Display name for the desktop companion")
	register_setting("general.pet_id", "general", TYPE_STRING, "", null, null, "Selected desktop companion")
	register_setting("general.click_through", "general", TYPE_BOOL, false, null, null, "Let pointer clicks pass through Ori")
	register_setting("appearance.ui_theme", "appearance", TYPE_STRING, "bright", null, null, "Settings interface theme")

	# Movement
	register_setting("movement.move_speed", "movement", TYPE_FLOAT, 150.0, 10.0, 1000.0, "Base walk speed (px/s)")
	register_setting("movement.gravity", "movement", TYPE_FLOAT, 1800.0, 200.0, 6000.0, "Gravity (px/s^2)")
	register_setting("movement.jump_height", "movement", TYPE_FLOAT, 450.0, 100.0, 2000.0, "Jump velocity (px/s)")

	# Behavior
	register_setting("behavior.decision_interval_min", "behavior", TYPE_FLOAT, 3.0, 0.5, 30.0, "Min decision interval (s)")
	register_setting("behavior.decision_interval_max", "behavior", TYPE_FLOAT, 6.0, 1.0, 60.0, "Max decision interval (s)")

	# Follow Cursor
	register_setting("follow_cursor.enabled_by_default", "follow_cursor", TYPE_BOOL, true, null, null, "Follow cursor on launch")
	register_setting("follow_cursor.follow_default_migrated", "follow_cursor", TYPE_BOOL, false, null, null, "One-time follow cursor default migration")
	register_setting("follow_cursor.detection_radius", "follow_cursor", TYPE_FLOAT, 2400.0, 200.0, 5000.0, "Cursor follow detection radius (px)")
	register_setting("follow_cursor.stop_distance", "follow_cursor", TYPE_FLOAT, 90.0, 20.0, 250.0, "Cursor follow stopping distance (px)")
	register_setting("follow_cursor.sprint_distance", "follow_cursor", TYPE_FLOAT, 480.0, 120.0, 1200.0, "Distance at which cursor follow starts running (px)")
	register_setting("follow_cursor.walk_speed", "follow_cursor", TYPE_FLOAT, 160.0, 60.0, 400.0, "Cursor follow walking speed (px/s)")
	register_setting("follow_cursor.run_speed", "follow_cursor", TYPE_FLOAT, 320.0, 100.0, 800.0, "Cursor follow running speed (px/s)")
	register_setting("follow_cursor.jump_height", "follow_cursor", TYPE_FLOAT, 130.0, 40.0, 400.0, "Cursor follow jump peak height (px)")
	register_setting("follow_cursor.max_jumps", "follow_cursor", TYPE_INT, 1, 0, 1, "Maximum follow jumps per overhead attempt")
	register_setting("follow_cursor.retry_delay", "follow_cursor", TYPE_FLOAT, 6.0, 2.0, 12.0, "Cursor jump retry delay (seconds)")
	register_setting("follow_cursor.reaction_probability", "follow_cursor", TYPE_FLOAT, 0.25, 0.0, 1.0, "Chance of a cursor arrival reaction")

	# Audio
	register_setting("audio.master_volume", "audio", TYPE_FLOAT, 0.0, -80.0, 24.0, "Master volume (dB)")
	register_setting("audio.muted", "audio", TYPE_BOOL, false, null, null, "Global mute")

	# Window
	register_setting("window.always_on_top", "window", TYPE_BOOL, true, null, null, "Window always on top")
	register_setting("window.opacity", "window", TYPE_FLOAT, 1.0, 0.35, 1.0, "Pet window opacity")

	# Debug
	register_setting("debug.debug_overlay_enabled", "debug", TYPE_BOOL, true, null, null, "Debug overlay on launch")
	register_setting("debug.verbose_logging", "debug", TYPE_BOOL, false, null, null, "Enable verbose logging")


## --- Debug Support -----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var modified := {}
	for key in _settings:
		var def: SettingDef = _settings[key]
		if def.current_value != def.default_value:
			modified[key] = def.current_value

	var categories_data := {}
	for cat in _categories:
		categories_data[cat] = _categories[cat].size()

	return {
		"total_settings": _settings.size(),
		"categories": categories_data,
		"modified_count": modified.size(),
		"modified": modified,
		"dirty": _dirty,
		"validation_errors": _validation_errors.size(),
		"save_path": SAVE_PATH,
	}
