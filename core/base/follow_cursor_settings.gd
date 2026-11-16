extends Resource
class_name FollowCursorSettings

## Data-driven tuning for the optional Follow Cursor Mode. Swapping this
## resource retunes how the pet chases the cursor with zero script changes -
## the same pattern as MovementSettings and PetDefinition.
##
## FollowCursorComponent reads these values once per episode. Every field is
## safe to change at runtime through set_settings() or the Settings window.

## Farthest distance (px) at which the pet notices and follows the cursor.
@export var detection_radius: float = 2400.0

## Distance (px) at which the pet considers the cursor reached and stops.
@export var stop_distance: float = 90.0

## Distance (px) beyond which the pet runs instead of walks.
@export var sprint_distance: float = 480.0

## Smoothly approached horizontal speed targets while cursor following.
@export var walk_speed: float = 160.0
@export var run_speed: float = 320.0

## Peak height (px) of a cursor-follow jump. The launch velocity is derived
## from the pet's gravity so the same height works for every pet definition.
@export var jump_height: float = 130.0

## Horizontal reach (px) of an overhead-cursor jump: the cursor must be
## within this horizontal distance for the pet to hop up to it.
@export var jump_distance: float = 160.0

## A hop is a close interaction only; the pet walks/runs while the pointer is
## farther away, even if it is vertically above the pet.
@export var jump_trigger_radius: float = 240.0

## Require the pointer to be meaningfully above the pet before hopping.
@export var jump_height_above: float = 80.0

## Number of hops allowed during one overhead-cursor attempt (0 or 1). The
## contract is deliberately capped at one so an overhead cursor cannot make
## the pet retry forever while it stays inside the detection radius.
@export_range(0, 1, 1) var max_jumps_per_attempt: int = 1

## Seconds the NOTICE phase holds before the chase begins.
@export var notice_duration: float = 0.22

## Chance of a brief happy/thinking/pet-specific reaction on reaching the cursor.
@export_range(0.0, 1.0, 0.01) var reaction_probability: float = 0.25

## Cursor movement smaller than this won't flip the pet's facing direction.
@export var stopping_hysteresis: float = 30.0

## Horizontal deadband (px): cursor jitter inside this distance is ignored
## when deciding which way to face.
@export var heading_deadband: float = 8.0
