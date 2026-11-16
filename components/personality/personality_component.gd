extends "res://core/base/pet_component.gd"
class_name PersonalityComponent

## Owns the pet's active personality: which PersonalityDefinition is selected,
## and the read gateway every other system uses to query its modifiers. It
## only loads/exposes data and notifies on change - it never moves the pet,
## picks behaviors, plays animations or transitions states (same contract as
## BehaviorMemoryComponent). PersonalityCatalog holds the resources; this
## component holds the *selection* and its persistence.

signal personality_changed(definition: PersonalityDefinition)

var current: PersonalityDefinition


func on_initialized() -> void:
	_restore_current()
	LoggerGlobal.info("PersonalityComponent initialized (%s)." % (current.id if current != null else "none"))


## --- Selection --------------------------------------------------------------

## Switches personality at runtime: modifiers are read live by the decision
## loop, so they apply on the very next decision. Persists through
## ConfigService; no restart needed.
func set_personality_by_id(id: String) -> bool:
	var defn: PersonalityDefinition = PersonalityCatalog.get_by_id(id)
	if defn == null:
		LoggerGlobal.warn("PersonalityComponent: unknown personality '%s'." % id)
		return false
	if current != null and current.id == id:
		return true
	current = defn
	ConfigService.set_personality_id(id)
	personality_changed.emit(current)
	var controller := pet.get_component(BehaviorController) as BehaviorController
	if controller != null:
		controller.apply_personality_change()
	LoggerGlobal.info("Personality changed to '%s'." % id)
	return true


## --- Reads (null-safe; neutral 1.0 / empty when no personality) -------------

func get_personality_id() -> String:
	return current.id if current != null else ""


func get_display_name() -> String:
	return current.display_name if current != null else ""


func get_description() -> String:
	return current.description if current != null else ""


func get_utility_multiplier_for(state: PetState.State) -> float:
	if current == null:
		return 1.0
	return current.utility_multiplier_for(state)


func get_duration_modifier_for(state: PetState.State) -> float:
	if current == null:
		return 1.0
	return current.duration_modifier_for(state)


func get_stat_scale_for(stat: PetStats.Stat) -> float:
	if current == null:
		return 1.0
	return current.stat_scale_for(stat)


func get_decision_delay_modifier() -> float:
	if current == null:
		return 1.0
	return maxf(current.decision_delay_modifier, 0.1)


func get_movement_speed_modifier() -> float:
	if current == null:
		return 1.0
	return maxf(current.movement_speed_modifier, 0.1)


func get_reaction_speed_modifier() -> float:
	if current == null:
		return 1.0
	return maxf(current.reaction_speed_modifier, 0.1)


## --- Debug support ----------------------------------------------------------

## Per-state utility multipliers from the active personality.
func get_utility_multipliers() -> Dictionary:
	var out := {}
	for state in PetState.State.values():
		out[state] = get_utility_multiplier_for(state)
	return out


func get_active_modifiers() -> Dictionary:
	if current == null:
		return {}
	return current.get_modifier_summary()


func get_debug_info() -> Dictionary:
	return {
		"personality_id": get_personality_id(),
		"display_name": get_display_name(),
		"description": get_description(),
		"resource": current,
		"modifiers": get_active_modifiers(),
		"utility_multipliers": get_utility_multipliers(),
	}


## --- Internals --------------------------------------------------------------

## Restore order: saved selection (runtime, persisted) wins, then the pet
## definition's default, then the catalog default.
func _restore_current() -> void:
	var saved := ConfigService.personality_id
	var candidate := ""
	if saved != "" and PersonalityCatalog.has_id(saved):
		candidate = saved
	elif pet.definition.default_personality_id != "" and PersonalityCatalog.has_id(pet.definition.default_personality_id):
		candidate = pet.definition.default_personality_id
	else:
		candidate = PersonalityCatalog.get_default_id()
	if candidate == "":
		current = null
		return
	current = PersonalityCatalog.get_by_id(candidate)
