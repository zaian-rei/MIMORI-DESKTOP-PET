extends Plugin

var init_calls := 0
var enable_calls := 0

func initialize() -> bool:
	init_calls += 1
	PluginManager.get_engine_services().register_setting(
		"fixtures.dep_core", "plugins", TYPE_BOOL, true,
		null, null, "Set by fixture_dep_core plugin")
	return true

func enable() -> bool:
	enable_calls += 1
	EventBus.emit(&"fixture_core_ready", {"core_version": "2.0.0"})
	return true
