extends SceneTree

func _initialize() -> void:
	var win := Window.new()
	root.add_child(win)
	print("has mouse_passthrough property: ", "mouse_passthrough" in win)
	print("has min_size property: ", "min_size" in win)
	print("DisplayServer has WINDOW_FLAG_MOUSE_PASSTHROUGH: ", DisplayServer.has_method("window_set_mouse_passthrough"))
	print("Window flags: ", DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP)
	win.queue_free()
	quit()
