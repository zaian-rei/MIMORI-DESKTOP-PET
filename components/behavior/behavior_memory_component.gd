extends "res://core/base/pet_component.gd"
class_name BehaviorMemoryComponent

## Pure recorder/query layer for the pet's history. It watches state
## transitions and interaction events and exposes read-only queries to the
## decision system:
##   - recent action history (last HISTORY_SIZE behaviors, session-only)
##   - interaction memory (drags, clicks, cursor-follow)
##   - per-action timestamps (time since last sleep/walk/action)
##   - lifetime counters (walks/sleeps/thoughts/dances, runtime, launches),
##     persisted through ConfigService alongside the stats
## It never moves, animates, transitions states or chooses behaviors -
## BehaviorDecisionComponent consumes these queries and does the scoring.

signal action_recorded(state: PetState.State)

const HISTORY_SIZE := 10

## Default "recent" window (seconds) used by was_recently_performed().
const RECENT_WINDOW_SECONDS := 60.0

const AUTOSAVE_SECONDS := 30.0

## States tracked as actions. Physics intermediates (FALL/LAND) are not
## actions and DRAG is handled separately as an interaction. IDLE is the
## resting state, not an action - excluding it keeps history/time-since-
## last-action meaningful ("what did the pet last actually do").
const RECORDED_STATES := [
	PetState.State.WALK,
	PetState.State.RUN,
	PetState.State.JUMP,
	PetState.State.SLEEP,
	PetState.State.THINK,
	PetState.State.HAPPY,
	PetState.State.SAD,
	PetState.State.DEEP_SLEEP,
	PetState.State.DANCE,
]

var state_machine: StateMachineComponent
var drag_component: DragComponent
var interaction_component: InteractionComponent

## Recent action states, newest last, paired with _history_timestamps.
var _history: Array = []
var _history_timestamps: Array = []

## State -> last start time (monotonic seconds) for time_since_last().
var _last_started_time: Dictionary = {}

## Timestamp of the last recorded action; time_since_last_action() reads it.
var _last_action_time: float = 0.0

## --- Interaction memory (session-only) -------------------------------------

var last_drag_time: float = 0.0
var total_drags: int = 0
var last_left_click_time: float = 0.0
var total_left_clicks: int = 0
var last_right_click_time: float = 0.0
var total_right_clicks: int = 0
var last_cursor_follow_time: float = 0.0
var total_cursor_follows: int = 0

## --- Lifetime counters (persisted) -----------------------------------------

var _lifetime_counts: Dictionary = {}
var runtime_seconds: float = 0.0
var launch_count: int = 0


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	drag_component = pet.get_component(DragComponent)
	interaction_component = pet.get_component(InteractionComponent)
	EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)
	EventBus.subscribe(EventBus.PET_CLICKED, _on_pet_clicked_event)
	pet.interaction_area.input_event.connect(_on_input_event)
	if interaction_component != null:
		EventBus.subscribe(EventBus.CURSOR_FOLLOW_STARTED, _on_cursor_follow_event)
	_restore_memory()
	launch_count += 1
	_start_autosave()
	LoggerGlobal.info("BehaviorMemoryComponent initialized.")


func _process(delta: float) -> void:
	if pet == null or not enabled:
		return
	runtime_seconds += delta


## --- Recording -------------------------------------------------------------

## Records that an action started. Safe to call directly; the state-machine
## observer routes every real behavior start here automatically.
func record_action(state: PetState.State) -> void:
	if state not in RECORDED_STATES:
		return
	var now := _now()
	_history.append(state)
	_history_timestamps.append(now)
	while _history.size() > HISTORY_SIZE:
		_history.pop_front()
		_history_timestamps.pop_front()
	_last_started_time[state] = now
	_last_action_time = now
	_lifetime_counts[state] = int(_lifetime_counts.get(state, 0)) + 1
	action_recorded.emit(state)
	EventBus.emit(EventBus.BEHAVIOR_SELECTED, {"state": state})


func _on_state_changed_event(payload: Dictionary) -> void:
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	if new_state == PetState.State.DRAG:
		_on_drag_started()
		return
	record_action(new_state)


func _on_drag_started() -> void:
	last_drag_time = _now()
	total_drags += 1


func _on_pet_clicked_event(_payload: Dictionary) -> void:
	last_left_click_time = _now()
	total_left_clicks += 1


func _on_input_event(
	_viewport,
	event: InputEvent,
	_shape_idx
) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		last_right_click_time = _now()
		total_right_clicks += 1


