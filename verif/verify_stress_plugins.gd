extends Node

## Plugin System Core stress harness.
## Covers: registration validation, boot auto-start, manual lifecycle,
## runtime enable/disable, event unsubscription on disable, dependency
## ordering + version checks + cycles, error isolation (broken plugin never
## crashes the engine), settings integration, theme event integration, and
## debug introspection.

var _fails := 0

## --- Test plugin types -------------------------------------------------------

## Basic plugin with call counters and configurable failures.
class CountingPlugin extends Plugin:
	var init_calls := 0
	var enable_calls := 0
	var disable_calls := 0
	var shutdown_calls := 0
	var unload_calls := 0
	var theme_events: Array = []
	var fail_init := false
	var fail_enable := false

	func _init(p_id: String, p_name: String = "Counting Plugin",
			p_version: String = "1.0.0", p_engine: String = "",
			p_deps: Array = []) -> void:
		plugin_metadata = Plugin.PluginMetadata.new(
			p_id, p_name, p_version, "Harness", "Test plugin", p_engine,
			"developer", true, p_deps)

	func initialize() -> bool:
		init_calls += 1
		return not fail_init

	func enable() -> bool:
		enable_calls += 1
		return not fail_enable

	func disable() -> bool:
		disable_calls += 1
		return true

	func shutdown() -> bool:
		shutdown_calls += 1
		return true

	func unload() -> void:
		unload_calls += 1

	func on_theme_changed(payload: Dictionary) -> void:
		theme_events.append(payload)


## Registers a setting at initialize() via engine services.
class SettingsPlugin extends Plugin:
	func _init() -> void:
		plugin_metadata = Plugin.PluginMetadata.new(
			"settings_plugin", "Settings Plugin")

	func initialize() -> bool:
		PluginManager.get_engine_services().register_setting(
			"plugins.test_float", "plugins", TYPE_FLOAT, 1.5, 0.0, 10.0,
			"Plugin-registered setting")
		return true


## Enable() calls a nonexistent method -> runtime error aborts enable() ->
## returns false -> manager must mark FAILED, engine must survive.
class BombPlugin extends Plugin:
	func _init() -> void:
		plugin_metadata = Plugin.PluginMetadata.new("bomb_plugin", "Bomb Plugin")

	func enable() -> bool:
		call("_nonexistent_method")
		return true


## --- Harness -----------------------------------------------------------------

