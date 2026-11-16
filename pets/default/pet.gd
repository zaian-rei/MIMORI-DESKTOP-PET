extends Node2D
class_name Pet

@export var definition: PetDefinition

## The pet's conceptual position in absolute desktop screen coordinates -
## this is the source of truth for where the pet actually is on the
## user's screen. Pet's own local Node2D position stays fixed at the
## center of its small window for its entire lifetime; all apparent
## movement comes from DesktopWindow repositioning the OS window itself
## to keep world_position centered on screen (see DesktopWindow).
var world_position: Vector2 = Vector2.ZERO

## Plain velocity used for simple arithmetic movement (gravity, walking).
## No CharacterBody2D/physics engine involved - there's no shared 2D
## world for the pet to collide within anymore, since each pet's own
## tiny window is its own isolated viewport.
var velocity: Vector2 = Vector2.ZERO

## The usable area of the current screen (excludes the menu bar/Dock
## where the OS reports it correctly), used for floor/boundary math. Set
## once by Bootstrap at startup.
var screen_bounds: Rect2i

## Set by Bootstrap right after creation. Lets components (e.g. the
## Settings menu item) reach the window-management system without a
## global singleton assuming there's only ever one pet.
var desktop_window: DesktopWindow

## Selected identity; animation clips are resolved from the matching profile.
var profile_id: String = "echo"
var _unscaled_size_cache: Vector2 = Vector2.ZERO
## Texture alpha bounds are cached per sprite frame so floor alignment uses
## the visible artwork edge rather than transparent padding in PNGs.
var _opaque_vertical_bounds_cache: Dictionary = {}
var _floor_reference_profile := ""
var _floor_reference_local_bottom := 0.0

@onready var visual: Node2D = $Visual
@onready var sprite: AnimatedSprite2D = $Visual/AnimatedSprite2D
@onready var components: Node = $Components
@onready var interaction_area: Area2D = $Interaction
@onready var click_polygon: Polygon2D = $ClickPolygon

func _ready() -> void:
	if definition == null:
		definition = PetDefinition.new()

	visual.scale = Vector2(definition.scale, definition.scale)

	_load_profile_sprites()
	_apply_sprite_pack()

	for component in components.get_children():
		if component.has_method("initialize"):
			component.initialize(self)

	get_component(StateMachineComponent).force_state(PetState.State.IDLE)
	var behavior := get_component(BehaviorController) as BehaviorController
	if behavior != null:
		behavior.play_startup_intro()

	EventBus.subscribe(EventBus.THEME_CHANGED, _on_theme_changed)

	LoggerGlobal.info("Pet created.")


## Finds a sibling component under the Components container by its type,
## instead of by a hardcoded scene tree path. Returns null if no matching
## component is present (same failure mode as a bad get_node path, so
## callers that previously assumed a component existed still behave the
## same way).
func get_component(component_type: Script) -> Node:
	for component in components.get_children():
		if is_instance_of(component, component_type):
			return component
	return null


## Applies the sprite_pack from the current definition to the AnimatedSprite2D.
## Falls back to the scene's baked-in sprites if no sprite_pack is set.
func _apply_sprite_pack() -> void:
	## Character artwork belongs to the selected pet. A UI theme may provide a
	## sprite pack for legacy pets, but must not replace these five identities.
	if PetRoster.get_profile(profile_id).is_empty() and definition != null and definition.sprite_pack != null:
		sprite.sprite_frames = definition.sprite_pack


func _configure_special_animations() -> void:
	if sprite.sprite_frames == null:
		return
	for move in PetRoster.get_special_animations(profile_id, sprite.sprite_frames):
		sprite.sprite_frames.set_animation_loop(str(move["animation"]), false)


func _load_profile_sprites() -> void:
	var frames := PetRoster.load_sprite_frames(profile_id)
	if frames == null:
		push_error("No animation frames found for pet: " + profile_id)
		return
	sprite.sprite_frames = frames.duplicate(true)
	_configure_special_animations()
	_unscaled_size_cache = Vector2.ZERO
	_opaque_vertical_bounds_cache.clear()
	_floor_reference_profile = ""


