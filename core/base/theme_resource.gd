extends Resource
class_name ThemeResource

## A complete pet identity bundle. A theme packages every visual, audio, and
## behavioral asset the engine needs to present a pet — sprites, sounds,
## personality, and default settings. The engine never knows which pet it is
## running; it only loads a ThemeResource and applies its contents.
##
## Design rules:
##   - The engine MUST NOT hardcode knowledge of specific themes.
##   - Every field is optional except `id` — missing assets fall back to the
##     engine's built-in defaults.
##   - Future extensions (custom behaviors, effects, plugins) go into the
##     `extensions` dictionary to avoid breaking the schema.

## ---- Metadata --------------------------------------------------------------

## Unique machine-readable id (e.g. "fox", "cat", "robot"). Used as the
## lookup key in ThemeManager and for persistence.
@export var id: String = ""

## Human-readable display name shown in UI.
@export var display_name: String = ""

## Semantic version string (e.g. "1.0.0").
@export var version: String = "1.0.0"

## Theme author / creator.
@export var author: String = ""

## Short description of this theme.
@export var description: String = ""

## Minimum engine version required to run this theme (semver string).
## ThemeManager rejects themes whose min_engine_version exceeds the running
## engine version.
@export var min_engine_version: String = ""

## Engine version this theme was built and tested against.
@export var supported_engine_version: String = ""

## Preview image shown in theme selection UI (future).
@export var preview_image: Texture2D

## Small icon for theme listings (future).
@export var icon: Texture2D

## ---- Core Assets -----------------------------------------------------------

## SpriteFrames containing all animation sprite sheets for this pet.
## When set, ThemeManager applies this to the pet's AnimatedSprite2D,
## completely replacing the visual identity. When null, the engine's
## built-in sprites (baked into pet.tscn) are used.
@export var sprite_pack: SpriteFrames

## Audio pack defining all sound events for this pet.
## When set, ThemeManager registers it with AudioManager.
## When null, the engine's default audio pack is used.
@export var audio_pack: AudioPack

## ---- Behavioral Defaults ---------------------------------------------------

## Default personality catalog id for this theme.
## When empty, the catalog's first personality is used.
@export var default_personality_id: String = ""

## ---- Future Extensibility --------------------------------------------------

## Open-ended dictionary for future additions (custom behaviors, effects,
## UI skins, plugins). ThemeManager ignores keys it doesn't recognise, so
## themes can ship extensions without breaking engine compatibility.
@export var extensions: Dictionary = {}


## ---- Validation -----------------------------------------------------------

## Returns an array of human-readable error strings. Empty array = valid.
func validate() -> Array[String]:
	var errors: Array[String] = []

	if id.is_empty():
		errors.append("Theme id is empty.")

	if display_name.is_empty():
		errors.append("Theme display_name is empty.")

	if version.is_empty():
		errors.append("Theme version is empty.")

	if not min_engine_version.is_empty() and not _is_compatible():
		errors.append(
			"Theme requires engine %s, but running engine is %s."
			% [min_engine_version, Engine.get_version_info().get("string", "unknown")]
		)

	return errors


func _is_compatible() -> bool:
	var running := _parse_semver(Engine.get_version_info().get("string", "0.0.0"))
	var required := _parse_semver(min_engine_version)
	if running.is_empty() or required.is_empty():
		return true
	for i in range(3):
		if running[i] > required[i]:
			return true
		if running[i] < required[i]:
			return false
	return true


func _parse_semver(version_string: String) -> Array[int]:
	var parts := version_string.strip_edges().split(".")
	var result: Array[int] = []
	for part in parts:
		result.append(int(part))
	while result.size() < 3:
		result.append(0)
	return result


func get_debug_info() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"version": version,
		"author": author,
		"description": description,
		"min_engine_version": min_engine_version,
		"supported_engine_version": supported_engine_version,
		"has_sprite_pack": sprite_pack != null,
		"has_audio_pack": audio_pack != null,
		"default_personality_id": default_personality_id,
		"extension_count": extensions.size(),
		"validation_errors": validate(),
	}
