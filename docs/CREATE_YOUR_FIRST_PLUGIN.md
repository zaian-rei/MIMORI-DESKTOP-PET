# Create Your First Plugin

Plugins are the engine's main extension point. A plugin is a folder under `plugins/` with two required files: `plugin.json` (manifest) and `plugin.gd` (a script extending `Plugin`). This guide walks through the real fixture plugins used by the verification harnesses (`verif/fixtures/plugins/`), so every example is copy-paste runnable.

---

## 1. Plugin anatomy

```
plugins/my_plugin/
├── plugin.json          manifest (metadata, version, deps)
└── plugin.gd            extends Plugin (lifecycle + logic)
```

Plugins are discovered once at boot by `PluginDiscovery`, validated, then initialized and enabled in dependency order by `PluginManager`. A failing plugin is reported and disabled — it can never crash the engine or stop other plugins from loading.

## 2. The manifest (`plugin.json`)

**Simplest valid manifest** — from the `theme` fixture:

```json
{
	"id": "fixture_theme",
	"name": "Fixture Theme",
	"version": "1.0.0",
	"author": "Discovery Harness",
	"description": "Theme shipped as a plugin.",
	"type": "theme",
	"enable_on_start": true
}
```

**With a dependency and engine constraint** — from the `behavior` fixture:

```json
{
	"id": "fixture_behavior",
	"name": "Fixture Behavior",
	"version": "1.0.0",
	"author": "Discovery Harness",
	"description": "Behavior fixture depending on the core fixture.",
	"type": "behavior",
	"enable_on_start": true,
	"dependencies": [
		{ "id": "fixture_dep_core", "min": "2.0.0" }
	]
}
```

Manifest fields:

| Field | Required | Notes |
|---|---|---|
| `id` | yes | Unique; lowercase snake_case convention |
| `name` | yes | Display name |
| `version` | yes | Semver string |
| `author`, `description` | no | Metadata |
| `type` | yes | `core`, `behavior`, `theme`, `interaction`, `audio`, `ui`, `developer` (drives category-priority load order) |
| `enable_on_start` | no | `true` to auto-enable after boot |
| `dependencies` | no | List of `{ "id": "...", "min": "...", "max": "...", "optional": true }`. Optional missing deps are warnings, not errors |
| `engine_version` | no | Version range, e.g. `">=4.0"` |
| `supported_engine_versions` | no | List, e.g. `["4.7"]`; all entries must be supported |

Dependency versions: a dep missing from the candidate set, or whose version is outside the requested `min`/`max`, makes the plugin invalid. A cycle between dependencies fails resolution with a cycle error.

## 3. The entry script (`plugin.gd`)

Extend the engine's `Plugin` base class (`core/plugins/plugin.gd`). Override any lifecycle hooks you need — all optional:

```gdscript
extends Plugin

func initialize() -> bool:   # runs once, after all dependencies initialized
func enable() -> bool:       # runs after initialize
func disable() -> bool:      # when the plugin is turned off
func shutdown() -> bool:     # when the engine is shutting down the plugin
func unload() -> bool:       # final cleanup / removal
```

Return `true` on success. A `false` return (or an unhandled script error inside a hook) marks the plugin `FAILED` and disables it.

### Example A — register a setting (from `dep_core` fixture)

```gdscript
extends Plugin

func initialize() -> bool:
	PluginManager.get_engine_services().register_setting(
		"fixtures.dep_core", "plugins", TYPE_BOOL, true,
		null, null, "Set by fixture_dep_core plugin")
	return true

func enable() -> bool:
	EventBus.emit(&"fixture_core_ready", {"core_version": "2.0.0"})
	return true
```

`get_engine_services()` is the **only** sanctioned access surface: `settings`, `theme`, `statistics`, `audio`, `config` wrappers. Everything else is `EventBus`.

### Example B — register a theme (from `theme` fixture)

```gdscript
extends Plugin

func initialize() -> bool:
	var theme := ThemeResource.new()
	theme.id = "fixture_theme_plugin"
	theme.display_name = "Fixture Theme Plugin"
	theme.version = "1.0.0"
	theme.author = "Discovery Harness"
	theme.description = "Theme shipped as a plugin."
	return ThemeManager.register_theme_resource(theme)
```

### Example C — subscribe to engine events (from `behavior` fixture)

```gdscript
extends Plugin

var trigger_count := 0

func enable() -> bool:
	subscribe_event(&"fixture_trigger", _on_trigger)   # auto-unsubscribed on disable/shutdown
	return true

func _on_trigger(_payload: Dictionary) -> void:
	trigger_count += 1
```

Use the base class `subscribe_event(name, callable)` instead of touching `EventBus` directly — the base class tracks subscriptions and cleans them up automatically when the plugin is disabled, shut down, or fails. The `behavior` fixture also demonstrates dependency gating at runtime:

```gdscript
core_enabled_before = PluginManager.get_status("fixture_dep_core") == PluginManager.Status.ENABLED
```

## 4. Lifecycle states

```
REGISTERED → INITIALIZING → INITIALIZED → ENABLED / DISABLED / FAILED / SHUTDOWN / UNLOADED
```

- **Boot order:** registered candidates are sorted by category priority (`core` < `behavior` < `theme` < `interaction` < `audio` < `ui` < `developer`), then topologically by dependency, then each is initialized, then each enabled.
- `PluginManager.get_status(id)` returns the current state; `get_status_name(id)` a printable string.
- Errors: lifecycle failures set `FAILED` + disable. Plugins can self-report non-fatal problems via `report_plugin_error(id, msg)`.
- On disable/shutdown/failure all plugin EventBus subscriptions are cleaned automatically.

## 5. Engine version checks

`PluginManager` exposes version helpers for in-script use:

```gdscript
PluginManager.engine_version_compatible(">=4.0")          # bool
PluginManager.supports_engine_versions(["4.7"])           # bool
PluginManager.version_satisfies(actual, min, max)         # bool
```

## 6. Debugging your plugin

1. Open the **debug overlay (F8)** → Plugins section. It shows the discovery scan report: scanned dirs, counts, load order, per-folder validation status, and any errors/warnings.
2. The overlay's state machine/data sections show you what the engine is doing live.
3. Logs: the engine logs plugin errors with a `[plugins]` prefix via `LoggerGlobal`.

## 7. Invalid-plugin examples (for reference)

The `verif/fixtures/plugins/` invalid fixtures show every rejection path:

| Fixture | Why it's rejected |
|---|---|
| `invalid_no_manifest` | No `plugin.json` at all |
| `invalid_bad_manifest` | `plugin.json` doesn't parse |
| `invalid_missing_entry` | No `plugin.gd` |
| `invalid_broken_script` | `plugin.gd` fails to compile/load |
| `invalid_engine` | `engine_version` requirement not met |
| `invalid_supported_list` | None of `supported_engine_versions` match |
| `invalid_dep_missing` | Dependency not present in the candidate set |
| `invalid_dep_version` | Dependency present but version outside `min`/`max` |

All are reported cleanly and skipped — none crash discovery.

---

## Checklist

- [ ] Folder `plugins/<id>/` with `plugin.json` + `plugin.gd` (+ `plugin.gd.uid` from the editor).
- [ ] Manifest `id`, `name`, `version`, `type` present and valid JSON.
- [ ] `plugin.gd` begins with `extends Plugin`.
- [ ] Use `get_engine_services()` / `subscribe_event()`; don't touch subsystem internals.
- [ ] Return `bool` from lifecycle hooks; `true` = success.
- [ ] Boot the engine; check debug overlay → Plugins for validation + load status.
