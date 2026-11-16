extends Node

## Plugin Discovery & Loading stress harness.
## Covers: boot-time auto-discovery, explicit discovery, manifest parsing,
## validation (structure / engine / supported-versions / dependencies),
## load ordering by category priority + topological deps, registration,
## settings integration, theme-plugin self-registration, EventBus decoupling,
## idempotent re-scan (hot-reload readiness), debug introspection, and the
## guarantee that broken plugins never crash the engine.

const FIXTURES_DIR := "res://verif/fixtures/plugins/"
const BOOT_DIR := "res://plugins/"
const TRIGGER_EVENT := &"fixture_trigger"

const EXPECTED_FIXTURES := [
	"fixture_dep_core", "fixture_behavior", "fixture_theme",
	"fixture_optional", "fixture_supported_ok",
]
const EXPECTED_INVALID := [
	"fixture_invalid_broken_script", "fixture_invalid_missing_entry",
	"fixture_invalid_engine", "fixture_invalid_supported_list",
	"fixture_invalid_dep_missing", "fixture_invalid_dep_version",
]
const EXPECTED_LOAD_ORDER := [
	"fixture_dep_core", "fixture_behavior", "fixture_theme",
	"fixture_optional", "fixture_supported_ok",
]

var _fails := 0


func _ready() -> void:
	_cleanup_boot_plugins()

	## 1. Boot-time auto-discovery --------------------------------------------
	_plant_boot_plugins()
	await _frames(4)

	_check("boot: discovered boot_core_plugin",
		PluginManager.has_plugin("boot_core_plugin"))
	_check("boot: discovered boot_behavior_plugin",
		PluginManager.has_plugin("boot_behavior_plugin"))
	_check("boot: core initialized",
		PluginManager.get_status("boot_core_plugin") == PluginManager.Status.ENABLED)
	_check("boot: behavior initialized",
		PluginManager.get_status("boot_behavior_plugin") == PluginManager.Status.ENABLED)
	var boot_order: Array = PluginManager.get_load_order()
	var boot_core_at: int = boot_order.find("boot_core_plugin")
	var boot_behavior_at: int = boot_order.find("boot_behavior_plugin")
	_check("boot: dependency before dependent in load order",
		boot_core_at != -1 and boot_behavior_at != -1 and boot_core_at < boot_behavior_at)
	var boot_report: Dictionary = PluginManager.get_discovery_report()
	_check("boot: report scanned res://plugins/",
		"res://plugins/" == boot_report.get("scanned_dir"))
	_check("boot: 2 valid discovered", boot_report.get("valid") == 2)
	_check("boot: 0 invalid discovered", boot_report.get("invalid") == 0)
	_check("boot: 2 newly registered", boot_report.get("newly_registered") == 2)

	var boot_core := PluginManager.get_plugin("boot_core_plugin")
	_check("boot: core setting registered",
		SettingsManager.has_setting("fixtures.boot_core") and SettingsManager.get_setting("fixtures.boot_core") == true)
	_check("boot: core emit ran", boot_core.get("enable_calls") == 1)

	## 2. Cleanup boot plugins ------------------------------------------------
	PluginManager.unload_plugin("boot_core_plugin")
	PluginManager.unload_plugin("boot_behavior_plugin")
	_check("boot: plugins unloaded", PluginManager.get_plugin_count() == 0)
	_cleanup_boot_plugins()
	_check("boot: plugin folders removed", not FileAccess.file_exists(BOOT_DIR + "boot_core/plugin.json"))

	## 3. Explicit discovery of fixtures ---------------------------------------
	var report: Dictionary = PluginManager.discover_plugins(FIXTURES_DIR)
	_check("fixtures: 13 folders found", report.get("folders_found") == 13)
	_check("fixtures: 5 valid", report.get("valid") == 5)
	_check("fixtures: 8 invalid", report.get("invalid") == 8)
	_check("fixtures: 5 newly registered", report.get("newly_registered") == 5)
	_check("fixtures: 0 already registered", report.get("already_registered") == 0)
	_check("fixtures: 0 registration failures", report.get("registration_failures") == 0)
	_check("fixtures: 8 aggregated errors", report.get("errors").size() == 8)

	## 4. Registry queries -----------------------------------------------------
	var discovered_ids: Array = PluginManager.get_discovered_plugin_ids()
	for id in EXPECTED_FIXTURES:
		_check("registry: discovered id '%s'" % id, discovered_ids.has(id))
	for id in EXPECTED_INVALID:
		_check("registry: invalid id '%s' present" % id, PluginManager.is_plugin_discovered(id))
	_check("registry: invalid ids not in manager",
		not PluginManager.has_plugin("fixture_invalid_engine"))
	_check("registry: plugin count is 5", PluginManager.get_plugin_count() == 5)

	## 5. Enable fixtures in load order (register -> initialize -> enable) ----
	for id in EXPECTED_LOAD_ORDER:
		PluginManager.enable_plugin(id)

	var order: Array = PluginManager.get_load_order()
	_check("load order matches category priority + deps",
		order == EXPECTED_LOAD_ORDER)

	var core := PluginManager.get_plugin("fixture_dep_core")
	var behavior := PluginManager.get_plugin("fixture_behavior")
	_check("fixtures: core initialized once", core.get("init_calls") == 1)
	_check("fixtures: core enabled", core.get("enable_calls") == 1)
	_check("fixtures: core setting registered",
		SettingsManager.has_setting("fixtures.dep_core") and SettingsManager.get_setting("fixtures.dep_core") == true)
	_check("fixtures: behavior dependency enabled before it",
		behavior.get("core_enabled_before") == true)
	_check("fixtures: all enabled",
		PluginManager.get_enabled_plugins().size() == 5)

	## 6. EventBus decoupling --------------------------------------------------
	var before_triggers: int = behavior.get("trigger_count")
	for i in 2:
		EventBus.emit(TRIGGER_EVENT, {"n": i})
	_check("fixtures: behavior subscribed via EventBus",
		behavior.get("trigger_count") == before_triggers + 2)

	## 7. Theme plugin self-registration ---------------------------------------
	_check("themes: plugin theme registered",
		ThemeManager.has_theme("fixture_theme_plugin"))
	var installed := ThemeManager.get_installed_themes()
	var theme_found := false
	for t in installed:
		if t["id"] == "fixture_theme_plugin":
			theme_found = true
	_check("themes: plugin theme listed", theme_found)

	## 8. Optional dependency warning ------------------------------------------
	var warn_found := false
	for w in report.get("warnings"):
		if str(w).begins_with("fixture_optional: Optional dependency 'fixture_ghost'"):
			warn_found = true
	_check("fixtures: optional missing dep only warns", warn_found)
	_check("fixtures: optional plugin still enabled",
		PluginManager.get_status("fixture_optional") == PluginManager.Status.ENABLED)

	## 9. Invalid candidates never loaded --------------------------------------
	for id in EXPECTED_INVALID:
		_check("invalid: '%s' not registered" % id, not PluginManager.has_plugin(id))
	_check("invalid: broken script never instantiated",
		not PluginManager.has_plugin("fixture_invalid_broken_script"))
	var broken_record: Dictionary = {}
	var invalid_detail := {}
	for candidate in PluginManager.get_discovered_plugins():
		if candidate.plugin_id == "fixture_invalid_engine":
			broken_record = candidate.get_debug_info()
		if candidate.plugin_id == "fixture_invalid_dep_version":
			invalid_detail = candidate.get_debug_info()
	_check("invalid: engine mismatch recorded",
		broken_record.get("valid") == false and not broken_record.get("errors").is_empty())
	_check("invalid: dep version mismatch recorded",
		invalid_detail.get("valid") == false and str(invalid_detail.get("errors")).contains("does not satisfy"))
	_check("invalid: engine survived (this line reached)", true)

	## 10. Idempotent re-scan (hot-reload readiness) ----------------------------
	var report2: Dictionary = PluginManager.discover_plugins(FIXTURES_DIR)
	_check("rescan: 0 newly registered", report2.get("newly_registered") == 0)
	_check("rescan: 5 already registered", report2.get("already_registered") == 5)
	_check("rescan: no duplicate plugins", PluginManager.get_plugin_count() == 5)

	## 11. Debug introspection ---------------------------------------------------
	var info: Dictionary = PluginManager.get_debug_info()
	var discovery: Dictionary = info.get("discovery")
	_check("debug: discovery section present", not discovery.is_empty())
	_check("debug: valid count", discovery.get("valid") == 5)
	_check("debug: invalid count", discovery.get("invalid") == 8)
	_check("debug: load order exposed", discovery.get("load_order") == EXPECTED_LOAD_ORDER)
	var types: Dictionary = discovery.get("types")
	_check("debug: types expose categories",
		types.get("core") == 1 and types.get("behavior") == 1 and types.get("theme") == 1)
	_check("debug: plugins records listed", discovery.get("plugins").size() == 13)

	## 12. Version helpers -------------------------------------------------------
	_check("version: supports ['4.7']", PluginManager.supports_engine_versions(["4.7"]))
	_check("version: rejects ['4.6']", not PluginManager.supports_engine_versions(["4.6"]))
	_check("version: empty list means any", PluginManager.supports_engine_versions([]))
	_check("version: rejects ['999.0']", not PluginManager.supports_engine_versions(["999.0"]))

	print("[VERIFY] DONE discovery_stress fails=%d -> %s" % [_fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit()


## --- Helpers ---------------------------------------------------------------

func _plant_boot_plugins() -> void:
	_write_plugin("boot_core", """{
	"id": "boot_core_plugin",
	"name": "Boot Core",
	"version": "1.0.0",
	"type": "core"
}""", """extends Plugin

var enable_calls := 0

func initialize() -> bool:
	PluginManager.get_engine_services().register_setting(
		"fixtures.boot_core", "plugins", TYPE_BOOL, true)
	return true

func enable() -> bool:
	enable_calls += 1
	return true
""")
	_write_plugin("boot_behavior", """{
	"id": "boot_behavior_plugin",
	"name": "Boot Behavior",
	"version": "1.0.0",
	"type": "behavior",
	"dependencies": [{ "id": "boot_core_plugin" }]
}""", """extends Plugin

func enable() -> bool:
	return true
""")


func _write_plugin(folder: String, manifest: String, script: String) -> void:
	var dir := BOOT_DIR + folder + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_write(dir + "plugin.json", manifest)
	_write(dir + "plugin.gd", script)


func _write(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(content)
		f.close()


func _cleanup_boot_plugins() -> void:
	var folders: Array[String] = ["boot_core", "boot_behavior"]
	for folder in folders:
		var dir := BOOT_DIR + folder
		var d := DirAccess.open(dir)
		if d:
			d.list_dir_begin()
			var entry := d.get_next()
			while entry != "":
				if not d.current_is_dir():
					DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(entry)))
				entry = d.get_next()
			d.list_dir_end()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[VERIFY] PASS %s" % label)
	else:
		_fails += 1
		printerr("[VERIFY] FAIL %s" % label)
