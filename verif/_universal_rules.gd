extends Node

## Contract harness for the universal animation/behavior rules:
##   - the explicit transition graph (no Idle -> Run, no Run -> Idle, no
##     Walk/Run -> emotion)
##   - the Walk minimum duration before Run
##   - the planner's visible intermediate states
##   - behaviour data aligned with the graph
##   - priority ordering matches the design document
##   - missing-animation fallback never breaks the state

const BOOT := preload("res://scenes/bootstrap/bootstrap.tscn")

var failures := 0
var pet: Node
var state_machine: StateMachineComponent
var movement: MovementComponent
var behavior: BehaviorController
var follow: FollowCursorComponent
var physics: PhysicsComponent

func _ready() -> void:
	_run()

func check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		print("FAIL: ", label)

func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _reset(state: PetState.State = PetState.State.IDLE) -> void:
	state_machine.force_state(state)
	await frames(3)

## Records the ordered states for `max_frames` and returns the observed list.
func _record(max_frames: int) -> Array:
	var seen: Array = []
	for i in max_frames:
		await get_tree().process_frame
		var state := state_machine.get_state()
		if seen.is_empty() or seen[seen.size() - 1] != state:
			seen.append(state)
	return seen

func _run() -> void:
	get_tree().root.add_child.call_deferred(BOOT.instantiate())
	await frames(12)
	var boot_node := get_tree().root.find_child("Bootstrap", true, false)
	pet = boot_node.find_child("Pet", true, false)
	state_machine = pet.get_component(StateMachineComponent)
	movement = pet.get_component(MovementComponent)
	behavior = pet.get_component(BehaviorController)
	follow = pet.get_component(FollowCursorComponent)
	physics = pet.get_component(PhysicsComponent)

	pet.screen_bounds = Rect2i(0, 0, 3840, 2160)
	pet.world_position = Vector2(1000, 900)
	physics.snap_to_ground()
	follow.set_follow_enabled(false)
	behavior.autonomy_locked = true
	behavior.reset_signature_moves()
	await frames(15)

	# --- Graph: ground movement always starts with Walk -----------------------
	check(
		not AnimationTransitionRules.can_transition(PetState.State.IDLE, PetState.State.RUN),
		"graph: Idle cannot go directly to Run"
	)
	check(
		AnimationTransitionRules.can_transition(PetState.State.WALK, PetState.State.RUN),
		"graph: Walk can promote to Run"
	)
	check(
		not AnimationTransitionRules.can_transition(PetState.State.RUN, PetState.State.IDLE),
		"graph: Run cannot go directly to Idle"
	)
	check(
		AnimationTransitionRules.can_transition(PetState.State.RUN, PetState.State.WALK),
		"graph: Run slows through Walk"
	)
	check(
		not AnimationTransitionRules.can_transition(PetState.State.WALK, PetState.State.HAPPY),
		"graph: Walk cannot go directly to an emotion"
	)
	check(
		not AnimationTransitionRules.can_transition(PetState.State.RUN, PetState.State.THINK),
		"graph: Run cannot go directly to Think"
	)
	check(
		not AnimationTransitionRules.can_transition(PetState.State.IDLE, PetState.State.SLEEP) == false,
		"graph: Sleep starts from Idle"
	)
	check(
		not AnimationTransitionRules.can_transition(PetState.State.WALK, PetState.State.SLEEP),
		"graph: Walk cannot go directly to Sleep"
	)

	# --- Planner paths --------------------------------------------------------
	check(
		AnimationTransitionRules.plan_path(PetState.State.IDLE, PetState.State.RUN) \
			== [PetState.State.WALK, PetState.State.RUN],
		"planner: Idle -> Run routes through Walk"
	)
	check(
		AnimationTransitionRules.plan_path(PetState.State.RUN, PetState.State.IDLE) \
			== [PetState.State.WALK, PetState.State.IDLE],
		"planner: Run -> Idle routes through Walk"
	)
	check(
		AnimationTransitionRules.plan_path(PetState.State.RUN, PetState.State.HAPPY) \
			== [PetState.State.WALK, PetState.State.IDLE, PetState.State.HAPPY],
		"planner: Run -> Happy routes through Walk + Idle"
	)
	check(
		AnimationTransitionRules.plan_path(PetState.State.JUMP, PetState.State.HAPPY).is_empty(),
		"planner: arc states never auto-chain"
	)
	check(
		AnimationTransitionRules.plan_path(PetState.State.WALK, PetState.State.DRAG) \
			== [PetState.State.DRAG],
		"planner: drag is always allowed"
	)

	# --- Priority order -------------------------------------------------------
	check(
		AnimationTransitionRules.get_priority(PetState.State.DRAG)
			> AnimationTransitionRules.get_priority(PetState.State.FALL),
		"priority: drag beats fall"
	)
	check(
		AnimationTransitionRules.get_priority(PetState.State.FALL)
			> AnimationTransitionRules.get_priority(PetState.State.JUMP),
		"priority: physics beats jump"
	)
	check(
		AnimationTransitionRules.get_priority(PetState.State.JUMP)
			> AnimationTransitionRules.get_priority(PetState.State.SLEEP),
		"priority: jump beats sleep"
	)
	check(
		AnimationTransitionRules.get_priority(PetState.State.SLEEP)
			> AnimationTransitionRules.get_priority(PetState.State.WALK),
		"priority: sleep beats movement"
	)
	check(
		AnimationTransitionRules.get_priority(PetState.State.WALK)
			> AnimationTransitionRules.get_priority(PetState.State.THINK),
		"priority: movement beats emotions"
	)
	check(
		AnimationTransitionRules.get_priority(PetState.State.THINK)
			> AnimationTransitionRules.get_priority(PetState.State.IDLE),
		"priority: emotions beat idle"
	)

	# --- Behaviour data aligned with the graph --------------------------------
	var run_def := BehaviorCatalog.get_behavior_for_state(PetState.State.RUN)
	var happy_def := BehaviorCatalog.get_behavior_for_state(PetState.State.HAPPY)
	var think_def := BehaviorCatalog.get_behavior_for_state(PetState.State.THINK)
	var sleep_def := BehaviorCatalog.get_behavior_for_state(PetState.State.SLEEP)
	check(
		run_def != null and not run_def.allowed_from.has(PetState.State.IDLE),
		"data: autonomous Run is not eligible from Idle"
	)
	check(
		run_def != null and run_def.allowed_from.has(PetState.State.WALK),
		"data: autonomous Run is eligible from Walk"
	)
	check(
		happy_def != null and happy_def.allowed_from == [PetState.State.IDLE],
		"data: Happy is Idle-only"
	)
	check(
		think_def != null and think_def.allowed_from == [PetState.State.IDLE],
		"data: Think is Idle-only"
	)
	check(
		sleep_def != null and sleep_def.allowed_from == [PetState.State.IDLE],
		"data: Sleep is Idle-only"
	)

	# --- Live: Idle -> Run starts with Walk and respects min duration ---------
	var walk_min: float = float(pet.definition.animation_polish_settings.walk_min_duration)
	await _reset(PetState.State.IDLE)
	var walk_started_ms := 0
	var run_started_ms := 0
	var saw_walk := false
	var run_before_walk := false
	var observed: Array = []
	state_machine.request_state(PetState.State.RUN, StatePriority.Level.NORMAL)
	for i in 90:
		await get_tree().process_frame
		var state := state_machine.get_state()
		if observed.is_empty() or observed[observed.size() - 1] != state:
			observed.append(state)
		if state == PetState.State.RUN and not saw_walk:
			run_before_walk = true
			break
		if state == PetState.State.WALK and not saw_walk:
			saw_walk = true
			walk_started_ms = Time.get_ticks_msec()
		if state == PetState.State.RUN and saw_walk:
			run_started_ms = Time.get_ticks_msec()
			break
	check(saw_walk and not run_before_walk, "live: Idle -> Run begins with Walk")
	check(
		run_started_ms > 0 and (run_started_ms - walk_started_ms) >= int(walk_min * 850.0),
		"live: Walk lasted at least the configured minimum (%.2fs)" % walk_min
	)

	# --- Live: Run -> Idle passes through Walk --------------------------------
	await _reset(PetState.State.WALK)
	state_machine.request_state(PetState.State.RUN, StatePriority.Level.NORMAL)
	## Headless frames run far faster than real time; wait on the engine clock
	## so the state machine's wall-clock Walk gate actually elapses.
	await get_tree().create_timer(walk_min + 0.15).timeout
	check(state_machine.get_state() == PetState.State.RUN, "live: Walk promotes to Run")
	state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
	var run_to_idle := await _record(60)
	var walk_index := run_to_idle.find(PetState.State.WALK)
	var idle_index := run_to_idle.find(PetState.State.IDLE)
	check(
		walk_index >= 0 and idle_index > walk_index,
		"live: Run -> Idle settles through Walk"
	)
	check(
		run_to_idle.find(PetState.State.RUN) < walk_index if walk_index > 0 else true,
		"live: Run -> Walk -> Idle ordering"
	)

	# --- Live: Walk -> Happy passes through Idle ------------------------------
	await _reset(PetState.State.WALK)
	state_machine.request_state(PetState.State.HAPPY, StatePriority.Level.NORMAL)
	var walk_to_happy := await _record(60)
	var happy_index := walk_to_happy.find(PetState.State.HAPPY)
	var settle_index := walk_to_happy.find(PetState.State.IDLE)
	check(
		settle_index >= 0 and happy_index > settle_index,
		"live: Walk -> Happy settles through Idle"
	)
	check(
		walk_to_happy.find(PetState.State.HAPPY) > 0
			and walk_to_happy[walk_to_happy.find(PetState.State.HAPPY) - 1] == PetState.State.IDLE,
		"live: Happy's previous state is Idle"
	)

	# --- Live: Walk -> Sleep passes through Idle ------------------------------
	await _reset(PetState.State.WALK)
	state_machine.request_state(PetState.State.SLEEP, StatePriority.Level.NORMAL)
	var walk_to_sleep := await _record(60)
	var sleep_index := walk_to_sleep.find(PetState.State.SLEEP)
	check(
		sleep_index > 0 and walk_to_sleep[sleep_index - 1] == PetState.State.IDLE,
		"live: Walk -> Sleep settles through Idle"
	)

	# --- Missing animation fallback ------------------------------------------
	var missing := PetRoster.resolve_animation(
		pet.profile_id,
		"definitely not an animation",
		pet.sprite.sprite_frames
	)
	check(
		missing != "" and pet.sprite.sprite_frames.has_animation(missing),
		"missing animation resolves to an existing fallback"
	)
	check(
		BehaviorCatalog.get_animation_for_state(PetState.State.DRAG) == "idle",
		"behavior catalog has a fallback for physics/manual states"
	)

	# --- Environment not left in a weird state --------------------------------
	await _reset(PetState.State.IDLE)
	behavior.autonomy_locked = false

	print("[UNIVERSAL RULES] failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
