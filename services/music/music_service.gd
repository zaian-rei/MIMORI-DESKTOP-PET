extends Node

## Owns the single looping music stream. Exposes a logical on/off for internal systems such as
## BehaviorController; no user-facing toggle is currently shipped.
## actual audio playback is delegated to the global AudioManager - this
## service never drives an AudioStreamPlayer itself. Playback is skipped in
## headless mode so tests still exercise the on/off logic without an audio
## device (the EventBus events always emit).

const STREAM_PATH := "res://assets/audio/pet_music_cherry.wav"

const DEFAULT_MUSIC_VOLUME_DB := -24.0

var music_enabled: bool = true

var _stream: AudioStream
var _player: AudioStreamPlayer


func _ready() -> void:
	_stream = load(STREAM_PATH)
	## Seed a quiet music level once. Existing non-default slider choices remain untouched.
	if not ConfigService.music_volume_initialized:
		var saved_music_volume := ConfigService.get_category_volume(AudioCategory.Category.MUSIC)
		if not ConfigService.category_volumes.has(AudioCategory.Category.MUSIC) or is_zero_approx(saved_music_volume):
			ConfigService.category_volumes[AudioCategory.Category.MUSIC] = DEFAULT_MUSIC_VOLUME_DB
		ConfigService.music_volume_initialized = true
		ConfigService._write_save()
	AudioManager.set_category_volume(
		AudioCategory.Category.MUSIC,
		ConfigService.get_category_volume(AudioCategory.Category.MUSIC)
	)
	music_enabled = true
	_start_playback()


func set_music_enabled(value: bool) -> void:
	if value == music_enabled:
		return
	music_enabled = value
	ConfigService.set_music_enabled(value)
	if value:
		_start_playback()
	else:
		_stop_playback()


func is_playing() -> bool:
	return music_enabled


func _start_playback() -> void:
	_player = AudioManager.play_stream(_stream, AudioCategory.Category.MUSIC)
	if _player != null:
		if not _player.finished.is_connected(_on_finished):
			_player.finished.connect(_on_finished)
	EventBus.emit(EventBus.MUSIC_STARTED)


func _stop_playback() -> void:
	if _player != null:
		AudioManager.stop_player(_player)
		_player = null
	EventBus.emit(EventBus.MUSIC_STOPPED)


## The stream ended naturally: keep the loop alive while music stays enabled
## (in headless the player never reports finished, matching the old behavior
## where the test suite drove the toggles directly).
func _on_finished() -> void:
	if music_enabled:
		_start_playback()
