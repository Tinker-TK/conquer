# 视频和音频偏好共用一个入口：即时应用、持久化，主菜单与暂停面板保持同步。
extends Node

signal changed
const PATH := "user://game_settings.cfg"
const VIDEO_DEFAULTS := {"fullscreen": false, "monitor": 0, "resolution": Vector2i(1920, 1080), "aspect": "16:9", "resizable": true, "vsync": 2, "fps": 60, "msaa": 1}
const AUDIO_DEFAULTS := {"master_volume": 0.8, "music_volume": 1.0, "sfx_volume": 1.0, "ambience_volume": 1.0, "mute_in_background": true}
const ASPECTS := {"16:9": 16.0 / 9.0, "16:10": 1.6, "4:3": 4.0 / 3.0, "21:9": 21.0 / 9.0}
const FPS_OPTIONS := [0, 30, 60, 90, 120, 144, 165, 240]
const AUDIO_BUSES := {"master_volume": &"Master", "music_volume": &"Music", "sfx_volume": &"SFX", "ambience_volume": &"Ambience"}
var video: Dictionary = VIDEO_DEFAULTS.duplicate()
var audio: Dictionary = AUDIO_DEFAULTS.duplicate()
var background := false
var last_error := ""
var video_notice := ""
var startup_settings_pending := "--open-settings" in OS.get_cmdline_user_args()
var resume_settings_pending := "--resume-settings" in OS.get_cmdline_user_args()


func consume_startup_settings() -> bool:
	var pending := startup_settings_pending
	startup_settings_pending = false
	return pending


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	for bus_name in [&"Music", &"SFX", &"Ambience"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, &"Master")
	apply_video()
	apply_audio()
	get_window().focus_entered.connect(_set_background.bind(false))
	get_window().focus_exited.connect(_set_background.bind(true))


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		for key in VIDEO_DEFAULTS:
			var value: Variant = config.get_value("video", key, VIDEO_DEFAULTS[key])
			video[key] = value if typeof(value) == typeof(VIDEO_DEFAULTS[key]) else VIDEO_DEFAULTS[key]
		for key in AUDIO_DEFAULTS:
			var value: Variant = config.get_value("audio", key, AUDIO_DEFAULTS[key])
			audio[key] = value if typeof(value) == typeof(AUDIO_DEFAULTS[key]) else AUDIO_DEFAULTS[key]
	else:
		# 迁移旧主菜单音量，不改变玩家已有偏好。
		var legacy := ConfigFile.new()
		if legacy.load("user://comic_ui_settings.cfg") == OK:
			audio.master_volume = legacy.get_value("audio", "master_volume", 0.8)
	for key in ["master_volume", "music_volume", "sfx_volume", "ambience_volume"]:
		audio[key] = clampf(float(audio[key]), 0.0, 1.0)
	if not video.resolution is Vector2i or video.resolution.x < 640 or video.resolution.y < 480:
		video.resolution = VIDEO_DEFAULTS.resolution
	if not ASPECTS.has(video.aspect):
		video.aspect = "16:9"
	video.vsync = clampi(int(video.vsync), 0, 2)
	video.msaa = clampi(int(video.msaa), 0, 3)
	if not FPS_OPTIONS.has(int(video.fps)):
		video.fps = 60


func save_settings() -> void:
	var config := ConfigFile.new()
	for key in video:
		config.set_value("video", key, video[key])
	for key in audio:
		config.set_value("audio", key, audio[key])
	var error := config.save(PATH)
	last_error = "设置未能保存：" + error_string(error) if error != OK else ""
	changed.emit()


func set_video(key: String, value: Variant) -> void:
	if not VIDEO_DEFAULTS.has(key):
		return
	video[key] = value
	apply_video(key)
	save_settings()


func set_audio(key: String, value: Variant) -> void:
	if not AUDIO_DEFAULTS.has(key):
		return
	if key == "mute_in_background":
		audio[key] = bool(value)
	else:
		audio[key] = clampf(float(value), 0, 1)
	apply_audio()
	save_settings()


