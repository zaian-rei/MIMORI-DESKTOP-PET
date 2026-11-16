extends Node

## Reusable Statistics Manager. A pure data-recording layer for the pet:
## session and lifetime statistics (launch count, runtime, distance, action
## counts, cursor-follow/idle time, decisions). Future systems - Achievements,
## Analytics, remote data collection, plugins - read from this manager, not
## from the pet's components.
##
## Design contract:
##   - It ONLY records. It never moves the pet, picks behaviors, plays audio
##     or controls animation, and it never writes to any component.
##   - Tracking is automatic: driven by existing engine signals
##     (StateMachineComponent.state_changed, BehaviorDecisionComponent
##     .decision_made) and the pet's own public state - never by manual
##     increments scattered through the codebase.
##   - Session counters reset on every launch / reset_session(); lifetime
##     counters persist through ConfigService under the "statistics" key.
##   - Effective lifetime = loaded baseline + current session, so persisted
##     values are always correct without ever clearing session counters.
##   - Near-zero overhead: no work happens until a pet is registered; while
##     idle it only accumulates runtime and a few lightweight floats.

const AUTOSAVE_SECONDS := 30.0

## Max entries in the "recently updated" debug feed.
const RECENT_UPDATES_MAX := 12

var _pet: Pet
var _state_machine: StateMachineComponent
var _movement_component: MovementComponent
var _drag_component: DragComponent

## Loaded lifetime baseline (persisted). Effective lifetime = baseline +
## session, so saves stay correct without clearing session counters.
var _lifetime: Dictionary = {}

## Current launch accumulators (session-only).
var _session_counts: Dictionary = {}
var _session_runtime: float = 0.0
var _session_walk_distance: float = 0.0
var _session_run_distance: float = 0.0
var _session_idle_time: float = 0.0
var _session_cursor_follow_time: float = 0.0
var _session_decisions: int = 0

var _last_distance_position: Vector2 = Vector2.ZERO
var _recent_updates: Array = []


func _ready() -> void:
	_restore_lifetime()
	_bump_launch_count()
	_start_autosave()
	LoggerGlobal.info(
		"StatisticsManager initialized (launch #%d)." % get_launch_count()
	)


## Bootstrap hands the pet over after instantiating it. Wires the automatic
## tracking sources via EventBus; nothing is counted before a pet is registered.
func register_pet(pet: Pet) -> void:
	_pet = pet
	_state_machine = pet.get_component(StateMachineComponent)
	_movement_component = pet.get_component(MovementComponent)
	_drag_component = pet.get_component(DragComponent)
	# Subscribe to EventBus for state changes and behavior decisions
	EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)
	EventBus.subscribe(EventBus.BEHAVIOR_SELECTED, _on_behavior_selected_event)
	_last_distance_position = pet.world_position
	LoggerGlobal.info("StatisticsManager: pet registered (via EventBus).")


func _process(delta: float) -> void:
	_session_runtime += delta
	if _pet == null:
		return

	var state := _state_machine.get_state() if _state_machine != null else PetState.State.IDLE
	var pos := _pet.world_position

	if state == PetState.State.WALK or state == PetState.State.RUN:
		var dist := _last_distance_position.distance_to(pos)
		if state == PetState.State.RUN:
			_session_run_distance += dist
		else:
			_session_walk_distance += dist
	_last_distance_position = pos

	var following := _movement_component.following_cursor if _movement_component != null else false
	var dragging := _drag_component.dragging if _drag_component != null else false
	if following:
		_session_cursor_follow_time += delta
	elif state == PetState.State.IDLE and not dragging:
		_session_idle_time += delta


## --- Automatic recording ----------------------------------------------------

func _on_state_changed_event(payload: Dictionary) -> void:
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	_session_counts[new_state] = int(_session_counts.get(new_state, 0)) + 1
	_note_recent_update(_state_name(new_state), int(_session_counts[new_state]))


