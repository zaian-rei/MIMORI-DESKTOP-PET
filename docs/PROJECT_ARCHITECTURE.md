# Project Architecture

This document describes the layered architecture of the desktop pet engine, the boot sequence, how data flows through the system, and the extension model. Everything here is derived from the actual codebase — see `API_DOCUMENTATION.md` for the full reference.

---

## 1. Layers

```
┌─────────────────────────────────────────────────────────────┐
│ Scenes / UI                          scenes/bootstrap, pet, │
│                                     ui/settings_window      │
├─────────────────────────────────────────────────────────────┤
│ Pet components (per-pet subsystems)         components/*     │
│  state machine, movement, gait, polish, animation, physics, │
│  behavior AI, memory, stats, emotion, awareness, drag,      │
│  interaction, follow-cursor, personality, audio, window     │
├─────────────────────────────────────────────────────────────┤
│ Global services (autoloads)                      services/*  │
│  settings, config, statistics, audio, music, menu bar,      │
│  debug overlay, theme, screen, logger                        │
├─────────────────────────────────────────────────────────────┤
│ Core framework                                core/*         │
│  events (EventBus), globals, base data resources + catalogs,│
│  plugins (base class, discovery, lifecycle manager)          │
├─────────────────────────────────────────────────────────────┤
│ Systems / platform                             systems/*      │
│  DesktopWindow (OS window follow + always-on-top watchdog)   │
└─────────────────────────────────────────────────────────────┘
```

**Ground rule:** components and services only communicate through (a) `EventBus` events, (b) a component's public API, or (c) the sanctioned `PluginManager.get_engine_services()` surface. Subsystems never reach into another subsystem's internals.

---

## 2. Autoloads (declared in `project.godot` `[autoload]`, load order matters)

| # | Name | Script | Role |
|---|---|---|---|
| 1 | `EngineGlobal` | `core/globals/engine.gd` | `initialize()` calls `randomize()`; invoked by Bootstrap |
| 2 | `EventBus` | `core/events/event_bus.gd` | Central publish/subscribe bus, all event-name constants |
| 3 | `LoggerGlobal` | `services/logger/logger.gd` | `debug/info/warn/error` print helpers |
| 4 | `SettingsManager` | `services/settings/settings_manager.gd` | Single source of truth for settings; validates, persists (`user://settings.json`), emits `SETTING_CHANGED` |
| 5 | `ConfigService` | `services/config/config_service.gd` | Persistence (`user://save_data.json`); proxies legacy settings to SettingsManager |
| 6 | `StatisticsManager` | `services/statistics/statistics_manager.gd` | Session + lifetime statistics; autosaves every 30 s |
| 7 | `AudioManager` | `services/audio/audio_manager.gd` | Single audio authority: category buses, event packs, cooldowns, variations, volume/mute |
| 8 | `BehaviorCatalog` | `core/base/behavior_catalog.gd` | Loads all behaviors from `data/behaviors/` |
| 9 | `PersonalityCatalog` | `core/base/personality_catalog.gd` | Loads all personalities from `data/personalities/` |
| 10 | `MusicService` | `services/music/music_service.gd` | Owns the looping music stream; delegates playback to AudioManager |
| 11 | `MenuBarService` | `services/menu/menu_bar_service.gd` | Native menu-bar "Pet" item (music/settings/quit); silent fallback when unavailable |
| 12 | `DebugOverlayManager` | `services/debug/debug_overlay_manager.gd` | Developer debug overlay (F8); reads each subsystem's `get_debug_info()` |
| 13 | `ThemeManager` | `services/theme/theme_manager.gd` | Discovers/validates/loads themes from `themes/` + plugin-registered themes |
| 14 | `PluginManager` | `core/plugins/plugin_manager.gd` | Plugin lifecycle manager; runs discovery at boot |

**Boot ordering rationale:** EventBus and Logger must exist first (everything emits/logs). SettingsManager then ConfigService provide config before AudioManager/StatisticsManager read it. Catalogs load data. ThemeManager must be up before PluginManager hands plugins `engine_services` (which include ThemeManager). PluginManager is last so every service a plugin may want already exists.

---

## 3. Boot sequence

1. **Autoloads `_ready()`** run in the order above.
2. **Main scene** `scenes/bootstrap/bootstrap.tscn` → `bootstrap.gd` `_ready()`:
   - `EngineGlobal.initialize()` → seeds `randomize()`.
   - `DesktopWindow.configure_small_window()` → 500×500 borderless transparent always-on-top window.
   - Reads the current screen's usable rect.
   - `ThemeManager.load_theme(ConfigService.theme_id)` loads the active theme.
   - Instantiates `scenes/pet/pet.tscn`; sets `screen_bounds`, copies `move_speed`, `gravity`, `jump_speed`, `scale` from ConfigService onto the pet's definition, and applies the active theme's `sprite_pack` / `audio_pack` / `default_personality_id`.
   - Restores the saved world position (or centers the pet near the top of the screen).
   - Adds the pet, registers it with `DebugOverlayManager` and `StatisticsManager`, and starts `DesktopWindow.track(pet)`.
   - Emits `EventBus.engine_initialized`.
