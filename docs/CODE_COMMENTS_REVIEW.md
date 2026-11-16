# Code Comments Review

A review of how comments are used across the codebase and the conventions the project follows. GDScript files: 75.

---

## 1. Comment conventions in use

The codebase follows a consistent, layered comment style:

- **`##` doc comments** — class-level design contracts and non-trivial method purpose. The heaviest and most valuable usage is in the plugin system:
  - `core/plugins/plugin_discovery.gd` opens with a "Design contract" block (pure scanner, never lifecycle; validation strict but safe; explicit bounded scans).
  - `core/plugins/plugin_manager.gd` opens with a "Design contract" block (only lifecycle; never behavior; error isolation; declarative deps; sanctioned `engine_services` surface).
  - `core/plugins/plugin.gd` documents why `subscribe_event()` exists (auto-unsubscribe on disable/shutdown/fail → no orphan listeners) and the "return true on success; a false return or script error marks the plugin FAILED" contract.
  - `services/settings/settings_manager.gd` documents its single-source-of-truth contract and "NEVER moves the pet" boundary.
- **`#` inline comments** — used sparingly for non-obvious logic and constants. Examples: the macOS always-on-top watchdog explanation in `systems/desktop/desktop_window.gd`, backward-compat proxy notes in `services/config/config_service.gd`, and persistence-field explanations in `ConfigService` (e.g. "Ephemeral history ... deliberately not stored").
- **Section banners** — `## --- Section Name ----` dividers inside larger files (`settings_manager.gd`, `plugin_manager.gd`) keep navigation predictable.

## 2. Quality assessment

**Strengths**

- Design-contract comments are placed at the architectural seams (plugins, settings) where misuse is costliest. They explain *why*, not *what*.
- Private/`_`-prefixed methods are rarely commented individually; the doc comment sits on the public API they serve, avoiding drift.
- Persistence fields in `ConfigService` document what is *not* saved and why (session-only data), which prevents future accidental writes.

**Weaknesses / gaps**

- `core/events/event_bus.gd` groups constants with short section comments but the *payload contracts* live only in this doc set; adding a one-line payload comment per constant would help editor tooltips.
- Component scripts under `components/` are lightly commented relative to their complexity (e.g. the state-machine priority semantics, gait planning, animation anti-thrash). The behavior is correct, but the *invariants* (e.g. "`MovementComponent` is the sole writer of `pet.velocity.x`") deserve `##` notes at the ownership boundary.
- A few numeric tuning constants (e.g. `CLICK_HOLD_SECONDS`, `DRAG_SLOP_PIXELS`, gait distance ranges, stat drift rates) are named well but lack the "why this value" context that tuning discussions often need.

**No-code issues found**

- No `TODO`, `FIXME`, `HACK`, `XXX`, or `DEPRECATED` markers anywhere in the GDScript sources — the tree is clean.
- No obsolete comments that contradict current behavior were found in the reviewed seams (EventBus, SettingsManager, ConfigService, plugin system, theme/audio/debug overlay managers, DesktopWindow).

## 3. Recommendations (low priority, non-blocking)

1. Add `##` payload-contract comments to `EventBus` constants (§1 of `API_DOCUMENTATION.md` is the source of truth today).
2. Add ownership-invariant notes to the movement/physics/animation components that `API_DOCUMENTATION.md §14` and `PROJECT_ARCHITECTURE.md §4` document.
3. Keep the "why, not what" rule: when touching a commented seam, preserve the design-contract style; when adding comments elsewhere, prefer a named constant or a short `##` on the method over inline noise.

## 4. Consistency with documented rules

`CONTRIBUTING.md` requires: no added comments unless clarifying non-obvious intent; tab indentation; `_`-prefixed private members; `##` doc comments on classes and non-trivial methods. The current tree complies with all four.
