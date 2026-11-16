extends RefCounted
class_name PluginDiscovery

## Automatic plugin discovery and validation. This class ONLY scans the
## plugin directory, reads manifests, validates candidates, and resolves
## dependency availability. It NEVER registers, initializes, enables, or
## manages plugin lifecycle - that is PluginManager's job.
##
## Design contract:
##   - Pure scanner: given a directory, returns DiscoveredPlugin records.
##     It has no reference to PluginManager internals, no lifecycle state,
##     and no dependency on any specific plugin.
##   - Manifest format: each plugin folder contains a plugin.json file.
##     A folder without a manifest is reported as invalid, never silently
##     ignored as "not a plugin".
##   - Validation is strict but safe: invalid plugins are reported with
##     detailed errors and skipped. A broken plugin can never crash the
##     engine during discovery.
##   - The registry / lifecycle manager decides what happens to the
##     DiscoveredPlugin records this class produces.
##   - Scanning is intentionally an explicit, bounded operation (startup or
##     explicit re-scan), never a per-frame poll.

## Manifest file name required inside each plugin folder.
const MANIFEST_FILENAME := "plugin.json"

## Default entry script name relative to the plugin folder.
const DEFAULT_ENTRY := "plugin.gd"

## Base plugin script used to verify entry scripts extend Plugin.
const PLUGIN_BASE_SCRIPT := "res://core/plugins/plugin.gd"

## Category load priority. Lower runs first. Unknown categories default to
## the general priority so future categories integrate without edits.
const CATEGORY_PRIORITY := {
	"core": 0,
	"behavior": 10,
	"theme": 20,
	"interaction": 30,
	"audio": 40,
	"ui": 50,
	"developer": 60,
	"analytics": 70,
	"general": 100,
}
const DEFAULT_CATEGORY_PRIORITY := 100


## A single discovered plugin candidate. Carries the raw manifest, the
## resolved metadata, validation outcome, and dependency-availability info.
class DiscoveredPlugin:
	var folder_name: String
	var folder_path: String
	var manifest_path: String
	var entry_path: String
	var plugin_id: String
	var category: String
	var metadata: Plugin.PluginMetadata
	var manifest: Dictionary = {}   # raw parsed manifest (registry / hot reload)
	var valid: bool = true
	var registered: bool = false
	var errors: Array = []       # Array[String]
	var warnings: Array = []     # Array[String]
	var priority: int = DEFAULT_CATEGORY_PRIORITY

	func get_debug_info() -> Dictionary:
		return {
			"folder": folder_name,
			"id": plugin_id,
			"category": category,
			"valid": valid,
			"registered": registered,
			"priority": priority,
			"entry": entry_path,
			"errors": errors,
			"warnings": warnings,
		}


## --- Discovery ----------------------------------------------------------------

## Scans a directory for plugin folders and returns DiscoveredPlugin records
## (one per folder). Does not instantiate any plugin. Never raises.
func scan(plugins_dir: String) -> Array:
	var results: Array = []
	var dir := DirAccess.open(plugins_dir)
	if dir == null:
		LoggerGlobal.warn("PluginDiscovery: could not open plugin directory '%s'." % plugins_dir)
		return results

	# Collect subdirectory names (deterministic order) so discovery order is
	# stable regardless of filesystem enumeration order.
	var folder_names: Array = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry != "." and entry != "..":
			folder_names.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	folder_names.sort()

	for folder in folder_names:
		var candidate := _discover_folder(plugins_dir.path_join(folder))
		results.append(candidate)

	# Dependency availability must be evaluated against the full candidate
	# set, so it runs after every folder has been scanned.
	_resolve_dependency_availability(results)
	return results


## Discovers a single plugin folder (reads + validates its manifest).
func _discover_folder(folder_path: String) -> DiscoveredPlugin:
	var candidate := DiscoveredPlugin.new()
	candidate.folder_path = folder_path
	candidate.folder_name = folder_path.get_file()
	candidate.manifest_path = folder_path.path_join(MANIFEST_FILENAME)

	if not FileAccess.file_exists(candidate.manifest_path):
		candidate.valid = false
		candidate.errors.append("Missing manifest '%s'." % MANIFEST_FILENAME)
		return candidate

	var manifest := _read_manifest(candidate)
	if manifest.is_empty():
		return candidate

	candidate.manifest = manifest
	_apply_manifest(candidate, manifest)
	if not candidate.valid:
		# Structural manifest errors are decisive: do not pile on entry/engine
		# diagnostics that cannot be meaningfully evaluated against a broken
		# manifest.
		return candidate
	_validate_entry_script(candidate)
	_validate_engine_version(candidate)
	return candidate