3. **Pet `_ready()`** (`pets/default/pet.gd`):
   - Defaults the `definition` if null, applies `visual.scale` and the sprite pack.
   - Calls `initialize(self)` on every component under `$Components` (each component's `on_initialized()` runs).
   - Forces `StateMachineComponent` to `IDLE`, subscribes to `THEME_CHANGED`.
4. **PluginManager `_ready()`** (last autoload) builds `EngineServices` and defers `_boot_registered_plugins()`, which runs after the rest of the engine has booted:
   - `_auto_discover()` scans `res://plugins/` once (`PluginDiscovery.scan`), validates every folder, and registers valid candidates in category-priority order.
   - `_resolve_init_order()` (topological, dependencies first, cycle detection) → `initialize_plugin()` each, then `enable_plugin()` each.

---

## 4. The pet scene (`scenes/pet/pet.tscn`)

```
Pet (Node2D, pet.gd)              world_position is the source of truth
├── Visual/AnimatedSprite2D       the sprite; flip_h mirrors facing
├── Interaction (Area2D)          CapsuleShape2D collision + input events
│   └── CollisionShape2D
├── Components (Node)             25 subsystems, each extends PetComponent
│   ├── StateMachine / StatePriority-aware request queue
│   ├── MovementComponent (+ NaturalGait, MovementPolishComponent)
│   ├── AnimationTransitionManager / AnimationComponent / AnimationController
│   ├── DragComponent / PhysicsComponent
│   ├── ContextMenuComponent / ClickThroughComponent
│   ├── BehaviorStats / BehaviorDecision / BehaviorMemory / BehaviorPolish / BehaviorController
│   ├── DesktopAwarenessComponent / InteractionComponent / EmotionComponent
│   ├── FollowCursorComponent / PersonalityComponent / AudioEventComponent
├── Timers (Node)
└── ClickPolygon (Polygon2D)      defines the mouse-passthrough region
```

**The world model is special:** there is no shared 2D world. Each pet lives in its own 500×500 window whose center is pinned to `pet.world_position` (absolute desktop coordinates). "Walking" is really `DesktopWindow._follow_pet()` repositioning the OS window every frame so the pet stays centered at `world_position`. All physics is arithmetic on `velocity` (no CharacterBody2D): `PhysicsComponent` owns vertical velocity/gravity (1800 px/s²) and floor snapping; `MovementComponent` is the **sole writer of `pet.velocity.x`**.

---

## 5. Core data flow

### 5.1 State machine (the spine)

- `StateMachineComponent` holds one pending request. `request_state(state, priority)` replaces the pending request only when the new priority is **strictly higher**; `request_behavior()` adds `allowed_from` gating; `force_state()` clears pending and applies immediately.
- On every applied change it emits `EventBus.STATE_CHANGED` with `{previous_state, new_state}`.
- Consumers of `STATE_CHANGED`: `AnimationComponent` (plays the animation), `MovementPolishComponent` (landing recovery / `_last_move_state`), `PhysicsComponent` (sets `_jump_pending`), `BehaviorMemoryComponent` (records actions), `AudioEventComponent` (plays the event), `StatisticsManager` (counts).

### 5.2 Behavior AI (needs → action)

1. `BehaviorStatsComponent` owns a `PetStats` and applies passive drift every frame (HAPPINESS −0.01/s, BOREDOM +0.15/s, SLEEPINESS +0.06/s), personality-scaled, emitting typed signals + `stats_updated`.
2. `BehaviorDecisionComponent.tick()` (the engine's only decision timer, 3–6 s window) filters `BehaviorCatalog.get_all()` by gates/maxes, `allowed_from`, cooldowns, autonomy, and drag/physics blocking, then scores each: `base_weight × (1 + Σ stat_weight × stat/50) × personality_utility × 0.45^repeats × registered utility modifiers`. Picks **argmax**.
3. `BehaviorController` (the **single** executor of behavior transitions) applies polish transition delays, randomizes walk headings, computes duration (`randf_range(min,max) × personality × polish jitter`), applies per-second `stat_effects`, and submits via `request_behavior()` at LOW (IDLE/THINK/HAPPY/SAD) or NORMAL priority.
4. `BehaviorMemoryComponent` records real actions into a 10-entry history + lifetime counters (persisted), and emits `BEHAVIOR_SELECTED`.
5. **Mood channel** (parallel): every 18–35 s with 40% chance the pet flashes a 2.5 s THINK/HAPPY/SAD quirk weighted toward its current emotion.

**Interruptions are ground truth and bypass gating:** DRAG (HIGH, per-frame), manual override (HIGH, per-frame), physics FALL/LAND/JUMP (NORMAL), and `force_state`.

### 5.3 Movement pipeline

1. `MovementComponent._physics_process` picks context: manual → direct walk/run; drag → hard stop; WALK/RUN → gait planner; JUMP → direct with prior profile; else glide-stop.
2. `NaturalGait` plans legs (hesitate → accelerate → cruise ±15% → decelerate → pause/turn), randomized distances (300–900 px), and flows through edge turns when the space beyond the current monitor is another screen.
3. `MovementPolishComponent` supplies acceleration/deceleration/turn/arrival/edge-slowdown/jump-anticipation/landing-recovery tuning; `MovementComponent` is the only executor of `pet.velocity.x`.
4. `PhysicsComponent` integrates vertical velocity, floors the pet, and emits `jump_landed`.

### 5.4 Animation pipeline

`STATE_CHANGED` → `AnimationComponent` resolves the animation name via `BehaviorCatalog.get_animation_for_state()` → `AnimationTransitionManager.request(state, name)` (priority + protection + bounded queue + anti-thrash) → `AnimationController.play(sprite, name, protect, interrupt, restart)` (the only code that calls `sprite.play()`). Locomotion syncs `sprite.speed_scale` to ground speed for WALK/RUN.

### 5.5 Events

All engine-wide events flow through `EventBus` (`subscribe` / `emit` / `unsubscribe`; payload dictionaries; automatic cleanup of freed listeners). The full constant list is in `API_DOCUMENTATION.md §EventBus`. Two legacy signals (`engine_initialized`, `settings_requested`) remain for backward compatibility and are fired by `emit()` automatically.

---

## 6. Persistence

Two files in `user://` (`~/Library/Application Support/Godot/app_userdata/lyra new/` on macOS):

| File | Owner | Contents |
|---|---|---|
| `save_data.json` | `ConfigService` | `pet_position`, `settings` (move_speed, gravity, jump_speed, scale, always_on_top, launch_at_login, music_enabled, follow_cursor_enabled, personality_id, theme_id, master_volume_db, muted, category_volumes), `pet_stats`, `pet_memory`, `statistics`, `debug_overlay` |
| `settings.json` | `SettingsManager` | `{ "settings": { key: value } }` for every registered setting |

Save triggers: SettingsManager autosaves 0.5 s after a change; StatisticsManager autosaves every 30 s; stats/memory autosave every 30 s and on `NOTIFICATION_WM_CLOSE_REQUEST`; position saves on exit.

---

## 7. Plugin system

- **Discovery** (`PluginDiscovery`, stateless scanner): reads `plugin.json` in each folder under `plugins/`, validates structure, entry script (must extend `Plugin`), engine-version requirements (`engine_version` range and/or `supported_engine_versions` list), and dependency availability across the full candidate set. Produces `DiscoveredPlugin` records (valid/invalid + errors/warnings). Invalid plugins are reported and skipped — never silently ignored, never able to crash discovery.
- **Lifecycle** (`PluginManager`): registers, initializes (dependency-ordered topological sort with cycle detection), enables, disables, shuts down, and unloads plugins. Lifecycle hooks return `bool`; a `false` return or an internal script error marks the plugin `FAILED` and disables it — the engine keeps running.
- **Access** (`EngineServices`): the narrow surface plugins may use (`settings`, `theme`, `statistics`, `audio`, `config` wrappers). Plugins communicate with the rest of the engine through `EventBus`.
- **Statuses:** `REGISTERED → INITIALIZING → INITIALIZED → ENABLED / DISABLED / FAILED / SHUTDOWN / UNLOADED`.

See `CREATE_YOUR_FIRST_PLUGIN.md` for the manifest schema and a full example.

---

## 8. Extension model (Open/Closed)

| Extension | Mechanism | Engine change |
|---|---|---|
| Behavior | `.tres` in `data/behaviors/` (`BehaviorDefinition`) | none |
| Personality | `.tres` in `data/personalities/` (`PersonalityDefinition`) | none |
| Theme | folder in `themes/` with `theme.tres`, or `ThemeManager.register_theme_resource()` from a plugin | none |
| Sound pack | `AudioPack` / `AudioSound` resources | none |
| Plugin | folder in `plugins/` (`plugin.json` + `plugin.gd`) | none |
| Retune | settings resources swapped via `set_settings()` seams | none |
| New state | extend `PetState.State` + catalog/audio/behavior entries | additive |
| New stat | extend `PetStats.Stat` + `STAT_DEFINITIONS` | additive |

**Closed-for-modification guarantees:** `ThemeManager` never hardcodes theme knowledge (unknown `extensions` keys are ignored); `BehaviorCatalog`/`PersonalityCatalog` are read-only after load; `AudioManager` resolves events by id and ignores unknown ids; `PluginManager` never inspects plugin internals or hardcodes a category.