func reset_video() -> void:
	video = VIDEO_DEFAULTS.duplicate()
	apply_video()
	save_settings()


func apply_video(changed_key: String = "") -> void:
	video_notice = ""
	Engine.max_fps = int(video.fps)
	var window := get_tree().root
	window.msaa_2d = int(video.msaa) as Viewport.MSAA
	window.content_scale_size = Vector2i(1920, roundi(1920.0 / float(ASPECTS[video.aspect])))
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if DisplayServer.get_name() == "headless":
		return
	# 嵌入窗口归编辑器所有，Windows 会拒绝这些请求。独立窗口启动后应用已保存的值。
	if Engine.is_embedded_in_editor():
		video_notice = "编辑器正在控制窗口。全屏、显示器和分辨率将在独立窗口中应用。"
		DisplayServer.window_set_vsync_mode(int(video.vsync) as DisplayServer.VSyncMode)
		return
	var screen := clampi(int(video.monitor), 0, maxi(0, DisplayServer.get_screen_count() - 1))
	video.monitor = screen
	var mode := Window.MODE_FULLSCREEN if bool(video.fullscreen) else Window.MODE_WINDOWED
	# Windows 更新缩放标记会重建窗口样式，必须先设置标记，再切换全屏。
	if window.unresizable == bool(video.resizable):
		window.unresizable = not bool(video.resizable)
	if changed_key in ["", "fullscreen", "monitor"] and window.current_screen != screen:
		window.mode = Window.MODE_WINDOWED
		window.current_screen = screen
	if window.mode != mode:
		window.mode = mode
	if not bool(video.fullscreen) and changed_key in ["", "fullscreen", "monitor", "resolution"]:
		# 小显示器也能恢复窗口，不把按钮移到屏幕外。
		var usable := DisplayServer.screen_get_usable_rect(screen)
		var wanted: Vector2i = video.resolution
		var extent := Vector2i(mini(wanted.x, usable.size.x), mini(wanted.y, maxi(480, usable.size.y - 48)))
		if window.size != extent:
			window.size = extent
			@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
			window.position = usable.position + (usable.size - extent) / 2
		if extent != wanted:
			video_notice = "分辨率超出桌面可用范围，窗口已调整为 %d × %d。" % [extent.x, extent.y]
	DisplayServer.window_set_vsync_mode(int(video.vsync) as DisplayServer.VSyncMode)
	if DisplayServer.window_get_vsync_mode() != int(video.vsync):
		video_notice += " 当前显卡不支持所选垂直同步模式，使用驱动支持的模式。"


# 编辑器嵌入运行时，一次点击保留进度并在真实窗口恢复设置页。
func open_standalone(resume_run: bool = false, restart_location: bool = false) -> void:
	if not Engine.is_embedded_in_editor():
		return
	if resume_run:
		last_error = RunManager.save_run(restart_location)
		if not last_error.is_empty():
			changed.emit()
			return
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--", "--open-settings"])
	if resume_run:
		args.append("--resume-settings")
	if "--no-mcp-server" in OS.get_cmdline_user_args():
		args.append("--no-mcp-server")
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid < 0:
		last_error = "独立窗口启动失败，请从 Godot 的游戏窗口菜单关闭嵌入运行后重试。"
		changed.emit()
		return
	get_tree().quit()


func apply_audio() -> void:
	for key in AUDIO_BUSES:
		var bus_name: StringName = AUDIO_BUSES[key]
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			continue
		var volume := float(audio[key])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.0001)))
		AudioServer.set_bus_mute(index, volume <= 0 or (key == "master_volume" and background and bool(audio.mute_in_background)))


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		_set_background(what == NOTIFICATION_APPLICATION_FOCUS_OUT)


func _set_background(value: bool) -> void:
	background = value
	if is_inside_tree():
		apply_audio()
