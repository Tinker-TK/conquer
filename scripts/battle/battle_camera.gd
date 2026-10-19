# 这玩意儿是干嘛的（核心逻辑）：按住鼠标中键拖动战场，WASD 也能移动，滚轮放大缩小；鼠标可自由移出窗口。
# 数据是咋流动的（数据流向）：中键按下 → 鼠标位移换成世界位移 → 松开停止；键盘每帧平移，滚轮围绕指针缩放，再限制视野边界。
# 为啥这么写（选型决策）：只改变 Camera2D，CanvasLayer 上的手牌和 HUD 不动；鼠标保持可见且不限制窗口范围。
# 性能咋样（复杂度）：每帧只检查键盘输入，鼠标拖动或滚轮触发时做矩形计算，不遍历单位或地形。
extends Camera2D

# 单位是屏幕像素/秒；放大后同步减少世界位移，避免镜头看起来突然变快。
## WASD 移动镜头的速度，单位为屏幕像素/秒；运行时按缩放换算世界位移，放大后画面移动速度仍保持一致。0 停止键盘平移，中键拖动仍可使用。
@export_range(0.0, 3000.0, 10.0) var move_speed: float = 600.0
# 1.0 为原始大小，0.5 能看到更大范围，3.0 把地图放大到三倍。
## 允许的最小镜头缩放倍率；1 为原始大小，小于 1 可看到更大地图范围。与 Max Zoom 共同限制滚轮缩放。
@export_range(0.1, 4.0, 0.05) var min_zoom: float = 0.5
## 允许的最大镜头缩放倍率；3 表示地图放大到三倍，越大则能更近地查看单位。CanvasLayer 上的手牌和 HUD 不随镜头放大。
@export_range(0.1, 4.0, 0.05) var max_zoom: float = 3.0
# 每格滚轮放大或缩小约 10%，使用倍率让来回滚动可以恢复原大小。
## 每格滚轮的缩放增幅，0.1 表示约 10%。使用倍率调整并围绕鼠标位置缩放，越大则每次缩放变化越明显。
@export_range(0.01, 0.5, 0.01) var zoom_step: float = 0.1
# 这是“允许画面看到的世界范围”，不是单位部署范围。
# 在原有范围上向四边各再扩展1000；1920×1080、zoom=1 时，相对开局中心允许左右1820、上下1680。
## 允许镜头画面看到的世界坐标矩形，移动和缩放后都会尽量限制视野在此范围内。它控制镜头边界，不决定单位可部署或可行走范围。
@export var view_bounds := Rect2(-1820.0, -1680.0, 5560.0, 4440.0)

var _window_focused: bool = false
# 只有从战场按下中键才开始拖动，经过 UI 可以继续，松开、暂停或移出窗口就结束。
var _middle_dragging: bool = false


# 作用：Godot 入树时初始化相机；没有参数，没有返回值。
func _ready() -> void:
	# 独立设置暂停模式，即使外壳 Always，查看卡组或地图时相机也不会偷跑。
	process_mode = Node.PROCESS_MODE_PAUSABLE
	position_smoothing_enabled = false
	drag_horizontal_enabled = false
	drag_vertical_enabled = false
	offset = Vector2.ZERO
	zoom = Vector2.ONE * clampf(zoom.x, minf(min_zoom, max_zoom), maxf(min_zoom, max_zoom))
	global_position = clamp_camera_position(global_position)
	force_update_scroll()
	# 进入战场使用普通可见鼠标；滚轮和中键拖动不需要限制鼠标活动范围。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 失去焦点时停止镜头输入；无窗口的自动测试仍可模拟输入。
	_window_focused = get_window().has_focus() or DisplayServer.get_name() == "headless"
	get_window().focus_entered.connect(_on_window_focus_entered)
	get_window().focus_exited.connect(_on_window_focus_exited)
	get_window().mouse_exited.connect(_on_window_mouse_exited)
	get_viewport().size_changed.connect(_on_viewport_resized)
	visibility_changed.connect(_cancel_inactive_drag)
	_cancel_inactive_drag()


# 作用：Godot 每帧读取 WASD；delta 为这一帧秒数，没有返回值。
func _process(delta: float) -> void:
	# 切换镜头、隐藏战场或结束战斗后，取消拖动并停止移动地图。
	_cancel_inactive_drag()
	if not _can_control_camera():
		return
	if _is_typing_or_using_shortcut():
		_middle_dragging = false
		return
	var direction := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	pan(direction, delta / Engine.time_scale)


# 作用：Godot 收到输入时处理正在进行的中键拖动和松开；event 为输入事件，没有返回值。
func _input(event: InputEvent) -> void:
	# 松开可能发生在按钮上，所以要在 UI 处理之前结束拖动，避免镜头一直跟着鼠标走。
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		var was_dragging := _middle_dragging
		_middle_dragging = false
		if was_dragging:
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseMotion or not _middle_dragging:
		return
	# 中键已经松开、战斗暂停或窗口失去焦点时，不使用残留的拖动状态。
	if not _can_control_camera() or _is_typing_or_using_shortcut() or (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) == 0:
		_middle_dragging = false
		return
	# 像用手拖地图一样，场景跟随鼠标方向，因此镜头向反方向移动；除以 zoom 保持屏幕上的拖动距离一致。
	global_position = clamp_camera_position(global_position - event.relative / zoom)
	force_update_scroll()
	get_viewport().set_input_as_handled()


