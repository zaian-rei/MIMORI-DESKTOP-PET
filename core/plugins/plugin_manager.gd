extends Node

## Central plugin lifecycle manager. The PluginManager ONLY:
##   registers, initializes, enables, disables, shuts down, unloads, tracks
##   metadata, and manages plugin lifecycle + dependencies.
## It NEVER implements plugin behavior: it does not move the pet, choose AI
## actions, control animations, play audio, or know what any plugin does.
##
## Design contract:
##   - Plugins are Plugin subclasses. The manager talks to them exclusively
##     through the base-class lifecycle contract; it never inspects subclass
##     internals or hardcodes any plugin category.
##   - Discovery is a separate scanner (PluginDiscovery). PluginManager asks
##     it to scan res://plugins/ once at boot, validates via its records, and
##     registers whatever is valid. Installing a plugin means copying a folder
##     into the plugins directory — no engine code changes. Explicit re-scans
##     are supported but never happen automatically after boot.
##   - Error isolation: lifecycle hooks return bool. A hook returning false -
##     or erroring internally (GDScript aborts only that method and returns
##     the default) - marks the plugin FAILED and disables it. The engine
##     itself never crashes.
##   - Dependencies are declarative. Required deps must be registered and
##     version-compatible; missing optional deps only warn. Initialization is
##     ordered by dependency (topological), with circular-dependency detection.
##   - Plugins get sanctioned engine access only through get_engine_services(),
##     a narrow surface over the public APIs of existing services.

enum Status {
	REGISTERED,   # registered, not yet initialized
	INITIALIZING, # initialize() in progress
	INITIALIZED,  # initialize() succeeded, not enabled
	ENABLED,      # enable() succeeded, active
	DISABLED,     # explicitly disabled
	FAILED,       # a lifecycle step failed
	SHUTDOWN,     # permanently shut down (before unload)
	UNLOADED,     # removed from the manager
}

## Max error messages kept per plugin.
const MAX_ERRORS_PER_PLUGIN := 20

## Directory scanned for plugin folders at boot.
const DEFAULT_PLUGINS_DIR := "res://plugins/"

## --- Internal state ----------------------------------------------------------

var _plugins: Dictionary = {}          # id -> Plugin
var _status: Dictionary = {}           # id -> Status
var _init_times_ms: Dictionary = {}    # id -> int
var _errors: Dictionary = {}           # id -> Array[String]
var _enable_on_start: Dictionary = {}  # id -> bool
var _booted := false

## Discovery state (scan results, not lifecycle).
var _discovery: PluginDiscovery = null
var _discovered_records: Array = []    # Array[DiscoveredPlugin]
var _discovery_report: Dictionary = {}
var _scanned := false

## Sanctioned engine access surface handed to plugins.
var engine_services: EngineServices = null


## --- Safe engine access ------------------------------------------------------

## Narrow, sanctioned surface for plugins to reach engine services. Exposes
## only the public APIs of the allowed services; plugins must go through this
## object instead of reaching into engine internals directly.
class EngineServices:
	var settings: SettingsManager
	var theme: ThemeManager
	var statistics: StatisticsManager
	var audio: AudioManager
	var config: ConfigService

	func _init() -> void:
		pass

	## Register a plugin setting with the central SettingsManager.
	func register_setting(key: String, category: String, type: int,
			default_value: Variant, min_value: Variant = null,
			max_value: Variant = null, description: String = "") -> void:
		if settings != null:
			settings.register_setting(key, category, type, default_value,
				min_value, max_value, description)

	## Read a setting value (delegates to SettingsManager).
	func get_setting(key: String, default: Variant = null) -> Variant:
		if settings != null:
			return settings.get_setting(key, default)
		return default

	func get_active_theme_id() -> String:
		if theme != null:
			return theme.get_active_id()
		return ""

	func get_theme_count() -> int:
		if theme != null:
			return theme.get_theme_count()
		return 0

	func reset_session_statistics() -> void:
		if statistics != null:
			statistics.reset_session()

	func set_master_volume_db(value_db: float) -> void:
		if audio != null:
			audio.set_master_volume_db(value_db)

	func set_muted(value: bool) -> void:
		if audio != null:
			audio.set_muted(value)

	func get_config_save_path() -> String:
		if config != null:
			return config.SAVE_PATH
		return ""


