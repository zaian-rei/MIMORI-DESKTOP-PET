extends Resource
class_name MovementPolishSettings

## Data-driven tuning for the Movement Polish System - everything that makes
## the pet move with weight and intention. Swapping this resource retunes the
## feel with zero script changes (same pattern as MovementSettings).
## MovementPolishComponent resolves these values; NaturalGait executes them;
## MovementComponent remains the sole executor of pet.velocity.x.

## --- Acceleration / deceleration profiles -----------------------------------
## Walk vs run use separate rates so a sprint feels heavier than a stroll.
## Applied to gait.direct() (manual, jump, cursor-follow) and the gait planner.

@export var walk_acceleration: float = 400.0
@export var run_acceleration: float = 520.0
@export var walk_deceleration: float = 420.0
@export var run_deceleration: float = 620.0

## --- Turning -----------------------------------------------------------------
## Gentler rate for slowing into a direction change, so the pet eases down
## instead of braking hard before a turn.

@export var turn_deceleration: float = 260.0

## Speed the pet carries through an edge-triggered turn (px/s). Non-zero makes
## it a flowing "shuffle-turn" (slow, sweep around, resume) instead of a full
## stop; 0 = turn fully stopped. Turns after a natural arrival still happen
## from a standstill.
@export var max_turn_speed: float = 24.0

## --- Arrival ----------------------------------------------------------------
## While walking toward a leg destination the pet's target speed ramps down
## in proportion to the remaining distance, so it glides in and settles
## instead of hitting a braking wall. `arrival_slowdown_distance` is where
## the ramp starts; `arrival_radius` is the point where it counts as arrived;
## `arrival_settle_delay` is a tiny catch-a-breath beat before the next action.

@export var arrival_slowdown_distance: float = 90.0
@export var arrival_deceleration: float = 220.0
@export var arrival_radius: float = 14.0
@export var arrival_settle_delay: float = 0.12

## --- Edge behavior ----------------------------------------------------------
## As the pet approaches the screen edge it heads toward, its cruise speed is
## scaled down progressively (never below edge_slowdown_min_speed) so it slows
## naturally instead of stopping suddenly, then turns at max_turn_speed.

@export var edge_slowdown_distance: float = 180.0
@export var edge_slowdown_min_speed: float = 0.45

## --- Jump / landing ---------------------------------------------------------
## Brief pause between stopping and leaving the ground, so a jump has intent.
## After a landing the pet collects itself before resuming full speed.

@export var jump_anticipation_time: float = 0.22
@export var landing_recovery_time: float = 0.28
@export var landing_recovery_acceleration: float = 220.0

## --- Follow cursor ----------------------------------------------------------
## Facing deadband (px): the larger of this and FollowCursorSettings'
## heading_deadband is used, so micro cursor jitter never flips the pet.
## Hysteresis (px): stop/start band around FollowCursorSettings' stop_distance
## - once stopped the pet stays stopped until the cursor moves this much
## further away, preventing stop/run oscillation at the boundary.

@export var follow_cursor_deadzone: float = 18.0
@export var follow_cursor_hysteresis: float = 60.0
