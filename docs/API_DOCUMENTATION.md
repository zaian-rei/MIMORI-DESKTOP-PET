# API Documentation

Reference for the engine's public APIs. Everything listed here exists in the codebase at the paths given. Line numbers are omitted because they shift; signatures are authoritative.

Conventions:
- Autoloads are accessed by name (`EventBus`, `SettingsManager`, `PluginManager`, ...).
- Events are `StringName` constants emitted on `EventBus`.
- `engine_services` (from `PluginManager.get_engine_services()`) is the only surface plugins may use.
- Each subsystem exposes `get_debug_info() -> Dictionary` for the debug overlay; that method is covered once under §Debug contract.

---

## §1. EventBus (`core/events/event_bus.gd`)

```gdscript
func subscribe(event_name: StringName, listener: Callable) -> void
func unsubscribe(event_name: StringName, listener: Callable) -> void
func emit(event_name: StringName, payload: Dictionary = {}) -> void
```

- Subscriptions are auto-cleaned when a listener's object is freed.
- Two legacy signals are preserved and fired on `emit()`: `engine_initialized`, `settings_requested`.

### Event constants

| Constant | Payload (keys) | Emitter |
|---|---|---|
| `BEHAVIOR_STARTED` / `BEHAVIOR_FINISHED` / `BEHAVIOR_SELECTED` | behavior id/state | BehaviorController / BehaviorDecision / BehaviorMemory |
| `WALK_STARTED` / `WALK_FINISHED` / `RUN_STARTED` / `RUN_FINISHED` | — | MovementComponent / gait |
| `JUMP_STARTED` / `LANDING_FINISHED` | — | Movement/Physics components |
| `STATE_CHANGED` | `previous_state`, `new_state` | StateMachineComponent |
| `ANIMATION_STARTED` / `ANIMATION_FINISHED` | animation name | Animation pipeline |
| `PET_DRAGGED` / `PET_RELEASED` / `PET_CLICKED` | — | DragComponent |
| `CURSOR_FOLLOW_ENABLED` / `CURSOR_FOLLOW_DISABLED` / `CURSOR_FOLLOW_STARTED` | — | FollowCursorComponent |
| `DESKTOP_CHANGED` / `MONITOR_CHANGED` | — | DesktopWindow / awareness |
| `MUSIC_STARTED` / `MUSIC_STOPPED` | — | MusicService |
| `THEME_LOADED` (`theme_id`, `display_name`) / `THEME_UNLOADED` / `THEME_CHANGED` / `THEME_LOAD_FAILED` (`theme_id`, `error`) / `THEME_VALIDATED` (`theme_id`, `valid`) | — | ThemeManager |
| `ENGINE_INITIALIZED` | — | Bootstrap |
| `SETTINGS_REQUESTED` / `SETTINGS_CHANGED` / `SETTINGS_LOADED` / `SETTINGS_SAVED` | — | Settings window / SettingsManager |
| `SETTING_CHANGED` | `key`, `category`, `old_value`, `new_value` | SettingsManager |
| `SETTINGS_CATEGORY_RESET` | `category` | SettingsManager |
| `SAVE_COMPLETED` / `LOAD_COMPLETED` | — | ConfigService |
| `PLUGIN_REGISTERED` / `PLUGIN_UNLOADED` / `PLUGIN_INITIALIZED` / `PLUGIN_ENABLED` / `PLUGIN_DISABLED` / `PLUGIN_SHUTDOWN` / `PLUGIN_ERROR` | `plugin_id`, ... | PluginManager |

---

## §2. SettingsManager (`services/settings/settings_manager.gd`)

Setting types: `TYPE_FLOAT`, `TYPE_INT`, `TYPE_BOOL`, `TYPE_STRING` (constants in the manager). Built-in categories: `general`, `movement`, `behavior`, `follow_cursor`, `audio`, `window`, `debug`, `theme`.

