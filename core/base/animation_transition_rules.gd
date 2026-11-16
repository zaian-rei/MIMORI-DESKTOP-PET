extends RefCounted
class_name AnimationTransitionRules

## Central, pet-agnostic transition graph for the whole desktop-pet engine.
##
## Every state request funnels through StateMachineComponent, which asks these
## rules before applying a transition. AnimationTransitionManager and the
## behaviour managers use the same table, so there is exactly one definition
## of what may follow what.
##
## The graph is deliberately allow-list based: anything not listed is denied.
## Physics (FALL/LAND), drag (DRAG) and explicit user/manual actions are the
## documented exceptions and pass `bypass = true` / use a HIGH request
## priority at the call site.

## Animation priority order from the universal design:
##   Grab/Drag > Physics Fall/Land > Special Moves > Jump > Sleep >
##   Movement Walk/Run > Emotions > Moments > Idle.
## Special moves are not a PetState (they play a clip directly), so their
## priority is consumed by AnimationTransitionManager.play_external().
const PRIORITIES := {
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

## Priority used for pet-specific special-move clips played outside the state
## machine. Kept below physics/drag and above jump so a special can't be
## stepped on by ordinary life, but a drag always wins.
const SPECIAL_PRIORITY := 80

## States that represent an expression/reaction and therefore may only be
## entered from IDLE. This is the emotion + moment rule from the design.
const EXPRESSION_STATES := [
	PetState.State.THINK,
	PetState.State.HAPPY,
	PetState.State.SAD,
	PetState.State.DANCE,
]

## States that are physically owned by the engine. Lower-level systems may
## request them from any state. Auto-chaining out of an arc is forbidden so a
## queued idle can never cut a jump/fall/land short.
const PHYSICS_STATES := [
	PetState.State.FALL,
	PetState.State.LAND,
	PetState.State.DRAG,
	PetState.State.FLOAT,
]

## Arc states the pet must leave on its own (physics or drag owns them).
const ARC_STATES := [
	PetState.State.JUMP,
	PetState.State.FALL,
	PetState.State.LAND,
	PetState.State.DRAG,
	PetState.State.FLOAT,
]

## Maximum number of intermediate states the planner may insert. Three is
## enough for Run -> Walk -> Idle -> Expression.
const MAX_PATH_DEPTH := 4


static func get_priority(state: PetState.State) -> int:
	return int(PRIORITIES.get(state, 10))


static func is_expression(state: PetState.State) -> bool:
	return state in EXPRESSION_STATES


static func is_physics_owned(state: PetState.State) -> bool:
	return state in PHYSICS_STATES


static func is_arc_locked(state: PetState.State) -> bool:
	return state in ARC_STATES


## True when `to` may follow `from`. `bypass` is reserved for explicit
## user/manual actions and engine recovery (profile swap, scene reset).
static func can_transition(from: PetState.State, to: PetState.State, bypass: bool = false) -> bool:
	if bypass:
		return true
	if from == to:
		return true

	## Drag owns the pet whenever it is active, and physics ground truth can
	## always interrupt animation-only states (fall/land are not negotiable).
	if to == PetState.State.DRAG:
		return true
	if to in PHYSICS_STATES:
		return true

	match from:
		PetState.State.IDLE:
			## Ground movement always begins with Walk; Run from Idle is
			## explicitly forbidden. Emotions/moments/sleep only from Idle.
			## A jump also begins from Walk, so the animation sequence is
			## always Walk -> Jump -> Idle.
			return to in [
				PetState.State.WALK,
				PetState.State.THINK,
				PetState.State.HAPPY,
				PetState.State.SAD,
				PetState.State.SLEEP,
				PetState.State.DEEP_SLEEP,
				PetState.State.DANCE,
			]
		PetState.State.WALK:
			return to in [
				PetState.State.IDLE,
				PetState.State.RUN,
				PetState.State.JUMP,
			]
		PetState.State.RUN:
			## Slowing down must pass through Walk; no direct Run -> Idle.
			return to in [
				PetState.State.WALK,
				PetState.State.JUMP,
			]
		PetState.State.JUMP:
			## Ordinary jumps end in Idle (no Fall/Land clips).
			return to == PetState.State.IDLE
		PetState.State.FALL:
			return to in [PetState.State.LAND, PetState.State.IDLE]
		PetState.State.LAND:
			return to == PetState.State.IDLE
		PetState.State.DRAG:
			## Release hands back to Idle; physics may then continue into Fall.
			return to in [PetState.State.IDLE, PetState.State.WALK, PetState.State.FALL]
		PetState.State.THINK, PetState.State.HAPPY, PetState.State.SAD, PetState.State.DANCE:
			## Expressions settle back to Idle. They never chain into another
			## expression or directly into movement.
			return to == PetState.State.IDLE
		PetState.State.SLEEP:
			return to in [PetState.State.DEEP_SLEEP, PetState.State.IDLE]
		PetState.State.DEEP_SLEEP:
			return to == PetState.State.IDLE
		PetState.State.FLOAT:
			return to in [PetState.State.IDLE, PetState.State.LAND]
		_:
			return true


## Returns the states to enter (in order, excluding `from`) to legally reach
## `to`. A direct transition yields a one-element array. Returns an empty array
## when no legal path exists. Arc states never auto-chain: physics/drag must
## leave them on their own.
static func plan_path(from: PetState.State, to: PetState.State, bypass: bool = false) -> Array:
	if bypass or from == to:
		return [to] if from != to else []
	if can_transition(from, to):
		return [to]
	if from in ARC_STATES:
		return []

	var queue: Array = [[from]]
	var visited := {from: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var last: int = path[path.size() - 1]
		if path.size() > MAX_PATH_DEPTH:
			continue
		for candidate in PetState.State.values():
			if visited.has(candidate):
				continue
			if not can_transition(last, candidate):
				continue
			if candidate in ARC_STATES and candidate != to:
				continue
			var next := path.duplicate()
			next.append(candidate)
			if candidate == to:
				next.remove_at(0)
				return next
			visited[candidate] = true
			queue.append(next)
	return []
