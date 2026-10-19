# 背景声由真实播放器输出到 Music/Ambience；暂停时继续播放，场景销毁时停止。
extends Node

const SOUND = preload("res://data/audio/game_soundscape.tres")
var music: AudioStreamPlayer
var ambience: AudioStreamPlayer
var preview: AudioStreamPlayer
var context: Node
var ambience_preview_until := 0
var poll_time := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	music = _player("Music", SOUND.music_db)
	music.stream = _loop(SOUND.music)
	ambience = _player("Ambience", SOUND.ambience_db)
	preview = _player("SFX", -12)
	preview.stream = SOUND.feedback


func _player(bus: StringName, volume: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.volume_db = volume
	add_child(player)
	return player


func _loop(stream: AudioStream) -> AudioStream:
	var result := stream.duplicate() as AudioStream
	if result is AudioStreamWAV:
		result.loop_mode = AudioStreamWAV.LOOP_FORWARD
		result.loop_begin = 0
		result.loop_end = roundi(result.get_length() * result.mix_rate)
	elif result is AudioStreamOggVorbis or result is AudioStreamMP3:
		result.loop = true
	return result


func set_context(scene: Node) -> void:
	context = scene
	if not music.playing:
		music.play()
	_refresh_ambience()


func _process(delta: float) -> void:
	poll_time += delta
	if poll_time < .25:
		return
	poll_time = 0.0
	if not is_instance_valid(context) or not context.is_inside_tree():
		music.stop()
		ambience.stop()
		return
	_refresh_ambience()


func _refresh_ambience() -> void:
	if not is_instance_valid(context):
		return
	var battle: Node = context.get("current_battle") if "current_battle" in context else null
	var stream: AudioStream
	if is_instance_valid(battle):
		var rain: Node = battle.get_node_or_null("RainWeather")
		stream = SOUND.rain if rain != null and rain.settings.enabled else SOUND.wind
	elif "current_battle" in context or Time.get_ticks_msec() < ambience_preview_until:
		stream = SOUND.wind
	if stream == null:
		ambience.stop()
		return
	if not ambience.has_meta("source") or ambience.get_meta("source") != stream:
		ambience.stream = _loop(stream)
		ambience.set_meta("source", stream)
		ambience.play()
	elif not ambience.playing:
		ambience.play()


func preview_channel(key: String) -> void:
	if key == "ambience_volume":
		ambience_preview_until = Time.get_ticks_msec() + 1600
		_refresh_ambience()
	elif key in ["master_volume", "sfx_volume"]:
		# 限制拖动滑条时的提示音频率，不叠加几十个声音。
		if not preview.playing:
			preview.play()


func stop_all() -> void:
	context = null
	music.stop()
	ambience.stop()
	preview.stop()
