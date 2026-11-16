extends Node

## Temporary LIVE diagnostic: adds a fresh, independent Area2D to the root
## viewport and clicks it. If it fires, the app/viewport config is fine and
## the pet's Interaction area is the problem; if not, the viewport config is.

const BOOT := preload("res://scenes/bootstrap/bootstrap.tscn")
const CTX_SCRIPT := preload("res://components/window/context_menu_component.gd")


func _ready() -> void:
	get_tree().root.add_child.call_deferred(BOOT.instantiate())
	for i in 12:
		await get_tree().process_frame

	var boot_node := get_tree().root.find_child("Bootstrap", true, false)
	var pet: Node = boot_node.find_child("Pet", true, false)
	var area: Area2D = pet.interaction_area
	var ctx: Node = pet.get_component(CTX_SCRIPT)
	var menu: Window = ctx._menu
	var viewport := pet.get_viewport()

	print("VP physics_object_picking=", viewport.physics_object_picking)
	print("VP tree paused=", get_tree().paused,
		" physics_ticks=", Engine.physics_ticks_per_second)

	area.input_event.connect(func(v, e, s):
		_pet_fired = true
		print("PET_AREA input_event FIRED at=", e.position)
	)

	var fresh := Area2D.new()
	fresh.name = "FreshProbe"
	var shape := CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 90.0
	cap.height = 264.0
	shape.shape = cap
	fresh.add_child(shape)
	get_tree().root.add_child(fresh)
	fresh.global_position = Vector2(140, 150)
	fresh.input_event.connect(func(v, e, s):
		_fresh_fired = true
		print("FRESH input_event FIRED at=", e.position)
	)
	var fresh_shape_rect := (shape.shape as CapsuleShape2D).get_rect()
	print("FRESH at=", fresh.global_position, " shape_rect=", fresh_shape_rect)
	await get_tree().process_frame

	var win_id: int = pet.get_window().get_window_id()
	for probe in [{"name": "PET_AREA", "pos": area.global_position}, {"name": "FRESH_AREA", "pos": fresh.global_position}]:
		print("CLICK ", probe["name"], " at=", probe["pos"])
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = probe["pos"]
		press.global_position = probe["pos"]
		press.window_id = win_id
		viewport.push_input(press)
		for i in 4:
			await get_tree().process_frame
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = probe["pos"]
		release.global_position = probe["pos"]
		release.window_id = win_id
		viewport.push_input(release)
		for i in 4:
			await get_tree().process_frame

	print("DONE pet area fired=", _pet_fired, " fresh fired=", _fresh_fired)
	get_tree().quit(0)

var _pet_fired := false
var _fresh_fired := false
