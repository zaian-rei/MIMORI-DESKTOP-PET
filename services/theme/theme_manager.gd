extends Node

## Central theme manager. Discovers, validates, loads, caches, and switches
## pet themes at runtime. The engine never knows which pet it is running —
## it only knows the active ThemeResource.
##
## Design contract:
##   - ThemeManager ONLY discovers, validates, loads/unloads, provides data,
##     and emits events. It NEVER moves the pet, plays sounds, controls
##     animations, or chooses behaviors.
##   - All other systems subscribe to EventBus theme events and pull data
##     from ThemeManager when they need it.
##   - New asset types (custom behaviors, effects, plugins) go into
##     ThemeResource.extensions — ThemeManager is closed for modification.

const THEMES_DIR := "res://themes/"
const THEME_FILENAME := "theme.tres"
const DEFAULT_THEME_ID := "default"

var _themes: Dictionary = {} # id -> ThemeResource
var _plugin_themes: Dictionary = {} # id -> ThemeResource (registered by plugins)
var _active_theme: ThemeResource = null
var _load_time_ms: int = 0
var _load_start_ms: int = 0


func _ready() -> void:
	discover_themes()
	LoggerGlobal.info("ThemeManager discovered %d theme(s)." % _themes.size())


## --- Discovery ---------------------------------------------------------------

## Scans THEMES_DIR for subdirectories containing a theme.tres file.
## Each valid theme is cached by its ThemeResource.id. Theme plugins register
## their themes separately (see register_theme_resource) and those are
## preserved here — discovery never wipes plugin-provided themes.
func discover_themes() -> void:
	_themes.clear()
	for id in _plugin_themes:
		_themes[id] = _plugin_themes[id]
	## ResourceLoader lists original paths in exported PCKs; DirAccess only
	## sees the physical converted files and can miss resource directories.
	for entry in ResourceLoader.list_directory(THEMES_DIR):
		if not entry.ends_with("/"):
			continue
		var theme_path := THEMES_DIR.path_join(entry.trim_suffix("/")).path_join(THEME_FILENAME)
		if not ResourceLoader.exists(theme_path):
			continue
		var theme := load(theme_path) as ThemeResource
		if theme == null or theme.id.is_empty():
			continue
		var validation_errors := theme.validate()
		if validation_errors.is_empty():
			_themes[theme.id] = theme
			EventBus.emit(EventBus.THEME_VALIDATED, {
				"theme_id": theme.id,
				"theme_name": theme.display_name,
			})
		else:
			for error in validation_errors:
				LoggerGlobal.warn("ThemeManager: validation failed for '%s': %s" % [theme.id, error])
			# Still register so the user can see it in debug UI, but not load it.
			_themes[theme.id] = theme


## Registers a ThemeResource supplied by a theme plugin. Validates it with the
## same rules as discovered themes, caches it, and emits THEME_VALIDATED.
## This is the single registration point so ThemeManager stays the only owner
## of the theme cache — no duplicated discovery logic anywhere else.
func register_theme_resource(theme: ThemeResource) -> bool:
	if theme == null:
		LoggerGlobal.error("ThemeManager: cannot register a null theme.")
		return false
	if theme.id.is_empty():
		LoggerGlobal.error("ThemeManager: cannot register a theme with an empty id.")
		return false
	var validation_errors := theme.validate()
	if not validation_errors.is_empty():
		for error in validation_errors:
			LoggerGlobal.warn("ThemeManager: plugin theme '%s' failed validation: %s" % [theme.id, error])
		return false
	_themes[theme.id] = theme
	_plugin_themes[theme.id] = theme
	EventBus.emit(EventBus.THEME_VALIDATED, {
		"theme_id": theme.id,
		"theme_name": theme.display_name,
	})
	LoggerGlobal.info("ThemeManager: registered theme '%s' (%s)." % [theme.id, theme.display_name])
	return true


## --- Loading -----------------------------------------------------------------

