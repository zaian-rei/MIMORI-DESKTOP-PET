extends Node

## The five companion identities currently shipped in pet.tscn. Animation
## names are stored here so missing clips are never requested by shared behavior.
const DEFAULT_ID := "echo"
const SPRITE_FRAME_PATHS := {
	"echo": "res://data/pets/echo_sprite_frames.tres",
	"kairo": "res://data/pets/kairo_sprite_frames.tres",
	"lumen": "res://data/pets/lumen_sprite_frames.tres",
	"miso": "res://data/pets/miso_sprite_frames.tres",
	"vex": "res://data/pets/vex_sprite_frames.tres",
}
const PROFILES := [
	{
		"id": "echo", "name": "Echo", "description": "A curious little machine that scans, repairs itself, and sparks with energy.", "portrait": "res://assets/sprites/new/echo.png",
		"aliases": {"think": "thinking", "sad": "thinking"}, "startup": "s1",
		"special_wait": Vector2(120.0, 240.0), "special_chance": 0.10,
		"mood_wait": Vector2(22.0, 38.0), "mood_chance": 0.34,
		"specials": [
			{"animation": "s1", "name": "Hologram Scan", "sound_event": "move_echo_scan"},
			{"animation": "s2", "name": "Self Repair", "sound_event": "move_echo_repair"},
			{"animation": "s3", "name": "Energy Burst", "sound_event": "move_echo_burst"},
		],
	},
	{
		"id": "kairo", "name": "Kairo", "description": "A quiet ninja cat who keeps watch and springs into action when needed.", "portrait": "res://assets/sprites/new/kairo.png",
		"aliases": {"thinking": "think", "sad": "think"}, "startup": "angry",
		"special_wait": Vector2(120.0, 240.0), "special_chance": 0.10,
		"mood_wait": Vector2(28.0, 46.0), "mood_chance": 0.30,
		"specials": [{"animation": "angry", "name": "Fight", "sound_event": "move_kairo_sword"}],
	},
	{
		"id": "lumen", "name": "Lumen", "description": "A gentle little ghost who drifts away and softly reappears.", "portrait": "res://assets/sprites/new/lumen.png",
		"aliases": {"thinking": "think"}, "startup": "appear",
		"special_wait": Vector2(120.0, 240.0), "special_chance": 0.10,
		"mood_wait": Vector2(18.0, 33.0), "mood_chance": 0.40,
		"specials": [
			{"animation": "disappear", "name": "Fade Away", "sound_event": "move_lumen_disappear"},
			{"animation": "appear", "name": "Reappear", "sound_event": "move_lumen_appear"},
		],
	},
	{
		"id": "miso", "name": "Miso", "description": "A playful slime who squishes, changes shape, and pops bubbles.", "portrait": "res://assets/sprites/new/miso.png",
		"aliases": {"thinking": "think"}, "startup": "s1",
		"special_wait": Vector2(120.0, 240.0), "special_chance": 0.10,
		"mood_wait": Vector2(16.0, 30.0), "mood_chance": 0.44,
		"specials": [
			{"animation": "s1", "name": "Slime Launch", "sound_event": "move_miso_launch"},
			{"animation": "s2", "name": "Shape Shift", "sound_event": "move_miso_shape"},
			{"animation": "s3", "name": "Bubble Pop", "sound_event": "move_miso_bubble"},
		],
	},
	{
		"id": "vex", "name": "Vex", "description": "A mischievous shadow creature who can split, sink, and vanish.", "portrait": "res://assets/sprites/new/vex.png",
		"aliases": {"thinking": "think"}, "startup": "s1",
		"special_wait": Vector2(120.0, 240.0), "special_chance": 0.10,
		"mood_wait": Vector2(25.0, 42.0), "mood_chance": 0.33,
		"specials": [
			{"animation": "s1", "name": "Shadow Double", "sound_event": "move_vex_double"},
			{"animation": "s2", "name": "Shadow Dive", "sound_event": "move_vex_dive"},
		],
	},
]

func get_all_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for profile in PROFILES:
		ids.append(str(profile["id"]))
	return ids

