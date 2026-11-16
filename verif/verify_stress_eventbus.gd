extends Node

# EventBus stress:
#  - duplicate subscribe prevention (same + different callables)
#  - subscribe/unsubscribe DURING emit (dictionary mutated while iterating)
#  - nested emit (re-entrancy)
#  - freed-object auto-cleanup (orphan listeners)
#  - callback arity (0-arg and 1-arg)
#  - event storm (10k emits) + tracking caps + listener accumulation

var _fails := 0

class OrphanListener extends Node:
	var cb: Callable = Callable()
	func set_callback(c: Callable) -> void:
		cb = c
	func _on_event(_p) -> void:
		cb.call()

func _ready() -> void:
	EventBus.reset_debug_data()

	## 1. Duplicate subscribe prevention --------------------------------------
	var calls: Array = []
	var cb := func(p): calls.append(1)
	EventBus.subscribe(EventBus.STATE_CHANGED, cb)
	EventBus.subscribe(EventBus.STATE_CHANGED, cb)
	EventBus.subscribe(EventBus.STATE_CHANGED, cb)
	EventBus.emit(EventBus.STATE_CHANGED, {"new_state": 1})
	_check("duplicate subscribe dedups", calls.size() == 1)
	EventBus.unsubscribe(EventBus.STATE_CHANGED, cb)

	## 2. Two distinct lambdas on the same object both fire --------------------
	var a: Array = []
	var b: Array = []
	EventBus.subscribe(EventBus.STATE_CHANGED, func(p): a.append(1))
	EventBus.subscribe(EventBus.STATE_CHANGED, func(p): b.append(1))
	EventBus.emit(EventBus.STATE_CHANGED, {"new_state": 2})
	_check("distinct lambdas both fire", a.size() == 1 and b.size() == 1)
	for c in EventBus._subscribers[EventBus.STATE_CHANGED].duplicate():
		EventBus.unsubscribe(EventBus.STATE_CHANGED, EventBus._subscribers[EventBus.STATE_CHANGED][c])

	## 3. Subscribe DURING emit (dict mutated while iterating) -----------------
	var first: Array = []
	var second: Array = []
	var extra_subscribed := false
	EventBus.subscribe(EventBus.THEME_CHANGED, func(p):
		first.append(1)
		if not extra_subscribed:
			extra_subscribed = true
			EventBus.subscribe(EventBus.THEME_CHANGED, func(p2): second.append(1))
	)
	EventBus.emit(EventBus.THEME_CHANGED)
	EventBus.emit(EventBus.THEME_CHANGED)
	var sub_after: int = EventBus._subscribers.get(EventBus.THEME_CHANGED, {}).size()
	_check("subscribe during emit does not crash", true)
	_check("extra listener stays registered", sub_after >= 2)
	for c in EventBus._subscribers.get(EventBus.THEME_CHANGED, {}).duplicate():
		EventBus.unsubscribe(EventBus.THEME_CHANGED, EventBus._subscribers[EventBus.THEME_CHANGED][c])

	## 4. Unsubscribe DURING emit (other listener) -----------------------------
	var u1: Array = []
	var u2: Array = []
	var u1_cb := func(p): u1.append(1)
	var u2_cb := func(p): u2.append(1)
	var killer := func(p): EventBus.unsubscribe(EventBus.MUSIC_STARTED, u2_cb)
	EventBus.subscribe(EventBus.MUSIC_STARTED, u1_cb)
	EventBus.subscribe(EventBus.MUSIC_STARTED, u2_cb)
	EventBus.subscribe(EventBus.MUSIC_STARTED, killer)
	var base_count: int = EventBus._subscribers.get(EventBus.MUSIC_STARTED, {}).size()
	EventBus.emit(EventBus.MUSIC_STARTED)
	_check("unsubscribe during emit does not crash", true)
	_check("removed listener no longer registered", not EventBus._subscribers.get(EventBus.MUSIC_STARTED, {}).has(u2_cb))
	_check("other listeners remain after", EventBus._subscribers.get(EventBus.MUSIC_STARTED, {}).size() == base_count - 1)
	for c in EventBus._subscribers.get(EventBus.MUSIC_STARTED, {}).duplicate():
		EventBus.unsubscribe(EventBus.MUSIC_STARTED, EventBus._subscribers[EventBus.MUSIC_STARTED][c])

	## 5. Nested emit (handler emits the same event) ---------------------------
	var depth_arr: Array = [0]
	var max_arr: Array = [0]
	var seen: Array = []
	EventBus.subscribe(EventBus.BEHAVIOR_SELECTED, func(p):
		seen.append(1)
		depth_arr[0] += 1
		max_arr[0] = maxi(max_arr[0], depth_arr[0])
		if depth_arr[0] < 3:
			EventBus.emit(EventBus.BEHAVIOR_SELECTED)
		depth_arr[0] -= 1
	)
	EventBus.emit(EventBus.BEHAVIOR_SELECTED)
	_check("nested emit terminates", seen.size() == 3)
	_check("nested emit max depth", max_arr[0] == 3)
	for c in EventBus._subscribers.get(EventBus.BEHAVIOR_SELECTED, {}).duplicate():
		EventBus.unsubscribe(EventBus.BEHAVIOR_SELECTED, EventBus._subscribers[EventBus.BEHAVIOR_SELECTED][c])

	## 6. Freed-object auto-cleanup (orphan listeners) -------------------------
	var orphan := OrphanListener.new()
	var orphan_called := 0
	orphan.set_callback(func(): orphan_called += 1)
	EventBus.subscribe(EventBus.PET_CLICKED, orphan._on_event)
	add_child(orphan)
	orphan.queue_free()
	await _frames(3)
	var before: Variant = EventBus.get_debug_info().get("current_listeners")
	EventBus.emit(EventBus.PET_CLICKED, {"x": 1})
	EventBus.emit(EventBus.PET_CLICKED, {"x": 2})
	var after_count: Variant = EventBus.get_debug_info().get("current_listeners")
	_check("freed listener auto-cleaned", after_count < before)
	_check("freed listener not called (no crash)", orphan_called == 0)

	## 7. Callback arity -------------------------------------------------------
	var zero_arg_called: Array = [0]
	var one_arg_called: Array = [0]
	EventBus.subscribe(EventBus.SETTINGS_SAVED, func(): zero_arg_called[0] += 1)
	EventBus.subscribe(EventBus.SETTINGS_SAVED, func(p): one_arg_called[0] += 1)
	EventBus.emit(EventBus.SETTINGS_SAVED, {"k": 1})
	_check("0-arg callback called", zero_arg_called[0] == 1)
	_check("1-arg callback called", one_arg_called[0] == 1)
	for c in EventBus._subscribers.get(EventBus.SETTINGS_SAVED, {}).duplicate():
		EventBus.unsubscribe(EventBus.SETTINGS_SAVED, EventBus._subscribers[EventBus.SETTINGS_SAVED][c])

	## 8. Event storm ----------------------------------------------------------
	var storm_seen: Array = [0]
	EventBus.subscribe(EventBus.STATE_CHANGED, func(p): storm_seen[0] += 1)
	for i in 10000:
		EventBus.emit(EventBus.STATE_CHANGED, {"new_state": i % 14, "frame": i})
	_check("storm delivers all events", storm_seen[0] == 10000)
	var info: Dictionary = EventBus.get_debug_info()
	_check("recent_events capped at 50", info["recently_emitted"].size() <= 50)
	_check("event_counts tracked", info["event_counts"].get(EventBus.STATE_CHANGED) == 10000 + 2)
	for c in EventBus._subscribers.get(EventBus.STATE_CHANGED, {}).duplicate():
		EventBus.unsubscribe(EventBus.STATE_CHANGED, EventBus._subscribers[EventBus.STATE_CHANGED][c])

	## 9. Listener accumulation after subscribe/unsubscribe churn --------------
	var base: Variant = EventBus.get_debug_info().get("current_listeners")
	for i in 500:
		EventBus.subscribe(EventBus.SETTING_CHANGED, func(p): pass)
		EventBus.unsubscribe(EventBus.SETTING_CHANGED, EventBus._subscribers[EventBus.SETTING_CHANGED].values()[0])
	var final: Variant = EventBus.get_debug_info().get("current_listeners")
	_check("no listener accumulation after churn", final <= base + 2)

	## 10. Unknown event emit / invalid payload --------------------------------
	EventBus.emit(&"nonexistent_event", {})
	EventBus.emit(EventBus.STATE_CHANGED, {})
	EventBus.emit(EventBus.STATE_CHANGED)
	_check("unknown event + empty payload safe", true)

	print("[VERIFY] DONE eventbus_stress fails=%d -> %s" % [_fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[VERIFY] PASS %s" % label)
	else:
		_fails += 1
		printerr("[VERIFY] FAIL %s" % label)