func set_profile(next_profile_id: String) -> void:
	var physics := get_component(PhysicsComponent) as PhysicsComponent
	profile_id = PetRoster.valid_id(next_profile_id)
	_load_profile_sprites()
	_floor_reference_profile = ""
	velocity = Vector2.ZERO
	var behavior := get_component(BehaviorController) as BehaviorController
	if behavior != null:
		behavior.reset_signature_moves()
	var state_machine := get_component(StateMachineComponent) as StateMachineComponent
	if state_machine != null:
		state_machine.force_state(PetState.State.IDLE)
	var animation := get_component(AnimationComponent) as AnimationComponent
	if animation != null:
		animation.play("idle", AnimationTransitionRules.get_priority(PetState.State.IDLE))
	if physics != null:
		physics.snap_to_ground()
	if behavior != null:
		behavior.play_startup_intro()


## Responds to theme changes at runtime. Updates the pet's visual identity
## without restarting.
func _on_theme_changed(_payload: Dictionary) -> void:
	_apply_sprite_pack()


## --- Rendered size ----------------------------------------------------------
## The pet's on-screen extent is data, not a fixed constant: it comes from
## the widest/tallest sprite frame across every animation in the active
## sprite pack, scaled by the pet's current scale. DesktopWindow sizes the
## window from this and every boundary check keeps this footprint on-screen.

const MIN_RENDERED_SIZE := 64.0

## Largest frame dimensions in the active sprite pack (unscaled px). Falls
## back to the definition's boundary margin so degenerate frames (no sprite
## pack, no animations) still produce a sane, never-zero size.
func get_unscaled_size() -> Vector2:
	if sprite == null or sprite.sprite_frames == null:
		return Vector2(boundary_margin(), boundary_margin())
	if _unscaled_size_cache != Vector2.ZERO:
		return _unscaled_size_cache
	var max_w := 0.0
	var max_h := 0.0
	var profile_prefix := profile_id.to_lower() + " "
	var filter_to_profile := not PetRoster.get_profile(profile_id).is_empty()
	for animation_name in sprite.sprite_frames.get_animation_names():
		if filter_to_profile and not animation_name.begins_with(profile_prefix):
			continue
		var count := sprite.sprite_frames.get_frame_count(animation_name)
		for i in count:
			var texture: Texture2D = sprite.sprite_frames.get_frame_texture(animation_name, i)
			if texture == null:
				continue
			max_w = maxf(max_w, texture.get_width())
			max_h = maxf(max_h, texture.get_height())
	_unscaled_size_cache = Vector2(maxf(max_w, MIN_RENDERED_SIZE), maxf(max_h, MIN_RENDERED_SIZE))
	return _unscaled_size_cache


## Rendered size in desktop pixels: largest frame scaled by the pet scale.
func get_rendered_size() -> Vector2:
	if sprite == null or visual == null:
		return get_unscaled_size() * Vector2(get_scale_factor(), get_scale_factor())
	var frame_size := get_unscaled_size() * sprite.scale.abs() * visual.scale.abs()
	var center_offset := (sprite.position + sprite.offset * sprite.scale) * visual.scale
	## The OS window is centered on the pet anchor. Include the sprite's
	## asymmetric local offset on both sides so the scaled artwork is never
	## clipped by its transparent window.
	return frame_size + center_offset.abs() * 2.0


## Distance from the pet's world-position anchor to the lowest visible sprite
## point, including the sprite's local offset and both scales.
func get_sprite_bottom_extent() -> float:
	if sprite == null or visual == null:
		return get_rendered_size().y * 0.5
	if _floor_reference_profile != profile_id:
		_cache_floor_reference_bottom()
	return maxf(_floor_reference_local_bottom * visual.scale.y, 0.0)