# 作用：Godot 在 UI 没有使用输入时开始中键拖动或滚轮缩放；event 为输入事件，没有返回值。
func _unhandled_input(event: InputEvent) -> void:
	if not _can_control_camera() or _is_typing_or_using_shortcut():
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	# 滚动列表到达顶端时可能放行滚轮，仍不能让背后的地图一起缩放。
	# 部署区虽然也是 Control，但代表战场本身，允许在它上面缩放。
	var hovered := get_viewport().gui_get_hovered_control()
	var deployment_surface := get_parent().get_node_or_null("CardUI/PlayerDeployDropZone")
	if hovered != null and hovered != deployment_surface:
		return
	# 从地图按下中键才接管拖动；正在拖卡牌时保持出牌操作，避免两种拖动争抢鼠标。
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		if not get_viewport().gui_is_dragging():
			_middle_dragging = true
			get_viewport().set_input_as_handled()
		return
	# 向上滚放大，向下滚缩小；按钮、滚动列表和暂停面板先由 UI 处理。
	var steps := 0.0
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		steps = event.factor
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		steps = -event.factor
	else:
		return
	zoom_at(steps, event.position)
	get_viewport().set_input_as_handled()


# 作用：判断是否正在输入文字或使用系统快捷键；没有参数，返回是否应暂时停止镜头输入。
func _is_typing_or_using_shortcut() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return true
	return Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_ALT) or Input.is_key_pressed(KEY_META)


# 作用：移动视角并立即同步鼠标世界坐标；direction 为方向、delta 为秒数，没有返回值。
func pan(direction: Vector2, delta: float) -> void:
	# 斜向和键鼠同时操作都不超过设置的速度，移动距离不受帧率影响。
	var movement := direction.limit_length(1.0) * move_speed * maxf(delta, 0.0) / zoom
	global_position = clamp_camera_position(global_position + movement)
	# 拖牌预览和右键部署需要读到本帧的新相机变换。
	force_update_scroll()


# 作用：围绕鼠标指向的地图位置缩放；steps 为滚轮格数（正数放大），point 为视口坐标，没有返回值。
func zoom_at(steps: float, point: Vector2) -> void:
	var next_zoom := clampf(zoom.x * pow(1.0 + zoom_step, steps), minf(min_zoom, max_zoom), maxf(min_zoom, max_zoom))
	if is_equal_approx(next_zoom, zoom.x):
		return
	# 先记住鼠标下面的世界位置，改变倍率后补偿中心，让想看的位置留在鼠标下面。
	force_update_scroll()
	var world_before := get_canvas_transform().affine_inverse() * point
	zoom = Vector2.ONE * next_zoom
	force_update_scroll()
	var world_after := get_canvas_transform().affine_inverse() * point
	# 缩小时会看到更宽的地图，必须重新限制中心；靠近边界时优先保证画面不越界。
	global_position = clamp_camera_position(global_position + world_before - world_after)
	force_update_scroll()


# 作用：判断战场是否允许玩家控制镜头；没有参数，返回是否正在前台正常战斗。
func _can_control_camera() -> bool:
	return is_current() and is_visible_in_tree() and not get_tree().paused and _window_focused and get_parent().get("battle_finished") != true and Global.game_phase != Global.GamePhase.ROUND_RESOLVE


# 作用：战场停止接受镜头输入时取消中键拖动；没有参数，没有返回值。
func _cancel_inactive_drag() -> void:
	if not is_node_ready():
		return
	if not _can_control_camera():
		_middle_dragging = false


# 作用：Godot 在窗口重新获得焦点时恢复镜头控制；没有参数，没有返回值。
func _on_window_focus_entered() -> void:
	_window_focused = true


# 作用：Godot 在切换到其他窗口时停止镜头输入与拖动；没有参数，没有返回值。
func _on_window_focus_exited() -> void:
	_window_focused = false
	_middle_dragging = false


# 作用：鼠标离开窗口时取消拖动，避免在窗口外松开中键后残留状态；没有参数，没有返回值。
func _on_window_mouse_exited() -> void:
	_middle_dragging = false


# 作用：Godot 改变窗口尺寸时重新限制视野边界；没有参数，没有返回值。
func _on_viewport_resized() -> void:
	# 改变窗口大小时结束旧拖动，避免尺寸变化造成意外跳动。
	_middle_dragging = false
	global_position = clamp_camera_position(global_position)
	force_update_scroll()


# 作用：Godot 暂停或禁用节点时也会发通知；what 为通知编号，没有返回值。
func _notification(what: int) -> void:
	# 暂停后不会再执行 _process，所以必须在通知中取消拖动。
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_DISABLED:
		_middle_dragging = false


# 作用：Godot 移走或销毁战场镜头时取消拖动并断开窗口信号；没有参数，没有返回值。
func _exit_tree() -> void:
	_middle_dragging = false
	# 镜头可能只被移出树而没有销毁，断开窗口信号才能避免它在菜单里再次响应。
	var window := get_window()
	if window.focus_entered.is_connected(_on_window_focus_entered):
		window.focus_entered.disconnect(_on_window_focus_entered)
	if window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.disconnect(_on_window_focus_exited)
	if window.mouse_exited.is_connected(_on_window_mouse_exited):
		window.mouse_exited.disconnect(_on_window_mouse_exited)
	if get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.disconnect(_on_viewport_resized)


# 作用：求不会越界的相机中心；candidate 为预期世界坐标，返回限制后的坐标。
func clamp_camera_position(candidate: Vector2) -> Vector2:
	var bounds := view_bounds.abs()
	var half_view := get_viewport_rect().size / zoom / 2.0
	var low := bounds.position + half_view
	var high := bounds.end - half_view
	# 某个方向的地图小于屏幕时居中锁住，不让 min > max 的夹取产生抖动。
	return Vector2(
		clampf(candidate.x, low.x, high.x) if low.x <= high.x else bounds.get_center().x,
		clampf(candidate.y, low.y, high.y) if low.y <= high.y else bounds.get_center().y
	)
