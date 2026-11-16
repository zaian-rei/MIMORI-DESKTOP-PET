extends Node

## Autoload singleton that owns all BehaviorDefinition resources loaded from
## res://data/behaviors/. New behaviors are pure data files - no engine code
## changes (Open/Closed). Read-only after load; runtime decision state lives in
## BehaviorController, not here.

const BEHAVIORS_DIR := "res://data/behaviors/"

## Animation fallbacks for the states that are NOT in the behavior catalog
## (physics/manual ground truth). Catalog states resolve through their .tres.
const FALLBACK_ANIMATION := {
	PetState.State.DRAG: "idle",
	PetState.State.FALL: "fall",
	PetState.State.LAND: "land",
}

var _behaviors_by_state: Dictionary = {}


func _ready() -> void:
	_load_all()
	LoggerGlobal.info("BehaviorCatalog loaded %d behaviors." % get_all().size())


func get_all() -> Array[BehaviorDefinition]:
	var out: Array[BehaviorDefinition] = []
	for state in _behaviors_by_state:
		for behavior in _behaviors_by_state[state]:
			out.append(behavior)
	return out


func get_for_state(state: PetState.State) -> Array[BehaviorDefinition]:
	var out: Array[BehaviorDefinition] = []
	for behavior in _behaviors_by_state.get(state, []):
		out.append(behavior)
	return out


func get_behavior_for_state(state: PetState.State) -> BehaviorDefinition:
	var list := get_for_state(state)
	if list.is_empty():
		return null
	return list[0]


func get_animation_for_state(state: PetState.State) -> String:
	var behavior := get_behavior_for_state(state)
	if behavior != null and behavior.animation_name != "":
		return behavior.animation_name
	return FALLBACK_ANIMATION.get(state, "idle")


func _load_all() -> void:
	_behaviors_by_state.clear()
	## ResourceLoader preserves the project's original resource names in
	## exported PCKs; DirAccess only sees converted .remap/.res files there.
	for file in ResourceLoader.list_directory(BEHAVIORS_DIR):
		if not file.ends_with(".tres"):
			continue
		var behavior := load(BEHAVIORS_DIR.path_join(file)) as BehaviorDefinition
		if behavior == null:
			LoggerGlobal.warn("BehaviorCatalog: '%s' did not load as BehaviorDefinition." % file)
			continue
		if not _behaviors_by_state.has(behavior.state):
			_behaviors_by_state[behavior.state] = []
		_behaviors_by_state[behavior.state].append(behavior)
