extends "res://core/base/pet_component.gd"
class_name AudioEventComponent

## The pet's audio integration point. Translates engine events into audio
## requests through the global AudioManager - it never plays a sound itself,
## and it keeps AudioManager pure (the manager never decides what to play).
##
## Responsibilities:
##   - register the pet's AudioPack (from PetDefinition) with the AudioManager
##   - map state machine transitions to event ids (walk/run/jump/land/sleep/
##     think/happy/sad/dance/drag)
##   - while the pet walks/runs/is dragged, keep requesting the event so the
##     AudioManager's per-event cooldown paces a rhythm (footsteps at max
##     frequency) instead of a single sound on state entry
##   - translate Follow Cursor Mode toggles into audio events
##
## Events without a definition in the active pack simply play nothing - adding
## a new behavior's sound is a data change (a new AudioSound in the pack), not
## a code change.

const STATE_EVENTS := {
	PetState.State.WALK: &"walk",
	PetState.State.RUN: &"run",
	PetState.State.JUMP: &"jump",
	PetState.State.LAND: &"land",
	PetState.State.SLEEP: &"sleep",
	PetState.State.DEEP_SLEEP: &"sleep",
	PetState.State.THINK: &"think",
	PetState.State.HAPPY: &"happy",
	PetState.State.SAD: &"sad",
	PetState.State.DANCE: &"dance",
	PetState.State.DRAG: &"drag",
}

var state_machine: StateMachineComponent


func on_initialized() -> void:
	state_machine = pet.get_component(StateMachineComponent)
	if pet.definition != null and pet.definition.audio_pack != null:
		AudioManager.set_active_pack(pet.definition.audio_pack)
	EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)
	var follow := pet.get_component(FollowCursorComponent) as FollowCursorComponent
	if follow != null:
		EventBus.subscribe(EventBus.CURSOR_FOLLOW_ENABLED, _on_follow_enabled_event)
		EventBus.subscribe(EventBus.CURSOR_FOLLOW_DISABLED, _on_follow_disabled_event)
	LoggerGlobal.info("AudioEventComponent initialized.")


func _on_state_changed_event(payload: Dictionary) -> void:
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	var event: StringName = STATE_EVENTS.get(new_state, &"")
	if event != &"":
		AudioManager.play_event(event)


func _on_follow_enabled_event(_payload: Dictionary) -> void:
	AudioManager.play_event(&"follow_cursor_enabled")


func _on_follow_disabled_event(_payload: Dictionary) -> void:
	AudioManager.play_event(&"follow_cursor_disabled")


func _physics_process(_delta: float) -> void:
	## Continuous events: re-request each frame while the pet walks/runs/is
	## dragged. The AudioManager's cooldown is the source of truth for how
	## often a sound may play, so this yields a paced rhythm (footsteps)
	## without duplicating cooldown knowledge here.
	var state := state_machine.get_state()
	if state == PetState.State.WALK:
		AudioManager.play_event(&"walk")
	elif state == PetState.State.RUN:
		AudioManager.play_event(&"run")
	elif state == PetState.State.DRAG:
		AudioManager.play_event(&"drag")


## --- Debug support ---------------------------------------------------------

## Which event id (if any) the given pet state maps to. Lets the future debug
## overlay explain why a state change did or didn't produce audio.
func get_event_for_state(state: PetState.State) -> StringName:
	return STATE_EVENTS.get(state, &"")


func get_debug_info() -> Dictionary:
	return {
		"state_event_map": STATE_EVENTS,
		"active_pack": AudioManager.get_debug_info().get("active_pack", ""),
	}
