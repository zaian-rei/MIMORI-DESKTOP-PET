extends "res://core/base/pet_component.gd"
class_name EmotionComponent

## Coherent emotional state derived from the pet's stats (and music). The
## pet's visible expressions are the THINK/HAPPY/SAD quirk animations, and
## this component biases which one the BehaviorController flashes so the
## quirk actually matches how the pet is feeling instead of being random.

signal emotion_changed(previous: Emotion, current: Emotion)

enum Emotion { CONTENT, HAPPY, SAD, SLEEPY, BORED, EXCITED }

const EVAL_INTERVAL_SECONDS := 3.0

const EMOTION_NAMES := {
	Emotion.CONTENT: &"content",
	Emotion.HAPPY: &"happy",
	Emotion.SAD: &"sad",
	Emotion.SLEEPY: &"sleepy",
	Emotion.BORED: &"bored",
	Emotion.EXCITED: &"excited",
}

var current_emotion: Emotion = Emotion.CONTENT

var _stats: PetStats
var _timer := 0.0


func on_initialized() -> void:
	_stats = pet.get_component(BehaviorStatsComponent).get_stats()
	_timer = EVAL_INTERVAL_SECONDS
	LoggerGlobal.info("EmotionComponent initialized.")


func get_emotion() -> Emotion:
	return current_emotion


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = EVAL_INTERVAL_SECONDS
	_recompute()


func _recompute() -> void:
	var new_emotion := _evaluate()
	if new_emotion == current_emotion:
		return
	var previous := current_emotion
	current_emotion = new_emotion
	emotion_changed.emit(previous, current_emotion)
	LoggerGlobal.debug("Emotion: %s" % EMOTION_NAMES[current_emotion])


func _evaluate() -> Emotion:
	if MusicService.is_playing():
		return Emotion.EXCITED
	if _stats.get_value(PetStats.Stat.SLEEPINESS) >= 70.0:
		return Emotion.SLEEPY
	if _stats.get_value(PetStats.Stat.HAPPINESS) >= 65.0:
		return Emotion.HAPPY
	if _stats.get_value(PetStats.Stat.HAPPINESS) <= 35.0:
		return Emotion.SAD
	if _stats.get_value(PetStats.Stat.BOREDOM) >= 70.0:
		return Emotion.BORED
	return Emotion.CONTENT


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"emotion": EMOTION_NAMES.get(current_emotion, &"unknown"),
		"emotion_index": current_emotion,
		"eval_interval_seconds": EVAL_INTERVAL_SECONDS,
	}
