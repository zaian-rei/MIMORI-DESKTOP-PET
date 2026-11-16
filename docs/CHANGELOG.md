# Changelog

The engine's change history. Entries are written from the actual codebase state. This repository has no prior git history; `v1.0.0` is the first documented release, capturing the current, fully-working system.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) — `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`.

---

## [Unreleased]

- Added separate Music and Ambient buses with distinct original looping tracks.
- Added eleven move-matched sound cues across Echo, Kairo, Lumen, Miso, and Vex. Special-move sounds remain grouped on their internal bus without a separate user-facing slider.
- Removed Music and Click-through toggle buttons from Settings and menus, removed Decision Timing and System pages, refreshed Personality choices, Help, and About, and rebuilt the Mac, Linux, and Windows downloads.

## [1.0.0] — 2026-08-07

First documented release. All subsystems verified green by the `verif/` harnesses.

### Added

- **Bootstrap** (`scenes/bootstrap/`): main scene configures the small desktop window, loads the active theme, instantiates the pet, restores/falls-back the world position, registers the pet with debug overlay + statistics, starts window tracking, and emits `engine_initialized`.
- **DesktopWindow** (`systems/desktop/`): 500×500 borderless transparent always-on-top window, per-frame centering on the pet's `world_position`, macOS always-on-top watchdog (0.5 s re-assert while enabled only), runtime always-on-top toggle.
- **EventBus** (`core/events/`): central publish/subscribe bus, typed event-name constants, payload dictionaries, freed-listener cleanup, legacy `engine_initialized` / `settings_requested` signals preserved.
- **SettingsManager** (`services/settings/`): registered settings by `"category.name"` key with types/limits/descriptions; validation; throttled persistence to `user://settings.json`; `SETTING_CHANGED` events; per-category and full resets.
- **ConfigService** (`services/config/`): `user://save_data.json` persistence; backward-compatible settings proxies delegating to SettingsManager; position/stats/memory/statistics/overlay persistence; macOS launch-at-login.
- **StatisticsManager** (`services/statistics/`): session + lifetime statistics recorded from engine signals (state changes, decisions), 30 s autosave, reset hooks.
- **AudioManager** (`services/audio/`): single audio authority — category buses, active `AudioPack` resolution, per-event cooldowns, non-repeating variations, random pitch, master/category volume + mute (survives mute across tracks), 16-voice pool.
- **MusicService** (`services/music/`): looping `pet_music.wav` via AudioManager ambient bus; `MUSIC_STARTED`/`MUSIC_STOPPED`; pet dance reaction; headless-safe.
- **MenuBarService** (`services/menu/`): native "Pet" menu (music/settings/quit) with silent degradation when unavailable.
- **ThemeManager** (`services/theme/`): theme discovery from `themes/`, validation, load/unload with events, plugin-registered theme preservation.
- **DebugOverlayManager** (`services/debug/`): F8-toggleable developer overlay, 17 data sections read from each subsystem's `get_debug_info()`, pause-AI/force-behavior/force-animation controls, visual toggles, persisted prefs.
- **Plugin system** (`core/plugins/`): `PluginDiscovery` (stateless scanner: manifest → entry → engine version → dependencies, category-priority ordering), `PluginManager` (lifecycle states, topological init order with cycle detection, error isolation, `EngineServices` access surface, debug introspection), `Plugin` base class (lifecycle hooks, `subscribe_event` auto-cleanup, dependency/metadata classes).
- **Pet components** (`components/`): state machine with priority gating, movement + gait + polish, physics (vertical velocity, floor snap, landing), animation pipeline (transition manager + controller), drag/click/interaction, behavior AI (stats/decision/memory/controller), personality, emotion, awareness, follow-cursor, audio events, context menu.
- **Base data** (`core/base/`): `BehaviorDefinition` + `BehaviorCatalog`, `PersonalityDefinition` + `PersonalityCatalog`, `ThemeResource`, `AudioPack`/`AudioSound`; built-in behaviors, personalities (`calm`, `curious`, `lazy`, `playful`), and default theme + audio pack.
- **Settings window** (`scenes/ui/`): live-apply sliders (speed/gravity/jump/scale), always-on-top + launch-at-login, snapshot cancel.
- **Verification harnesses** (`verif/`): discovery (68 assertions), plugin lifecycle, and EventBus stress scenes; 13 plugin fixtures covering valid/invalid discovery paths.

### Changed

- Project configured for Godot 4.7 Forward Plus, Jolt Physics, per-pixel transparency, 1920×1080 borderless always-on-top window, `expand` aspect.
- Autoload registration order fixed to a dependency-safe sequence (see `PROJECT_ARCHITECTURE.md §2`).

### Fixed

- macOS always-on-top flag being silently dropped after focus events (watchdog re-assert).
- Unknown audio/theme ids being fatal — now ignored gracefully.
- Broken plugins previously able to interrupt loading — now isolated, reported, and disabled.

### Notes

- User data lives in `user://` → `~/Library/Application Support/Godot/app_userdata/lyra new/` (`save_data.json`, `settings.json`).
- Release binary used for verification: `/Applications/Godot.app/Contents/MacOS/Godot`.

---

## Documented-from / provenance

This changelog is derived from the current codebase (autoloads, services, components, plugin system, verification harnesses). No claims are made about changes before this snapshot.
