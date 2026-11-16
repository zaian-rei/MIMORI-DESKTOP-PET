extends Node

## The engine's single audio playback authority. Every sound - music, ambience, SFX,
## future voice lines - plays through this manager and no other system creates
## or drives an AudioStreamPlayer directly.
##
## Responsibilities (and only these):
##   - load audio resources (an active AudioPack, or raw streams)
##   - play sounds with random variation + subtle pitch variation
##   - manage category buses (each category = its own volume, all into Master)
##   - manage per-event cooldowns (max playback frequency, anti-spam)
##   - persist master volume, category volumes and mute through ConfigService
##
## It NEVER chooses behaviors, moves the pet, changes animations or states -
## callers decide WHAT to play, this decides HOW (data-driven via the pack).
##
## The theme seam: set_active_pack() swaps all sound assets at once. Future
## SettingsManager talks to the public volume/mute setters below.

const DEFAULT_PACK_PATH := "res://data/configs/default_audio_pack.tres"
const PLAYER_POOL_SIZE := 16
const MASTER_VOLUME_MIN_DB := -80.0
const MASTER_VOLUME_MAX_DB := 24.0

## Currently active sound pack. Swapped by set_active_pack() when a pet or a
## theme registers its own pack.
var active_pack: AudioPack = null

## Pack names/paths that have been loaded this session (debug: "Loaded Sound
## Packs"). The active pack is always last.
var loaded_pack_names: Array[String] = []

## Mirrors ConfigService.muted so callers can read the effective state without
## touching the audio server.
var muted: bool = false

## Mirrors ConfigService.master_volume_db.
var master_volume_db: float = 0.0

var _players: Array[AudioStreamPlayer] = []
var _playing: Array[Dictionary] = []
var _cooldowns: Dictionary = {}
var _last_variation: Dictionary = {}
var _requests_total := 0
var _requests_played := 0
var _requests_rejected := 0


func _ready() -> void:
	_build_buses()
	_apply_persisted_settings()
	_pool_players()
	if ResourceLoader.exists(DEFAULT_PACK_PATH):
		_set_active_pack(load(DEFAULT_PACK_PATH) as AudioPack)
	LoggerGlobal.info("AudioManager initialized (via EventBus).")


## --- Public API -------------------------------------------------------------

## Plays the event with the given id (e.g. &"walk", &"happy") from the active
## pack. Applies the event's cooldown (returns false when it would spam),
## picks a non-repeating variation and a subtle random pitch. Unknown events
## and empty packs are ignored gracefully. Returns true when a sound actually
## started.
func play_event(event_id: StringName) -> bool:
	_requests_total += 1
	if muted or active_pack == null:
		_requests_rejected += 1
		return false
	var sound := active_pack.get_sound(event_id)
	if sound == null or sound.streams.is_empty():
		_requests_rejected += 1
		return false
	if not _cooldown_ready(sound, event_id):
		_requests_rejected += 1
		return false
	_start_play(sound, event_id)
	return true


## Plays a raw stream on a category bus - for systems that already hold an
## AudioStream (the MusicService music loop, future ambient tracks). Returns
## the player so the caller can stop it later via stop_player(). The optional
## cooldown is keyed per stream instance (two different streams never share a
## cooldown).
##
## Unlike play_event(), a muted master does NOT reject the request: streams
## are continuous and are simply silenced by the Master bus mute, so toggling
## mute never kills an ongoing track or its resume chain.
func play_stream(
	stream: AudioStream,
	category: int = AudioCategory.Category.MOVEMENT,
	cooldown_seconds: float = 0.0,
	pitch_variation: float = 0.0,
	volume_db: float = 0.0
) -> AudioStreamPlayer:
	_requests_total += 1
	if stream == null:
		_requests_rejected += 1
		return null
	if cooldown_seconds > 0.0 and not _cooldown_ready_for_stream(stream, cooldown_seconds):
		_requests_rejected += 1
		return null
	var player := _acquire_player()
	player.stream = stream
	player.bus = AudioCategory.bus_name(category)
	player.volume_db = volume_db
	player.pitch_scale = 1.0 if pitch_variation <= 0.0 else randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	if not OS.has_feature("headless"):
		player.play()
	_requests_played += 1
	if cooldown_seconds > 0.0:
		_cooldowns[stream] = Time.get_ticks_msec() + int(cooldown_seconds * 1000.0)
	_playing.append({
		"player": player,
		"event_id": &"",
		"stream": stream,
		"category": category,
		"is_voice": category == AudioCategory.Category.VOICE,
		"started_ms": Time.get_ticks_msec(),
	})
	return player


