extends "res://core/base/pet_component.gd"
class_name AnimationComponent

const LAND_ANIMATION_PROTECTION_SECONDS := 0.4
const DefaultMovementSettings := preload("res://data/configs/movement_settings.tres")


const SPEED_SCALE_MIN := 0.1
const SPEED_SCALE_MAX := 3.0

var controller: AnimationController
var manager: AnimationTransitionManager
var sprite: AnimatedSprite2D
var state_machine: StateMachineComponent

var movement_settings: MovementSettings


var _last_speed_scale := 1.0

func on_initialized() -> void:
	sprite = pet.sprite
	state_machine = pet.get_component(StateMachineComponent)
	movement_settings = pet.definition.movement_settings if pet.definition.movement_settings != null else DefaultMovementSettings
	controller = pet.get_component(AnimationController)
	manager = pet.get_component(AnimationTransitionManager)
	EventBus.subscribe(EventBus.STATE_CHANGED, _on_state_changed_event)

	LoggerGlobal.info("AnimationComponent initialized.")


func _process(_delta: float) -> void:
	if sprite == null or state_machine == null:
		return
	var target := 1.0
	var state := state_machine.get_state()
	if state == PetState.State.WALK or state == PetState.State.RUN:
		var design := _design_speed_for(state)
		if design > 0.0:
			target = clampf(absf(pet.velocity.x) / design, SPEED_SCALE_MIN, SPEED_SCALE_MAX)
	if not is_equal_approx(target, _last_speed_scale):
		sprite.speed_scale = target
		_last_speed_scale = target

func _design_speed_for(state: int) -> float:
	if state == PetState.State.RUN:
		return movement_settings.run_animation_design_speed
	return movement_settings.walk_animation_design_speed

func play(
	animation_name: String,
	priority: int = AnimationTransitionRules.SPECIAL_PRIORITY
) -> void:
	if sprite == null:
		LoggerGlobal.error("Sprite reference is null.")
		return

	if sprite.sprite_frames == null:
		LoggerGlobal.error("SpriteFrames is null.")
		return

	var resolved := PetRoster.resolve_animation(pet.profile_id, animation_name, sprite.sprite_frames)
	if resolved.is_empty():
		LoggerGlobal.warn("Animation '%s' is unavailable for %s." % [animation_name, pet.profile_id])
		return
	## Keep the transition manager in sync when a signature move or idle restore
	## is played directly; otherwise reconcile() replaces the one-shot next frame.
	## When the manager owns the sprite, a rejected request is final - never
	## bypass its permission check with a raw sprite.play().
	if manager != null:
		manager.play_external(resolved, priority)
		return
	sprite.play(resolved)

func stop() -> void:
	sprite.stop()

func _on_state_changed_event(payload: Dictionary) -> void:
	var new_state: PetState.State = payload.get("new_state", PetState.State.IDLE)
	_apply_animation_for_state(new_state)

func _apply_animation_for_state(state: PetState.State) -> void:
	var animation_name := BehaviorCatalog.get_animation_for_state(state)

	if state == PetState.State.LAND:
		var protection := manager.get_protection_seconds(state) if manager != null else LAND_ANIMATION_PROTECTION_SECONDS
		_route(state, animation_name, protection)
		get_tree().create_timer(protection).timeout.connect(
			func():
				if state_machine.get_state() == PetState.State.LAND:
					state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
		)
		return

	_route(state, animation_name)

func _route(state: PetState.State, animation_name: String, protection: float = 0.0) -> void:
	var resolved := PetRoster.resolve_animation(pet.profile_id, animation_name, sprite.sprite_frames)
	if resolved.is_empty():
		return
	if manager != null:
		manager.request(state, resolved)
	else:
		controller.play(sprite, resolved, protection)


## --- Debug support ---------------------------------------------------------

func get_debug_info() -> Dictionary:
	return {
		"animation": sprite.animation if sprite != null else "no sprite",
		"playing": sprite.is_playing() if sprite != null else false,
		"frame": sprite.frame if sprite != null else -1,
		"frame_count": sprite.sprite_frames.get_frame_count(sprite.animation) if sprite != null and sprite.sprite_frames != null else -1,
	}
