extends Node

const BOOT := preload("res://scenes/bootstrap/bootstrap.tscn")

func _ready() -> void:
	_run()


func _run() -> void:
	get_tree().root.add_child.call_deferred(BOOT.instantiate())
	for i in 12:
		await get_tree().process_frame

	var boot_node := get_tree().root.find_child("Bootstrap", true, false)
	var pet: Node = boot_node.find_child("Pet", true, false)
	var follow: FollowCursorComponent = pet.get_component(FollowCursorComponent)
	var awareness: DesktopAwarenessComponent = pet.get_component(DesktopAwarenessComponent)
	var movement: MovementComponent = pet.get_component(MovementComponent)
	var state_machine: StateMachineComponent = pet.get_component(StateMachineComponent)

	for i in 120:
		await get_tree().physics_frame

	var cursor_target: Vector2 = pet.world_position + Vector2(400, 0)
	awareness.cursor_override = cursor_target
	follow.set_follow_enabled(true)

	var start_x: float = pet.world_position.x
	for i in 240:
		await get_tree().physics_frame
		if i % 60 == 0:
			print("TICK %d state=%s y=%.1f floor=%.1f vel=%s following=%s pos=%s" % [
				i,
				PetState.State.keys()[state_machine.get_state()],
				pet.world_position.y,
				awareness.floor_position(),
				pet.velocity,
				movement.following_cursor,
				pet.world_position,
			])

	var moved: float = pet.world_position.x - start_x
	print("[VERIFY] follow_cursor moved=%f follow_enabled=%s following_cursor=%s state=%s cursor=%s pos=%s" % [
		moved,
		follow.is_follow_enabled(),
		movement.following_cursor,
		PetState.State.keys()[state_machine.get_state()],
		cursor_target,
		pet.world_position,
	])
	get_tree().quit(0 if moved > 50.0 else 1)