## Stops a player obtained from play_stream() and frees its slot.
func stop_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	player.stop()
	_remove_playing_for(player)


## Swaps the active sound pack (theme/sound-pack seam). All subsequent
## play_event() requests resolve against the new pack.
func set_active_pack(pack: AudioPack) -> void:
	if pack == null:
		return
	_set_active_pack(pack)


func set_active_pack_by_path(path: String) -> bool:
	if not ResourceLoader.exists(path):
		LoggerGlobal.warn("AudioManager: pack not found at %s" % path)
		return false
	_set_active_pack(load(path) as AudioPack)
	return true


func get_sound(event_id: StringName) -> AudioSound:
	return active_pack.get_sound(event_id) if active_pack != null else null


## --- Volume / mute (SettingsManager seam) -----------------------------------

func set_master_volume_db(value: float) -> void:
	master_volume_db = clampf(value, MASTER_VOLUME_MIN_DB, MASTER_VOLUME_MAX_DB)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), master_volume_db)
	ConfigService.set_master_volume_db(master_volume_db)


func get_master_volume_db() -> float:
	return master_volume_db


func set_category_volume(category: int, value_db: float) -> void:
	if not AudioCategory.is_valid(category):
		return
	var bus := AudioServer.get_bus_index(AudioCategory.bus_name(category))
	if bus != -1:
		AudioServer.set_bus_volume_db(bus, value_db)
	ConfigService.set_category_volume(category, value_db)


func get_category_volume(category: int) -> float:
	var bus := AudioServer.get_bus_index(AudioCategory.bus_name(category))
	if bus == -1:
		return 0.0
	return AudioServer.get_bus_volume_db(bus)


func set_category_muted(category: int, value: bool) -> void:
	if not AudioCategory.is_valid(category):
		return
	var bus := AudioServer.get_bus_index(AudioCategory.bus_name(category))
	if bus != -1:
		AudioServer.set_bus_mute(bus, value)
	ConfigService.set_category_muted(category, value)


func is_category_muted(category: int) -> bool:
	return ConfigService.get_category_muted(category)


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), value)
	ConfigService.set_muted(value)


func is_muted() -> bool:
	return muted


## --- Internal ---------------------------------------------------------------

## Creates a category bus for every AudioCategory entry, routed into Master.
## Idempotent: buses that already exist are reused (safe across restarts).
func _build_buses() -> void:
	for category in AudioCategory.all():
		var name := AudioCategory.bus_name(category)
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, &"Master")


func _apply_persisted_settings() -> void:
	master_volume_db = clampf(ConfigService.master_volume_db, MASTER_VOLUME_MIN_DB, MASTER_VOLUME_MAX_DB)
	muted = ConfigService.muted
	var master_idx := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(master_idx, master_volume_db)
	AudioServer.set_bus_mute(master_idx, muted)
	for category in AudioCategory.all():
		AudioServer.set_bus_volume_db(
			AudioServer.get_bus_index(AudioCategory.bus_name(category)),
			ConfigService.get_category_volume(category)
		)
		AudioServer.set_bus_mute(
			AudioServer.get_bus_index(AudioCategory.bus_name(category)),
			ConfigService.get_category_muted(category)
		)


func _pool_players() -> void:
	for i in PLAYER_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "PoolPlayer%d" % i
		player.finished.connect(_on_player_finished.bind(player))
		add_child(player)
		_players.append(player)


func _set_active_pack(pack: AudioPack) -> void:
	active_pack = pack
	var name_str := pack.pack_name if not pack.pack_name.is_empty() else "unnamed"
	loaded_pack_names.append("%s (%s)" % [name_str, pack.resource_path if pack.resource_path != "" else "in-memory"])
	LoggerGlobal.debug("AudioManager: active pack = %s" % name_str)


