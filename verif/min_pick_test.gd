extends Node

## Minimal picking probe inside the pet project (no bootstrap).

var _fired := false

func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0 and int(OS.get_cmdline_user_args()[0]) == 1:
		get_window().transparent = false
		print("MINPICK transparent forced OFF")
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	print("MINPICK window transparent=", get_window().transparent, " borderless=", get_window().borderless)

	get_tree().root.physics_object_picking = true
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 90.0
	cap.height = 264.0
	shape.shape = cap
	area.add_child(shape)
	add_child(area)
	area.global_position = get_viewport().size / 2
	area.input_event.connect(func(v, e, s):
		_fired = true
		print("MINPICK area FIRED at=", e.position)
	)
	await get_tree().process_frame

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = area.global_position
	press.global_position = area.global_position
	press.window_id = get_window().get_window_id()
	get_viewport().push_input(press)
	await get_tree().process_frame
	print("MINPICK fired=", _fired)
	get_tree().quit(0)
