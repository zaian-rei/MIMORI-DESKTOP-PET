extends Resource
class_name AudioPack

## A bundle of AudioSound definitions, keyed by event id. The AudioManager
## loads exactly one active pack and resolves every play_event() request
## against it. This is the theme / sound-pack seam: switching pets or themes
## swaps the active pack and all sounds change with zero engine changes.
## A pack is just data - it never decides what to play.

@export var pack_name: String = "unnamed"

@export var sounds: Array[AudioSound] = []

## Resolves an event id to its sound definition, or null when this pack does
## not define the event (callers treat that as "no sound", never an error).
func get_sound(event_id: StringName) -> AudioSound:
	for sound in sounds:
		if sound != null and sound.event_id == event_id:
			return sound
	return null
