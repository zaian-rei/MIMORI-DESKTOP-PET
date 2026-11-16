# Engine Guide

A practical tour of how the engine runs, what settings and save data exist, how to use the debug overlay, and how the subsystems fit together. Read `PROJECT_ARCHITECTURE.md` for the architecture overview and `API_DOCUMENTATION.md` for the reference.

---

## 1. Running the engine

| Command | What it does |
|---|---|
| `godot --path /Users/zaian/pet` | Run the project (main scene `scenes/bootstrap/bootstrap.tscn`) |
| `godot --path /Users/zaian/pet --quit-after 300` | Headless smoke test (window + audio skipped, boot + quit) |
| Open the project in the Godot editor and press F5 | Same as running; project name is **"lyra new"** |

The engine is designed for macOS (per-pixel transparent windows, native menu bar, `osascript` launch-at-login). In `--headless` mode the window and audio are skipped but the full autoload/boot path and EventBus still run, which is how the verification harnesses work.

## 2. The desktop window

`DesktopWindow` (`systems/desktop/desktop_window.gd`) configures a 500×500 px borderless, transparent, always-on-top, unresizable OS window.

- `configure_small_window()` applies the size/flags; `always_on_top` honors `ConfigService.always_on_top`.
- `track(pet)` + `_process` continuously re-center the window on `pet.world_position` every frame.
- **macOS watchdog:** the always-on-top flag is re-asserted every `ALWAYS_ON_TOP_REASSERT_INTERVAL_SECONDS` (0.5 s) **only while the setting is on**, because macOS can silently drop the flag after focus events. Unchecking it in Settings sticks.
- `apply_always_on_top(value)` is the runtime toggle; it persists through ConfigService and applies immediately.

## 3. Settings

### 3.1 SettingsManager (single source of truth)

`SettingsManager` (`services/settings/settings_manager.gd`) owns every configurable engine value. Settings are registered by key (`"category.name"`) with a type, default, optional min/max, and description.

- `register_setting(key, category, type, default, min, max, desc)` — idempotent; plugins can register their own.
- `get_setting(key, default)` / `set_setting(key, value)` (validates; emits `SETTING_CHANGED`) / `has_setting` / `get_default`.
- `reset_setting(key)` / `reset_category(category)` / `reset_all()` (emit `SETTINGS_CATEGORY_RESET`).
- `get_category_keys(category)` / `get_categories()` / `get_validation_errors()` / `is_dirty()` / `mark_clean()`.
- Persists to `user://settings.json` (throttled 0.5 s auto-save). `_register_defaults()` defines the built-in categories: `general`, `movement`, `behavior`, `follow_cursor`, `audio`, `window`, `debug`, `theme`.

Every change goes through `EventBus.SETTING_CHANGED` (`{key, category, old_value, new_value}`) so live systems can react.

### 3.2 ConfigService (save data + legacy proxies)

`ConfigService` (`services/config/config_service.gd`) is the persistence service for `user://save_data.json` and keeps backward-compatible settings proxies that delegate to SettingsManager:

| Proxy | SettingsManager key | Default |
|---|---|---|
| `move_speed` | `movement.move_speed` | 150.0 |
| `gravity` | `movement.gravity` | 1800.0 |
| `jump_speed` | `movement.jump_height` | 450.0 |
| `scale` | `general.pet_scale` | 1.0 |
| `always_on_top` | `window.always_on_top` | true |
| `follow_cursor_enabled` | `follow_cursor.enabled_by_default` | false |
| `master_volume_db` | `audio.master_volume` | 0.0 |
| `muted` | `audio.muted` | false |

Non-delegated fields: `launch_at_login`, `music_enabled`, `personality_id`, `theme_id`, `category_volumes`, `pet_world_position`, `pet_stats`, `pet_memory`, `statistics`, `debug_overlay`.

On load, old-style save data is migrated into SettingsManager; on save, the file is written with tab-indented JSON. `set_launch_at_login()` shells out to `osascript` on macOS (no-op warning when running from the editor).

### 3.3 Settings window

Right-click → Settings (or native menu → Settings) opens `scenes/ui/settings_window.tscn`. Sliders: Speed (10–1000), Gravity (200–6000), Jump (100–2000), Scale (0.1–5.0) — all apply **live** as you move them, and Save persists while Cancel restores a snapshot taken when the window opened. Always-on-top and Launch-at-Login checkboxes apply live too.

