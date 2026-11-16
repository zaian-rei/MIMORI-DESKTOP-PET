extends Node



const BEHAVIOR_STARTED := &"behavior_started"
const BEHAVIOR_FINISHED := &"behavior_finished"
const BEHAVIOR_SELECTED := &"behavior_selected"


const WALK_STARTED := &"walk_started"
const WALK_FINISHED := &"walk_finished"
const RUN_STARTED := &"run_started"
const RUN_FINISHED := &"run_finished"
const JUMP_STARTED := &"jump_started"
const LANDING_FINISHED := &"landing_finished"


const STATE_CHANGED := &"state_changed"


const ANIMATION_STARTED := &"animation_started"
const ANIMATION_FINISHED := &"animation_finished"


const PET_DRAGGED := &"pet_dragged"
const PET_RELEASED := &"pet_released"
const PET_CLICKED := &"pet_clicked"
const CURSOR_FOLLOW_ENABLED := &"cursor_follow_enabled"
const CURSOR_FOLLOW_DISABLED := &"cursor_follow_disabled"
const CURSOR_FOLLOW_STARTED := &"cursor_follow_started"


const DESKTOP_CHANGED := &"desktop_changed"
const MONITOR_CHANGED := &"monitor_changed"


const MUSIC_STARTED := &"music_started"
const MUSIC_STOPPED := &"music_stopped"


const THEME_LOADED := &"theme_loaded"
const THEME_UNLOADED := &"theme_unloaded"
const THEME_CHANGED := &"theme_changed"
const THEME_LOAD_FAILED := &"theme_load_failed"
const THEME_VALIDATED := &"theme_validated"


const SETTINGS_CHANGED := &"settings_changed"
const SETTING_CHANGED := &"setting_changed"
const SETTINGS_CATEGORY_RESET := &"settings_category_reset"
const SETTINGS_LOADED := &"settings_loaded"
const SETTINGS_SAVED := &"settings_saved"

const PLUGIN_REGISTERED := &"plugin_registered"
const PLUGIN_UNLOADED := &"plugin_unloaded"
const PLUGIN_INITIALIZED := &"plugin_initialized"
const PLUGIN_ENABLED := &"plugin_enabled"
const PLUGIN_DISABLED := &"plugin_disabled"
const PLUGIN_SHUTDOWN := &"plugin_shutdown"
const PLUGIN_ERROR := &"plugin_error"



signal engine_initialized
signal settings_requested



var _subscribers: Dictionary = {}


var _event_counts: Dictionary = {}
var _recent_events: Array[Dictionary] = []
var _emit_count_this_second: int = 0
var _avg_events_per_second: float = 0.0
var _last_second_time: float = 0.0
const MAX_RECENT_EVENTS := 50

func _ready() -> void:
	_last_second_time = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	var current_time := Time.get_ticks_msec() / 1000.0
	if current_time - _last_second_time >= 1.0:
		_avg_events_per_second = _emit_count_this_second
		_emit_count_this_second = 0
		_last_second_time = current_time



func subscribe(event_name: StringName, callback: Callable) -> void:
	if not _subscribers.has(event_name):
		_subscribers[event_name] = {}

	var callbacks: Dictionary = _subscribers[event_name]

	if callbacks.has(callback):
		return

	callbacks[callback] = callback


func unsubscribe(event_name: StringName, callback: Callable) -> void:
	if not _subscribers.has(event_name):
		return

	var callbacks: Dictionary = _subscribers[event_name]

	callbacks.erase(callback)

	if callbacks.is_empty():
		_subscribers.erase(event_name)


func emit(event_name: StringName, payload: Dictionary = {}) -> void:

	if not _event_counts.has(event_name):
		_event_counts[event_name] = 0
	_event_counts[event_name] += 1
	_emit_count_this_second += 1

	_recent_events.push_back({
		"event": event_name,
		"payload": payload.duplicate() if not payload.is_empty() else {},
		"time": Time.get_ticks_msec()
	})
	if _recent_events.size() > MAX_RECENT_EVENTS:
		_recent_events.pop_front()

	if not _subscribers.has(event_name):
		return

	var callbacks: Dictionary = _subscribers[event_name]
	var to_remove: Array[Callable] = []

	for callback_id in callbacks:
		var callback: Callable = callbacks[callback_id]
		var obj := callback.get_object()

		# Auto-cleanup: remove freed objects
		if not is_instance_valid(obj):
			to_remove.append(callback_id)
			continue

		# Call with payload if it accepts parameters
		if callback.get_argument_count() > 0:
			callback.call(payload)
		else:
			callback.call()

	# Clean up freed listeners
	for callback_id in to_remove:
		callbacks.erase(callback_id)

	if callbacks.is_empty():
		_subscribers.erase(event_name)


## Get debug information for the debug overlay.
func get_debug_info() -> Dictionary:
	var total_listeners := 0
	for event_name in _subscribers:
		total_listeners += _subscribers[event_name].size()

	return {
		"recently_emitted": _recent_events.slice(-10),
		"subscriber_counts": _get_subscriber_counts(),
		"event_counts": _event_counts.duplicate(),
		"average_events_per_second": _avg_events_per_second,
		"current_listeners": total_listeners,
	}


func _get_subscriber_counts() -> Dictionary:
	var counts := {}
	for event_name in _subscribers:
		counts[event_name] = _subscribers[event_name].size()
	return counts


## Reset all debug tracking data (called from debug overlay).
func reset_debug_data() -> void:
	_event_counts.clear()
	_recent_events.clear()
	_emit_count_this_second = 0
	_avg_events_per_second = 0.0
