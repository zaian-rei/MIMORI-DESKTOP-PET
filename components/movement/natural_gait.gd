class_name NaturalGait
extends RefCounted

## Leg-based gait planner used by MovementComponent. Pure logic - no nodes,
## no state transitions, no stats/memory reads. Given a MovementSettings
## resource it turns "the pet is walking in this direction" into a smooth
## stream of speeds:
##
##   hesitate -> accelerate -> cruise -> ease to a stop -> pause -> turn
##
## Every walk is assembled from randomized legs (travel distance, cruise
## speed, hesitations, pauses, spontaneous turns), so movement feels
## intentional and never repeats exactly. All tuning comes from the settings
## resource - this class carries no hardcoded values.
##
## Movement Polish integration: update()/direct()/stop() accept an optional
## `profiles` dictionary whose keys override the settings defaults for that
## call only (walk/run acceleration & deceleration, turn deceleration, max
## turn speed, arrival ramp tuning). An empty dict - or a missing key - is
## byte-for-byte the original behavior, so the polish system layers on top
## without ever rewriting the planner.

enum Phase {
	STOPPED,
	HESITATE,
	MOVE,
	DECEL,
	PAUSE,
	TURN,
}

## Below this speed the pet is considered stopped (avoids sub-pixel crawl).
const STOP_EPSILON := 2.0

## Resolved profile values for the current call (mirror MovementSettings
## when a key is absent).
var _accel := -1.0
var _decel := -1.0
var _turn_decel := -1.0
var _max_turn_speed := -1.0
var _arrival_distance := -1.0
var _arrival_decel := -1.0
var _arrival_radius := 0.0
var _arrival_settle := 0.0

var settings: MovementSettings

var phase: int = Phase.STOPPED
var direction: int = 1

## Current signed x-speed applied to the pet (px/s).
var speed: float = 0.0

## Cruise speed planned for the active leg (px/s, magnitude).
var cruise_speed: float = 0.0

## Distance planned for the active leg and how much of it has been covered.
var leg_distance: float = 0.0
var leg_traveled: float = 0.0

var phase_timer: float = 0.0

var _edge_stop := false

## True while easing into an edge-triggered flowing turn (carries max_turn_speed
## through the turn pause instead of stopping dead).
var _flowing_turn := false

## Small settling beat at the destination before the next leg/pause/turn.
var _settling := false
var _settle_left := 0.0


func _init(cfg: MovementSettings) -> void:
	settings = cfg


## Begins a natural walk in `dir` at the pet's base speed. Resets any
## previous leg/pause state so every walk starts fresh (with a small
## hesitation before the first step).
func start_walk(dir: int, base_speed: float) -> void:
	direction = dir
	speed = 0.0
	leg_traveled = 0.0
	_edge_stop = false
	_flowing_turn = false
	_settling = false
	_settle_left = 0.0
	_plan_leg(base_speed)
	phase = Phase.HESITATE
	phase_timer = randf_range(settings.hesitation_duration_min, settings.hesitation_duration_max)