## 4. Save data layout

`user://save_data.json` (`~/Library/Application Support/Godot/app_userdata/lyra new/save_data.json`):

```json
{
  "pet_position": { "x": ..., "y": ... },
  "settings": {
    "move_speed": ..., "gravity": ..., "jump_speed": ...,
    "scale": ..., "always_on_top": ..., "launch_at_login": ...,
    "music_enabled": ..., "follow_cursor_enabled": ...,
    "personality_id": "...", "theme_id": "...",
    "master_volume_db": ..., "muted": ..., "category_volumes": {...}
  },
  "pet_stats": {...},
  "pet_memory": {...},
  "statistics": {...},
  "debug_overlay": {...}
}
```

`user://settings.json`:

```json
{ "settings": { "movement.move_speed": 150.0, ... } }
```

**Caution:** the engine autosaves (stats every 30 s, settings 0.5 s after change). If you hand-edit these files while the engine runs, the engine may overwrite your changes. Back them up before experimenting.

## 5. Audio

- **AudioManager** is the only audio authority. It builds one bus per `AudioCategory` (Movement, Animations, Interactions, UI, Ambient, Voice — named `Audio*` to avoid clashing with Godot defaults), each routed into Master.
- `play_event(&"walk")` resolves the id against the **active pack** (`AudioPack`), applies per-event cooldown, picks a non-repeating variation, and adds random pitch. Unknown ids are ignored gracefully.
- `play_stream(...)` plays raw streams (music) on a category bus; master mute silences rather than rejecting, so a continuous track survives mute toggles.
- **MusicService** retains an internal looping track on the MUSIC bus, but the release UI exposes no music toggle. **AmbientService** plays the quiet `ambient_cherry_breeze.wav` loop on its own AMBIENT bus. Each signature animation maps to its own move-specific sound cue on the SPECIAL_MOVES bus.
- Volume/mute setters on AudioManager persist through ConfigService (`master_volume_db` clamped −80..+24 dB).

## 6. Themes

- **ThemeManager** discovers folders in `themes/` containing `theme.tres`, validates each (`id`, `display_name`, `version`, engine compatibility), and caches by `ThemeResource.id`. Themes shipped by plugins are registered via `register_theme_resource()` and are preserved across `discover_themes()`.
- `load_theme(id)` unloads the current theme, applies the audio pack, and emits `THEME_UNLOADED` → `THEME_LOADED` → `THEME_CHANGED`.
- At boot, Bootstrap loads `ConfigService.theme_id` (default `"default"`) and applies the theme's `sprite_pack` / `audio_pack` / `default_personality_id` to the pet definition. Runtime `THEME_CHANGED` re-applies the sprite pack on the live pet (`pet.gd` `_on_theme_changed`).
- The built-in theme (`themes/default/theme.tres`, "Default Pet") provides 12 animations (idle, walk, run, jump, fall, land, sleep, deep sleep, thinking, happy, sad, music) and the default audio pack.

## 7. Personalities

- **PersonalityCatalog** loads every `.tres` in `data/personalities/`; the first file is the fallback default. Built-ins: `calm`, `curious`, `lazy`, `playful`.
- **PersonalityComponent** holds the *selection* (`current`), restores in order: saved `ConfigService.personality_id` → `pet.definition.default_personality_id` → catalog default. `set_personality_by_id(id)` switches at runtime, persists, and emits `personality_changed`.
- A personality biases the utility decision (movement/thinking/dance/sleep/idle frequency), behavior durations, decision delay, and the stat economy — it never moves the pet or picks behaviors itself.

## 8. Behaviors & the decision loop

- **BehaviorCatalog** loads all `BehaviorDefinition` `.tres` from `data/behaviors/`. Built-ins: `idle`, `walk`, `run`, `jump`, `sleep`, `deep_sleep`, `think`, `happy`, `sad`, `dance` (dance is `autonomous = false`: music/manual only).
- The decision loop (3–6 s window) scores eligible behaviors and picks the highest utility; `register_utility_modifier(state, callable)` is the documented seam for extra scoring rules (used by memory novelty and behavior fatigue).
- Behaviors apply per-second `stat_effects` and have cooldowns, stat gates/maxes, and `allowed_from` constraints.

## 9. Debug overlay (developer tool)