## Reads and parses the manifest JSON. Returns {} and marks invalid on any
## parse/structure error.
func _read_manifest(candidate: DiscoveredPlugin) -> Dictionary:
	var file := FileAccess.open(candidate.manifest_path, FileAccess.READ)
	if file == null:
		candidate.valid = false
		candidate.errors.append("Could not read manifest file.")
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		candidate.valid = false
		candidate.errors.append("Manifest is not valid JSON.")
		return {}
	return parsed


## Extracts all manifest fields into the candidate. Malformed required
## fields invalidate the candidate; optional fields fall back to defaults.
func _apply_manifest(candidate: DiscoveredPlugin, manifest: Dictionary) -> void:
	var manifest_id := str(manifest.get("id", ""))
	var name := str(manifest.get("name", ""))
	var version := str(manifest.get("version", "1.0.0"))
	var author := str(manifest.get("author", ""))
	var description := str(manifest.get("description", ""))
	var engine_version := str(manifest.get("engine_version", ""))
	var category := str(manifest.get("type", manifest.get("category", "general")))
	var enable_on_start := bool(manifest.get("enable_on_start", true))
	var entry_name := str(manifest.get("entry", DEFAULT_ENTRY))

	if manifest_id.is_empty():
		_invalidate(candidate, "Manifest is missing required field 'id'.")
	if name.is_empty():
		_invalidate(candidate, "Manifest is missing required field 'name'.")

	candidate.plugin_id = manifest_id
	candidate.category = category
	candidate.priority = CATEGORY_PRIORITY.get(category, DEFAULT_CATEGORY_PRIORITY)
	candidate.entry_path = candidate.folder_path.path_join(entry_name)

	var dependencies := _parse_dependencies(candidate, manifest.get("dependencies", []), false)
	var optional_dependencies := _parse_dependencies(candidate, manifest.get("optional_dependencies", []), true)
	var supported_versions := _parse_supported_versions(candidate, manifest.get("supported_engine_versions", []))

	candidate.metadata = Plugin.PluginMetadata.new(
		manifest_id, name, version, author, description,
		engine_version, category, enable_on_start,
		dependencies + optional_dependencies,
		supported_versions
	)


## Parses the supported_engine_versions manifest field into an Array[String].
## Accepts an array of version strings or a comma/space-separated string.
func _parse_supported_versions(candidate: DiscoveredPlugin, raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) == TYPE_STRING:
		raw = raw.split(",")
	if typeof(raw) != TYPE_ARRAY:
		_invalidate(candidate, "'supported_engine_versions' must be an array or a string.")
		return out
	for entry in raw:
		var v := str(entry).strip_edges()
		if not v.is_empty():
			out.append(v)
	return out


## Parses the dependencies array into PluginDependency objects. Malformed
## entries invalidate the candidate.
func _parse_dependencies(candidate: DiscoveredPlugin, raw: Variant, optional: bool) -> Array:
	var deps: Array = []
	if typeof(raw) != TYPE_ARRAY:
		_invalidate(candidate, "'dependencies' must be an array.")
		return deps
	for dep in raw:
		if typeof(dep) != TYPE_DICTIONARY:
			_invalidate(candidate, "Malformed dependency entry (not an object).")
			continue
		var dep_id := str(dep.get("id", ""))
		if dep_id.is_empty():
			_invalidate(candidate, "Dependency entry is missing 'id'.")
			continue
		deps.append(Plugin.PluginDependency.new(
			dep_id,
			str(dep.get("min", "")),
			str(dep.get("max", "")),
			optional,
		))
	return deps


## Verifies the entry script exists and extends Plugin. Does NOT instantiate.
func _validate_entry_script(candidate: DiscoveredPlugin) -> void:
	if not FileAccess.file_exists(candidate.entry_path):
		_invalidate(candidate, "Entry script '%s' not found." % candidate.entry_path)
		return
	if not candidate.entry_path.ends_with(".gd"):
		_invalidate(candidate, "Entry script must be a .gd file.")
		return
	if not _script_extends_plugin(candidate.entry_path):
		_invalidate(candidate, "Entry script does not extend Plugin.")


## Checks that a script (by path) ultimately extends Plugin via its base
## class chain, without instantiating it.
func _script_extends_plugin(script_path: String) -> bool:
	var script = load(script_path)
	if script == null or not (script is Script):
		return false
	var base: Script = script
	var depth := 0
	while base != null and depth < 64:
		if base.resource_path == PLUGIN_BASE_SCRIPT:
			return true
		if not base.has_method("get_base_script"):
			return false
		base = base.get_base_script()
		depth += 1
	return false


