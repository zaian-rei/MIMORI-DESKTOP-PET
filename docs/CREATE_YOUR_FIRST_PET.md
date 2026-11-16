# Create Your First Pet (Theme)

In this engine a **pet** is a theme. A theme bundles the sprite pack (what the pet looks like and its animation frames), the audio pack (what the pet sounds like), and a default personality. To make a new pet you create a new theme folder under `themes/`.

This guide walks you through the built-in theme as the reference implementation.

---

## 1. Anatomy of a theme

```
themes/<your_theme_id>/
├── theme.tres            ThemeResource definition (required)
├── sprites/              SpriteFrames resources for each animation
└── audio/                AudioPack resources (optional; falls back to default)
```

The engine finds themes by scanning folders in `themes/` for a file named `theme.tres`. Anything else is ignored. The `id` inside `theme.tres` must match the folder name for the theme to be selectable.

## 2. The ThemeResource (`themes/default/theme.tres`)

This is the real built-in theme. Copy the structure:

```
[gd_resource type="Resource" script_class="ThemeResource" format=3]

[ext_resource type="Script" uid="uid://bahcobvk4ioii" path="res://core/base/theme_resource.gd" id="1_theme"]
[ext_resource type="SpriteFrames" path="res://themes/default/sprites/default_sprite_frames.tres" id="2_sprites"]
[ext_resource type="Resource" uid="uid://bgtnw63yntbmu" path="res://data/configs/default_audio_pack.tres" id="3_audio"]

[resource]
script = ExtResource("1_theme")
id = "default"
display_name = "Default Pet"
version = "1.0.0"
author = "Desktop Pet Engine"
description = "The built-in default pet theme with standard animations and sounds."
supported_engine_version = "4.7"
sprite_pack = ExtResource("2_sprites")
audio_pack = ExtResource("3_audio")
default_personality_id = "calm"
extensions = {}
```

Fields:

| Field | Purpose |
|---|---|
| `id` | Unique theme id; must match the folder name |
| `display_name` | Human-readable name (shown in the debug overlay / Theme section) |
| `version` | Your theme version (semver string) |
| `author`, `description` | Metadata |
| `min_engine_version` / `supported_engine_version` | Validation constraints (see §5) |
| `sprite_pack` | The `SpriteFrames` resource with every animation the pet can play |
| `audio_pack` | The `AudioPack` resource for sounds; optional, falls back to the default pack |
| `default_personality_id` | Which personality to use if the user hasn't chosen one (see `data/personalities/`) |
| `extensions` | Reserved dictionary for future/custom data; unknown keys are ignored by `ThemeManager` |

## 3. The sprite pack (animations)

The pet can play these animation names. Include only the ones your sprites support; missing ones fall back to `idle`:

`idle`, `walk`, `run`, `jump`, `fall`, `land`, `sleep`, `deep_sleep`, `thinking`, `happy`, `sad`, `music` (the default theme ships all 12 — see `themes/default/theme.tres`).

A `SpriteFrames` resource (Godot editor → SpriteFrames → New SpriteFrames) holds one `Animation` per name. Locomotion speed is synced to ground speed for `walk`/`run`, so your `walk`/`run` animations are expected to be looped, side-view frames (the pet flips horizontally via `flip_h` when turning).

The animation-to-behavior mapping is data-driven: `BehaviorCatalog.get_animation_for_state(state)` resolves each `BehaviorDefinition`'s `animation_name`; the overlay's Force Animation and the manual context-menu animations use the same names.

## 4. The audio pack (sounds)

An `AudioPack` (`data/configs/default_audio_pack.tres`) maps event ids to `AudioSound` entries. Event ids the engine listens for include `&"walk"`, `&"jump"`, `&"land"`, `&"happy"`, `&"sad"`, `&"think"`, `&"music"`, `&"sleep"`, `&"feed"`, `&"drag"`, `&"release"`, and more. Each `AudioSound` has an optional stream, per-event cooldown, volume range, and pitch variation. Unknown event ids are ignored gracefully, so a minimal pack with just a few sounds is fine.

If you omit `audio_pack`, `ThemeManager` falls back to the default pack rather than erroring.

## 5. Validation rules

`ThemeManager.validate_theme()` checks, in order (first failure wins):

1. Resource is a `ThemeResource`.
2. `id` is a non-empty `StringName`.
3. `display_name` is a non-empty `String`.
4. `version` is a non-empty `String`.
5. Engine compatibility: either `min_engine_version` is empty or `>= 4.7` is satisfied; and either `supported_engine_version` is empty or it exactly matches the running engine version.
6. `sprite_pack` is a valid `SpriteFrames`.
7. `audio_pack` is a valid `AudioPack` (or the fallback applies).

A theme that fails validation is reported but the engine keeps running with the previous theme.

## 6. Registering your theme

Two ways:

1. **File-based (no code):** drop the folder into `themes/`. `ThemeManager._ready()` calls `discover_themes()`, which finds and validates it. Restart, or switch to it from the debug overlay's Theme section.
2. **Plugin-provided:** build a `ThemeResource` in a plugin and call `ThemeManager.register_theme_resource(theme)` — exactly what the `fixture_theme` fixture does:

```gdscript
# plugins/my_theme/plugin.gd
extends Plugin

func initialize() -> bool:
	var theme := ThemeResource.new()
	theme.id = "my_theme"
	theme.display_name = "My Pet"
	theme.version = "1.0.0"
	theme.author = "You"
	theme.description = "A theme shipped as a plugin."
	theme.sprite_pack = preload("res://plugins/my_theme/sprites.gd:sprites")
	theme.audio_pack = preload("res://data/configs/default_audio_pack.tres")
	return ThemeManager.register_theme_resource(theme)
```

Theming a plugin-registered theme is preserved: `register_theme_resource()` keeps it across later `discover_themes()` calls so a plugin theme can't be wiped by a folder rescan.

## 7. What the engine does with your theme

At boot, `Bootstrap` calls `ThemeManager.load_theme(ConfigService.theme_id)`. On load the engine:

1. Unloads the current theme (emits `THEME_UNLOADED`).
2. Applies `audio_pack` to `AudioManager` and emits `THEME_LOADED` → `THEME_CHANGED`.
3. Applies `sprite_pack`, `audio_pack`, and `default_personality_id` to the pet's `definition`.
4. The live pet re-applies the sprite pack on `THEME_CHANGED` (`pet.gd` `_on_theme_changed`).

So a theme switch is fully live: sprites, sounds, and personality bias all swap without a restart.

---

## Checklist

- [ ] Folder `themes/my_pet/` with `theme.tres` inside.
- [ ] `id` in `theme.tres` == folder name, `display_name` set, `version` set.
- [ ] `sprite_pack` set with at least `idle`; animation names match the 12 engine names above.
- [ ] `supported_engine_version = "4.7"` (or empty).
- [ ] Optional: `audio_pack`, `default_personality_id`.
- [ ] Restart / run, and confirm the theme appears in the debug overlay Theme section.