## --- Lifecycle ---------------------------------------------------------------

func _ready() -> void:
	engine_services = EngineServices.new()
	engine_services.settings = SettingsManager
	engine_services.theme = ThemeManager
	engine_services.statistics = StatisticsManager
	engine_services.audio = AudioManager
	engine_services.config = ConfigService
	_discovery = PluginDiscovery.new()
	LoggerGlobal.info("PluginManager initialized.")
	# Run after the rest of the engine has booted so any plugin registered
	# during other autoloads' _ready() is picked up in dependency order.
	call_deferred("_boot_registered_plugins")


## Initializes and enables every currently registered plugin in dependency
## order. Safe to call more than once (plugins already started are skipped).
func _boot_registered_plugins() -> void:
	if _booted:
		return
	_booted = true
	_auto_discover()
	var order := _resolve_init_order()
	for plugin_id in order:
		initialize_plugin(plugin_id)
	for plugin_id in order:
		if bool(_enable_on_start.get(plugin_id, true)):
			enable_plugin(plugin_id)
	if order.is_empty():
		LoggerGlobal.info("PluginManager: no plugins registered.")


## --- Discovery ---------------------------------------------------------------

## Boot-time auto-discovery: scans the default plugins directory once. Never
## runs after boot; explicit re-scans go through discover_plugins().
func _auto_discover() -> void:
	if _scanned:
		return
	_scanned = true
	discover_plugins(DEFAULT_PLUGINS_DIR)


## Scans a plugin directory, validates every candidate, and registers the
## valid ones (idempotent: plugin ids already registered — programmatically or
## by a previous scan — are skipped). Returns a summary report Dictionary.
## This is the only public entry point for discovery.
func discover_plugins(plugins_dir: String = DEFAULT_PLUGINS_DIR) -> Dictionary:
	if _discovery == null:
		_discovery = PluginDiscovery.new()
	var candidates: Array = _discovery.scan(plugins_dir)
	_discovered_records = candidates
	var report := _register_discovered(candidates)
	report["scanned_dir"] = plugins_dir
	report["load_order"] = _resolve_init_order()
	_discovery_report = report
	LoggerGlobal.info("PluginDiscovery: scanned '%s' — %d folder(s), %d valid, %d invalid, %d newly registered." % [
		plugins_dir, report["folders_found"], report["valid"],
		report["invalid"], report["newly_registered"],
	])
	return report.duplicate(true)


## Registers valid discovered candidates in load order (category priority,
## then id). Invalid candidates are never instantiated; their errors and
## warnings are aggregated into the returned report.
func _register_discovered(candidates: Array) -> Dictionary:
	var valid_list: Array = []
	var invalid_list: Array = []
	for candidate in candidates:
		if candidate.valid:
			valid_list.append(candidate)
		else:
			invalid_list.append(candidate)
	valid_list.sort_custom(PluginDiscovery.sort_by_load_order)

	var newly_registered := 0
	var already_registered := 0
	var failures := 0
	var errors_agg: Array = []
	var warnings_agg: Array = []

	for candidate in valid_list:
		for w in candidate.warnings:
			warnings_agg.append("%s: %s" % [candidate.plugin_id, w])
		if _plugins.has(candidate.plugin_id):
			candidate.registered = true
			already_registered += 1
			continue
		var plugin := _discovery.instantiate(candidate)
		if plugin == null:
			failures += 1
			errors_agg.append("%s: could not instantiate entry script." % candidate.plugin_id)
			continue
		if register_plugin(plugin):
			candidate.registered = true
			newly_registered += 1
		else:
			failures += 1
			errors_agg.append("%s: registration rejected." % candidate.plugin_id)
			plugin.free()

	for candidate in invalid_list:
		for e in candidate.errors:
			errors_agg.append("%s: %s" % [candidate.plugin_id, e])
		for w in candidate.warnings:
			warnings_agg.append("%s: %s" % [candidate.plugin_id, w])

	return {
		"folders_found": candidates.size(),
		"valid": valid_list.size(),
		"invalid": invalid_list.size(),
		"newly_registered": newly_registered,
		"already_registered": already_registered,
		"registration_failures": failures,
		"errors": errors_agg,
		"warnings": warnings_agg,
	}