func get_names() -> PackedStringArray:
	var names := PackedStringArray()
	for profile in PROFILES:
		names.append(str(profile["name"]))
	return names

func get_profile(profile_id: String) -> Dictionary:
	for profile in PROFILES:
		if profile["id"] == profile_id.to_lower():
			return profile
	return {}

func valid_id(profile_id: String) -> String:
	return profile_id.to_lower() if not get_profile(profile_id).is_empty() else DEFAULT_ID

## Load only the selected pet's atlas and animation clips.
func load_sprite_frames(profile_id: String) -> SpriteFrames:
	var path := str(SPRITE_FRAME_PATHS.get(valid_id(profile_id), ""))
	return load(path) as SpriteFrames if not path.is_empty() else null

func special_wait_range(profile_id: String) -> Vector2:
	var profile := get_profile(profile_id)
	return profile.get("special_wait", Vector2(60.0, 110.0))

func special_chance(profile_id: String) -> float:
	var profile := get_profile(profile_id)
	return float(profile.get("special_chance", 0.35))

func mood_wait_range(profile_id: String) -> Vector2:
	var profile := get_profile(profile_id)
	return profile.get("mood_wait", Vector2(18.0, 35.0))

func mood_chance(profile_id: String) -> float:
	var profile := get_profile(profile_id)
	return float(profile.get("mood_chance", 0.4))

func has_animation(profile_id: String, animation_name: String, frames: SpriteFrames) -> bool:
	if frames == null:
		return false
	var profile := get_profile(profile_id)
	if profile.is_empty():
		return frames.has_animation(animation_name)
	var canonical := _canonical_name(animation_name)
	var aliases: Dictionary = profile.get("aliases", {})
	var actual := str(aliases.get(canonical, canonical))
	return frames.has_animation(profile_id.to_lower() + " " + actual)

func has_native_animation(profile_id: String, animation_name: String, frames: SpriteFrames) -> bool:
	if frames == null:
		return false
	var profile := get_profile(profile_id)
	if profile.is_empty():
		return frames.has_animation(animation_name)
	var canonical := _canonical_name(animation_name)
	var aliases: Dictionary = profile.get("aliases", {})
	## A safe alias may render a manual sad request but must not make a missing
	## sad clip an autonomous emotion.
	var actual := canonical if canonical == "sad" else str(aliases.get(canonical, canonical))
	return frames.has_animation(profile_id.to_lower() + " " + actual)

func resolve_animation(profile_id: String, requested: String, frames: SpriteFrames) -> String:
	if frames == null:
		return ""
	if frames.has_animation(requested):
		return requested
	var profile := get_profile(profile_id)
	if profile.is_empty():
		return ""
	var canonical := _canonical_name(requested)
	var aliases: Dictionary = profile.get("aliases", {})
	var actual := str(aliases.get(canonical, canonical))
	var candidate := profile_id.to_lower() + " " + actual
	if frames.has_animation(candidate):
		return candidate
	var idle := profile_id.to_lower() + " idle"
	return idle if frames.has_animation(idle) else ""

func get_startup_animation(profile_id: String, frames: SpriteFrames) -> String:
	var profile := get_profile(profile_id)
	if profile.is_empty() or frames == null:
		return ""
	var animation := profile_id.to_lower() + " " + str(profile.get("startup", ""))
	return animation if frames.has_animation(animation) else ""

func get_special_animations(profile_id: String, frames: SpriteFrames) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var profile := get_profile(profile_id)
	if profile.is_empty() or frames == null:
		return found
	for move in profile.get("specials", []):
		var animation := profile_id.to_lower() + " " + str(move["animation"])
		if frames.has_animation(animation):
			found.append({
				"animation": animation,
				"name": str(move["name"]),
				"sound_event": str(move.get("sound_event", "")),
			})
	return found

func _canonical_name(animation_name: String) -> String:
	var name := animation_name.strip_edges().to_lower().replace("_", " ")
	match name:
		"think", "thinking": return "thinking"
		"dance", "music": return "music"
		"deep sleep", "deepsleep": return "deep sleep"
		_: return name
