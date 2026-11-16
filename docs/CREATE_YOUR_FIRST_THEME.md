# Create Your First Theme

> Note: in this engine, themes **are** pets. "Theme" and "pet" are the same extension point — see `CREATE_YOUR_FIRST_PET.md` for the full walkthrough of building a sprite pack, audio pack, and personality defaults. This document is the reference for theme authoring.

---

## 1. What a theme is

A `ThemeResource` (`core/base/theme_resource.gd`) that bundles:

- **sprite_pack** (`SpriteFrames`) — the pet's appearance and animation frames.
- **audio_pack** (`AudioPack`) — the pet's sounds (falls back to the default pack).
- **default_personality_id** — the personality used when the user hasn't chosen one.

Themes live in `themes/<id>/theme.tres` or are provided by plugins via `ThemeManager.register_theme_resource()`.

## 2. Folder layout

```
themes/
└── <theme_id>/
    ├── theme.tres                 (required)
    ├── sprites/                   SpriteFrames resources
    └── audio/                     AudioPack resources (optional)
```

## 3. theme.tres reference

Reference the real built-in file `themes/default/theme.tres`:

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
min_engine_version = ""
supported_engine_version = "4.7"
sprite_pack = ExtResource("2_sprites")
audio_pack = ExtResource("3_audio")
default_personality_id = "calm"
extensions = {}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | StringName | yes | Must match the folder name for file-based themes |
| `display_name` | String | yes | Shown in the debug overlay Theme section |
| `version` | String | yes | Semver string |
| `author` | String | no | Metadata |
| `description` | String | no | Metadata |
| `min_engine_version` | String | no | Empty = any engine; else `>=` requirement |
| `supported_engine_version` | String | no | Empty = any engine; else exact match |
| `sprite_pack` | SpriteFrames | yes | At minimum an `idle` animation |
| `audio_pack` | AudioPack | no | Falls back to `data/configs/default_audio_pack.tres` |
| `default_personality_id` | StringName | no | Fallback when no saved personality; default built-ins: `calm`, `curious`, `lazy`, `playful` |
| `extensions` | Dictionary | no | Reserved; unknown keys ignored |

## 4. Animation names

The engine plays these names (missing ones fall back to `idle`):

```
idle  walk  run  jump  fall  land  sleep  deep_sleep  thinking  happy  sad  music
```

- `walk` / `run` are side-view loops; the pet flips via `flip_h`.
- Locomotion `speed_scale` syncs to ground speed.
- The default theme ships all 12 animations.

## 5. Validation (what ThemeManager checks)

In order, first failure wins; a failed theme is reported and the engine keeps the previous theme:

1. Is a `ThemeResource`.
2. `id` is a non-empty `StringName`.
3. `display_name` is a non-empty `String`.
4. `version` is a non-empty `String`.
5. Engine compatibility (`min_engine_version` range and/or `supported_engine_version` exact match against `4.7`).
6. `sprite_pack` is a valid `SpriteFrames`.
7. `audio_pack` is a valid `AudioPack` or the fallback applies.

## 6. Events

`ThemeManager` emits on `EventBus`:

- `THEME_VALIDATED` — `{theme_id, valid}` after discovery/validation.
- `THEME_UNLOADED` — before switching away.
- `THEME_LOADED` — `{theme_id, display_name}` after a successful load.
- `THEME_CHANGED` — after load; the live pet re-applies the sprite pack on this event.

## 7. Shipping a theme as a plugin

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
	return ThemeManager.register_theme_resource(theme)
```

Registered plugin themes survive `discover_themes()` rescans.
