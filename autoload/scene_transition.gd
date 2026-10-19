# 这玩意儿是干嘛的（核心逻辑）：常驻在场景外的切场管理器，先遮住旧场景，再加载新场景，最后展开幕布。
# 数据是咋流动的（数据流向）：入口提供目的地与色系 → 防重复点击 → 合拢 → 真实加载 → 阅读停留 → 展开 → 完成信号。
# 为啥这么写（选型决策）：autoload 不随旧场景销毁；线程加载避免读取场景资源时把加载动画一起卡住。
# 性能咋样（复杂度）：平时不处理帧，只在切场时查询一个资源任务；加载层只保留一份。
extends CanvasLayer

const Overlay = preload("res://scripts/ui/comic_loading_overlay.gd")
const SETTINGS_PATH := "user://comic_ui_settings.cfg"
# 正常切场只保留半秒的短遮盖；资源加载仍使用真实进度。
const COVER_SECONDS := 0.20
const READY_HOLD_SECONDS := 0.05
const REVEAL_SECONDS := 0.25
signal started
signal finished(success: bool)
var busy := false
var reduced_motion := false
var overlay: Control
var blocker: Control
var previous_pause := false
var last_error := ""
var master_volume: float:
	get:
		return float(GameSettings.audio.master_volume)
	set(value):
		GameSettings.set_audio("master_volume", value)


# 作用：引擎启动时建立常驻幕布并读取设置；没有参数，没有返回值。
func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	blocker = Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	overlay = Overlay.new()
	blocker.add_child(overlay)
	blocker.hide()
	get_viewport().size_changed.connect(_resize)
	_resize()
	_load_settings()


# 作用：窗口尺寸变化时缩放加载画布；没有参数，没有返回值，覆盖屏幕时使用等比例填满以免边缘露出旧场景。
func _resize() -> void:
	var view_size := get_viewport().get_visible_rect().size
	var factor := maxf(view_size.x / 1920.0, view_size.y / 1080.0)
	overlay.scale = Vector2.ONE * factor
	overlay.position = (view_size - Vector2(1920, 1080) * factor) * 0.5


# 作用：引擎送入玩家输入时阻止切场重入；event 是当前输入，没有返回值，幕布期间键盘也不能触发背景按钮。
func _input(_event: InputEvent) -> void:
	if busy:
		get_viewport().set_input_as_handled()


# 作用：读取音量与减少动效偏好；没有参数，没有返回值，缺少配置时使用默认值。
func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		reduced_motion = bool(config.get_value("ui", "reduced_motion", false))


# 作用：保存面板修改后的偏好；volume 为 0 到 1 的总音量，reduce 表示减少动效，没有返回值。
func save_settings(volume: float, reduce: bool) -> void:
	master_volume = clampf(volume, 0, 1)
	reduced_motion = reduce
	var config := ConfigFile.new()
	config.set_value("ui", "reduced_motion", reduced_motion)
	config.set_value("audio", "master_volume", master_volume)
	var error := config.save(SETTINGS_PATH)
	if error != OK:
		push_warning("界面设置未保存：%s" % error_string(error))


