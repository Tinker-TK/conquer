# 用真实鼠标和键盘操作设置，检查点击路径而不是直接发射控件信号。
extends SceneTree
var panel: Control
var service: Node
var count := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	count += 1
	if not value:
		push_error("SETTINGS_CONTROLS: " + message)
		quit(1)
		assert(value, message)

func click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	await process_frame
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		root.push_input(event, true)
		await process_frame
	for i in 5:
		await process_frame

func choose(option: OptionButton, index: int) -> void:
	await click(option.get_global_rect().get_center())
	var popup := option.get_popup()
	check(popup.visible, "真实点击打开下拉框 " + option.name)
	var current := popup.get_focused_item()
	while current != index:
		var event := InputEventKey.new()
		event.keycode = KEY_DOWN if current < index else KEY_UP
		event.pressed = true
		event.window_id = popup.get_window_id()
		Input.parse_input_event(event)
		await process_frame
		event.pressed = false
		Input.parse_input_event(event)
		current = popup.get_focused_item()
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	enter.window_id = popup.get_window_id()
	Input.parse_input_event(enter)
	await process_frame
	enter.pressed = false
	Input.parse_input_event(enter)
	for i in 5:
		await process_frame
	check(not popup.visible, "真实键盘选择关闭下拉框")

func drag_slider(slider: HSlider, from: float, to: float) -> void:
	var rect := slider.get_global_rect()
	var begin := Vector2(rect.position.x + rect.size.x * from, rect.get_center().y)
	await click(begin)
	var press := InputEventMouseButton.new()
	press.position = begin
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press, true)
	for i in range(1, 6):
		var motion := InputEventMouseMotion.new()
		motion.position = begin.lerp(Vector2(rect.position.x + rect.size.x * to, begin.y), float(i) / 5)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(motion, true)
		await process_frame
	press.position = Vector2(rect.position.x + rect.size.x * to, begin.y)
	press.pressed = false
	root.push_input(press, true)
	await process_frame

func _run() -> void:
	service = root.get_node("GameSettings")
	service.reset_video()
	service.set_video("resolution", Vector2i(1280, 720))
	service.set_audio("mute_in_background", false)
	var pause = load("res://scripts/ui/pause_menu.gd").new()
	root.add_child(pause)
	await process_frame
	pause.open()
	await click(pause.buttons[1].get_global_rect().get_center())
	panel = pause.settings
	check(panel.visible, "点击设置打开面板")
	await click(panel.controls.fullscreen.get_global_rect().get_center())
	check(service.video.fullscreen, "鼠标点击全屏开关")
	if DisplayServer.get_name() != "headless":
		print("SETTINGS_NATIVE_FULLSCREEN: display=%d root=%d embedded=%s" % [DisplayServer.window_get_mode(), root.mode, Engine.is_embedded_in_editor()])
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN, "操作系统实际全屏")
	await click(panel.controls.fullscreen.get_global_rect().get_center())
	check(not service.video.fullscreen, "鼠标关闭全屏")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED, "操作系统实际恢复窗口")
	await choose(panel.controls.resolution, 1)
	check(service.video.resolution == Vector2i(1600, 900), "真实分辨率下拉选择")
	if DisplayServer.get_name() != "headless":
		print("SETTINGS_NATIVE_SIZE: %s usable=%s screen=%d" % [DisplayServer.window_get_size(), DisplayServer.screen_get_usable_rect(service.video.monitor), service.video.monitor])
		check(DisplayServer.window_get_size() == Vector2i(1600, 900), "操作系统实际窗口尺寸")
	await choose(panel.controls.monitor, mini(1, panel.controls.monitor.item_count - 1))
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_current_screen() == service.video.monitor, "实际显示器")
	await choose(panel.controls.aspect, 2)
	check(root.content_scale_size == Vector2i(1920, 1440), "宽高比实际改变画布")
	await click(panel.controls.resizable.get_global_rect().get_center())
	check(not service.video.resizable, "鼠标点击窗口缩放")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_RESIZE_DISABLED), "系统实际禁止调整窗口")
	var fps_arrow: Button = panel.pages[0].get_node("fps_next")
	await click(fps_arrow.get_global_rect().get_center())
	check(Engine.max_fps == 90, "鼠标点击帧数箭头")
	await click(panel.pages[0].get_node("vsync_previous").get_global_rect().get_center())
	check(service.video.vsync == 1, "真实点击垂直同步")
	if DisplayServer.get_name() != "headless":
		check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED, "驱动实际开启垂直同步")
	await click(panel.pages[0].get_node("msaa_next").get_global_rect().get_center())
	check(root.msaa_2d == Viewport.MSAA_4X, "真实点击 MSAA 改变渲染器")
	var reset: Button
	for child in panel.pages[0].get_children():
		if child is Button and child.text == "重置":
			reset = child
	await click(reset.get_global_rect().get_center())
	check(service.video.fps == 60 and service.video.resizable and service.video.msaa == 1 and service.video.aspect == "16:9", "真实点击重置恢复默认")
	await click(panel.tabs[1].get_global_rect().get_center())
	check(panel.active_tab == 1, "鼠标切换音频页")
	for key in ["master_volume", "music_volume", "sfx_volume", "ambience_volume"]:
		service.set_audio(key, 1.0)
		var rect: Rect2 = panel.controls[key].get_global_rect()
		await click(Vector2(rect.position.x + rect.size.x * 0.2, rect.get_center().y))
		check(float(service.audio[key]) < 0.3, "鼠标点击音量滑条 " + key)
		await drag_slider(panel.controls[key], .2, .7)
		check(float(service.audio[key]) > .6, "真实拖动音量 " + key)
	await click(panel.controls.mute_in_background.get_global_rect().get_center())
	check(service.audio.mute_in_background, "鼠标后台静音开关")
	service._set_background(true)
	check(AudioServer.is_bus_mute(0), "失去焦点实际静音")
	service._set_background(false)
	check(not AudioServer.is_bus_mute(0), "恢复焦点实际恢复音量")
	var audio := root.get_node("GameAudio")
	audio.stop_all()
	paused = false
	pause.queue_free()
	for i in 10:
		await process_frame
		OS.delay_msec(12)
	print("SETTINGS_CONTROLS_PASS: %d checks" % count)
	quit()
