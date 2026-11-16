# Roadmap

Direction for the engine beyond v1.0.0. Items are grouped by theme; status reflects the current codebase and the plugin system's readiness for each. Nothing here is committed work — it's a proposal.

---

## 1.0 — Current (complete)

Stable core: bootstrap, desktop window with macOS watchdog, EventBus, settings + save data, statistics, audio/music/menu bar, themes, behaviors, personalities, debug overlay, full plugin system, verification harnesses. All verified green.

---

## 1.1 — Plugin ecosystem hardening

- [ ] Ship example plugins in `plugins/` (a theme plugin, a behavior plugin, a utility plugin) so `CREATE_YOUR_FIRST_PLUGIN.md` has living in-repo examples rather than fixtures only.
- [ ] Plugin hot-reload: `PluginDiscovery` is already idempotent re-scan safe; wire the debug overlay to re-run discovery and report diffs (added/removed/updated plugins).
- [ ] Plugin category API surface: currently `EngineServices` exposes `settings`, `theme`, `statistics`, `audio`, `config`. Extend with read-only stats queries for behavior plugins (documented via the same seam).
- [ ] Plugin manifest schema versioning so future breaking manifest changes are detectable.

## 1.2 — Content & authoring

- [ ] Theme gallery: multiple shipped themes beyond the default to validate the theme pipeline against real art.
- [ ] Behavior authoring tooling: a `BehaviorDefinition` inspector/validator (the catalog already validates at load; a UI would shorten iteration).
- [ ] Personality fine-tuning UI in the settings window (today personalities are data-only and switch via the debug overlay).
- [ ] Audio pack authoring guide + a second example audio pack.

## 1.3 — Multi-pet & desktops

- [ ] Multiple pets: `StatisticsManager` and `DesktopWindow` already key per-pet; formalize spawning/destroying pets at runtime.
- [ ] Per-monitor awareness: `DesktopAwarenessComponent` + `NaturalGait` already handle edge turns across monitors; extend to prefer the active/focused monitor.
- [ ] Shared "room" concept: two pets in adjacent windows coordinating via EventBus (a natural plugin showcase).

## 1.4 — Robustness & release

- [ ] Save-data schema versioning + graceful migration in `ConfigService` (today it migrates old-style settings; a schema field would future-proof it).
- [ ] Crash/backup strategy: the stress backup lives at `/tmp/pet_stress_backup/`; formalize rotating backups of `save_data.json`/`settings.json`.
- [ ] Signed/notarized macOS build pipeline (launch-at-login currently uses `osascript`).
- [ ] Windows/Linux porting notes: `DesktopWindow`, `MenuBarService`, and launch-at-login are macOS-specific today.

## 2.0 — Stretch

- [ ] Plugin marketplace / install-from-zip (discovery already reads folder manifests; a downloader + verifier would be the new surface).
- [ ] Webcam/mouse-reactive personality kit (new personality dimension — currently personalities are data weights only).
- [ ] Accessibility: high-contrast themes, reduced-motion respect, screen-reader labels for the debug overlay.

---

## Principles

- **Closed-for-modification, open-for-extension:** all roadmap items should be achievable via behaviors, personalities, themes, or plugins — not by editing core subsystems.
- **Verification stays the contract:** every feature ships with a `verif/` harness update.
- **No breaking the desktop pet contract:** pet window, always-on-top, follow-cursor, drag, and the state machine remain the foundation.
