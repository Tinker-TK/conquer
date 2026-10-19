# 通过混音采样检查实际声道输出、衰减和静音，而不只读取设置字典。
extends SceneTree
var count := 0
var capture := AudioEffectCapture.new()
var service: Node
var audio: Node

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	count += 1
	if not value:
		push_error("SETTINGS_AUDIO: " + message)
		quit(1)
		assert(value, message)

func mix(frames: int = 24) -> void:
	for i in frames:
		await process_frame
		OS.delay_msec(12)

func output(player: AudioStreamPlayer) -> float:
	player.stop()
	await mix(8)
	capture.clear_buffer()
	player.play(0)
	await mix()
	var frames := capture.get_buffer(capture.get_frames_available())
	var power := 0.0
	for frame in frames:
		power += frame.length_squared()
	player.stop()
	return sqrt(power / maxi(1, frames.size()))

func _run() -> void:
	service = root.get_node("GameSettings")
	audio = root.get_node("GameAudio")
	service.set_audio("mute_in_background", false)
	service.set_audio("master_volume", 1.0)
	AudioServer.add_bus(1)
	AudioServer.set_bus_name(1, &"SettingsOutputProbe")
	AudioServer.add_bus_effect(1, capture)
	for name in [&"Music", &"SFX", &"Ambience"]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(name), &"SettingsOutputProbe")
	var context := Node.new()
	root.add_child(context)
	audio.set_context(context)
	check(audio.music.playing and audio.music.bus == &"Music", "背景音乐实际启动并路由")
	check(audio.music.stream is AudioStreamWAV and audio.music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "音乐循环")
	audio.music.stop()
	audio.preview_channel("ambience_volume")
	check(audio.ambience.playing and audio.ambience.bus == &"Ambience", "环境音试听实际启动")
	check(audio.ambience.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "环境音循环")
	audio.ambience.stop()
	# 关闭自动场景轮询，逐个隔离声道测量同一片段。
	audio.set_process(false)
	for pair in [["music_volume", audio.music], ["ambience_volume", audio.ambience], ["sfx_volume", audio.preview]]:
		var key: String = pair[0]
		var player: AudioStreamPlayer = pair[1]
		service.set_audio(key, 1.0)
		var loud := await output(player)
		check(loud > .00005, key + " 有真实混音输出")
		service.set_audio(key, .25)
		var quiet := await output(player)
		check(quiet > 0 and quiet < loud * .45, key + " 调低后实际衰减")
		service.set_audio(key, 0.0)
		var silent := await output(player)
		check(silent < .000001, key + " 零音量输出静音")
		service.set_audio(key, 1.0)
		print("SETTINGS_AUDIO_CAPTURE: %s loud=%.6f quiet=%.6f silent=%.6f" % [key, loud, quiet, silent])
	service.set_audio("master_volume", 0)
	check(AudioServer.is_bus_mute(0), "全局零音量静音整个输出")
	service.set_audio("master_volume", .37)
	service.set_audio("mute_in_background", true)
	service._set_background(true)
	check(AudioServer.is_bus_mute(0), "后台关闭整体输出")
	service._set_background(false)
	check(not AudioServer.is_bus_mute(0) and is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(0)), .37), "恢复焦点保留全局音量")
	audio.stop_all()
	context.queue_free()
	await mix(8)
	for name in [&"Music", &"SFX", &"Ambience"]:
		AudioServer.set_bus_send(AudioServer.get_bus_index(name), &"Master")
	AudioServer.remove_bus(1)
	print("SETTINGS_AUDIO_PASS: %d checks" % count)
	quit()