## --- Registration / unload ---------------------------------------------------

## Register a plugin. Validates metadata and engine compatibility, stores it,
## and emits PLUGIN_REGISTERED. Returns true on success.
func register_plugin(plugin: Plugin) -> bool:
	if plugin == null:
		LoggerGlobal.error("PluginManager: cannot register a null plugin.")
		return false
	if plugin.plugin_metadata == null:
		LoggerGlobal.error("PluginManager: plugin '%s' has no metadata." % str(plugin.name))
		return false
	var plugin_id := plugin.plugin_metadata.id
	if plugin_id.is_empty():
		LoggerGlobal.error("PluginManager: cannot register a plugin with an empty id.")
		return false
	if _plugins.has(plugin_id):
		LoggerGlobal.error("PluginManager: plugin id '%s' is already registered." % plugin_id)
		return false
	if not _engine_version_compatible(plugin.plugin_metadata.engine_version):
		LoggerGlobal.error(
			"PluginManager: plugin '%s' requires engine '%s', current is '%s'." % [
				plugin_id,
				plugin.plugin_metadata.engine_version,
				Engine.get_version_info().string,
			]
		)
		return false

	_plugins[plugin_id] = plugin
	_status[plugin_id] = Status.REGISTERED
	_errors[plugin_id] = []
	_init_times_ms[plugin_id] = 0
	_enable_on_start[plugin_id] = plugin.plugin_metadata.enable_on_start

	_warn_missing_optional_deps(plugin_id)
	LoggerGlobal.info("PluginManager: registered plugin '%s' v%s." % [
		plugin_id, plugin.plugin_metadata.version
	])
	EventBus.emit(EventBus.PLUGIN_REGISTERED, {"plugin_id": plugin_id})
	return true


## Initialize a registered plugin. Automatically initializes any required
## dependencies first. Returns true on success.
func initialize_plugin(plugin_id: String) -> bool:
	var plugin := _get_plugin(plugin_id)
	if plugin == null:
		return false
	match _status[plugin_id]:
		Status.INITIALIZED, Status.ENABLED, Status.DISABLED:
			return true
		Status.INITIALIZING:
			_fail(plugin_id, "Circular dependency detected while initializing '%s'." % plugin_id)
			return false
		Status.FAILED, Status.SHUTDOWN, Status.UNLOADED:
			return false

	if not plugin.has_method("initialize"):
		_fail(plugin_id, "Missing initialize() method.")
		return false

	# Set INITIALIZING before resolving dependencies so that a dependency
	# cycle back into this plugin is detected by the guard above instead of
	# recursing until a stack overflow.
	_status[plugin_id] = Status.INITIALIZING
	var dep_error := _check_required_deps_ready(plugin_id)
	if not dep_error.is_empty():
		_fail(plugin_id, dep_error)
		return false

	var start_ms := Time.get_ticks_msec()
	var ok := plugin.initialize()
	if not ok:
		_fail(plugin_id, "initialize() returned false.")
		return false
	_init_times_ms[plugin_id] = Time.get_ticks_msec() - start_ms
	_status[plugin_id] = Status.INITIALIZED
	plugin._initialized = true
	LoggerGlobal.info("PluginManager: initialized plugin '%s' in %dms." % [
		plugin_id, _init_times_ms[plugin_id]
	])
	EventBus.emit(EventBus.PLUGIN_INITIALIZED, {"plugin_id": plugin_id})
	return true


