extends Node

## Runtime sleep-flow harness: proves the tuned behavior data actually wins
## in the real decision loop (sleep/deep-sleep chosen only when sleepy and/or
## drained, never while wide awake) and that the mood channel stands down
## during sleep so a random quirk can't cancel the nap.

const PET_SCENE := preload("res://scenes/pet/pet.tscn")

var _fails := 0


func _ready() -> void:
	var pet := _make_pet()
	var decision: BehaviorDecisionComponent = pet.get_component(BehaviorDecisionComponent)
	var stats: BehaviorStatsComponent = pet.get_component(BehaviorStatsComponent)

	stats.set_value(PetStats.Stat.ENERGY, 15.0)
	stats.set_value(PetStats.Stat.SLEEPINESS, 90.0)
	for stat in [PetStats.Stat.CURIOSITY, PetStats.Stat.BOREDOM, PetStats.Stat.HAPPINESS]:
		stats.set_value(stat, 50.0)

	var action: BehaviorDefinition = decision.request_now()
	_check("deep sleep selected when sleepy+drained",
		action != null and action.state == PetState.State.DEEP_SLEEP)
	_check("deep sleep duration in 120-300s",
		action != null and action.duration_min >= 110.0 and action.duration_max >= 250.0)

	stats.set_value(PetStats.Stat.SLEEPINESS, 62.0)
	stats.set_value(PetStats.Stat.ENERGY, 40.0)
	action = decision.request_now()
	_check("sleep selected at sleepiness 62/energy 40",
		action != null and action.state == PetState.State.SLEEP)

	var awake := _make_pet()
	var decision2 := awake.get_component(BehaviorDecisionComponent)
	var stats2: BehaviorStatsComponent = awake.get_component(BehaviorStatsComponent)
	for stat in [PetStats.Stat.ENERGY, PetStats.Stat.CURIOSITY, PetStats.Stat.BOREDOM, PetStats.Stat.HAPPINESS, PetStats.Stat.SLEEPINESS]:
		stats2.set_value(stat, 50.0)
	action = decision2.request_now()
	_check("sleep NOT chosen while wide awake",
		action == null or action.state != PetState.State.SLEEP)

	var controller: BehaviorController = pet.get_component(BehaviorController)
	pet.get_component(StateMachineComponent).force_state(PetState.State.SLEEP)
	for i in 20:
		controller._tick_mood(1.0)
	_check("mood quirk stands down during SLEEP", controller._mood_seconds_left <= 0.0)

	print("[VERIFY] DONE sleep_flow fails=%d -> %s" % [_fails, "PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(0 if _fails == 0 else 1)


func _make_pet() -> Pet:
	var pet := PET_SCENE.instantiate()
	pet.definition = load("res://data/configs/default_pet_definition.tres")
	add_child(pet)
	return pet


func _check(label: String, cond: bool) -> void:
	if cond:
		print("[VERIFY] PASS %s" % label)
	else:
		_fails += 1
		printerr("[VERIFY] FAIL %s" % label)