```gdscript
func register_setting(key: String, category: String, type: int, default_value: Variant,
		min_value: Variant, max_value: Variant, description: String) -> void
func get_setting(key: String, default: Variant = null) -> Variant
func set_setting(key: String, value: Variant) -> bool
func has_setting(key: String) -> bool
func get_default(key: String) -> Variant
func reset_setting(key: String) -> void
func reset_category(category: String) -> void
func reset_all() -> void
func get_category_keys(category: String) -> Array
func get_categories() -> Array
func get_validation_errors() -> Array
func clear_validation_errors() -> void
func is_dirty() -> bool
func mark_clean() -> void
func save_settings() -> void
func get_debug_info() -> Dictionary
```

`set_setting()` validates type + min/max before applying; invalid values are rejected and recorded. Every successful change emits `SETTING_CHANGED`. Persistence: `user://settings.json`, auto-save throttled ~0.5 s after a change.

---

## §3. ConfigService (`services/config/config_service.gd`)

```gdscript
func load_data() -> void
func save_data(world_position: Vector2) -> void
func set_music_enabled(value: bool) -> void
func set_follow_cursor_enabled(value: bool) -> void
func set_master_volume_db(value: float) -> void
func set_muted(value: bool) -> void
func set_category_volume(category: int, value_db: float) -> void
func get_category_volume(category: int) -> float
func set_personality_id(value: String) -> void
func set_theme_id(value: String) -> void
func save_stats(stats: Dictionary) -> void
func save_memory(memory: Dictionary) -> void
func save_statistics(stats_data: Dictionary) -> void
func set_debug_overlay(prefs: Dictionary) -> void
func set_launch_at_login(enabled: bool) -> void
func get_debug_info() -> Dictionary
```

Backward-compatible properties (proxy to SettingsManager): `move_speed`, `gravity`, `jump_speed`, `scale`, `always_on_top`, `follow_cursor_enabled`, `master_volume_db`, `muted`. Persisted fields: `personality_id`, `theme_id`, `pet_world_position`, `pet_stats`, `pet_memory`, `statistics`, `debug_overlay`, `launch_at_login`, `music_enabled`, `category_volumes`.

---

## §4. StatisticsManager (`services/statistics/statistics_manager.gd`)

```gdscript
func get_launch_count() -> int
func get_total_runtime() -> float
func get_total_distance() -> float
func get_count(state: int) -> int
func get_decision_count() -> int
func get_idle_time() -> float
func get_cursor_follow_time() -> float
func get_session_data() -> Dictionary
func get_lifetime_data() -> Dictionary
func reset_session() -> void
func reset_lifetime() -> void
```

Session + lifetime split; recorded from engine signals only. Autosaves every 30 s; `reset_lifetime()` also persists.

---

## §5. AudioManager (`services/audio/audio_manager.gd`)

```gdscript
func play_event(id: StringName) -> void          # resolves in active pack; unknown ids ignored
func play_stream(stream: AudioStream, category: int, volume_db: float = 0.0, loop: bool = true) -> void
func set_master_volume_db(value_db: float) -> void
func get_master_volume_db() -> float
func set_muted(value: bool) -> void
func is_muted() -> bool
func set_category_volume(category: int, value_db: float) -> void
func get_category_volume(category: int) -> float
func get_active_pack() -> AudioPack
func get_debug_info() -> Dictionary
```

Master volume range −80.0..24.0 dB. Buses are created per `AudioCategory` (Movement, Animations, Interactions, UI, Ambient, Voice) and routed into Master. Mute silences rather than rejecting, so continuous streams survive mute toggles. Event packs apply per-event cooldowns and non-repeating pitch-varied variations.

---

## §6. MusicService (`services/music/music_service.gd`)

```gdscript
func is_playing() -> bool
func start() -> void
func stop() -> void
func toggle() -> void
```

Delegates to `AudioManager.play_stream(..., MUSIC)` for the looping `pet_music_cherry.wav`. Emits `MUSIC_STARTED` / `MUSIC_STOPPED`. Headless-safe (skips playback but still emits). The separate `AmbientService` owns `ambient_cherry_breeze.wav` on the AMBIENT bus.

---

## §7. MenuBarService (`services/menu/menu_bar_service.gd`)

Uses `NativeMenu` to install a "Pet" item with Settings... and Quit. `Settings...` emits `settings_requested`. Degrades silently when no system menu bar exists or in headless mode.

---