## Enable an active plugin (initializes it first if needed). Returns true on
## success.
func enable_plugin(plugin_id: String) -> bool:
	var plugin := _get_plugin(plugin_id)
	if plugin == null:
		return false
	var current: int = _status[plugin_id]
	if current == Status.ENABLED:
		return true
	if current == Status.REGISTERED:
		if not initialize_plugin(plugin_id):
			return false
		current = _status[plugin_id]
	if current != Status.INITIALIZED and current != Status.DISABLED:
		_fail(plugin_id, "Cannot enable plugin in status %s." % _status_name(current))
		return false

	if not plugin.has_method("enable"):
		_fail(plugin_id, "Missing enable() method.")
		return false
	if not plugin.enable():
		_fail(plugin_id, "enable() returned false.")
		return false

	_status[plugin_id] = Status.ENABLED
	plugin._enabled = true
	LoggerGlobal.info("PluginManager: enabled plugin '%s'." % plugin_id)
	EventBus.emit(EventBus.PLUGIN_ENABLED, {"plugin_id": plugin_id})
	return true


## Disable an enabled plugin. Calls disable() and unsubscribes every tracked
## EventBus subscription so the plugin leaves no listeners behind.
func disable_plugin(plugin_id: String) -> bool:
	var plugin := _get_plugin(plugin_id)
	if plugin == null:
		return false
	if _status[plugin_id] != Status.ENABLED:
		return false

	if plugin.has_method("disable"):
		plugin.disable()
	plugin.unsubscribe_all_events()
	_status[plugin_id] = Status.DISABLED
	plugin._enabled = false
	LoggerGlobal.info("PluginManager: disabled plugin '%s'." % plugin_id)
	EventBus.emit(EventBus.PLUGIN_DISABLED, {"plugin_id": plugin_id})
	return true


## Shut down a plugin permanently (disables it first). Returns true on success.
func shutdown_plugin(plugin_id: String) -> bool:
	var plugin := _get_plugin(plugin_id)
	if plugin == null:
		return false
	if _status[plugin_id] == Status.SHUTDOWN or _status[plugin_id] == Status.UNLOADED:
		return true
	if _status[plugin_id] == Status.ENABLED:
		disable_plugin(plugin_id)

	if plugin.has_method("shutdown"):
		plugin.shutdown()
	plugin.unsubscribe_all_events()
	_status[plugin_id] = Status.SHUTDOWN
	plugin._enabled = false
	LoggerGlobal.info("PluginManager: shut down plugin '%s'." % plugin_id)
	EventBus.emit(EventBus.PLUGIN_SHUTDOWN, {"plugin_id": plugin_id})
	return true


## Unload a plugin: shuts it down, calls unload(), and removes it from the
## manager. Returns true on success.
func unload_plugin(plugin_id: String) -> bool:
	var plugin := _get_plugin(plugin_id)
	if plugin == null:
		return false
	shutdown_plugin(plugin_id)
	if plugin.has_method("unload"):
		plugin.unload()
	_plugins.erase(plugin_id)
	_status.erase(plugin_id)
	_init_times_ms.erase(plugin_id)
	_errors.erase(plugin_id)
	_enable_on_start.erase(plugin_id)
	LoggerGlobal.info("PluginManager: unloaded plugin '%s'." % plugin_id)
	EventBus.emit(EventBus.PLUGIN_UNLOADED, {"plugin_id": plugin_id})
	return true


## Shut down all plugins (reverse dependency order), used at engine shutdown.
func shutdown_all() -> void:
	var ids := _plugins.keys()
	ids.reverse()
	for plugin_id in ids:
		if _plugins.has(plugin_id):
			shutdown_plugin(plugin_id)


## --- Queries -----------------------------------------------------------------

func has_plugin(plugin_id: String) -> bool:
	return _plugins.has(plugin_id)


func get_plugin(plugin_id: String) -> Plugin:
	return _get_plugin(plugin_id)


func get_plugin_ids() -> Array:
	var ids: Array = []
	for id in _plugins:
		ids.append(id)
	return ids


func get_plugin_count() -> int:
	return _plugins.size()


