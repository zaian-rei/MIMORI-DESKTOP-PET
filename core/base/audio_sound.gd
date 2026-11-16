extends Resource
class_name AudioSound

## One playable audio event. A reusable, data-driven sound definition - the
## engine never hardcodes a path. `streams` holds the random variations for
## the event (Footstep_01..04 etc.); the AudioManager picks one at random
## without repeating the previous pick. `cooldown_seconds` throttles replay
## (footsteps at max frequency, one-shot landing sounds), and
## `pitch_variation` adds a small random pitch offset to fight sameness.
##
## Future sound packs/themes ship new AudioSound resources (or replace the
## whole AudioPack) - engine code never changes.

## Logical event id requested through AudioManager.play_event(), e.g.
## &"walk", &"happy", &"ui_click". Unknown ids are ignored gracefully.
@export var event_id: StringName = &""

## Which category bus (and thus volume/mute group) this sound plays on.
@export var category: AudioCategory.Category = AudioCategory.Category.MOVEMENT

## The variation streams. A single stream is played as-is; with several, one
## is picked at random and the previous pick is never repeated back-to-back.
@export var streams: Array[AudioStream] = []

## Minimum seconds between two plays of this event. 0.0 = no limit (rarely
## useful - most events want a small cooldown to prevent spam).
@export var cooldown_seconds: float = 0.0

## Random pitch variation as a fraction of 1.0 (e.g. 0.03 = +/-3%). Subtle by
## design so variations sound like natural takes, not detuned artifacts.
@export var pitch_variation: float = 0.0

## Per-sound volume offset in dB on top of the category bus volume.
@export var volume_db: float = 0.0

## Whether this event counts toward the "voice" count in debug info. Future
## voice lines set this; it is purely informational for now.
@export var is_voice: bool = false
