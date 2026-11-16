extends RefCounted
class_name AudioCategory

## The audio categories every sound belongs to. Each category owns a dedicated
## audio bus with its own volume, all routed into Master so the master volume
## and mute govern everything. New categories extend the enum + BUS_NAMES and
## are picked up automatically (the AudioManager iterates Category.values()).
##
## The bus names intentionally avoid clashing with Godot's default buses
## (only "Master" exists out of the box) and with future UI labels.

enum Category {
	MOVEMENT,
	ANIMATIONS,
	INTERACTIONS,
	UI,
	AMBIENT,
	VOICE,
	SPECIAL_MOVES,
	MUSIC,
}

const BUS_NAMES := {
	Category.MOVEMENT: "AudioMovement",
	Category.ANIMATIONS: "AudioAnimations",
	Category.INTERACTIONS: "AudioInteractions",
	Category.UI: "AudioUi",
	Category.AMBIENT: "AudioAmbient",
	Category.VOICE: "AudioVoice",
	Category.SPECIAL_MOVES: "AudioSpecialMoves",
	Category.MUSIC: "AudioMusic",
}

## Human-readable labels, in the same order as the enum (useful for the
## future settings UI and the debug overlay).
const LABELS := {
	Category.MOVEMENT: "Movement",
	Category.ANIMATIONS: "Animations",
	Category.INTERACTIONS: "Interactions",
	Category.UI: "UI",
	Category.AMBIENT: "Ambient",
	Category.VOICE: "Voice",
	Category.SPECIAL_MOVES: "Special Moves",
	Category.MUSIC: "Music",
}

## All categories, in enum order.
static func all() -> Array:
	return Category.values()


static func bus_name(category: int) -> String:
	return BUS_NAMES.get(category, "Master")


static func label(category: int) -> String:
	return LABELS.get(category, "Master")


static func is_valid(category: int) -> bool:
	return category in BUS_NAMES