## Advances the gait and returns the desired signed x-velocity for this
## frame. `base_speed` is re-read every frame so live settings changes
## propagate to newly-planned legs. `at_left_edge`/`at_right_edge` tell the
## planner when the pet is up against a real screen edge so it eases to a
## stop and turns instead of walking into the void. `profiles` (optional)
## overrides acceleration/deceleration/turn/arrival tuning for this call.
func update(
	delta: float,
	base_speed: float,
	at_left_edge: bool,
	at_right_edge: bool,
	profiles: Dictionary = {}
) -> float:
	_resolve_profiles(profiles)
	var blocked := _is_blocked(at_left_edge, at_right_edge)
	## Degenerate geometry (zero-size window, no monitor): nowhere to go.
	var blocked_both := at_left_edge and at_right_edge

	match phase:
		Phase.HESITATE:
			speed = _approach(0.0, _decel, delta)
			phase_timer -= delta
			if phase_timer <= 0.0:
				if blocked_both:
					## No room in either direction - wait instead of spinning
					## in place forever. A real screen never reports this.
					phase_timer = randf_range(settings.hesitation_duration_min, settings.hesitation_duration_max)
				elif blocked:
					_begin_turn()
				else:
					phase = Phase.MOVE
		Phase.MOVE:
			if blocked:
				_edge_stop = true
				phase = Phase.DECEL
			elif _arrival_distance > 0.0:
				_tick_arrival_leg(delta)
			elif _reached_braking_point():
				phase = Phase.DECEL
			else:
				speed = _approach(cruise_speed, _accel, delta)
				leg_traveled += speed * delta
				if leg_traveled >= leg_distance:
					phase = Phase.DECEL
		Phase.DECEL:
			if _edge_stop and _max_turn_speed >= 0.0:
				## Flowing edge turn: ease down to a comfortable turn speed
				## (never accelerating toward the edge), then sweep around
				## while shuffling forward.
				var turn_target := minf(_max_turn_speed, speed)
				speed = _approach(turn_target, _turn_decel, delta)
				if speed <= _max_turn_speed + STOP_EPSILON:
					speed = minf(_max_turn_speed, speed)
					_edge_stop = false
					_begin_turn(true)
			else:
				var rate := _turn_decel if _edge_stop else _decel
				speed = _approach(0.0, rate, delta)
				leg_traveled += speed * delta
				if speed <= STOP_EPSILON:
					speed = 0.0
					if _edge_stop:
						_edge_stop = false
						if blocked_both:
							phase = Phase.STOPPED
						else:
							_begin_turn()
					elif _settling:
						_settle_left -= delta
						if _settle_left <= 0.0:
							_settling = false
							_on_leg_complete(base_speed)
					elif _arrival_settle > 0.0:
						_settling = true
						_settle_left = _arrival_settle
					else:
						_on_leg_complete(base_speed)
		Phase.PAUSE:
			speed = 0.0
			phase_timer -= delta
			if phase_timer <= 0.0:
				_on_leg_complete(base_speed)
		Phase.TURN:
			if _flowing_turn:
				## Keep the reduced turn speed through the pause - a shuffle,
				## not a full stop.
				speed = _approach(_max_turn_speed, _turn_decel, delta)
			else:
				speed = _approach(0.0, _turn_decel, delta)
			phase_timer -= delta
			if phase_timer <= 0.0:
				_end_turn(base_speed)

	return direction * speed


## Eases the current speed toward a fixed target (used for manual walk/run,
## jumps and cursor-follow, where leg/pause/turn behavior is unwanted).
func direct(dir: int, target_speed: float, delta: float, profiles: Dictionary = {}) -> float:
	_resolve_profiles(profiles)
	direction = dir
	if target_speed >= speed:
		speed = _approach(target_speed, _accel, delta)
	else:
		speed = _approach(target_speed, _decel, delta)
	return direction * speed


## Brakes to a stop (used whenever the pet leaves walking: state changes,
## mood, sleep, manual non-walk). Returns the signed easing velocity so the
## pet glides a few pixels instead of snapping.
func stop(delta: float, profiles: Dictionary = {}) -> float:
	_resolve_profiles(profiles)
	speed = _approach(0.0, _decel, delta)
	if speed <= STOP_EPSILON:
		speed = 0.0
		phase = Phase.STOPPED
	return direction * speed


## Instantly zeroes the gait (drag grab, hard interruption).
func hard_stop() -> void:
	speed = 0.0
	leg_traveled = 0.0
	phase = Phase.STOPPED
	_edge_stop = false
	_flowing_turn = false
	_settling = false
	_settle_left = 0.0


## --- Internals -------------------------------------------------------------

