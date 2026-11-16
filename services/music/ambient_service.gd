extends Node

## Quiet environmental bed, deliberately independent from the user-toggleable
## music track. It has its own category bus and can be muted/adjusted in Audio settings.
const STREAM_PATH := "res://assets/audio/ambient_cherry_breeze.wav"
const AMBIENT_GAIN_DB := -24.0

var _stream: AudioStream
var _player: AudioStreamPlayer

func _ready() -> void:
	_stream = load(STREAM_PATH)
	_start_playback()

func _start_playback() -> void:
	if _stream == null:
		return
	_player = AudioManager.play_stream(_stream, AudioCategory.Category.AMBIENT, 0.0, 0.0, AMBIENT_GAIN_DB)
	if _player != null and not _player.finished.is_connected(_on_finished):
		_player.finished.connect(_on_finished)

func _on_finished() -> void:
	_start_playback()
