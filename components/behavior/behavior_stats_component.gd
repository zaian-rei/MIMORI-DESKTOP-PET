extends "res://core/base/pet_component.gd"
class_name BehaviorStatsComponent

## Owns the pet's internal needs (a PetStats instance) and is the single
## gateway for reading and mutating them. Every frame the passive drift is
## applied; every value change - drift, behavior effects, interactions,
## future systems - emits a typed signal plus `stats_updated` so other
## systems react without polling.
##
## Save/restore delegates to ConfigService (the existing storage layer), so
## there is exactly one save path and no duplicated save logic. Mutations
## only ever enter through this component so signals can't be bypassed.

signal energy_changed(new_value: float)
signal happiness_changed(new_value: float)
signal curiosity_changed(new_value: float)
signal boredom_changed(new_value: float)
signal sleepiness_changed(new_value: float)
signal stats_updated

const AUTOSAVE_SECONDS := 30.0

## The pet's stats. Read via get_stats()/get_*(); never mutate directly.
var stats := PetStats.new()

var personality_component: PersonalityComponent


func on_initialized() -> void:
	personality_component = pet.get_component(PersonalityComponent)
	_restore_stats()
	_start_autosave()
	LoggerGlobal.info("BehaviorStatsComponent initialized.")


## Applies passive drift and reports any stat that actually moved.
func _process(delta: float) -> void:
	if pet == null or not enabled:
		return

	var before := {}
	for stat in PetStats.Stat.values():
		before[stat] = stats.get_value(stat)

	var drift_scales := {}
	if personality_component != null:
		for stat in PetStats.Stat.values():
			drift_scales[stat] = personality_component.get_stat_scale_for(stat)

	stats.tick(delta, drift_scales)

	var changed := false
	for stat in PetStats.Stat.values():
		var now := stats.get_value(stat)
		if not is_equal_approx(before[stat], now):
			changed = true
			_emit_stat_changed(stat, now)
	if changed:
		stats_updated.emit()


## --- Reads ----------------------------------------------------------------

func get_stats() -> PetStats:
	return stats


func get_value(stat: int) -> float:
	return stats.get_value(stat)


func get_energy() -> float:
	return stats.get_value(PetStats.Stat.ENERGY)


func get_happiness() -> float:
	return stats.get_value(PetStats.Stat.HAPPINESS)


func get_curiosity() -> float:
	return stats.get_value(PetStats.Stat.CURIOSITY)


func get_boredom() -> float:
	return stats.get_value(PetStats.Stat.BOREDOM)


func get_sleepiness() -> float:
	return stats.get_value(PetStats.Stat.SLEEPINESS)


## --- Metadata -------------------------------------------------------------

func get_stat_min(stat: int) -> float:
	return stats.get_min(stat)


func get_stat_max(stat: int) -> float:
	return stats.get_max(stat)


func get_stat_default(stat: int) -> float:
	return stats.get_default(stat)


## --- Writes (clamped; emit change signals) --------------------------------

func set_value(stat: int, value: float) -> void:
	var before := stats.get_value(stat)
	stats.set_value(stat, value)
	_emit_if_changed(before, stat)


func add(stat: int, amount: float) -> void:
	var before := stats.get_value(stat)
	stats.add(stat, amount)
	_emit_if_changed(before, stat)


## Applies Stat -> per-second change from an active behavior. Stat changes
## are scaled by the active personality's stat economy modifiers.
func apply_effects(effects: Dictionary, delta: float) -> void:
	for stat in effects:
		var amount := float(effects[stat]) * delta
		if personality_component != null:
			amount *= personality_component.get_stat_scale_for(stat)
		add(stat, amount)


## --- Save / restore --------------------------------------------------------

func _restore_stats() -> void:
	if ConfigService.has_saved_stats and not ConfigService.pet_stats.is_empty():
		stats.from_dict(ConfigService.pet_stats)


func _start_autosave() -> void:
	var timer := Timer.new()
	timer.wait_time = AUTOSAVE_SECONDS
	timer.autostart = true
	timer.timeout.connect(_save_stats)
	add_child(timer)


func _save_stats() -> void:
	ConfigService.save_stats(stats.to_dict())


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_stats()


## --- Internals -------------------------------------------------------------

func _emit_if_changed(before: float, stat: int) -> void:
	var now := stats.get_value(stat)
	if is_equal_approx(before, now):
		return
	_emit_stat_changed(stat, now)
	stats_updated.emit()


func _emit_stat_changed(stat: int, new_value: float) -> void:
	match stat:
		PetStats.Stat.ENERGY:
			energy_changed.emit(new_value)
		PetStats.Stat.HAPPINESS:
			happiness_changed.emit(new_value)
		PetStats.Stat.CURIOSITY:
			curiosity_changed.emit(new_value)
		PetStats.Stat.BOREDOM:
			boredom_changed.emit(new_value)
		PetStats.Stat.SLEEPINESS:
			sleepiness_changed.emit(new_value)


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	var drift_scales := {}
	if personality_component != null:
		for stat in PetStats.Stat.values():
			drift_scales[PetStats.Stat.keys()[stat]] = personality_component.get_stat_scale_for(stat)
	return {
		"energy": get_energy(),
		"happiness": get_happiness(),
		"curiosity": get_curiosity(),
		"boredom": get_boredom(),
		"sleepiness": get_sleepiness(),
		"drift_scales": drift_scales,
		"autosave_seconds": AUTOSAVE_SECONDS,
	}
