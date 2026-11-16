# Contributing

Guidelines for working on the engine, with an emphasis on the verification harness workflow that keeps every subsystem green.

---

## 1. Ground rules

- **Never regress the engine.** Subsystems must keep running after any change. The `verif/` harnesses are the contract — run them before and after your work.
- **Components and services communicate via `EventBus` or a public API only.** Never reach into another subsystem's internals.
- **No architecture redesigns without discussion.** The layered structure in `PROJECT_ARCHITECTURE.md` is intentional.
- **Follow the code style of the file you're editing:** GDScript, tab indentation, typed variables (`:=` inference, explicit types on members), `_`-prefixed private members, doc comments (`##`) on classes and non-trivial methods.
- Do not add comments to code unless they clarify non-obvious intent. (See `CODE_COMMENTS_REVIEW.md`.)

## 2. Development loop

1. Make your change.
2. Run the affected verification harness (below).
3. Run the full verification pass.
4. If you touched documentation, re-check `docs/` facts against the code — the docs are written only from real code.

## 3. Verification harnesses

All harnesses live in `verif/` as standalone scenes (`verify_stress_*.gd` + `.tscn`). They are headless-safe: the window and audio are skipped, but the full autoload/boot path and `EventBus` still run.

Run from the project root with the release binary:

```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --path /Users/zaian/pet --headless --quit-after 600 res://verif/verify_stress_discovery.tscn
$GODOT --path /Users/zaian/pet --headless --quit-after 600 res://verif/verify_stress_plugins.tscn
$GODOT --path /Users/zaian/pet --headless --quit-after 600 res://verif/verify_stress_eventbus.tscn
```

(If the path differs on your machine, adjust `$GODOT`.) Every harness prints `[VERIFY] PASS ...` lines and ends with a failure count. Expected results:

| Harness | Scope | Expected |
|---|---|---|
| `verify_stress_discovery` | Plugin discovery: boot-time auto-discovery, explicit discovery, manifest parsing, validation (structure/engine/supported-versions/deps), load order by category + topological deps, registration, settings + theme-plugin integration, idempotent re-scan, broken-plugin isolation | 68 PASS, fails = 0 |
| `verify_stress_plugins` | Plugin lifecycle: registration validation, boot auto-start, manual lifecycle, enable/disable, event unsubscription on disable, dependency ordering/version checks/cycles, error isolation, settings + theme integration, debug introspection | fails = 0 |
| `verify_stress_eventbus` | EventBus: subscribe/emit/unsubscribe, payloads, freed-listener cleanup | fails = 0 |

Also run a plain headless boot to confirm the project boots cleanly:

```bash
$GODOT --path /Users/zaian/pet --headless --quit-after 120
```

**Fixture note:** discovery/plugin harnesses copy fixture plugins in and out of `res://plugins/` at runtime and clean up after themselves (`_cleanup_boot_plugins`). Do not leave stray plugin folders in `res://plugins/` — it's normally empty in the shipped project.

## 4. What to check before submitting

- [ ] `verif` harnesses green (fails = 0).
- [ ] Clean headless boot (no errors).
- [ ] New autoloads added in dependency-safe order (see `PROJECT_ARCHITECTURE.md §2`).
- [ ] New events added to `EventBus` constants + documented in `API_DOCUMENTATION.md §EventBus`.
- [ ] Settings keys documented in `ENGINE_GUIDE.md §3` and `API_DOCUMENTATION.md §SettingsManager`.
- [ ] Extension points (behaviors/personalities/themes/plugins) don't require engine changes.
- [ ] No secrets or absolute personal paths committed.

## 5. Submitting changes

This repository is not currently under git. If git is initialized later, keep commits focused, one logical change per commit, and write a message that summarizes *what* and *why* (the *how* is in the diff).

## 6. Where to add docs

- User/authoring guides: `CREATE_YOUR_FIRST_PET.md`, `CREATE_YOUR_FIRST_THEME.md`, `CREATE_YOUR_FIRST_PLUGIN.md`.
- Runtime reference: `ENGINE_GUIDE.md`.
- Architecture: `PROJECT_ARCHITECTURE.md`.
- API surface: `API_DOCUMENTATION.md`.
- Change history: `CHANGELOG.md` (unreleased changes go under an `[Unreleased]` heading).
