extends Node

## Autoload singleton that owns all PersonalityDefinition resources loaded
## from res://data/personalities/. New personalities are pure data files -
## no engine code changes (Open/Closed). Read-only after load; the active
## personality selection lives in PersonalityComponent, not here.

const PERSONALITIES_DIR := "res://data/personalities/"

var _by_id: Dictionary = {}
var _order: Array = []


func _ready() -> void:
	_load_all()
	LoggerGlobal.info("PersonalityCatalog loaded %d personalities." % _by_id.size())


func get_by_id(id: String) -> PersonalityDefinition:
	return _by_id.get(id)


func has_id(id: String) -> bool:
	return _by_id.has(id)


func get_all() -> Array[PersonalityDefinition]:
	var out: Array[PersonalityDefinition] = []
	for defn in _order:
		out.append(defn)
	return out


## First-loaded personality, used when neither a saved selection nor a
## pet-definition default is set.
func get_default_id() -> String:
	if _order.is_empty():
		return ""
	return _order[0].id


func _load_all() -> void:
	_by_id.clear()
	_order.clear()
	## ResourceLoader keeps original resource names available in exported PCKs.
	for file in ResourceLoader.list_directory(PERSONALITIES_DIR):
		if not file.ends_with(".tres"):
			continue
		var defn := load(PERSONALITIES_DIR.path_join(file)) as PersonalityDefinition
		if defn == null or defn.id == "":
			LoggerGlobal.warn("PersonalityCatalog: '%s' did not load as PersonalityDefinition." % file)
			continue
		if _by_id.has(defn.id):
			LoggerGlobal.warn("PersonalityCatalog: duplicate id '%s' in '%s', ignoring." % [defn.id, file])
			continue
		_by_id[defn.id] = defn
		_order.append(defn)
