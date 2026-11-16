extends Resource
class_name AnimationPolishSettings

## Data-driven tuning for the Animation Polish System - the transition
## mechanics that make animation changes feel deliberate instead of abrupt:
## per-state priorities (what may interrupt what), safe interruption
## (protection windows), a bounded transition queue, duplicate protection and
## anti-thrash. Swapping this resource retunes the feel with zero script
## changes (same pattern as MovementPolishSettings).
## AnimationTransitionManager resolves these values; AnimationComponent stays
## responsible for mapping states to animations; AnimationController stays the
## sole low-level executor that flips the sprite.

## Per-state priority. Higher = more important: a request at a higher priority
## always interrupts the current animation (DRAG must always win), while equal
## or lower requests wait behind the current animation's protection window.
## Reference order: DRAG > FLOAT > FALL > LAND > JUMP > RUN > WALK > THINK >
## HAPPY > DANCE > SLEEP > IDLE.
@export var priorities: Dictionary = {
	PetState.State.DRAG: 100,
	PetState.State.FLOAT: 95,
	PetState.State.FALL: 90,
	PetState.State.LAND: 90,
	PetState.State.JUMP: 80,
	PetState.State.SLEEP: 70,
	PetState.State.DEEP_SLEEP: 70,
	PetState.State.WALK: 60,
	PetState.State.RUN: 60,
	PetState.State.THINK: 40,
	PetState.State.HAPPY: 40,
	PetState.State.SAD: 40,
	PetState.State.DANCE: 40,
	PetState.State.IDLE: 10,
}

## Short physical animations that belong to a state arc (jump owns its whole
## arc; a real drop is fall -> land). Played through unless a higher priority
## (DRAG) interrupts. BehaviorDefinition.Category wins first when a behavior
## explicitly marks itself TRANSITION.
@export var transition_states: Array = [
	PetState.State.JUMP,
	PetState.State.FALL,
	PetState.State.FLOAT,
]

## One-shot reactions (happy/sad/think/dance/land). Protected for
## one_shot_protection_seconds so they complete before equal/lower requests,
## then the pet settles back to its loop animation.
@export var one_shot_states: Array = [
	PetState.State.HAPPY,
	PetState.State.SAD,
	PetState.State.THINK,
	PetState.State.DANCE,
	PetState.State.LAND,
]

## How long a transition animation resists equal/lower-priority interruption.
@export var transition_protection_seconds: float = 0.08

## How long a one-shot animation resists equal/lower-priority interruption
## (keeps the previous hardcoded LAND settle at ~0.4s).
@export var one_shot_protection_seconds: float = 0.4

## Minimum time an animation must have been playing before an equal/lower
## priority request may switch to a different animation (anti-thrash: swallows
## gait/brain flapping right after a switch so the sprite never flickers).
@export var minimum_dwell_time: float = 0.08

## Maximum number of deferred animation requests held while the current one is
## protected. When full, the lowest-priority queued request is dropped.
@export var max_queue_length: int = 4

## States whose animation is allowed to restart from frame 0 on re-request.
## Empty = duplicate requests never restart (default duplicate protection).
@export var restart_allowed_states: Array = []

## --- Movement transition timing ---------------------------------------------
## Minimum time a ground movement must spend in Walk before it may promote to
## Run. This is the "never Idle -> Run" rule made physical: even when a
## decision asks for Run, the pet first walks for this long.
@export var walk_min_duration: float = 0.32

## Time a planner-inserted intermediate state is held before the next step.
## Only intermediate states are held (e.g. Run -> Walk -> Idle, or
## Walk -> Idle -> Happy), so the pet visibly settles instead of snapping.
@export var chain_settle_seconds: float = 0.06

## Maximum steps StateMachineComponent may insert to reach a legal target.
## Kept small so a request can never wander through unrelated states.
@export var max_transition_steps: int = 3


func get_priority(state: PetState.State) -> int:
	return int(priorities.get(state, 0))


func is_restart_allowed(state: PetState.State) -> bool:
	return state in restart_allowed_states