## §8. ThemeManager (`services/theme/theme_manager.gd`)

```gdscript
func discover_themes() -> Dictionary          # scans themes/, validates, caches
func register_theme_resource(theme: ThemeResource) -> bool
func get_themes() -> Array                    # Array[ThemeResource]
func get_theme(id: StringName) -> ThemeResource
func get_loaded_theme() -> ThemeResource
func get_active_theme_id() -> StringName
func load_theme(id: StringName) -> bool
func validate_theme(theme: ThemeResource) -> Dictionary   # {valid, error, code}
func get_debug_info() -> Dictionary
```

Validation order and event emissions are documented in `CREATE_YOUR_FIRST_THEME.md §5` and `§6`.

---

## §9. DebugOverlayManager (`services/debug/debug_overlay_manager.gd`)

```gdscript
func set_overlay_enabled(value: bool) -> void
func is_overlay_enabled() -> bool
func set_visual_toggle(section: String, enabled: bool) -> void
func is_visual_toggle_enabled(section: String) -> bool
func get_debug_info() -> Dictionary
```

Constants: `DEFAULT_PREFS`, `HOTKEY_CHOICES`, `REFRESH_CHOICES`, `VISUAL_TOGGLES`. Reads every subsystem's `get_debug_info()`; plugins appear via `PluginManager.get_debug_info()`.

### Debug contract

Any subsystem that wants a debug section implements:

```gdscript
func get_debug_info() -> Dictionary
```

Returned dictionary must be plain data (strings, numbers, arrays, dictionaries) suitable for the overlay to render. This is the *only* way subsystems expose runtime state to the overlay — the overlay never reads internals.

---

## §10. PluginManager (`core/plugins/plugin_manager.gd`)

```gdscript
enum Status { REGISTERED, INITIALIZING, INITIALIZED, ENABLED, DISABLED, FAILED, SHUTDOWN, UNLOADED }

func discover_plugins(plugins_dir: String = DEFAULT_PLUGINS_DIR) -> Dictionary
func register_plugin(plugin: Plugin) -> bool
func initialize_plugin(plugin_id: String) -> bool
func enable_plugin(plugin_id: String) -> bool
func disable_plugin(plugin_id: String) -> bool
func shutdown_plugin(plugin_id: String) -> bool
func unload_plugin(plugin_id: String) -> bool
func shutdown_all() -> void
func has_plugin(plugin_id: String) -> bool
func get_plugin(plugin_id: String) -> Plugin
func get_plugin_ids() -> Array
func get_plugin_count() -> int
func get_status(plugin_id: String) -> int
func get_status_name(plugin_id: String) -> String
func get_init_time_ms(plugin_id: String) -> int
func get_plugin_errors(plugin_id: String) -> Array
func get_enabled_plugins() -> Array
func get_disabled_plugins() -> Array
func get_failed_plugins() -> Array
func get_engine_services() -> EngineServices
func get_discovered_plugins() -> Array
func get_discovered_plugin_ids() -> Array
func is_plugin_discovered(plugin_id: String) -> bool
func get_discovery_report() -> Dictionary
func get_load_order() -> Array
func report_plugin_error(plugin_id: String, message: String) -> void
func engine_version_compatible(required: String) -> bool
func version_satisfies(actual: String, min_version: String, max_version: String) -> bool
func supports_engine_versions(supported: Array) -> bool
func get_debug_info() -> Dictionary
```

`DEFAULT_PLUGINS_DIR = "res://plugins/"`. Init order is topological (dependencies first) with cycle detection; a cycle reports a `CYCLE` error and the cycle is skipped.

### EngineServices (plugins only)

Exposed via `get_engine_services()`; wraps the public APIs of `settings`, `theme`, `statistics`, `audio`, `config` (e.g. `register_setting(...)` as in the `dep_core` fixture). Plugins must not reach beyond this surface.

---

## §11. Plugin base class (`core/plugins/plugin.gd`)