func _on_behavior_selected_event(payload: Dictionary) -> void:
	_session_decisions += 1
	_note_recent_update("decisions", _session_decisions)


## --- Query API --------------------------------------------------------------

func get_launch_count() -> int:
	return int(_lifetime.get("launch_count", 0))


func get_session_runtime() -> float:
	return _session_runtime


## Total runtime across all launches, including the current session.
func get_total_runtime() -> float:
	return float(_lifetime.get("runtime", 0.0)) + _session_runtime


func get_runtime() -> float:
	return get_total_runtime()


func get_session_distance() -> float:
	return _session_walk_distance + _session_run_distance


func get_total_distance() -> float:
	return float(_lifetime.get("walk_distance", 0.0)) + _session_walk_distance \
		+ float(_lifetime.get("run_distance", 0.0)) + _session_run_distance


## Lifetime walk count (use get_session_count() for the current launch).
func get_walk_count() -> int:
	return int(_lifetime_counts().get(PetState.State.WALK, 0)) + int(_session_counts.get(PetState.State.WALK, 0))


## Lifetime jump count (use get_session_count() for the current launch).
func get_jump_count() -> int:
	return int(_lifetime_counts().get(PetState.State.JUMP, 0)) + int(_session_counts.get(PetState.State.JUMP, 0))


## Lifetime count for any PetState.State (covers FALL, LAND and DRAG too).
func get_count(state: PetState.State) -> int:
	return int(_lifetime_counts().get(state, 0)) + int(_session_counts.get(state, 0))


func get_session_count(state: PetState.State) -> int:
	return int(_session_counts.get(state, 0))


## Lifetime decisions made (use get_session_count() for the current launch).
func get_decision_count() -> int:
	return int(_lifetime.get("decisions", 0)) + _session_decisions


## Lifetime time spent resting in IDLE (not dragging or following).
func get_idle_time() -> float:
	return float(_lifetime.get("idle_time", 0.0)) + _session_idle_time


## Lifetime time spent chasing the cursor.
func get_cursor_follow_time() -> float:
	return float(_lifetime.get("cursor_follow_time", 0.0)) + _session_cursor_follow_time


## Full session snapshot (counts keyed by PetState.State ints).
func get_session_data() -> Dictionary:
	return {
		"runtime": _session_runtime,
		"distance": get_session_distance(),
		"walk_distance": _session_walk_distance,
		"run_distance": _session_run_distance,
		"idle_time": _session_idle_time,
		"cursor_follow_time": _session_cursor_follow_time,
		"decisions": _session_decisions,
		"counts": _session_counts.duplicate(),
	}


## Full lifetime snapshot (counts keyed by PetState.State ints), including
## everything recorded so far this launch.
func get_lifetime_data() -> Dictionary:
	return _effective_lifetime()


## --- Reset ------------------------------------------------------------------

## Clears the current launch's stats and persists, so the reset sticks.
func reset_session() -> void:
	_session_counts = {}
	_session_runtime = 0.0
	_session_walk_distance = 0.0
	_session_run_distance = 0.0
	_session_idle_time = 0.0
	_session_cursor_follow_time = 0.0
	_session_decisions = 0
	_recent_updates.clear()
	if _pet != null:
		_last_distance_position = _pet.world_position
	_save_lifetime()
	LoggerGlobal.info("StatisticsManager: session reset.")


## Clears lifetime (and session) stats and persists. Lifetime restarts from
## zero going forward.
func reset_lifetime() -> void:
	_lifetime = {}
	reset_session()
	LoggerGlobal.info("StatisticsManager: lifetime reset.")


## --- Save / restore ---------------------------------------------------------

func _restore_lifetime() -> void:
	if ConfigService.has_saved_statistics and not ConfigService.statistics.is_empty():
		_from_dict(ConfigService.statistics)