- Toggle with **F8** (configurable to F7/F9/F10/Ctrl+Shift+D). In release builds the overlay is inert unless the saved pref explicitly enables it.
- **17 data sections** (see `DebugOverlayManager.SECTION_DEFS`): General, State Machine, Animation, Movement, Follow Cursor, Behavior Stats, Utility AI, Memory, Personality, Desktop, Audio, Save System, Statistics, Settings, Theme, Event Bus, **Plugins**.
- Controls: **Pause AI** (locks autonomy and force-states IDLE), Force Behavior / Force Animation, Reset Stats, Reset Memory, Reset Session / Reset Lifetime statistics, visual toggles (Ground, Safe Area, Cursor, Arrival, Bounds), scale/opacity/refresh-rate/hotkey, and per-section visibility. All prefs persist.
- Every data section is produced by the subsystem's public `get_debug_info()` — the overlay never reaches into internals.
- **Plugins section** renders `PluginManager.get_debug_info()` including the discovery scan report (scanned dir, counts, load order, types, per-folder validation status, errors, warnings).

## 10. Statistics

`StatisticsManager` records session + lifetime stats automatically from engine signals (state changes, decisions) — it never writes to components. Queries: `get_launch_count()`, `get_total_runtime()`, `get_total_distance()`, `get_count(state)`, `get_decision_count()`, `get_idle_time()`, `get_cursor_follow_time()`, `get_session_data()`, `get_lifetime_data()`. `reset_session()` / `reset_lifetime()` from the debug overlay. Autosaves every 30 s.

## 11. Menu bar & context menu

- **MenuBarService** installs a native "Pet" menu with Settings and Quit using `NativeMenu`; it degrades silently when there's no system menu bar or in headless mode.
- **ContextMenuComponent** is the pet's right-click companion menu (`CompanionMenu` — a neon glass window, always on top). Item ids mirror the legacy PopupMenu contract: `item_pressed(id)` dispatches Settings/About/Exit, the Follow Cursor toggle, Feed, and the Actions group (Happy 20 / Think 21 / Dance 22 / Sleep 23 map to `PetState.State`). Manual animations play a fixed number of loops (`MANUAL_ITERATIONS`) then return to autonomy.

## 12. Interaction recap

- **DragComponent**: hold-left past `CLICK_HOLD_SECONDS` (0.18 s) or move past `DRAG_SLOP_PIXELS` (8 px) becomes a drag (emits `PET_DRAGGED`); release emits `PET_RELEASED`; a quick click emits `PET_CLICKED`.
- **InteractionComponent**: on `PET_CLICKED` → +8 happiness, −6 boredom, happy reaction; `feed()` → +15 energy, +10 happiness. Cursor lingering within 320 px can trigger a curiosity-follow (WALK toward the cursor, up to 2.5 s, cooldown 3 s).
- **FollowCursorComponent** (optional, toggle via context menu): walks/sprints to the cursor, hops to meet an overhead cursor (cooldown 3 s), yields to drags, manual control, and high sleepiness. Emits `CURSOR_FOLLOW_ENABLED` / `CURSOR_FOLLOW_DISABLED`.

## 13. Plugins at runtime

`PluginManager` (`core/plugins/plugin_manager.gd`) is an autoload:

- Boot: scans `res://plugins/` once, registers valid candidates, then initializes and enables them in dependency order.
- Query: `has_plugin(id)`, `get_plugin(id)`, `get_plugin_ids()`, `get_plugin_count()`, `get_status(id)`, `get_status_name(id)`, `get_enabled_plugins()`, `get_disabled_plugins()`, `get_failed_plugins()`.
- Lifecycle: `register_plugin(plugin)`, `initialize_plugin(id)`, `enable_plugin(id)`, `disable_plugin(id)`, `shutdown_plugin(id)`, `unload_plugin(id)`, `shutdown_all()`.
- Discovery queries: `get_discovered_plugins()`, `get_discovered_plugin_ids()`, `is_plugin_discovered(id)`, `get_discovery_report()`, `get_load_order()`.
- Version helpers: `engine_version_compatible(required)`, `version_satisfies(actual, min, max)`, `supports_engine_versions(list)`.
- Error handling: lifecycle failures mark a plugin `FAILED` and disable it; `report_plugin_error(id, msg)` is for non-fatal self-reported errors. All plugin EventBus subscriptions are auto-cleaned on disable/shutdown/failure.

See `CREATE_YOUR_FIRST_PLUGIN.md` for authoring.