## Loads a theme by id. Returns true on success.
## If another theme is active, it is unloaded first.
func load_theme(theme_id: String) -> bool:
	if theme_id.is_empty():
		LoggerGlobal.warn("ThemeManager: cannot load empty theme id.")
		return false

	if theme_id == get_active_id():
		return true

	var theme := _themes.get(theme_id) as ThemeResource
	if theme == null:
		LoggerGlobal.error("ThemeManager: theme '%s' not found." % theme_id)
		EventBus.emit(EventBus.THEME_LOAD_FAILED, {
			"theme_id": theme_id,
			"reason": "not_found",
		})
		return false

	var validation_errors := theme.validate()
	if not validation_errors.is_empty():
		for error in validation_errors:
			LoggerGlobal.error("ThemeManager: theme '%s' failed validation: %s" % [theme_id, error])
		EventBus.emit(EventBus.THEME_LOAD_FAILED, {
			"theme_id": theme_id,
			"reason": "validation_failed",
			"errors": validation_errors,
		})
		return false

	_load_start_ms = Time.get_ticks_msec()

	# Unload current theme if any
	if _active_theme != null:
		var old_id := _active_theme.id
		EventBus.emit(EventBus.THEME_UNLOADED, {"theme_id": old_id})
		_active_theme = null

	# Apply theme
	_active_theme = theme
	_apply_theme_assets(theme)

	_load_time_ms = Time.get_ticks_msec() - _load_start_ms

	EventBus.emit(EventBus.THEME_LOADED, {
		"theme_id": theme.id,
		"theme_name": theme.display_name,
		"load_time_ms": _load_time_ms,
	})
	EventBus.emit(EventBus.THEME_CHANGED, {
		"theme_id": theme.id,
		"theme_name": theme.display_name,
	})

	LoggerGlobal.info("ThemeManager: loaded theme '%s' (%s) in %dms." % [
		theme.id, theme.display_name, _load_time_ms
	])
	return true


## Applies a theme's assets to the engine. Called internally by load_theme
## and by Bootstrap during initial setup.
func _apply_theme_assets(theme: ThemeResource) -> void:
	# Audio pack
	if theme.audio_pack != null:
		AudioManager.set_active_pack(theme.audio_pack)

	# Pet definition overrides are applied by Bootstrap when it creates the
	# pet — ThemeManager doesn't own the pet node.

	# Personality default — stored for Bootstrap to read
	# (ThemeManager doesn't own the personality selection)


## --- Queries -----------------------------------------------------------------

func get_active_theme() -> ThemeResource:
	return _active_theme


func get_active_id() -> String:
	if _active_theme == null:
		return ""
	return _active_theme.id


func get_theme(theme_id: String) -> ThemeResource:
	return _themes.get(theme_id)


func has_theme(theme_id: String) -> bool:
	return _themes.has(theme_id)


func get_theme_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in _themes:
		ids.append(id)
	ids.sort()
	return ids


func get_theme_count() -> int:
	return _themes.size()


func get_installed_themes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _themes:
		var theme: ThemeResource = _themes[id]
		result.append({
			"id": theme.id,
			"name": theme.display_name,
			"version": theme.version,
			"author": theme.author,
			"active": id == get_active_id(),
		})
	return result


func get_default_theme_id() -> String:
	return DEFAULT_THEME_ID


## --- Debug Support -----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var theme_list: Array[Dictionary] = []
	for id in _themes:
		var theme: ThemeResource = _themes[id]
		theme_list.append({
			"id": theme.id,
			"name": theme.display_name,
			"version": theme.version,
			"active": id == get_active_id(),
			"valid": theme.validate().is_empty(),
		})

	return {
		"active_theme_id": get_active_id(),
		"active_theme_name": _active_theme.display_name if _active_theme else "",
		"theme_count": _themes.size(),
		"themes": theme_list,
		"load_time_ms": _load_time_ms,
		"themes_dir": THEMES_DIR,
	}
