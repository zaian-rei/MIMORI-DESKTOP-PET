extends Node
class_name Plugin

## Base class for engine plugins. Plugins extend Plugin and override the
## lifecycle methods. The PluginManager NEVER knows what a plugin does - it
## only decides WHEN each lifecycle method runs.
##
## Design contract:
##   - Plugins communicate through the EventBus. They must not hardcode
##     references to engine internals; the only sanctioned engine access is
##     through PluginManager.get_engine_services().
##   - Subscribing via subscribe_event() lets the PluginManager cleanly
##     unsubscribe every subscription when a plugin is disabled, shut down,
##     or marked failed - no orphan listeners.
##   - Lifecycle methods return true on success. Returning false - or erroring
##     out (GDScript aborts the method and returns the default) - causes the
##     manager to mark the plugin FAILED and disable it. The engine keeps
##     running regardless: script errors abort only the plugin's own method.
##   - Metadata is declarative: the manager reads it, never executes it.

## --- Metadata ----------------------------------------------------------------

## Declares an optional or required dependency on another plugin.
class PluginDependency:
	var id: String
	var min_version: String
	var max_version: String
	var optional: bool

	func _init(p_id: String, p_min: String = "", p_max: String = "",
			p_optional: bool = false) -> void:
		id = p_id
		min_version = p_min
		max_version = p_max
		optional = p_optional


## Static, author-declared identity of a plugin. Read by the PluginManager at
## registration; never mutated by the manager.
class PluginMetadata:
	var id: String
	var name: String
	var version: String
	var author: String
	var description: String
	var engine_version: String
	var category: String
	var enable_on_start: bool
	var dependencies: Array  # Array[PluginDependency]
	var supported_engine_versions: Array = []  # Array[String]; empty = any

	func _init(p_id: String, p_name: String, p_version: String = "1.0.0",
			p_author: String = "", p_description: String = "",
			p_engine_version: String = "", p_category: String = "general",
			p_enable_on_start: bool = true, p_dependencies: Array = [],
			p_supported_engine_versions: Array = []) -> void:
		id = p_id
		name = p_name
		version = p_version
		author = p_author
		description = p_description
		engine_version = p_engine_version
		category = p_category
		enable_on_start = p_enable_on_start
		dependencies = p_dependencies
		supported_engine_versions = p_supported_engine_versions


## The plugin's declarative identity. Must be set by the subclass before it is
## registered with the PluginManager (typically in _init()).
var plugin_metadata: PluginMetadata

## --- Internal lifecycle state (managed by the PluginManager) -----------------

var _initialized: bool = false
var _enabled: bool = false
var _subscriptions: Array = []  # Array[Dictionary] of {event, callback}


## --- Lifecycle hooks ---------------------------------------------------------

## Set up resources, register settings, prepare data. The plugin is NOT active
## yet (no events, no behavior). Return true on success.
func initialize() -> bool:
	return true


## Start acting: subscribe to events, start timers, apply behaviors.
## Return true on success.
func enable() -> bool:
	return true


## Stop acting: pause timers, hide UI, stop behaviors. Event subscriptions
## made through subscribe_event() are unsubscribed by the manager afterwards.
func disable() -> bool:
	return true


## Permanent teardown: release resources. Called before the plugin is unloaded
## and during engine shutdown.
func shutdown() -> bool:
	return true


## Final cleanup right before the plugin is removed from the manager.
func unload() -> void:
	pass


## --- State queries -----------------------------------------------------------

func is_initialized() -> bool:
	return _initialized


func is_enabled() -> bool:
	return _enabled


## --- EventBus helpers (tracked so the manager can clean up) ------------------

## Subscribe to an EventBus event and track the subscription for automatic
## cleanup on disable/shutdown/failure.
func subscribe_event(event_name: StringName, callback: Callable) -> void:
	if not callback.is_valid():
		LoggerGlobal.warn("Plugin '%s': cannot subscribe an invalid callback." % _id_for_log())
		return
	EventBus.subscribe(event_name, callback)
	_subscriptions.append({"event": event_name, "callback": callback})


## Unsubscribe from an EventBus event and stop tracking it.
func unsubscribe_event(event_name: StringName, callback: Callable) -> void:
	EventBus.unsubscribe(event_name, callback)
	for i in range(_subscriptions.size() - 1, -1, -1):
		var sub: Dictionary = _subscriptions[i]
		if sub["event"] == event_name and sub["callback"] == callback:
			_subscriptions.remove_at(i)


## Unsubscribe every tracked EventBus subscription. Called by the manager on
## disable, shutdown, and failure.
func unsubscribe_all_events() -> void:
	for sub in _subscriptions:
		EventBus.unsubscribe(sub["event"], sub["callback"])
	_subscriptions.clear()


## --- Error reporting ---------------------------------------------------------

## Report a non-fatal plugin error. Logs it, records it in the manager, and
## emits PLUGIN_ERROR. Does NOT disable the plugin.
func report_error(message: String) -> void:
	if plugin_metadata != null and not plugin_metadata.id.is_empty():
		PluginManager.report_plugin_error(plugin_metadata.id, message)
	else:
		LoggerGlobal.error("Plugin: %s" % message)


## --- Introspection -----------------------------------------------------------

## Full metadata as a JSON-safe Dictionary. Includes current enabled state so
## plugins can be rendered in the debug overlay without extra plumbing.
func get_metadata() -> Dictionary:
	var deps: Array = []
	if plugin_metadata != null:
		for dep in plugin_metadata.dependencies:
			var d: PluginDependency = dep
			deps.append({
				"id": d.id,
				"min_version": d.min_version,
				"max_version": d.max_version,
				"optional": d.optional,
			})
	return {
		"id": plugin_metadata.id if plugin_metadata != null else "",
		"name": plugin_metadata.name if plugin_metadata != null else "",
		"version": plugin_metadata.version if plugin_metadata != null else "",
		"author": plugin_metadata.author if plugin_metadata != null else "",
		"description": plugin_metadata.description if plugin_metadata != null else "",
		"engine_version": plugin_metadata.engine_version if plugin_metadata != null else "",
		"supported_engine_versions": plugin_metadata.supported_engine_versions if plugin_metadata != null else [],
		"category": plugin_metadata.category if plugin_metadata != null else "",
		"enable_on_start": plugin_metadata.enable_on_start if plugin_metadata != null else true,
		"dependencies": deps,
		"enabled": _enabled,
		"initialized": _initialized,
	}


## Default debug interface, consumed by the debug overlay.
func get_debug_info() -> Dictionary:
	return get_metadata()


func _id_for_log() -> String:
	if plugin_metadata != null and not plugin_metadata.id.is_empty():
		return plugin_metadata.id
	return str(get_instance_id())