func get_status(plugin_id: String) -> int:
	return int(_status.get(plugin_id, Status.UNLOADED))


func get_status_name(plugin_id: String) -> String:
	return _status_name(int(_status.get(plugin_id, Status.UNLOADED)))


func get_init_time_ms(plugin_id: String) -> int:
	return int(_init_times_ms.get(plugin_id, 0))


func get_plugin_errors(plugin_id: String) -> Array:
	if _errors.has(plugin_id):
		return (_errors[plugin_id] as Array).duplicate()
	return []


func get_enabled_plugins() -> Array:
	var result: Array = []
	for plugin_id in _plugins:
		if _status[plugin_id] == Status.ENABLED:
			result.append(plugin_id)
	return result


func get_disabled_plugins() -> Array:
	var result: Array = []
	for plugin_id in _plugins:
		var s: int = _status[plugin_id]
		if s == Status.DISABLED or s == Status.SHUTDOWN or s == Status.UNLOADED:
			result.append(plugin_id)
	return result


func get_failed_plugins() -> Array:
	var result: Array = []
	for plugin_id in _plugins:
		if _status[plugin_id] == Status.FAILED:
			result.append(plugin_id)
	return result


func get_engine_services() -> EngineServices:
	return engine_services


## --- Discovery queries -------------------------------------------------------

## All discovery records (valid and invalid) from the last scan, in
## deterministic order. Other systems can inspect validation status, errors,
## and warnings without coupling to the scanner.
func get_discovered_plugins() -> Array:
	return _discovered_records.duplicate()


## Plugin ids of every valid discovered plugin.
func get_discovered_plugin_ids() -> Array:
	var ids: Array = []
	for candidate in _discovered_records:
		if candidate.valid and not candidate.plugin_id.is_empty():
			ids.append(candidate.plugin_id)
	return ids


func is_plugin_discovered(plugin_id: String) -> bool:
	for candidate in _discovered_records:
		if candidate.plugin_id == plugin_id:
			return true
	return false


## Summary report of the most recent discovery scan.
func get_discovery_report() -> Dictionary:
	return _discovery_report.duplicate(true)


## Topological plugin initialization order (dependencies first), across all
## registered plugins — both discovered and programmatic.
func get_load_order() -> Array:
	return _resolve_init_order()


## --- Dependency management ---------------------------------------------------

## Warns (does not fail) when an optional dependency is not registered.
func _warn_missing_optional_deps(plugin_id: String) -> void:
	var plugin := _get_plugin(plugin_id)
	if plugin == null or plugin.plugin_metadata == null:
		return
	for dep in plugin.plugin_metadata.dependencies:
		var d: Plugin.PluginDependency = dep
		if d.optional and not _plugins.has(d.id):
			LoggerGlobal.warn(
				"PluginManager: plugin '%s' optional dependency '%s' is not registered." % [
					plugin_id, d.id
				]
			)


## Ensures every required dependency of a plugin is registered, initialized,
## and version-compatible. Returns an error string, or "" if all good.
func _check_required_deps_ready(plugin_id: String) -> String:
	var plugin := _get_plugin(plugin_id)
	if plugin == null or plugin.plugin_metadata == null:
		return ""
	for dep in plugin.plugin_metadata.dependencies:
		var d: Plugin.PluginDependency = dep
		if d.optional:
			continue
		if not _plugins.has(d.id):
			return "Required dependency '%s' is not registered." % d.id
		var dep_plugin := _get_plugin(d.id)
		if dep_plugin != null and dep_plugin.plugin_metadata != null \
				and not _version_satisfies(dep_plugin.plugin_metadata.version, d.min_version, d.max_version):
			return "Dependency '%s' v%s is incompatible (requires min '%s', max '%s')." % [
				d.id, dep_plugin.plugin_metadata.version, d.min_version, d.max_version
			]
		if _status[d.id] != Status.INITIALIZED and _status[d.id] != Status.ENABLED:
			# Initialize the dependency first; cycles are caught via INITIALIZING.
			if not initialize_plugin(d.id):
				return "Required dependency '%s' failed to initialize." % d.id
	return ""