func _on_cursor_follow_event(_payload: Dictionary) -> void:
	last_cursor_follow_time = _now()
	total_cursor_follows += 1


## --- Decision queries (data only; never scores) ----------------------------

func get_last_action() -> PetState.State:
	if _history.is_empty():
		return PetState.State.IDLE
	return _history.back()


## Copy of the recent action states, newest last.
func get_recent_actions() -> Array:
	return _history.duplicate()


func was_recently_performed(state: PetState.State, window: float = RECENT_WINDOW_SECONDS) -> bool:
	return count_recent_occurrences(state, window) > 0


## How many times `state` was performed within the last `window` seconds.
func count_recent_occurrences(state: PetState.State, window: float = RECENT_WINDOW_SECONDS) -> int:
	var now := _now()
	var count := 0
	for i in _history.size():
		if _history[i] == state and now - _history_timestamps[i] <= window:
			count += 1
	return count


## Seconds since `state` last started (INF if never).
func time_since_last(state: PetState.State) -> float:
	if not _last_started_time.has(state):
		return INF
	return maxf(_now() - _last_started_time[state], 0.0)


## Seconds since the pet last did anything (INF if nothing recorded yet).
func time_since_last_action() -> float:
	if _last_action_time <= 0.0:
		return INF
	return maxf(_now() - _last_action_time, 0.0)


## --- Lifetime counters -----------------------------------------------------

func times_walked() -> int:
	return get_lifetime_count(PetState.State.WALK)


func times_slept() -> int:
	return get_lifetime_count(PetState.State.SLEEP) + get_lifetime_count(PetState.State.DEEP_SLEEP)


func times_thought() -> int:
	return get_lifetime_count(PetState.State.THINK)


func times_danced() -> int:
	return get_lifetime_count(PetState.State.DANCE)


func get_lifetime_count(state: PetState.State) -> int:
	return int(_lifetime_counts.get(state, 0))


func get_runtime_seconds() -> float:
	return runtime_seconds


func get_launch_count() -> int:
	return launch_count


## --- Save / restore --------------------------------------------------------

func _to_dict() -> Dictionary:
	return {
		"lifetime": _lifetime_counts,
		"runtime": runtime_seconds,
		"launch_count": launch_count,
	}


func _from_dict(data: Dictionary) -> void:
	## JSON round-trips dict keys as strings; re-key to ints so new
	## record_action() int-key writes accumulate instead of duplicating.
	_lifetime_counts = {}
	for key in data.get("lifetime", {}):
		_lifetime_counts[int(key)] = int(data["lifetime"][key])
	runtime_seconds = _as_float(data.get("runtime"), 0.0)
	launch_count = int(data.get("launch_count", 0))


func _restore_memory() -> void:
	if ConfigService.has_saved_memory and not ConfigService.pet_memory.is_empty():
		_from_dict(ConfigService.pet_memory)


## Clears all recorded history, interactions and lifetime counters, then
## persists the reset. Used by the debug overlay's "Reset Memory" control.
func reset_session_memory() -> void:
	_history.clear()
	_history_timestamps.clear()
	_last_started_time.clear()
	_last_action_time = 0.0
	last_drag_time = 0.0
	total_drags = 0
	last_left_click_time = 0.0
	total_left_clicks = 0
	last_right_click_time = 0.0
	total_right_clicks = 0
	last_cursor_follow_time = 0.0
	total_cursor_follows = 0
	_lifetime_counts = {}
	runtime_seconds = 0.0
	launch_count = 0
	_save_memory()


func _start_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(_save_memory)
	add_child(timer)


func _save_memory() -> void:
	ConfigService.save_memory(_to_dict())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_memory()


## --- Internals -------------------------------------------------------------

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _as_float(value: Variant, fallback: float) -> float:
	if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT:
		return float(value)
	return fallback


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"recent_actions": get_recent_actions(),
		"last_action": get_last_action(),
		"time_since_last_action": time_since_last_action(),
		"time_since_last_sleep": time_since_last(PetState.State.SLEEP),
		"time_since_last_walk": time_since_last(PetState.State.WALK),
		"total_drags": total_drags,
		"last_drag_time": last_drag_time,
		"total_left_clicks": total_left_clicks,
		"total_right_clicks": total_right_clicks,
		"total_cursor_follows": total_cursor_follows,
		"lifetime": _lifetime_counts,
		"runtime_seconds": runtime_seconds,
		"launch_count": launch_count,
	}
