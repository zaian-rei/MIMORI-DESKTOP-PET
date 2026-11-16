extends SceneTree


func _run_checks() -> bool:
	var failures: Array[String] = []
	var by_state := {}
	var dir := DirAccess.open("res://data/behaviors/")
	if dir == null:
		failures.append("could not open data/behaviors/")
		return false
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var behavior := load("res://data/behaviors/".path_join(file)) as BehaviorDefinition
		if behavior != null:
			by_state[behavior.state] = behavior

	var sleep: BehaviorDefinition = by_state.get(8)
	var deep: BehaviorDefinition = by_state.get(12)
	if sleep == null or deep == null:
		failures.append("sleep/deep_sleep definitions missing from catalog")

	if sleep != null:
		if sleep.duration_min < 55.0 or sleep.duration_max < 100.0:
			failures.append("sleep durations not in 60-120s range: min=%f max=%f" % [sleep.duration_min, sleep.duration_max])
		if not sleep.stat_effects.has(4):
			failures.append("sleep does not restore sleepiness (stat 4)")
		if sleep.stat_effects.get(0, 0.0) <= 0.0:
			failures.append("sleep does not restore energy (stat 0)")
	if deep != null:
		if deep.duration_min < 110.0 or deep.duration_max < 250.0:
			failures.append("deep sleep durations not in 120-300s range: min=%f max=%f" % [deep.duration_min, deep.duration_max])
		if deep.stat_gates.get(4, 0.0) < 80.0 or deep.stat_maxes.get(0, 101.0) > 35.0:
			failures.append("deep sleep gates wrong (want sleepiness>=85, energy<=30)")
		if deep.stat_effects.get(0, 0.0) <= sleep.stat_effects.get(0, 0.0):
			failures.append("deep sleep should restore energy faster than sleep")

	var walk: BehaviorDefinition = by_state.get(1)
	if walk != null:
		if walk.stat_effects.get(0, 0.0) >= 0.0:
			failures.append("walk should drain energy (stat 0)")
		if walk.stat_effects.get(4, 0.0) <= 0.0:
			failures.append("walk should raise sleepiness (stat 4)")

	if failures.is_empty():
		print("[VERIFY] behavior tuning: PASS")
	else:
		for f in failures:
			print("[VERIFY] FAIL: %s" % f)
	return failures.is_empty()


func _initialize() -> void:
	var ok := _run_checks()
	print("[VERIFY] behavior_tuning=%s" % ("PASS" if ok else "FAIL"))
	quit(0 if ok else 1)