## Resolves a stable initialization order (dependencies first). Detects
## dependency cycles and marks the involved plugins FAILED.
func _resolve_init_order() -> Array:
	var order: Array = []
	var visited: Dictionary = {}
	var visiting: Dictionary = {}
	for plugin_id in _plugins:
		_resolve_dfs(plugin_id, visited, visiting, order)
	return order


func _resolve_dfs(plugin_id: String, visited: Dictionary, visiting: Dictionary,
		order: Array) -> void:
	if visited.has(plugin_id):
		return
	if visiting.has(plugin_id):
		_fail(plugin_id, "Circular dependency detected (cycle involves '%s')." % plugin_id)
		return
	visiting[plugin_id] = true
	var plugin := _get_plugin(plugin_id)
	if plugin != null and plugin.plugin_metadata != null:
		for dep in plugin.plugin_metadata.dependencies:
			var d: Plugin.PluginDependency = dep
			if not d.optional and _plugins.has(d.id):
				_resolve_dfs(d.id, visited, visiting, order)
	visiting.erase(plugin_id)
	visited[plugin_id] = true
	order.append(plugin_id)


## --- Error handling ----------------------------------------------------------

## Marks a plugin FAILED: logs, records the error, disables it, unsubscribes
## its events, and emits PLUGIN_ERROR. The engine continues running.
func _fail(plugin_id: String, message: String) -> void:
	if not _plugins.has(plugin_id):
		return
	var plugin := _get_plugin(plugin_id)
	if plugin != null:
		plugin._enabled = false
		plugin.unsubscribe_all_events()
	_status[plugin_id] = Status.FAILED
	_append_error(plugin_id, message)
	LoggerGlobal.error("PluginManager: plugin '%s' failed: %s" % [plugin_id, message])
	EventBus.emit(EventBus.PLUGIN_ERROR, {"plugin_id": plugin_id, "message": message})


## Public entry point for plugins to self-report a non-fatal error. Logs,
## records, emits PLUGIN_ERROR. Does not disable the plugin.
func report_plugin_error(plugin_id: String, message: String) -> void:
	if not _plugins.has(plugin_id):
		LoggerGlobal.error("PluginManager: error from unknown plugin '%s': %s" % [plugin_id, message])
		return
	_append_error(plugin_id, message)
	LoggerGlobal.error("PluginManager: plugin '%s' error: %s" % [plugin_id, message])
	EventBus.emit(EventBus.PLUGIN_ERROR, {"plugin_id": plugin_id, "message": message})


func _append_error(plugin_id: String, message: String) -> void:
	if not _errors.has(plugin_id):
		_errors[plugin_id] = []
	var errors: Array = _errors[plugin_id]
	errors.append(message)
	if errors.size() > MAX_ERRORS_PER_PLUGIN:
		errors.pop_front()


## --- Version helpers ---------------------------------------------------------

## Returns true if the plugin's declared engine version requirement is met by
## the running engine. Empty requirement means "any". Supports operators
## (>=, <=, >, <, ==) and dotted versions; bare "4" or "4.7" are accepted.
func engine_version_compatible(required: String) -> bool:
	return _engine_version_compatible(required)


## Returns true if `actual` satisfies both min and max constraints (inclusive).
## Empty min/max means "no constraint". Public so discovery and other systems
## reuse the same version semantics.
func version_satisfies(actual: String, min_version: String, max_version: String) -> bool:
	return _version_satisfies(actual, min_version, max_version)


## Returns true if the running engine version is explicitly listed in the
## plugin's supported_engine_versions (triplet equality). Empty list = "any".
func supports_engine_versions(supported: Array) -> bool:
	if supported.is_empty():
		return true
	var current := _current_version_triplet()
	for v in supported:
		if _compare_triplets(current, _version_triplet(str(v))) == 0:
			return true
	return false


