extends Node

const BOOT := preload("res://scenes/bootstrap/bootstrap.tscn")

var failures := 0
var pet: Node
var follow: FollowCursorComponent
var awareness: DesktopAwarenessComponent
var movement: MovementComponent
var state_machine: StateMachineComponent
var physics: PhysicsComponent
var drag: DragComponent
var behavior: BehaviorController
var jump_launches := 0

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
		await get_tree().physics_frame

func wait_for(condition: Callable, max_frames: int, label: String) -> bool:
	for i in max_frames:
		await get_tree().physics_frame
		if condition.call():
			return true
	print("TIMEOUT: ", label, " phase=", follow.get_phase_name(), " debug=", follow.get_debug_info(), " state=", PetState.State.keys()[state_machine.get_state()], " pos=", pet.world_position, " cursor=", awareness.cursor_position())
	return false

func _run() -> void:
	get_tree().root.add_child.call_deferred(BOOT.instantiate())
	await frames(12)
	var boot_node := get_tree().root.find_child("Bootstrap", true, false)
	pet = boot_node.find_child("Pet", true, false)
	follow = pet.get_component(FollowCursorComponent)
	awareness = pet.get_component(DesktopAwarenessComponent)
	movement = pet.get_component(MovementComponent)
	state_machine = pet.get_component(StateMachineComponent)
	physics = pet.get_component(PhysicsComponent)
	drag = pet.get_component(DragComponent)
	behavior = pet.get_component(BehaviorController)

	pet.screen_bounds = Rect2i(0, 0, 3840, 2160)
	pet.world_position = Vector2(1000, awareness.floor_position())
	physics.snap_to_ground()
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	behavior.reset_signature_moves()
	follow.settings.detection_radius = 600.0
	follow.settings.stop_distance = 60.0
	follow.settings.sprint_distance = 300.0
	follow.settings.walk_speed = 120.0
	follow.settings.run_speed = 240.0
	follow.settings.jump_height = 120.0
	follow.settings.jump_trigger_radius = 240.0
	follow.settings.jump_distance = 160.0
	follow.settings.jump_height_above = 40.0
	follow.settings.notice_duration = 0.05
	follow.settings.max_jumps_per_attempt = 1
	follow.set_follow_enabled(true)
	physics.jump_launched.connect(func(): jump_launches += 1)

	await frames(20)
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, "reset: phase IDLE")
	check(state_machine.get_state() == PetState.State.IDLE, "reset: pet IDLE")

	# --- Detect + RUN when far ------------------------------------------------
	var start_x: float = pet.world_position.x
	awareness.cursor_override = pet.world_position + Vector2(520, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.RUN, 30, "notice->run")
	check(follow.get_phase_name() == "RUN", "far cursor enters RUN")
	check(movement.following_cursor, "movement follows cursor")
	await frames(40)
	check(pet.world_position.x > start_x + 10.0, "pet moved toward cursor")
	check(movement.direction == 1, "facing direction follows cursor to the right")

	# --- RUN -> WALK hysteresis ----------------------------------------------
	awareness.cursor_override = pet.world_position + Vector2(200, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.WALK, 30, "run->walk")
	check(follow.get_phase_name() == "WALK", "near cursor transitions to WALK")
	check(state_machine.get_state() == PetState.State.WALK, "WALK state requested")

	# --- Exit radius re-arms --------------------------------------------------
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, 10, "leave radius")
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, "leaving radius resets to IDLE")
	check(not movement.following_cursor, "leaving radius releases movement")

	# --- Never jumps mid-stride ----------------------------------------------
	# An overhead cursor far away must be walked to first; the pet may only hop
	# after it has settled at the cursor.
	await frames(20)
	var before_probe := jump_launches
	awareness.cursor_override = Vector2(pet.world_position.x + 520.0, awareness.floor_position() - 150.0)
	await wait_for(
		func():
			return follow.get_phase() == FollowCursorComponent.FollowPhase.RUN \
				or follow.get_phase() == FollowCursorComponent.FollowPhase.WALK,
		30,
		"walk toward overhead"
	)
	var jumped_mid_stride := false
	for i in 115:
		await get_tree().physics_frame
		if jump_launches > before_probe:
			jumped_mid_stride = true
			break
	check(not jumped_mid_stride, "no jump while walking toward an overhead cursor")
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, 10, "reset after mid-walk probe")

	# --- Single overhead jump -> RESTING -------------------------------------
	await frames(20)
	var floor_y: float = awareness.floor_position()
	var start_jumps := jump_launches
	var jump_anim := PetRoster.resolve_animation(pet.profile_id, "jump", pet.sprite.sprite_frames)
	var used_fall_or_land := false
	var lost_jump_animation := false
	awareness.cursor_override = Vector2(pet.world_position.x, floor_y - 200.0)
	var saw_jump := await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.JUMP, 30, "jump")
	check(saw_jump, "overhead cursor triggers JUMP")
	var min_y: float = pet.world_position.y
	var saw_walk_before_jump := false
	var saw_jump_state := false
	for i in 120:
		await get_tree().physics_frame
		min_y = minf(min_y, pet.world_position.y)
		var observed_state := state_machine.get_state()
		if observed_state == PetState.State.WALK:
			saw_walk_before_jump = true
		elif observed_state == PetState.State.JUMP:
			saw_jump_state = true
		if physics.is_jumping:
			if state_machine.get_state() in [PetState.State.FALL, PetState.State.LAND]:
				used_fall_or_land = true
			if pet.sprite.animation != jump_anim:
				lost_jump_animation = true
		if follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING and state_machine.get_state() == PetState.State.IDLE:
			break
	var peak: float = floor_y - min_y
	check(jump_launches - start_jumps == 1, "exactly one jump launch")
	check(peak > 70.0 and peak < 180.0, "configured jump height is used (%.1f px)" % peak)
	check(not used_fall_or_land, "jump arc uses no FALL/LAND states")
	check(not lost_jump_animation, "jump animation holds for the whole arc")
	check(saw_walk_before_jump and saw_jump_state, "ordinary jump enters through Walk")
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING, "landing enters RESTING")
	check(not movement.following_cursor, "following stops immediately after jump")
	check(state_machine.get_state() == PetState.State.IDLE, "jump ends in IDLE")

	# --- No retry while cursor stays inside ----------------------------------
	awareness.cursor_override = Vector2(pet.world_position.x, floor_y - 50.0)
	await frames(120)
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING, "RESTING holds while cursor remains inside")
	check(jump_launches - start_jumps == 1, "no second jump while cursor remains inside")
	check(not movement.following_cursor, "no resumed chase while resting")

	# --- Exit + re-enter re-arms ---------------------------------------------
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, 10, "reset after jump")
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, "exit after jump clears RESTING")
	awareness.cursor_override = pet.world_position + Vector2(420, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.NOTICE or follow.get_phase() == FollowCursorComponent.FollowPhase.RUN or follow.get_phase() == FollowCursorComponent.FollowPhase.WALK, 30, "re-enter")
	check(follow.get_phase() != FollowCursorComponent.FollowPhase.RESTING, "re-entry re-arms following")
	check(movement.following_cursor, "re-entry re-engages movement")

	# --- Arrival also completes the attempt ----------------------------------
	awareness.cursor_override = pet.world_position + Vector2(40, 0)
	var arrived := await wait_for(
		func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING,
		120,
		"arrival latch"
	)
	check(arrived, "reaching the cursor enters RESTING")
	check(not movement.following_cursor, "arrival stops follow steering")
	## Moving the pointer within the radius must not restart the chase.
	awareness.cursor_override = pet.world_position + Vector2(240, 0)
	await frames(60)
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING, "arrival RESTING holds inside radius")
	check(not movement.following_cursor, "no resumed chase after arrival")
	## Only a real exit re-arms the system.
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	await wait_for(func(): return follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, 10, "exit after arrival")
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.IDLE, "exit after arrival clears RESTING")
	awareness.cursor_override = pet.world_position + Vector2(420, 0)
	await wait_for(func(): return follow.get_phase() != FollowCursorComponent.FollowPhase.IDLE, 30, "re-enter after arrival")
	check(follow.get_phase() != FollowCursorComponent.FollowPhase.RESTING, "re-entry after arrival re-arms following")

	# --- Drag wins ------------------------------------------------------------
	drag.dragging = true
	await frames(5)
	check(follow.get_phase() == FollowCursorComponent.FollowPhase.RESTING, "drag latches follow while cursor stays inside")
	check(not movement.following_cursor, "drag stops follow steering")
	drag.dragging = false
	awareness.cursor_override = pet.world_position + Vector2(5000, 0)
	await frames(5)

	print("[FOLLOW CONTRACT] failures=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