func _from_dict(data: Dictionary) -> void:
	var counts = data.get("lifetime_counts", {})
	if typeof(counts) == TYPE_DICTIONARY:
		var rekeyed := {}
		for key in counts:
			rekeyed[int(key)] = int(counts[key])
		_lifetime["counts"] = rekeyed
	_lifetime["runtime"] = _as_float(data.get("lifetime_runtime"), 0.0)
	_lifetime["walk_distance"] = _as_float(data.get("lifetime_walk_distance"), 0.0)
	_lifetime["run_distance"] = _as_float(data.get("lifetime_run_distance"), 0.0)
	_lifetime["idle_time"] = _as_float(data.get("lifetime_idle_time"), 0.0)
	_lifetime["cursor_follow_time"] = _as_float(data.get("lifetime_cursor_follow_time"), 0.0)
	_lifetime["decisions"] = int(data.get("lifetime_decisions", 0))
	_lifetime["launch_count"] = int(data.get("launch_count", 0))


## Baseline + current session merged - the canonical lifetime view.
func _effective_lifetime() -> Dictionary:
	var counts: Dictionary = _lifetime_counts().duplicate()
	for state in _session_counts:
		counts[state] = int(counts.get(state, 0)) + int(_session_counts[state])
	return {
		"counts": counts,
		"runtime": float(_lifetime.get("runtime", 0.0)) + _session_runtime,
		"walk_distance": float(_lifetime.get("walk_distance", 0.0)) + _session_walk_distance,
		"run_distance": float(_lifetime.get("run_distance", 0.0)) + _session_run_distance,
		"idle_time": float(_lifetime.get("idle_time", 0.0)) + _session_idle_time,
		"cursor_follow_time": float(_lifetime.get("cursor_follow_time", 0.0)) + _session_cursor_follow_time,
		"decisions": int(_lifetime.get("decisions", 0)) + _session_decisions,
		"launch_count": int(_lifetime.get("launch_count", 0)),
	}


func _to_dict() -> Dictionary:
	var eff := _effective_lifetime()
	return {
		"lifetime_counts": eff["counts"],
		"lifetime_runtime": eff["runtime"],
		"lifetime_walk_distance": eff["walk_distance"],
		"lifetime_run_distance": eff["run_distance"],
		"lifetime_idle_time": eff["idle_time"],
		"lifetime_cursor_follow_time": eff["cursor_follow_time"],
		"lifetime_decisions": eff["decisions"],
		"launch_count": eff["launch_count"],
	}


func _bump_launch_count() -> void:
	_lifetime["launch_count"] = get_launch_count() + 1


func _save_lifetime() -> void:
	if ConfigService != null:
		ConfigService.save_statistics(_to_dict())


func _start_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(_save_lifetime)
	add_child(timer)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_lifetime()


## --- Internals --------------------------------------------------------------

func _lifetime_counts() -> Dictionary:
	return _lifetime.get("counts", {})


func _state_name(state: PetState.State) -> String:
	var keys := PetState.State.keys()
	return keys[state] if state >= 0 and state < keys.size() else str(state)


func _note_recent_update(key: String, value: Variant) -> void:
	_recent_updates.append({"stat": key, "value": value, "time": _session_runtime})
	if _recent_updates.size() > RECENT_UPDATES_MAX:
		_recent_updates.pop_front()


func _as_float(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


## --- Debug support ----------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"launch_count": get_launch_count(),
		"session_runtime": get_session_runtime(),
		"total_runtime": get_total_runtime(),
		"session_distance": get_session_distance(),
		"total_distance": get_total_distance(),
		"jump_count": get_jump_count(),
		"decisions": get_decision_count(),
		"idle_time": get_idle_time(),
		"cursor_follow_time": get_cursor_follow_time(),
		"session": _named_counts(_session_counts),
		"lifetime": _named_counts(_effective_lifetime()["counts"]),
		"recently_updated": _recent_updates.duplicate(),
	}


func _named_counts(counts: Dictionary) -> Dictionary:
	var out := {}
	for state in counts:
		out[_state_name(state)] = counts[state]
	return out