func _start_play(sound: AudioSound, event_id: StringName) -> void:
	var player := _acquire_player()
	player.stream = _pick_variation(sound, event_id)
	player.bus = AudioCategory.bus_name(sound.category)
	player.volume_db = sound.volume_db
	player.pitch_scale = 1.0 if sound.pitch_variation <= 0.0 else randf_range(1.0 - sound.pitch_variation, 1.0 + sound.pitch_variation)
	if not OS.has_feature("headless"):
		player.play()
	_requests_played += 1
	if sound.cooldown_seconds > 0.0:
		_cooldowns[event_id] = Time.get_ticks_msec() + int(sound.cooldown_seconds * 1000.0)
	_playing.append({
		"player": player,
		"event_id": event_id,
		"stream": player.stream,
		"category": sound.category,
		"is_voice": sound.is_voice,
		"started_ms": Time.get_ticks_msec(),
	})


## Returns a free pooled player; when the pool is exhausted the longest-running
## sound is cut to make room (never cut during normal operation - the pool is
## sized for simultaneous footsteps + UI + chirps).
func _acquire_player() -> AudioStreamPlayer:
	for player in _players:
		if not player.playing:
			_remove_playing_for(player)
			return player
	var oldest := _playing[0]
	_playing.remove_at(0)
	oldest["player"].stop()
	return oldest["player"]


## Picks a random stream for the event, never repeating the previous pick
## back-to-back (when more than one variation exists).
func _pick_variation(sound: AudioSound, event_id: StringName) -> AudioStream:
	var streams := sound.streams
	var count := streams.size()
	if count == 1:
		_last_variation[event_id] = 0
		return streams[0]
	var previous := int(_last_variation.get(event_id, -1))
	var pick := randi_range(0, count - 1)
	if count > 1 and pick == previous:
		pick = (pick + 1) % count
	_last_variation[event_id] = pick
	return streams[pick]


func _cooldown_ready(sound: AudioSound, event_id: StringName) -> bool:
	if sound.cooldown_seconds <= 0.0:
		return true
	return Time.get_ticks_msec() >= int(_cooldowns.get(event_id, 0))


func _cooldown_ready_for_stream(stream: AudioStream, cooldown_seconds: float) -> bool:
	return Time.get_ticks_msec() >= int(_cooldowns.get(stream, 0))


func _on_player_finished(player: AudioStreamPlayer) -> void:
	_remove_playing_for(player)


func _remove_playing_for(player: AudioStreamPlayer) -> void:
	for i in range(_playing.size() - 1, -1, -1):
		if _playing[i]["player"] == player:
			_playing.remove_at(i)
			return


## --- Debug support ---------------------------------------------------------

## All currently active plays, category volumes, cooldown timers, request
## counters, loaded packs and the voice count - everything the future debug
## overlay needs, in one snapshot.
func get_debug_info() -> Dictionary:
	var now := Time.get_ticks_msec()
	var playing := []
	for entry in _playing:
		playing.append({
			"event_id": entry["event_id"],
			"stream": _stream_label(entry["stream"]),
			"category": AudioCategory.label(entry["category"]),
			"playing_for_ms": now - int(entry["started_ms"]),
		})
	var cooldowns := {}
	for key in _cooldowns:
		cooldowns[str(key)] = maxi(int(_cooldowns[key]) - now, 0)
	var volumes := {}
	for category in AudioCategory.all():
		volumes[AudioCategory.label(category)] = get_category_volume(category)
	var voice_count := 0
	for entry in _playing:
		if entry["is_voice"]:
			voice_count += 1
	return {
		"active_pack": active_pack.pack_name if active_pack != null else "",
		"loaded_packs": loaded_pack_names,
		"playing": playing,
		"voice_count": voice_count,
		"category_volumes": volumes,
		"master_volume_db": master_volume_db,
		"muted": muted,
		"cooldowns": cooldowns,
		"requests_total": _requests_total,
		"requests_played": _requests_played,
		"requests_rejected": _requests_rejected,
	}


func _stream_label(stream: AudioStream) -> String:
	if stream == null:
		return ""
	var path := stream.resource_path
	if path != "":
		return path.get_file()
	return stream.get_class()
