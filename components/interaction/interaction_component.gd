extends "res://core/base/pet_component.gd"
class_name InteractionComponent

## The pet's social life: it reacts to being poked, can be fed from the
## context menu, and notices the cursor when it lingers nearby - walking
## over to investigate like a curious pet. All reactions lock autonomy so
## the decision brain can't fight them, then hand control back.

const NOTICE_INTERVAL_SECONDS := 0.6
const NOTICE_RADIUS := 320.0
const REACH_RADIUS := 40.0
const FOLLOW_TIMEOUT_SECONDS := 2.5
const FOLLOW_COOLDOWN_SECONDS := 3.0

const POKE_HAPPINESS := 8.0
const POKE_BOREDOM := -6.0
const FEED_ENERGY := 15.0
const FEED_HAPPINESS := 10.0

const REACTION_SECONDS := 1.2

var drag_component: DragComponent
var movement_component: MovementComponent
var behavior_controller: BehaviorController
var stats_component: BehaviorStatsComponent
var context_menu: ContextMenuComponent
var state_machine: StateMachineComponent
var awareness: DesktopAwarenessComponent

var _following_cursor := false
var _follow_timeout := 0.0
var _notice_timer := 0.0
var _follow_cooldown := 0.0


func on_initialized() -> void:
	drag_component = pet.get_component(DragComponent)
	movement_component = pet.get_component(MovementComponent)
	behavior_controller = pet.get_component(BehaviorController)
	stats_component = pet.get_component(BehaviorStatsComponent)
	context_menu = pet.get_component(ContextMenuComponent)
	state_machine = pet.get_component(StateMachineComponent)
	awareness = pet.get_component(DesktopAwarenessComponent)
	EventBus.subscribe(EventBus.PET_CLICKED, _on_pet_clicked_event)
	_notice_timer = NOTICE_INTERVAL_SECONDS
	LoggerGlobal.info("InteractionComponent initialized.")


## Feeding: a positive interaction that restores energy and happiness and
## plays a short happy reaction.
func feed() -> void:
	stats_component.add(PetStats.Stat.ENERGY, FEED_ENERGY)
	stats_component.add(PetStats.Stat.HAPPINESS, FEED_HAPPINESS)
	LoggerGlobal.debug("Pet fed.")
	_play_reaction(PetState.State.HAPPY, REACTION_SECONDS)


func _on_pet_clicked_event(_payload: Dictionary) -> void:
	stats_component.add(PetStats.Stat.HAPPINESS, POKE_HAPPINESS)
	stats_component.add(PetStats.Stat.BOREDOM, POKE_BOREDOM)
	LoggerGlobal.debug("Pet poked.")
	_play_reaction(PetState.State.HAPPY, REACTION_SECONDS)


## Locks the brain, plays the reaction state for a fixed time, then returns
## the pet to idle and asks the brain to reconsider.
func _play_reaction(state: PetState.State, seconds: float) -> void:
	_end_follow()
	behavior_controller.autonomy_locked = true
	state_machine.request_state(state, StatePriority.Level.NORMAL)
	get_tree().create_timer(seconds).timeout.connect(
		func():
			behavior_controller.autonomy_locked = false
			if state_machine.get_state() == state:
				state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
			behavior_controller.kick_decision()
	)


func _process(_delta: float) -> void:
	_tick_cursor()


func _tick_cursor() -> void:
	if drag_component.dragging:
		_end_follow()
		return

	if _following_cursor:
		_continue_follow()
		return

	if _follow_cooldown > 0.0:
		_follow_cooldown -= get_process_delta_time()

	_notice_timer -= get_process_delta_time()
	if _notice_timer <= 0.0:
		_notice_timer = NOTICE_INTERVAL_SECONDS
		_try_notice_cursor()


func _try_notice_cursor() -> void:
	if _follow_cooldown > 0.0 or not _can_interact():
		return
	var cursor := awareness.cursor_position()
	## Reachable when the cursor sits on this or any adjacent monitor: the
	## pet can walk across display edges to get there.
	if not awareness.can_move_toward(cursor):
		return
	if cursor.distance_to(pet.world_position) > NOTICE_RADIUS:
		return
	_start_follow(cursor)


func _start_follow(cursor: Vector2) -> void:
	_following_cursor = true
	_follow_timeout = FOLLOW_TIMEOUT_SECONDS
	behavior_controller.autonomy_locked = true
	movement_component.set_following_cursor(true)
	_update_heading(cursor)
	state_machine.request_state(PetState.State.WALK, StatePriority.Level.NORMAL)
	EventBus.emit(EventBus.CURSOR_FOLLOW_STARTED)


func _continue_follow() -> void:
	var cursor := awareness.cursor_position()
	_follow_timeout -= get_process_delta_time()
	if _follow_timeout <= 0.0 or cursor.distance_to(pet.world_position) <= REACH_RADIUS:
		_end_follow()
		return
	_update_heading(cursor)
	if state_machine.get_state() != PetState.State.WALK:
		state_machine.request_state(PetState.State.WALK, StatePriority.Level.NORMAL)


func _update_heading(cursor: Vector2) -> void:
	var dx := cursor.x - pet.world_position.x
	if absf(dx) > REACH_RADIUS:
		movement_component.direction = 1 if dx > 0.0 else -1


func _end_follow() -> void:
	if not _following_cursor:
		return
	_following_cursor = false
	_follow_cooldown = FOLLOW_COOLDOWN_SECONDS
	behavior_controller.autonomy_locked = false
	movement_component.set_following_cursor(false)
	if state_machine.get_state() == PetState.State.WALK:
		state_machine.request_state(PetState.State.IDLE, StatePriority.Level.NORMAL)
	behavior_controller.kick_decision()


## True while the pet is free to be social: not being dragged or manually
## driven, not mid-air or asleep, and not under Follow Cursor Mode (which
## already steers the pet toward the cursor - a second curiosity follow
## would fight it).
func _can_interact() -> bool:
	if drag_component.dragging:
		return false
	if context_menu.manual_override_active:
		return false
	if state_machine.get_state() in [PetState.State.FALL, PetState.State.JUMP, PetState.State.LAND, PetState.State.DRAG, PetState.State.SLEEP, PetState.State.DEEP_SLEEP]:
		return false
	var follow_component := pet.get_component(FollowCursorComponent) as FollowCursorComponent
	if follow_component != null and follow_component.is_follow_enabled():
		return false
	return true
