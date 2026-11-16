extends Resource
class_name MovementSettings

## Data-driven tuning for the pet's natural gait. Swapping this resource
## retunes movement feel with zero script changes - the same pattern as
## PetDefinition and BehaviorDefinition. Future settings screens can
## replace/adjust these values without touching code.

## How fast the pet ramps up toward its cruise speed (px/s^2).
@export var acceleration: float = 400.0

## How fast the pet eases down to a stop or a lower speed (px/s^2).
@export var deceleration: float = 500.0

## +/- fraction of the base speed each leg cruises at (0.15 = +/-15%).
## "Variable movement speed within safe limits" - the speed always stays
## near the base speed, never off into run territory.
@export var speed_variation: float = 0.15

## Random travel distance per leg (px) - the "destination" the pet walks
## toward before easing to a stop. Short/medium/long legs come from these
## bounds, so the pet never trudges the same distance every time.
@export var min_travel_distance: float = 300.0
@export var max_travel_distance: float = 900.0

## Stand-still before starting to walk (and before resuming after a turn).
@export var hesitation_duration_min: float = 0.2
@export var hesitation_duration_max: float = 0.5

## Brief pause at the moment of a direction change, so the pet doesn't
## snap around instantly.
@export var turn_delay_min: float = 0.15
@export var turn_delay_max: float = 0.4

## Chance a leg ends with a pause instead of rolling straight into the next.
@export var pause_chance: float = 0.2

## Length of an occasional mid-walk pause.
@export var pause_duration_min: float = 0.4
@export var pause_duration_max: float = 0.9

## Chance to spontaneously change direction at a leg boundary.
@export var direction_change_chance: float = 0.18

## Horizontal speed (px/s) the walk animation was authored for. Playback
## scales with the pet's actual speed relative to this, so the feet always
## match the ground (no moonwalking) and future speed changes auto-sync.
@export var walk_animation_design_speed: float = 150.0

## Horizontal speed (px/s) the run animation was authored for. Same
## auto-sync as walk_animation_design_speed, for the run cycle.
@export var run_animation_design_speed: float = 240.0