```gdscript
class PluginDependency:   # id, min_version, max_version, optional
class PluginMetadata:     # id, name, version, author, description, engine_version, type, enable_on_start, dependencies

func initialize() -> bool
func enable() -> bool
func disable() -> bool
func shutdown() -> bool
func unload() -> void
func is_initialized() -> bool
func is_enabled() -> bool
func subscribe_event(event_name: StringName, callback: Callable) -> void
func unsubscribe_event(event_name: StringName, callback: Callable) -> void
func unsubscribe_all_events() -> void
func report_error(message: String) -> void
func get_metadata() -> Dictionary
func get_debug_info() -> Dictionary
```

`plugin_metadata` must be set by the subclass before registration. `subscribe_event()` subscriptions are auto-cleaned on disable/shutdown/failure. See `CREATE_YOUR_FIRST_PLUGIN.md`.

---

## §12. PluginDiscovery (`core/plugins/plugin_discovery.gd`)

Pure scanner. Constants: `MANIFEST_FILENAME = "plugin.json"`, `DEFAULT_ENTRY = "plugin.gd"`, `CATEGORY_PRIORITY` (core 0, behavior 10, theme 20, interaction 30, audio 40, ui 50, developer 60).

```gdscript
func scan(plugins_dir: String) -> Array                  # Array[DiscoveredPlugin]
func instantiate(candidate: DiscoveredPlugin) -> Plugin
class DiscoveredPlugin:  # folder, valid, errors, warnings, metadata, category priority, ...; getters for manifest data
```

Invalid plugins are reported with errors and skipped; broken entries never crash scanning.

---

## §13. DesktopWindow (`systems/desktop/desktop_window.gd`)

```gdscript
func configure_small_window() -> void
func apply_always_on_top(value: bool) -> void
func track(pet: Node) -> void
func get_window_size() -> Vector2i
```

`WINDOW_SIZE = Vector2i(500, 500)`. `track(pet)` + `_process` center the window on `pet.world_position` each frame. `ALWAYS_ON_TOP_REASSERT_INTERVAL_SECONDS = 0.5`; the macOS watchdog re-asserts the flag only while `always_on_top` is on.

---

## §14. Pet state machine (`components/state_machine/`)

`PetState.State` (order is meaningful): `IDLE, WALK, RUN, JUMP, FALL, LAND, DRAG, FLOAT, SLEEP, THINK, HAPPY, SAD, DEEP_SLEEP, DANCE`.

`StatePriority.Level`: `LOW, NORMAL, HIGH, CRITICAL`.

`StateMachineComponent`:

```gdscript
func request_state(state: int, priority: int) -> bool   # replaces pending only if strictly higher priority
func request_behavior(state: int, priority: int, allowed_from: Array = []) -> bool
func force_state(state: int) -> void                     # clears pending, applies immediately
func get_state() -> int
func is_state(state: int) -> bool
```

Interruptions (DRAG, manual override, physics states) bypass `allowed_from` gating. Every applied change emits `STATE_CHANGED`.

---

## §15. Data resources (`core/base/`)

- **`BehaviorDefinition`** (`behavior_definition.gd`): `state`, `category`, `animation_name`, `base_weight`, `duration_min/max`, `cooldown_min/max`, `allowed_from`, `stat_gates`, `stat_maxes`, `stat_weights`, `stat_effects`, `autonomous`. Example: `data/behaviors/walk.tres`.
- **`PersonalityDefinition`** (`personality_definition.gd`): frequency/preference/duration/decision/speed/reaction/curiosity/modifier fields. Example: `data/personalities/curious.tres`.
- **`ThemeResource`** (`theme_resource.gd`): fields per `CREATE_YOUR_FIRST_THEME.md §3`.
- **`AudioPack` / `AudioSound`** (`data/configs/default_audio_pack.tres`): event-id → sound mappings with cooldown/volume/pitch.
- **`BehaviorCatalog`** / **`PersonalityCatalog`**: read-only after load; `get_all()`, `get_by_id()`, `get_animation_for_state()`, `get_default_personality()`.

Stat enums (`PetStats.Stat`, `STAT_DEFINITIONS`) define the behavior-economy stats: happiness, energy, boredom, sleepiness, and friends. Behavior decision scoring:

```
utility = base_weight × (1 + Σ stat_weight × stat/50) × personality_utility × 0.45^repeats × registered_utility_modifiers
```