## Keep the ground anchor independent of the currently playing animation frame.
## Otherwise a pose with different transparent padding moves the calculated
## floor every frame, repeatedly triggering FALL and LAND while standing still.
func _cache_floor_reference_bottom() -> void:
	_floor_reference_profile = profile_id
	_floor_reference_local_bottom = sprite.position.y + sprite.offset.y * sprite.scale.y + get_unscaled_size().y * absf(sprite.scale.y) * 0.5
	if sprite.sprite_frames == null:
		return
	var idle_name := profile_id.to_lower() + " idle"
	var best_bottom := -INF
	for animation_name in sprite.sprite_frames.get_animation_names():
		if str(animation_name).to_lower() != idle_name:
			continue
		for frame_index in sprite.sprite_frames.get_frame_count(animation_name):
			var texture := sprite.sprite_frames.get_frame_texture(animation_name, frame_index)
			if texture == null:
				continue
			var bounds := _get_opaque_vertical_bounds(texture)
			var use_lower_texture_edge := (sprite.scale.y >= 0.0) != sprite.flip_v
			var edge_y := float(bounds.y if use_lower_texture_edge else bounds.x)
			var frame_bottom := sprite.position.y + sprite.offset.y * sprite.scale.y + (edge_y - float(texture.get_height()) * 0.5) * sprite.scale.y * (-1.0 if sprite.flip_v else 1.0)
			best_bottom = maxf(best_bottom, frame_bottom)
		if best_bottom > -INF:
			break
	if best_bottom > -INF:
		_floor_reference_local_bottom = best_bottom


func _get_opaque_vertical_bounds(texture: Texture2D) -> Vector2i:
	var cache_key := texture.get_instance_id()
	if _opaque_vertical_bounds_cache.has(cache_key):
		return _opaque_vertical_bounds_cache[cache_key]
	var image := texture.get_image()
	if image == null or image.is_empty():
		var full_height := texture.get_height()
		var fallback := Vector2i(0, full_height)
		_opaque_vertical_bounds_cache[cache_key] = fallback
		return fallback
	image.convert(Image.FORMAT_RGBA8)
	var pixels := image.get_data()
	var width := image.get_width()
	var height := image.get_height()
	var top := height
	var bottom := 0
	for y in height:
		for x in width:
			if pixels[(y * width + x) * 4 + 3] > 8:
				top = mini(top, y)
				bottom = maxi(bottom, y + 1)
			if top == 0 and bottom == height:
				break
		if top == 0 and bottom == height:
			break
	if bottom <= top:
		top = 0
		bottom = height
	var bounds := Vector2i(top, bottom)
	_opaque_vertical_bounds_cache[cache_key] = bounds
	return bounds


## Horizontal half-extent of the rendered sprite (px). Boundary logic uses
## this so the pet's body - not just its center - stays on-screen.
func get_half_width() -> float:
	return get_rendered_size().x * 0.5


## Current visual scale factor (mirrors definition.scale).
func get_scale_factor() -> float:
	return definition.scale if definition != null else 1.0


func boundary_margin() -> float:
	return definition.boundary_margin if definition != null else 32.0


## Clamps `world_position` so the pet's full rendered footprint stays inside
## the usable rect of its current screen. Horizontal uses the sprite
## half-width; vertical keeps the whole body on-screen (the floor already
## keeps it off the bottom edge). No-op before screen_bounds is known.
func clamp_world_position_to_screen(pos: Vector2) -> Vector2:
	if screen_bounds == Rect2i():
		return pos
	var half_w := get_half_width()
	var half_h := get_rendered_size().y * 0.5
	var b := screen_bounds
	return Vector2(
		clampf(pos.x, float(b.position.x) + half_w, float(b.position.x + b.size.x) - half_w),
		clampf(pos.y, float(b.position.y) + half_h, float(b.position.y + b.size.y) - half_h)
	)


## Keeps the pet's local position at the center of its OS window, so the
## sprite stays centered no matter how the window is resized.
func center_in_window() -> void:
	var window_size := get_viewport_rect().size if is_inside_tree() else Vector2(500.0, 500.0)
	position = window_size * 0.5
