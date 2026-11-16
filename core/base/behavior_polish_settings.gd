extends Resource
class_name BehaviorPolishSettings

## Data-driven tuning for the Behavior Polish System. Swapping this resource
## retunes how naturally the pet's behaviors flow with zero script changes -
## the same pattern as MovementSettings, FollowCursorSettings, etc.

## --- Behavior fatigue -------------------------------------------------------
## A behavior's utility is multiplied by (1 - strength * clamp(fatigue, 0, 1))
## while it has accumulated fatigue, so recently repeated behaviors cool down
## before being picked again. Fatigue recovers over time; nothing is ever
## permanently disabled.

## Max utility penalty fraction (0..1). 0.4 = a fully fatigued behavior loses
## up to 40% of its score.
@export var fatigue_strength: float = 0.4

## Fatigue added to a behavior each time it is performed.
@export var fatigue_per_action: float = 0.5

## Fatigue recovered per second (0..1). Higher = behaviors become available
## again sooner.
@export var fatigue_recovery_per_second: float = 0.05

## --- Decision interval ------------------------------------------------------
## The decision loop picks a fresh random interval inside these bounds every
## decision, so the pet's rhythm is never a fixed timer.

@export var decision_min_seconds: float = 3.0
@export var decision_max_seconds: float = 6.0

## --- Duration variation -----------------------------------------------------
## Behavior durations are multiplied by a random factor in
## [1 - variation, 1 + variation], so idle/walk/think never last exactly the
## same length.

@export var duration_variation: float = 0.15

## --- Natural pacing ---------------------------------------------------------
## Occasionally the pet stays idle noticeably longer than its duration would
## suggest, breaking up perfectly predictable idle/walk/idle rhythm.

@export var idle_extension_chance: float = 0.25
@export var idle_extension_factor: float = 1.8

## --- Transition delays ------------------------------------------------------
## Before these states start, the pet briefly settles into idle first (a short
## pause before sleeping/thinking). Direction changes already carry their own
## delay in MovementSettings and are not touched here.

@export var transition_delay_min: float = 0.2
@export var transition_delay_max: float = 0.6
@export var delayed_states: Array = [
	PetState.State.SLEEP,
	PetState.State.DEEP_SLEEP,
	PetState.State.THINK,
]

## --- Moments ---------------------------------------------------------------
## Moments are the short idle-only expressions (think/happy/sad quirks). Their
## cadence range and probability are per-profile in PetRoster; these scale the
## shared timing without touching the profile data. Moments never start from
## Walk/Run and never repeat the same expression back to back.

@export var moment_duration_seconds: float = 2.5
@export_range(0.0, 4.0, 0.05) var moment_probability_scale: float = 1.0
@export_range(0.1, 4.0, 0.05) var moment_gap_scale: float = 1.0
