extends Node

var pet: Pet
var enabled: bool = true

func initialize(owner_pet: Pet) -> void:
	pet = owner_pet
	on_initialized()

func on_initialized() -> void:
	pass

func set_enabled(value: bool) -> void:
	enabled = value

func is_enabled() -> bool:
	return enabled

## Default debug interface. Subsystems override this to expose their current
## state; the debug overlay consumes it without reaching into internals.
func get_debug_info() -> Dictionary:
	return {}