func _ready() -> void:
	EventBus.reset_debug_data()

	## 1. Boot auto-start: plugin registered during this _ready should be
	##    initialized + enabled by the manager's deferred boot.
	var boot_plugin := CountingPlugin.new("boot_plugin")
	var reg_ok := PluginManager.register_plugin(boot_plugin)
	_check("register returns true", reg_ok)
	_check("status REGISTERED after register",
		PluginManager.get_status("boot_plugin") == PluginManager.Status.REGISTERED)

	await _frames(3)
	_check("boot auto-initialized", boot_plugin.init_calls == 1)
	_check("boot auto-enabled", boot_plugin.enable_calls == 1)
	_check("status ENABLED after boot",
		PluginManager.get_status("boot_plugin") == PluginManager.Status.ENABLED)

	PluginManager.unload_plugin("boot_plugin")
	_check("unload removes plugin", not PluginManager.has_plugin("boot_plugin"))
	_check("unload called unload()", boot_plugin.unload_calls == 1)

	## 2. Registration validation ---------------------------------------------
	var empty_id := CountingPlugin.new("")
	_check("reject empty id", not PluginManager.register_plugin(empty_id))
	empty_id.free()

	var dup := CountingPlugin.new("dup_plugin")
	PluginManager.register_plugin(dup)
	var dup2 := CountingPlugin.new("dup_plugin")
	_check("reject duplicate id", not PluginManager.register_plugin(dup2))
	dup2.free()

	var bad_engine := CountingPlugin.new("bad_engine", "Bad Engine", "1.0.0", "999.0")
	_check("reject engine-incompatible plugin",
		not PluginManager.register_plugin(bad_engine))
	bad_engine.free()

	var no_meta := Plugin.new()
	_check("reject plugin without metadata", not PluginManager.register_plugin(no_meta))
	no_meta.free()

	PluginManager.unload_plugin("dup_plugin")

	## 3. Manual lifecycle -----------------------------------------------------
	var life := CountingPlugin.new("life_plugin")
	PluginManager.register_plugin(life)
	_check("initialize returns true", PluginManager.initialize_plugin("life_plugin"))
	_check("init counter", life.init_calls == 1)
	_check("status INITIALIZED",
		PluginManager.get_status("life_plugin") == PluginManager.Status.INITIALIZED)
	_check("init idempotent", PluginManager.initialize_plugin("life_plugin"))
	_check("no double init", life.init_calls == 1)

	_check("enable returns true", PluginManager.enable_plugin("life_plugin"))
	_check("enable counter", life.enable_calls == 1)
	_check("plugin.is_enabled", life.is_enabled())

	_check("disable returns true", PluginManager.disable_plugin("life_plugin"))
	_check("disable counter", life.disable_calls == 1)
	_check("status DISABLED",
		PluginManager.get_status("life_plugin") == PluginManager.Status.DISABLED)
	_check("plugin not enabled after disable", not life.is_enabled())

	_check("re-enable works", PluginManager.enable_plugin("life_plugin"))
	_check("re-enable counter", life.enable_calls == 2)

	_check("shutdown returns true", PluginManager.shutdown_plugin("life_plugin"))
	_check("shutdown counter", life.shutdown_calls == 1)
	_check("status SHUTDOWN",
		PluginManager.get_status("life_plugin") == PluginManager.Status.SHUTDOWN)

	PluginManager.unload_plugin("life_plugin")

	## 4. Enable auto-initializes ----------------------------------------------
	var lazy := CountingPlugin.new("lazy_plugin")
	PluginManager.register_plugin(lazy)
	_check("enable auto-inits", PluginManager.enable_plugin("lazy_plugin"))
	_check("auto init ran", lazy.init_calls == 1)
	PluginManager.unload_plugin("lazy_plugin")

	## 5. Event subscription lifecycle ------------------------------------------
	var event_plugin := CountingPlugin.new("event_plugin")
	PluginManager.register_plugin(event_plugin)
	PluginManager.enable_plugin("event_plugin")
	event_plugin.subscribe_event(EventBus.THEME_CHANGED, event_plugin.on_theme_changed)
	var before_listeners: Variant = EventBus.get_debug_info().get("current_listeners")
	EventBus.emit(EventBus.THEME_CHANGED, {"theme_id": "a"})
	_check("plugin receives themed event", event_plugin.theme_events.size() == 1)

	PluginManager.disable_plugin("event_plugin")
	var after_disable: Variant = EventBus.get_debug_info().get("current_listeners")
	_check("disable unsubscribes events (no listeners leak)",
		after_disable <= before_listeners)
	EventBus.emit(EventBus.THEME_CHANGED, {"theme_id": "b"})
	_check("disabled plugin does not receive events", event_plugin.theme_events.size() == 1)
	_check("plugin subscriptions cleared", event_plugin._subscriptions.is_empty())
	PluginManager.unload_plugin("event_plugin")

	## 6. Dependency ordering ---------------------------------------------------
	var child := CountingPlugin.new("dep_child", "Child", "1.0.0", "",
		[Plugin.PluginDependency.new("dep_parent")])
	var parent := CountingPlugin.new("dep_parent", "Parent")
	PluginManager.register_plugin(child)
	PluginManager.register_plugin(parent)
	PluginManager.initialize_plugin("dep_child")
	_check("dependency auto-initialized first", parent.init_calls == 1)
	_check("child initialized after dep", child.init_calls == 1)
	PluginManager.unload_plugin("dep_child")
	PluginManager.unload_plugin("dep_parent")

	## 7. Optional dependency missing -> still works ---------------------------
	var opt := CountingPlugin.new("opt_plugin", "Opt", "1.0.0", "",
		[Plugin.PluginDependency.new("ghost_dep", "", "", true)])
	PluginManager.register_plugin(opt)
	_check("optional dep missing still initializes",
		PluginManager.initialize_plugin("opt_plugin"))
	PluginManager.unload_plugin("opt_plugin")

	## 8. Required dependency missing -> FAILED, engine continues --------------
	var missing := CountingPlugin.new("missing_dep", "Missing", "1.0.0", "",
		[Plugin.PluginDependency.new("ghost_dep")])
	PluginManager.register_plugin(missing)
	_check("missing required dep fails", not PluginManager.initialize_plugin("missing_dep"))
	_check("status FAILED", PluginManager.get_status("missing_dep") == PluginManager.Status.FAILED)
	_check("failed plugin listed", PluginManager.get_failed_plugins().has("missing_dep"))
	_check("error recorded", PluginManager.get_plugin_errors("missing_dep").size() >= 1)
	PluginManager.unload_plugin("missing_dep")

	## 9. Version-incompatible dependency --------------------------------------
	var parent_v1 := CountingPlugin.new("ver_parent", "VerParent", "2.0.0")
	PluginManager.register_plugin(parent_v1)
	var child_v := CountingPlugin.new("ver_child", "VerChild", "1.0.0", "",
		[Plugin.PluginDependency.new("ver_parent", "3.0.0")])
	PluginManager.register_plugin(child_v)
	_check("version-incompatible dep fails", not PluginManager.initialize_plugin("ver_child"))
	_check("version mismatch FAILED",
		PluginManager.get_status("ver_child") == PluginManager.Status.FAILED)
	PluginManager.unload_plugin("ver_child")
	PluginManager.unload_plugin("ver_parent")

	## 10. Circular dependency --------------------------------------------------
	var cyc_a := CountingPlugin.new("cyc_a", "CycA", "1.0.0", "",
		[Plugin.PluginDependency.new("cyc_b")])
	var cyc_b := CountingPlugin.new("cyc_b", "CycB", "1.0.0", "",
		[Plugin.PluginDependency.new("cyc_a")])
	PluginManager.register_plugin(cyc_a)
	PluginManager.register_plugin(cyc_b)
	var cyc_before: Variant = PluginManager.get_plugin_ids().size()
	PluginManager.enable_plugin("cyc_a")
	_check("circular dep does not hang (boot continued)", true)
	_check("cycle detected -> FAILED", PluginManager.get_status("cyc_a") == PluginManager.Status.FAILED \
		or PluginManager.get_status("cyc_b") == PluginManager.Status.FAILED)
	_check("plugins still tracked", PluginManager.get_plugin_ids().size() == cyc_before)
	PluginManager.unload_plugin("cyc_a")
	PluginManager.unload_plugin("cyc_b")

	## 11. Broken plugin error isolation ----------------------------------------
	var bomb := BombPlugin.new()
	PluginManager.register_plugin(bomb)
	PluginManager.enable_plugin("bomb_plugin")
	_check("bombed plugin marked FAILED",
		PluginManager.get_status("bomb_plugin") == PluginManager.Status.FAILED)
	_check("engine survived broken plugin (this line reached)", true)
	PluginManager.unload_plugin("bomb_plugin")

	## 12. Settings integration -------------------------------------------------
	var settings_plugin := SettingsPlugin.new()
	PluginManager.register_plugin(settings_plugin)
	PluginManager.initialize_plugin("settings_plugin")
	_check("plugin setting registered in SettingsManager",
		SettingsManager.has_setting("plugins.test_float"))
	var sval: Variant = SettingsManager.get_setting("plugins.test_float", null)
	_check("plugin setting default value", sval == 1.5)
	PluginManager.unload_plugin("settings_plugin")

	## 13. Non-fatal error reporting --------------------------------------------
	var reporter := CountingPlugin.new("reporter_plugin")
	PluginManager.register_plugin(reporter)
	reporter.report_error("something is off")
	_check("error recorded", PluginManager.get_plugin_errors("reporter_plugin").size() >= 1)
	_check("non-fatal error does not disable",
		PluginManager.get_status("reporter_plugin") != PluginManager.Status.FAILED)
	PluginManager.unload_plugin("reporter_plugin")

	## 14. Debug introspection --------------------------------------------------
	var info: Dictionary = PluginManager.get_debug_info()
	var infosize: Variant = info.get("plugin_count")
	_check("debug info present", infosize == PluginManager.get_plugin_count())

	## 15. Engine-version compatibility helpers ---------------------------------
	_check("engine 4.7 satisfies >=4.0", PluginManager._engine_version_compatible(">=4.0"))
	_check("engine 4.7 satisfies <5.0", PluginManager._engine_version_compatible("<5.0"))
	_check("engine 4.7 does not satisfy >=5.0", not PluginManager._engine_version_compatible(">=5.0"))

	print("[VERIFY] DONE plugin_stress fails=%d -> %s" % [_fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[VERIFY] PASS %s" % label)
	else:
		_fails += 1
		printerr("[VERIFY] FAIL %s" % label)