## Resolves the profile overrides for this call; absent keys fall back to the
## settings resource (the exact original behavior).
func _resolve_profiles(profiles: Dictionary) -> void:
	_accel = profiles.get("accel", -1.0)
	_decel = profiles.get("decel", -1.0)
	_turn_decel = profiles.get("turn_decel", -1.0)
	_max_turn_speed = profiles.get("max_turn_speed", -1.0)
	_arrival_distance = profiles.get("arrival_slowdown_distance", -1.0)
	_arrival_decel = profiles.get("arrival_decel", -1.0)
	_arrival_radius = profiles.get("arrival_radius", 0.0)
	_arrival_settle = profiles.get("arrival_settle_delay", 0.0)
	if _accel < 0.0:
		_accel = settings.acceleration
	if _decel < 0.0:
		_decel = settings.deceleration
	if _turn_decel < 0.0:
		_turn_decel = settings.deceleration
	if _arrival_decel < 0.0:
		_arrival_decel = settings.deceleration


func _is_blocked(at_left_edge: bool, at_right_edge: bool) -> bool:
	if direction > 0:
		return at_right_edge
	return at_left_edge


func _plan_leg(base_speed: float) -> void:
	cruise_speed = base_speed * randf_range(1.0 - settings.speed_variation, 1.0 + settings.speed_variation)
	leg_distance = randf_range(settings.min_travel_distance, settings.max_travel_distance)
	leg_traveled = 0.0
	_settling = false
	_settle_left = 0.0


## Arrival-smoothed leg advance: target speed scales with the remaining
## distance (full cruise far out, gliding down to a stop at the destination),
## so the pet slows naturally instead of hitting a braking wall.
func _tick_arrival_leg(delta: float) -> void:
	var remaining := leg_distance - leg_traveled
	if remaining <= _arrival_radius:
		speed = 0.0
		phase = Phase.DECEL
		return
	var target := cruise_speed * clampf(remaining / _arrival_distance, 0.0, 1.0)
	speed = _approach(target, _accel if target >= speed else _arrival_decel, delta)
	leg_traveled += speed * delta
	if leg_traveled >= leg_distance:
		phase = Phase.DECEL


## True once the remaining leg distance fits inside the current braking
## distance, so the pet eases to a stop at its destination instead of
## overshooting. Only used when arrival smoothing is inactive.
func _reached_braking_point() -> bool:
	var remaining := leg_distance - leg_traveled
	var brake_dist := (speed * speed) / (2.0 * _decel)
	return remaining <= brake_dist


## Decides what comes after a leg finishes (or a pause ends): roll for a
## pause, a spontaneous turn, or roll straight into the next leg.
func _on_leg_complete(base_speed: float) -> void:
	if randf() < settings.pause_chance:
		phase = Phase.PAUSE
		phase_timer = randf_range(settings.pause_duration_min, settings.pause_duration_max)
		return
	if randf() < settings.direction_change_chance:
		_begin_turn()
		return
	_plan_leg(base_speed)
	phase = Phase.MOVE


## Brief stand-still before actually flipping direction. `flowing` marks an
## edge-triggered turn that carries max_turn_speed through the pause instead
## of stopping dead.
func _begin_turn(flowing := false) -> void:
	_flowing_turn = flowing
	phase = Phase.TURN
	phase_timer = randf_range(settings.turn_delay_min, settings.turn_delay_max)


## The turn delay elapsed: flip, then hesitate briefly before stepping off.
func _end_turn(base_speed: float) -> void:
	direction = -direction
	_flowing_turn = false
	_plan_leg(base_speed)
	phase = Phase.HESITATE
	phase_timer = randf_range(settings.hesitation_duration_min, settings.hesitation_duration_max)


## Approaches `target` (magnitude) at `rate` px/s^2, clamped so it never
## overshoots. Returns the new speed.
func _approach(target: float, rate: float, delta: float) -> float:
	if is_equal_approx(speed, target):
		return speed
	var diff := target - speed
	var step := rate * delta
	if absf(diff) <= step:
		return target
	return speed + signf(diff) * step
