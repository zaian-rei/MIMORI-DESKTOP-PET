# Project Audit

A snapshot audit of the desktop pet engine at v1.0.0. It records what was verified, what was inspected, findings, and open risks. Facts only — no invented systems.

Audit date: 2026-08-07. Engine: Godot 4.7, project name **"lyra new"**.

---

## 1. Scope & method

- **Inspected:** `project.godot` (autoloads, display, physics), bootstrap scene + script, `systems/desktop/desktop_window.gd`, all 14 autoload services, `core/events/event_bus.gd`, `core/base/` resources, `core/plugins/` (base, discovery, manager), pet scene + `components/`, settings window, debug overlay + `debug_draw.gd`, `verif/` harnesses + fixtures.
- **Verified by execution:** headless boot, discovery stress harness, plugin stress harness, eventbus stress harness (green results below).
- **Not audited:** pixel-perfect art correctness of `default_sprite_frames.tres`, actual audio asset content, or real-desktop window behavior (requires a non-headless session on macOS).

## 2. Verification results

| Check | Command | Result |
|---|---|---|
| Clean headless boot | `Godot --headless --quit-after 120` | Green (no errors) |
| Plugin discovery stress | `res://verif/verify_stress_discovery.tscn` | 68 PASS, fails = 0 |
| Plugin lifecycle stress | `res://verif/verify_stress_plugins.tscn` | fails = 0 |
| EventBus stress | `res://verif/verify_stress_eventbus.tscn` | fails = 0 |

Release binary used: `/Applications/Godot.app/Contents/MacOS/Godot`.

## 3. Findings

### 3.1 Positive

- **Dependency-safe autoload order** (`PROJECT_ARCHITECTURE.md §2`): EventBus + Logger → Settings → Config → Statistics/Audio → catalogs → Music/Menu → Debug → Theme → PluginManager last. Plugins therefore always see a fully-booted engine.
- **Error isolation end to end:** broken plugin manifests, missing entries, engine-version mismatches, and runtime hook failures all disable only the offending plugin (13 fixtures exercise every path).
- **Clean seam discipline:** the debug overlay renders only `get_debug_info()` output; plugins touch the engine only via `get_engine_services()`; MovementComponent is the sole writer of horizontal velocity; BehaviorController is the single behavior executor; only `AnimationController` calls `sprite.play()`.
- **Backward compatibility preserved:** ConfigService proxies keep legacy `move_speed`/`gravity`/`always_on_top` reads working while the single source of truth moved to SettingsManager.
- **Data-driven extension points need no engine edits:** behaviors/personalities are `.tres` files; themes are folders or plugin-registered resources; the two catalogs are read-only after load.
- **Verification culture:** a working harness suite ships in-tree with an expected-result contract.

### 3.2 Risks / open items

| # | Risk | Notes | Suggested follow-up |
|---|---|---|---|
| 1 | macOS-specific surfaces | `DesktopWindow` flags, `MenuBarService` (NativeMenu), `osascript` launch-at-login are macOS-only. | Windows/Linux porting plan (ROADMAP §1.4) |
| 2 | Save-data schema has no version field | `ConfigService` migrates old-style settings but lacks an explicit schema version; future field renames would be ambiguous. | Add `schema_version` + migration table (ROADMAP §1.4) |
| 3 | Backup strategy is ad hoc | Stress backups land in `/tmp/pet_stress_backup/`; no rotating backup of real user data. | Formalize backup rotation |
| 4 | Always-on-top relies on a watchdog | macOS can drop the flag; the 0.5 s re-assert mitigates but is a workaround, not a guarantee. | Monitor upstream/OS behavior in 4.7+ |
| 5 | `res://plugins/` is empty in the shipped tree | The plugin pipeline is fixture-verified but ships no living example. | Ship example plugins (ROADMAP §1.1) |
| 6 | Single-pet assumption in several services | `StatisticsManager`/`DesktopWindow` are per-pet-parameterized but runtime multi-pet spawning is unformalized. | ROADMAP §1.3 |
| 7 | Audio/art content not content-audited | Behavior logic verified; actual WAV/sprite-frames quality is unverified. | Authoring guides + gallery (ROADMAP §1.2) |

## 4. Size snapshot

- 75 GDScript source files.
- 13 plugin fixtures under `verif/fixtures/plugins/` (5 valid, 8 invalid) exercising all discovery rejection paths.
- 3 verification harness scenes.
- User data: `~/Library/Application Support/Godot/app_userdata/lyra new/` (`save_data.json`, `settings.json`).

## 5. Conclusion

The engine meets its v1.0.0 contract: boot, pet lifecycle, windowing, settings/save, audio/music/menu, themes, behaviors/personalities, debug overlay, and the plugin system are all present, wired, and verified green by the in-tree harnesses. The open risks are platform scope, save-schema versioning, and ecosystem polish — none are correctness blockers for the shipped feature set.
