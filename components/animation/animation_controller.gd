extends Node

class_name AnimationController

var _protected_until_ms: int = 0


func play(
	sprite: AnimatedSprite2D,
	animation_name: String,
	protect_for_seconds: float = 0.0,
	interrupt: bool = false,
	restart: bool = false
) -> void:
	var now := Time.get_ticks_msec()

	if not interrupt and now < _protected_until_ms and sprite.animation != animation_name:
		return

	if sprite.sprite_frames == null:
		return

	if not sprite.sprite_frames.has_animation(animation_name):
		return

	if sprite.animation == animation_name and sprite.is_playing() and not restart:
		return

	sprite.play(animation_name)
	_protected_until_ms = now + int(protect_for_seconds * 1000.0)
