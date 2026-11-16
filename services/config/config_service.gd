extends Node


const SAVE_PATH := "user://save_data.json"


var move_speed: float:
	get: return SettingsManager.get_setting("movement.move_speed", 150.0)
	set(v): SettingsManager.set_setting("movement.move_speed", v)

var gravity: float:
	get: return SettingsManager.get_setting("movement.gravity", 1800.0)
	set(v): SettingsManager.set_setting("movement.gravity", v)

var jump_speed: float:
	get: return SettingsManager.get_setting("movement.jump_height", 450.0)
	set(v): SettingsManager.set_setting("movement.jump_height", v)

var scale: float:
	get: return clampf(SettingsManager.get_setting("general.pet_scale", 1.0), 0.75, 1.25)
	set(v): SettingsManager.set_setting("general.pet_scale", clampf(v, 0.75, 1.25))

var always_on_top: bool:
	get: return SettingsManager.get_setting("window.always_on_top", true)
	set(v): SettingsManager.set_setting("window.always_on_top", v)

var window_opacity: float:
	get: return SettingsManager.get_setting("window.opacity", 1.0)
	set(v): SettingsManager.set_setting("window.opacity", v)

var launch_at_login: bool = false

var music_enabled: bool = false

var follow_cursor_enabled: bool:
	get: return SettingsManager.get_setting("follow_cursor.enabled_by_default", false)
	set(v): SettingsManager.set_setting("follow_cursor.enabled_by_default", v)

var master_volume_db: float:
	get: return SettingsManager.get_setting("audio.master_volume", 0.0)
	set(v): SettingsManager.set_setting("audio.master_volume", v)

var muted: bool:
	get: return SettingsManager.get_setting("audio.muted", false)
	set(v): SettingsManager.set_setting("audio.muted", v)

var category_volumes: Dictionary = {}
var category_mutes: Dictionary = {}
var music_volume_initialized: bool = false

var personality_id: String = ""

var theme_id: String = "default"

var pet_world_position: Vector2 = Vector2.ZERO
var has_saved_position: bool = false


var pet_stats: Dictionary = {}
var has_saved_stats: bool = false


var pet_memory: Dictionary = {}
var has_saved_memory: bool = false

var statistics: Dictionary = {}
var has_saved_statistics: bool = false


var debug_overlay: Dictionary = {}


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		LoggerGlobal.error("Save file could not be parsed, ignoring it.")
		return

	if parsed.has("pet_position"):
		var pos: Dictionary = parsed["pet_position"]
		pet_world_position = Vector2(pos.get("x", 0.0), pos.get("y", 0.0))
		has_saved_position = true

	if parsed.has("settings"):
		var settings: Dictionary = parsed["settings"]
		# Non-delegated settings (kept here for backward compat)
		launch_at_login = _as_bool(settings.get("launch_at_login"), launch_at_login)
		music_enabled = _as_bool(settings.get("music_enabled"), music_enabled)
		personality_id = str(settings.get("personality_id", personality_id))
		theme_id = str(settings.get("theme_id", theme_id))
		var stored_volumes = settings.get("category_volumes")
		if typeof(stored_volumes) == TYPE_DICTIONARY:
			category_volumes = {}
			for key in stored_volumes:
				category_volumes[int(key)] = _as_float(stored_volumes[key], 0.0)
		var stored_mutes = settings.get("category_mutes")
		if typeof(stored_mutes) == TYPE_DICTIONARY:
			category_mutes = {}
			for key in stored_mutes:
				category_mutes[int(key)] = _as_bool(stored_mutes[key], false)
		music_volume_initialized = _as_bool(settings.get("music_volume_initialized"), false)

		# Legacy migration to SettingsManager. Runs only on first launch of a
		# new-style build (when the centralized settings.json does not exist):
		# once that file exists it is authoritative, and re-applying these
		# values here could revert changes made through SettingsManager.
		if not FileAccess.file_exists(SettingsManager.SAVE_PATH):
			if settings.has("move_speed"):
				SettingsManager.set_setting("movement.move_speed", _as_float(settings.get("move_speed"), 150.0))
			if settings.has("gravity"):
				SettingsManager.set_setting("movement.gravity", _as_float(settings.get("gravity"), 1800.0))
			if settings.has("jump_speed"):
				SettingsManager.set_setting("movement.jump_height", _as_float(settings.get("jump_speed"), 450.0))
			if settings.has("scale"):
				SettingsManager.set_setting("general.pet_scale", clampf(_as_float(settings.get("scale"), 1.0), 0.75, 1.25))
			if settings.has("always_on_top"):
				SettingsManager.set_setting("window.always_on_top", _as_bool(settings.get("always_on_top"), true))
			if settings.has("follow_cursor_enabled"):
				SettingsManager.set_setting("follow_cursor.enabled_by_default", _as_bool(settings.get("follow_cursor_enabled"), false))
			if settings.has("master_volume_db"):
				SettingsManager.set_setting("audio.master_volume", _as_float(settings.get("master_volume_db"), 0.0))
			if settings.has("muted"):
				SettingsManager.set_setting("audio.muted", _as_bool(settings.get("muted"), false))

	if parsed.has("pet_stats"):
		var stats: Dictionary = parsed["pet_stats"]
		if typeof(stats) == TYPE_DICTIONARY:
			pet_stats = stats
			has_saved_stats = true

	if parsed.has("pet_memory"):
		var memory: Dictionary = parsed["pet_memory"]
		if typeof(memory) == TYPE_DICTIONARY:
			pet_memory = memory
			has_saved_memory = true

	if parsed.has("statistics"):
		var stats_data: Dictionary = parsed["statistics"]
		if typeof(stats_data) == TYPE_DICTIONARY:
			statistics = stats_data
			has_saved_statistics = true

	if parsed.has("debug_overlay"):
		var overlay: Dictionary = parsed["debug_overlay"]
		if typeof(overlay) == TYPE_DICTIONARY:
			debug_overlay = overlay