func _engine_version_compatible(required: String) -> bool:
	if required.strip_edges().is_empty():
		return true
	var current := _current_version_triplet()
	var op := ">="
	var version_text := required.strip_edges()
	for candidate in [">=", "<=", "==", ">", "<"]:
		if version_text.begins_with(candidate):
			op = candidate
			version_text = version_text.substr(candidate.length()).strip_edges()
			break
	var target := _version_triplet(version_text)
	var cmp := _compare_triplets(current, target)
	match op:
		">=":
			return cmp >= 0
		"<=":
			return cmp <= 0
		"==":
			return cmp == 0
		">":
			return cmp > 0
		"<":
			return cmp < 0
	return cmp >= 0


## Returns true if `actual` satisfies both min and max constraints (inclusive).
## Empty min/max means "no constraint".
func _version_satisfies(actual: String, min_version: String, max_version: String) -> bool:
	var a := _version_triplet(actual)
	if not min_version.strip_edges().is_empty() and _compare_triplets(a, _version_triplet(min_version)) < 0:
		return false
	if not max_version.strip_edges().is_empty() and _compare_triplets(a, _version_triplet(max_version)) > 0:
		return false
	return true


func _version_triplet(version_text: String) -> Array:
	var parts := version_text.strip_edges().split(".")
	var out := [0, 0, 0]
	for i in mini(parts.size(), 3):
		if parts[i].is_valid_int():
			out[i] = int(parts[i])
	return out


## Triplet for the running engine, parsed from the numeric version fields.
## Engine.get_version_info().string is not dotted (e.g. "4.7-stable (official)")
## so string parsing would silently lose the minor/patch digits.
func _current_version_triplet() -> Array:
	var info := Engine.get_version_info()
	return [int(info.major), int(info.minor), int(info.patch)]


func _compare_triplets(a: Array, b: Array) -> int:
	for i in 3:
		if int(a[i]) < int(b[i]):
			return -1
		if int(a[i]) > int(b[i]):
			return 1
	return 0


## --- Introspection -----------------------------------------------------------

func _get_plugin(plugin_id: String) -> Plugin:
	return _plugins.get(plugin_id) as Plugin


func _status_name(status: int) -> String:
	return Status.keys()[status]


## --- Debug support -----------------------------------------------------------

func get_debug_info() -> Dictionary:
	var plugins_data := {}
	for plugin_id in _plugins:
		var plugin := _get_plugin(plugin_id)
		var data: Dictionary = plugin.get_metadata() if plugin != null else {}
		data["status"] = _status_name(int(_status[plugin_id]))
		data["init_time_ms"] = int(_init_times_ms[plugin_id])
		data["errors"] = get_plugin_errors(plugin_id)
		data["event_subscriptions"] = plugin._subscriptions.size() if plugin != null else 0
		plugins_data[plugin_id] = data

	return {
		"plugin_count": _plugins.size(),
		"loaded": get_plugin_ids(),
		"enabled": get_enabled_plugins(),
		"disabled": get_disabled_plugins(),
		"failed": get_failed_plugins(),
		"plugins": plugins_data,
		"discovery": _debug_discovery_info(),
	}


## Discovery info for the debug overlay: scan summary, load order, validation
## status per folder, errors, warnings, and registered plugin types.
func _debug_discovery_info() -> Dictionary:
	var records: Array = []
	var types := {}
	for candidate in _discovered_records:
		records.append(candidate.get_debug_info())
		if candidate.valid and not candidate.category.is_empty():
			types[candidate.category] = int(types.get(candidate.category, 0)) + 1
	return {
		"scanned_dir": _discovery_report.get("scanned_dir", ""),
		"folders_found": _discovery_report.get("folders_found", 0),
		"valid": _discovery_report.get("valid", 0),
		"invalid": _discovery_report.get("invalid", 0),
		"newly_registered": _discovery_report.get("newly_registered", 0),
		"load_order": get_load_order(),
		"types": types,
		"errors": _discovery_report.get("errors", []),
		"warnings": _discovery_report.get("warnings", []),
		"plugins": records,
	}
