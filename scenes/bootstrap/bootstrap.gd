extends Node

const PET_SCENE := preload("res://scenes/pet/pet.tscn")

@onready var desktop_window: DesktopWindow = $DesktopWindow

func _ready() -> void:
	EngineGlobal.initialize()

	desktop_window.configure_small_window()

	var screen_index := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(screen_index)

	
	ThemeManager.load_theme(ConfigService.theme_id)

	var saved_profile_id := str(SettingsManager.get_setting("general.pet_id", "")).strip_edges()
	var show_pet_picker := saved_profile_id.is_empty() or PetRoster.get_profile(saved_profile_id).is_empty()
	var pet := PET_SCENE.instantiate()
	pet.profile_id = PetRoster.valid_id(saved_profile_id)
	pet.screen_bounds = usable_rect

	pet.definition.move_speed = ConfigService.move_speed
	pet.definition.gravity = ConfigService.gravity
	pet.definition.jump_speed = ConfigService.jump_speed
	pet.definition.scale = ConfigService.scale

	# Apply theme assets to the pet definition
	var active_theme := ThemeManager.get_active_theme()
	if active_theme != null:
		## Preserve the selected pet's own prefixed sprite animations. Themes may
		## still supply UI/audio identity without replacing character artwork.
		if active_theme.audio_pack != null:
			pet.definition.audio_pack = active_theme.audio_pack
		if not active_theme.default_personality_id.is_empty():
			pet.definition.default_personality_id = active_theme.default_personality_id

	if ConfigService.has_saved_position:
		pet.world_position = ConfigService.pet_world_position
	else:
		pet.world_position = Vector2(
			usable_rect.position.x + usable_rect.size.x / 2.0,
			usable_rect.position.y + 50.0
		)

	pet.desktop_window = desktop_window

	add_child(pet)

	DebugOverlayManager.register_pet(pet)
	StatisticsManager.register_pet(pet)

	desktop_window.track(pet)

	if show_pet_picker:
		var context_menu := pet.get_component(ContextMenuComponent) as ContextMenuComponent
		if context_menu != null:
			context_menu.call_deferred("open_first_run_picker")

	EventBus.engine_initialized.emit()
