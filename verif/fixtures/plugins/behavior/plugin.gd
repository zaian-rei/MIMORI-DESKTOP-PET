extends Plugin

var trigger_count := 0
var core_enabled_before := false

func enable() -> bool:
	core_enabled_before = PluginManager.get_status("fixture_dep_core") == PluginManager.Status.ENABLED
	subscribe_event(&"fixture_trigger", _on_trigger)
	return true

func _on_trigger(_payload: Dictionary) -> void:
	trigger_count += 1