## Validates the plugin's engine version requirement against the running
## engine. Delegates to PluginManager's shared version semantics.
func _validate_engine_version(candidate: DiscoveredPlugin) -> void:
	if candidate.metadata == null:
		return
	var required := candidate.metadata.engine_version
	if not required.strip_edges().is_empty():
		if not PluginManager.engine_version_compatible(required):
			_invalidate(candidate,
				"Requires engine '%s', current is '%s'." % [
					required, Engine.get_version_info().string,
				]
			)
	if not candidate.metadata.supported_engine_versions.is_empty():
		if not PluginManager.supports_engine_versions(candidate.metadata.supported_engine_versions):
			_invalidate(candidate,
				"Does not list engine '%s' as a supported version." % Engine.get_version_info().string
			)


## Marks a candidate invalid with a message.
func _invalidate(candidate: DiscoveredPlugin, message: String) -> void:
	candidate.valid = false
	candidate.errors.append(message)


## Resolves dependency availability across the full candidate set. A required
## dependency that is missing, invalid, or version-incompatible invalidates
## its dependent. Optional dependency problems only warn.
func _resolve_dependency_availability(candidates: Array) -> void:
	var by_id := {}
	for candidate in candidates:
		if candidate.valid and not candidate.plugin_id.is_empty():
			by_id[candidate.plugin_id] = candidate

	for candidate in candidates:
		if not candidate.valid or candidate.metadata == null:
			continue
		for dep in candidate.metadata.dependencies:
			var d: Plugin.PluginDependency = dep
			var dep_candidate = by_id.get(d.id)
			if dep_candidate == null:
				_record_dep_missing(candidate, d)
				continue
			if not dep_candidate.valid:
				_record_dep_invalid(candidate, d)
				continue
			if not d.min_version.is_empty() or not d.max_version.is_empty():
				var satisfies := PluginManager.version_satisfies(
					dep_candidate.metadata.version, d.min_version, d.max_version
				)
				if not satisfies:
					_record_dep_version(candidate, d, dep_candidate)


func _record_dep_missing(candidate: DiscoveredPlugin, d: Plugin.PluginDependency) -> void:
	var msg := "Required dependency '%s' is not present." % d.id
	if d.optional:
		candidate.warnings.append("Optional dependency '%s' is not present." % d.id)
	else:
		_invalidate(candidate, msg)


func _record_dep_invalid(candidate: DiscoveredPlugin, d: Plugin.PluginDependency) -> void:
	if d.optional:
		candidate.warnings.append("Optional dependency '%s' failed validation." % d.id)
	else:
		_invalidate(candidate, "Required dependency '%s' failed validation." % d.id)


func _record_dep_version(candidate: DiscoveredPlugin, d: Plugin.PluginDependency,
		dep_candidate: DiscoveredPlugin) -> void:
	var msg := "Dependency '%s' v%s does not satisfy required min '%s' / max '%s'." % [
		d.id, dep_candidate.metadata.version, d.min_version, d.max_version
	]
	if d.optional:
		candidate.warnings.append(msg)
	else:
		_invalidate(candidate, msg)


## --- Loading -----------------------------------------------------------------

## Instantiates a valid DiscoveredPlugin into a Plugin instance, applying the
## manifest metadata. Returns null if the plugin cannot be instantiated.
func instantiate(candidate: DiscoveredPlugin) -> Plugin:
	if candidate == null or not candidate.valid or candidate.metadata == null:
		return null
	var script = load(candidate.entry_path)
	if script == null:
		LoggerGlobal.error("PluginDiscovery: could not load entry script '%s'." % candidate.entry_path)
		return null
	var plugin = script.new()
	if plugin == null or not (plugin is Plugin):
		if plugin != null:
			plugin.free()
		LoggerGlobal.error("PluginDiscovery: entry script '%s' did not instantiate a Plugin." % candidate.entry_path)
		return null
	plugin.plugin_metadata = candidate.metadata
	return plugin


## --- Ordering ----------------------------------------------------------------

## Stable sort key for plugin folders: category priority then plugin id.
## Dependency ordering is handled by PluginManager's topological sort at
## initialization time.
static func sort_by_load_order(a: DiscoveredPlugin, b: DiscoveredPlugin) -> bool:
	if a.priority != b.priority:
		return a.priority < b.priority
	return a.plugin_id < b.plugin_id
