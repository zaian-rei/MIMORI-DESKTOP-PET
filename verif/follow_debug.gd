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
	var drag: DragComponent = pet.get_component(DragComponent)

	# Print initial state
	print("INIT: follow_enabled=%s following_cursor=%s dragging=%s" % [
		follow.is_follow_enabled(),
		movement.following_cursor,
		drag.dragging,
	])

	# Enable follow immediately after initialization
	follow.set_follow_enabled(true)

	print("AFTER SET: follow_enabled=%s following_cursor=%s" % [
		follow.is_follow_enabled(),
		movement.following_cursor,
	])

	# Check mouse position
	var cursor := DisplayServer.mouse_get_position()
	print("cursor pos: %s" % [cursor])

	# Enable follow and run physics to see if it works
	var start_x: float = pet.world_position.x
	for i in 120:
		await get_tree().physics_frame
		print("TICK %d: state=%s y=%.0f follow_enabled=%s following_cursor=%s vel=(%.1f,%.1f) pos=(%.0f,%.0f)" % [
			i,
			PetState.State.keys()[state_machine.get_state()],
			pet.world_position.y,
			follow.is_follow_enabled(),
			movement.following_cursor,
			pet.velocity.x,
			pet.velocity.y,
			pet.world_position.x,
			pet.world_position.y,
		])

	var moved: float = pet.world_position.x - start_x
	print("[VERIFY] moved=%f follow_enabled=%s following_cursor=%s state=%s pos=(%.0f,%.0f)" % [
		moved,
		follow.is_follow_enabled(),
		movement.following_cursor,
		PetState.State.keys()[state_machine.get_state()],
		pet.world_position.x,
		pet.world_position.y,
	])
	get_tree().quit(0 if moved > 50.0 else 1)