# 作用：锁住输入并合拢幕布；title 是目的地文案，palette 是目的地色系，返回是否成功取得切场锁。
func _cover(title: String, palette: String) -> bool:
	if busy:
		return false
	busy = true
	last_error = ""
	previous_pause = get_tree().paused
	get_tree().paused = true
	overlay.heading = title
	# 第一幕入口传草原色系，返回菜单则传默认值；幕布不靠上一场的颜色猜测新目的地。
	overlay.set_palette(palette)
	overlay.status = "正在准备资源"
	overlay.progress = 0.0
	overlay.elapsed = 0.0
	overlay.set_coverage(0.0)
	started.emit()
	# 无显示的回归检查跳过动画等待，保留真实切换逻辑和防重入。
	if DisplayServer.get_name() == "headless":
		return true
	blocker.show()
	overlay.set_process(true)
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(overlay.set_coverage, 0.0, 1.0, 0.08 if reduced_motion else COVER_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	return true


# 作用：新画面就绪后展开幕布；success 表示切换结果，没有返回值，失败时仍恢复旧画面操作。
func _reveal(success: bool) -> void:
	overlay.progress = 1.0 if success else overlay.progress
	overlay.status = "准备就绪" if success else "加载失败，请重试"
	if DisplayServer.get_name() != "headless":
		# 就绪后只留一帧左右完成布局，减少动效仍使用短遮盖。
		await get_tree().create_timer(0.04 if reduced_motion else READY_HOLD_SECONDS, true).timeout
		var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_method(overlay.set_coverage, 1.0, 0.0, 0.08 if reduced_motion else REVEAL_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		await tween.finished
	blocker.hide()
	overlay.set_process(false)
	get_tree().paused = previous_pause
	busy = false
	finished.emit(success)


# 作用：用真实加载进度切换整棵场景；path 是 res 路径，title 是目的地文案，palette 是色系，返回切换是否成功。
func change_scene(path: String, title: String = "展开征途", palette: String = "default") -> bool:
	if busy:
		return false
	# 错误路径先拦截，旧场景保持可操作；调用者可把 last_error 显示给玩家。
	if not ResourceLoader.exists(path, "PackedScene"):
		last_error = "找不到场景：%s" % path
		finished.emit(false)
		return false
	if not await _cover(title, palette):
		return false
	var error := ResourceLoader.load_threaded_request(path, "PackedScene")
	if error != OK and error != ERR_BUSY:
		last_error = "场景加载请求失败：%s" % error_string(error)
		await _reveal(false)
		return false
	var begin_time := Time.get_ticks_msec()
	var state := ResourceLoader.THREAD_LOAD_IN_PROGRESS
	while state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var resource_progress: Array = []
		state = ResourceLoader.load_threaded_get_status(path, resource_progress)
		if not resource_progress.is_empty():
			overlay.progress = clampf(float(resource_progress[0]) * 0.90, 0, 0.90)
		# 如果磁盘请求长时间无响应，撤回幕布；不永远把玩家锁在加载页。
		if Time.get_ticks_msec() - begin_time > 30000:
			last_error = "场景读取超时，请重试。"
			await _reveal(false)
			return false
		if state == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
	if state != ResourceLoader.THREAD_LOAD_LOADED:
		last_error = "场景资源读取失败：%s" % path
		await _reveal(false)
		return false
	var packed := ResourceLoader.load_threaded_get(path) as PackedScene
	if packed == null:
		last_error = "目标资源不是可用场景。"
		await _reveal(false)
		return false
	overlay.status = "正在布置场景"
	overlay.progress = 0.94
	error = get_tree().change_scene_to_packed(packed)
	if error != OK:
		last_error = "场景切换失败：%s" % error_string(error)
		await _reveal(false)
		return false
	# 等新场景真正进入树并完成布局，再露出画面，避免先看到一帧空白。
	await get_tree().scene_changed
	await get_tree().process_frame
	await _reveal(true)
	return true


# 作用：给外壳里的地图/战斗替换加幕布；action 是遮盖后的回调，title 是目的地，palette 是色系，返回是否完成。
func play_transition(action: Callable, title: String, palette: String = "default") -> bool:
	if busy or not action.is_valid():
		return false
	# 无显示测试需要维持原有同步接口，地图与卡牌回归无需等待视觉动画。
	if DisplayServer.get_name() == "headless":
		action.call()
		return true
	if not await _cover(title, palette):
		return false
	overlay.status = "正在布置场景"
	overlay.progress = 0.50
	var result: Variant = action.call()
	var success: bool = not (result is bool and result == false)
	await get_tree().process_frame
	await _reveal(success)
	return success