func _as_float(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


func _as_bool(value: Variant, fallback: bool) -> bool:
	if typeof(value) == TYPE_BOOL:
		return value
	if typeof(value) == TYPE_INT:
		return value != 0
	return fallback


func save_data(world_position: Vector2) -> void:
	pet_world_position = world_position
	has_saved_position = true
	_write_save()


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	_write_save()


func set_follow_cursor_enabled(value: bool) -> void:
	follow_cursor_enabled = value


func set_master_volume_db(value: float) -> void:
	master_volume_db = value


func set_muted(value: bool) -> void:
	muted = value


func set_category_volume(category: int, value_db: float) -> void:
	category_volumes[category] = value_db
	_write_save()


func get_category_volume(category: int) -> float:
	return _as_float(category_volumes.get(category, 0.0), 0.0)


func set_category_muted(category: int, value: bool) -> void:
	category_mutes[category] = value
	_write_save()


func get_category_muted(category: int) -> bool:
	return bool(category_mutes.get(category, false))


func set_personality_id(value: String) -> void:
	personality_id = value
	_write_save()


func set_theme_id(value: String) -> void:
	theme_id = value
	_write_save()


func save_stats(stats: Dictionary) -> void:
	pet_stats = stats
	has_saved_stats = true
	_write_save()


func save_memory(memory: Dictionary) -> void:
	pet_memory = memory
	has_saved_memory = true
	_write_save()


func save_statistics(stats_data: Dictionary) -> void:
	statistics = stats_data
	has_saved_statistics = true
	_write_save()


func set_debug_overlay(prefs: Dictionary) -> void:
	debug_overlay = prefs
	_write_save()


func _write_save() -> void:
	var data := {
		"pet_position": {"x": pet_world_position.x, "y": pet_world_position.y},
		"settings": {
			"move_speed": move_speed,
			"gravity": gravity,
			"jump_speed": jump_speed,
			"scale": scale,
			"always_on_top": always_on_top,
			"launch_at_login": launch_at_login,
			"music_enabled": music_enabled,
			"follow_cursor_enabled": follow_cursor_enabled,
			"personality_id": personality_id,
			"theme_id": theme_id,
			"master_volume_db": master_volume_db,
			"muted": muted,
			"category_volumes": category_volumes,
			"category_mutes": category_mutes,
			"music_volume_initialized": music_volume_initialized,
		},
		"pet_stats": pet_stats,
		"pet_memory": pet_memory,
		"statistics": statistics,
		"debug_overlay": debug_overlay,
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		LoggerGlobal.error("Could not write save file.")
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()


func set_launch_at_login(enabled: bool) -> void:
	launch_at_login = enabled
	_write_save()
	match OS.get_name():
		"macOS":
			_set_macos_launch_at_login(enabled)
		"Linux":
			_set_linux_launch_at_login(enabled)
		"Windows":
			_set_windows_launch_at_login(enabled)
		_:
			LoggerGlobal.warning("Launch at Login is not supported on this platform.")


func _set_macos_launch_at_login(enabled: bool) -> void:
	var app_path := _get_app_bundle_path()
	if app_path.is_empty():
		LoggerGlobal.error("Could not determine app bundle path for Launch at Login (expected when running from the editor).")
		return

	var script: String
	if enabled:
		script = 'tell application "System Events" to make login item at end with properties {path:"%s", hidden:false}' % app_path
	else:
		var app_name := app_path.get_file().get_basename()
		script = 'tell application "System Events" to delete login item "%s"' % app_name

	OS.execute("osascript", ["-e", script])


func _set_linux_launch_at_login(enabled: bool) -> void:
	var executable_path := OS.get_executable_path()
	if OS.has_feature("editor") or executable_path.is_empty():
		LoggerGlobal.error("Launch at Login needs an exported application executable.")
		return

	var config_home := OS.get_environment("XDG_CONFIG_HOME")
	if config_home.is_empty():
		config_home = OS.get_environment("HOME").path_join(".config")
	var autostart_dir := config_home.path_join("autostart")
	var entry_path := autostart_dir.path_join("mimori.desktop")
	if not enabled:
		if FileAccess.file_exists(entry_path):
			DirAccess.remove_absolute(entry_path)
		return

	if DirAccess.make_dir_recursive_absolute(autostart_dir) != OK:
		LoggerGlobal.error("Could not create the Linux autostart folder.")
		return
	var entry := FileAccess.open(entry_path, FileAccess.WRITE)
	if entry == null:
		LoggerGlobal.error("Could not create the Linux autostart entry.")
		return
	var icon_path := executable_path.get_base_dir().path_join("appicon.png")
	entry.store_string("[Desktop Entry]\nType=Application\nName=Mimori\nComment=Start the Mimori desktop companion\nExec=\"%s\"\nIcon=%s\nTerminal=false\nX-GNOME-Autostart-enabled=true\n" % [_escape_desktop_exec_argument(executable_path), icon_path])
	entry.close()


func _escape_desktop_exec_argument(value: String) -> String:
	return value.replace("\\", "\\\\").replace("\"", "\\\"").replace("`", "\\`").replace("$", "\\$")


func _set_windows_launch_at_login(enabled: bool) -> void:
	var executable_path := OS.get_executable_path()
	if OS.has_feature("editor") or executable_path.is_empty():
		LoggerGlobal.error("Launch at Login needs an exported application executable.")
		return
	var app_data := OS.get_environment("APPDATA")
	if app_data.is_empty():
		LoggerGlobal.error("Could not locate the Windows Startup folder.")
		return
	var startup_dir := app_data.path_join("Microsoft/Windows/Start Menu/Programs/Startup")
	var entry_path := startup_dir.path_join("Mimori.cmd")
	if not enabled:
		if FileAccess.file_exists(entry_path):
			DirAccess.remove_absolute(entry_path)
		return
	if DirAccess.make_dir_recursive_absolute(startup_dir) != OK:
		LoggerGlobal.error("Could not create the Windows Startup folder entry.")
		return
	var entry := FileAccess.open(entry_path, FileAccess.WRITE)
	if entry == null:
		LoggerGlobal.error("Could not create the Windows Startup folder entry.")
		return
	var escaped_path := executable_path.replace("%", "%%")
	entry.store_string("@echo off\r\nstart \"\" \"%s\"\r\n" % escaped_path)
	entry.close()


func _get_app_bundle_path() -> String:
	var executable_path := OS.get_executable_path()
	var bundle_index := executable_path.find(".app/")
	if bundle_index == -1:
		return ""
	return executable_path.substr(0, bundle_index + 4)


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"save_path": SAVE_PATH,
		"save_exists": FileAccess.file_exists(SAVE_PATH),
		"has_saved_position": has_saved_position,
		"has_saved_stats": has_saved_stats,
		"has_saved_memory": has_saved_memory,
		"has_saved_statistics": has_saved_statistics,
		"pet_position": pet_world_position,
		"move_speed": move_speed,
		"gravity": gravity,
		"jump_speed": jump_speed,
		"scale": scale,
		"always_on_top": always_on_top,
		"launch_at_login": launch_at_login,
		"music_enabled": music_enabled,
		"follow_cursor_enabled": follow_cursor_enabled,
		"personality_id": personality_id,
		"master_volume_db": master_volume_db,
		"muted": muted,
		"category_volumes": category_volumes,
	}
