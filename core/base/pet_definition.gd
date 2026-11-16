extends Resource
class_name PetDefinition

## Per-pet tunable values, stored as data instead of hardcoded script
## constants. Swapping which PetDefinition resource is assigned to a Pet
## instance changes its physics/movement feel with zero script changes -
## this is the foundation for supporting many different pets later without
## branching or duplicating component code.

@export var gravity: float = 1800.0
@export var jump_speed: float = 450.0
@export var floor_offset: float = 80.0
@export var move_speed: float = 150.0
@export var run_speed_multiplier: float = 1.6
@export var boundary_margin: float = 32.0
@export var scale: float = 1.0

## Data-driven tuning for the pet's natural gait (hesitations, leg lengths,
## acceleration, turning). When unset, MovementComponent falls back to the
## bundled default settings.
@export var movement_settings: MovementSettings

## Data-driven tuning for the Movement Polish System (walk/run acceleration,
## turning, arrival, edge, jump anticipation, landing recovery, follow-cursor
## smoothing). When unset, MovementPolishComponent falls back to the bundled
## default settings.
@export var movement_polish_settings: MovementPolishSettings

## Data-driven tuning for the Animation Polish System (transition priorities,
## safe interruption windows, the transition queue, duplicate protection and
## anti-thrash). When unset, AnimationTransitionManager falls back to the
## bundled default settings.
@export var animation_polish_settings: AnimationPolishSettings

## Data-driven tuning for the optional Follow Cursor Mode. When unset,
## FollowCursorComponent falls back to the bundled default settings.
@export var follow_cursor_settings: FollowCursorSettings

## Data-driven tuning for the pet's environmental awareness (edges, cursor
## radius, refresh cadence, floor offset). When unset,
## DesktopAwarenessComponent falls back to the bundled default settings.
@export var desktop_awareness_settings: DesktopAwarenessSettings

## Personality this pet defaults to (a PersonalityCatalog id). When empty the
## catalog's first personality is used; a personality selected at runtime
## (and saved) always wins over this default.
@export var default_personality_id: String = ""

## Data-driven tuning for the Behavior Polish System (fatigue, timing
## variation, transition delays). When unset, BehaviorPolishComponent falls
## back to the bundled default settings.
@export var polish_settings: BehaviorPolishSettings

## This pet's sound pack (a bundle of AudioSound event definitions). When
## unset, the pet uses the AudioManager's active default pack. Swapping this
## resource changes every sound this pet makes with zero script changes.
@export var audio_pack: AudioPack

## This pet's visual identity — a SpriteFrames containing all animation
## sprite sheets. When unset, the pet uses the sprites baked into pet.tscn.
## Swapping this resource completely changes the pet's appearance with zero
## script changes. Set by ThemeManager when a theme is loaded.
@export var sprite_pack: SpriteFrames
