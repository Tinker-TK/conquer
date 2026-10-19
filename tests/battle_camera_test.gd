# 这玩意儿是干嘛的（核心逻辑）：验证中键拖动、滚轮、WASD、鼠标自由出入窗口和固定 UI，以及缩放后的出牌落点。
# 数据是咋流动的（数据流向）：真实战场发牌完成 → 模拟鼠标、键盘和面板切换 → 检查镜头与屏幕/世界变换。
# 为啥这么写（选型决策）：向真实视口发送滚轮事件，并检查实际面板暂停，防止只测函数而漏掉 UI 拦截或鼠标限制。
# 性能咋样（复杂度）：只手动运行，正常游戏不会加载。
extends Node


# 作用：Godot 入树后延迟启动测试；没有参数，没有返回值。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_run.call_deferred()


# 作用：执行边界及交互测试；没有参数，没有返回值。
func _run() -> void:
	var battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	get_tree().root.add_child(battle)
	var camera = battle.get_node("Camera2D")
	camera._on_window_focus_entered()
	await get_tree().process_frame
	var ui = battle.get_node("CardUI")
	# 发牌现在会从牌堆飞入；等卡到位再记录，才能分辨卡牌自身动画和相机错误带动 UI。
	await get_tree().create_timer(1.1).timeout
	var button: Control = ui.get_node("CardButtons/DrawButton")
	var button_before := button.get_global_transform_with_canvas()
	var card: Control = ui.get_node("Hand").get_child(0)
	var card_before := card.get_global_transform_with_canvas()
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_test_keyboard_and_bounds(camera)
	_test_middle_drag(battle, camera, ui)
	await _test_wheel(battle, camera, ui)
	_test_focus_and_pause(camera)
	# 固定 UI 的屏幕位置和大小必须同时保持不变，不仅仅检查节点的 position。
	assert(button.get_global_transform_with_canvas().is_equal_approx(button_before))
	assert(card.get_global_transform_with_canvas().is_equal_approx(card_before))
	# 子关卡继承同一脚本，仍能单独配置自己的边界。
	var inherited = load("res://scenes/levels/battles/battle_001.tscn").instantiate()
	assert(inherited.get_node("Camera2D").has_method("zoom_at"))
	inherited.free()
	# 结算后停止镜头，移走场景后鼠标仍可自由活动。
	battle.battle_finished = true
	camera._process(0.1)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	battle.queue_free()
	await get_tree().process_frame
	await _test_session_panels()
	print("BATTLE_CAMERA_PASS")
	get_tree().quit()


# 作用：验证原有 WASD、四周边界和小地图居中；camera 为实际战场相机，没有返回值。
func _test_keyboard_and_bounds(camera: Camera2D) -> void:
	for pair in [["camera_left", KEY_A], ["camera_right", KEY_D], ["camera_up", KEY_W], ["camera_down", KEY_S]]:
		assert(InputMap.action_get_events(pair[0])[0].physical_keycode == pair[1])
		Input.action_press(pair[0])
		var before: Vector2 = camera.global_position
		camera._process(0.1)
		Input.action_release(pair[0])
		assert(camera.global_position.distance_to(before) > 1.0)
		camera.global_position = Vector2(960, 540)
	# 四周极限；持续顶住后反向应立即响应，不积累不可见位移。
	camera.pan(Vector2(-1, -1), 100.0)
	assert(camera.global_position.is_equal_approx(Vector2(-860, -1140)))
	camera.pan(Vector2(1, 1), 100.0)
	assert(camera.global_position.is_equal_approx(Vector2(2780, 2220)))
	camera.pan(Vector2.LEFT, 0.1)
	assert(is_equal_approx(camera.global_position.x, 2720.0))
	# 缩放后仍按整幅画面限制；地图小于画面时固定在中心。
	camera.zoom = Vector2(2, 2)
	camera.pan(Vector2.RIGHT, 100.0)
	assert(is_equal_approx(camera.global_position.x, 3260.0))
	camera.view_bounds = Rect2(0, 0, 100, 100)
	camera.pan(Vector2.ONE, 100.0)
	assert(camera.global_position.is_equal_approx(Vector2(50, 50)))
	camera.view_bounds = Rect2(-1820, -1680, 5560, 4440)
	camera.zoom = Vector2.ONE
	camera.global_position = Vector2(960, 540)
	camera.force_update_scroll()


# 作用：验证中键拖动、松开、边界和 UI；battle 为战场，camera 为相机，ui 为固定界面，没有返回值。
func _test_middle_drag(battle: Node2D, camera: Camera2D, ui: CanvasLayer) -> void:
	var point := Vector2(1100, 450)
	var origin := Vector2(960, 540)
	# 不按中键，移动到任意边缘也不能让镜头自动移动。
	for edge in [Vector2(1, 1), camera.get_viewport_rect().end - Vector2.ONE]:
		_move_mouse(edge, Vector2(100, 60))
		camera._process(0.1)
		assert(camera.global_position.is_equal_approx(origin))
	# 地图跟随鼠标拖动方向；放大后按倍率换算，屏幕位移仍与手势一致。
	for scale_value in [1.0, 2.0]:
		camera.zoom = Vector2.ONE * scale_value
		for displacement in [Vector2(60, 0), Vector2(-60, 0), Vector2(0, 60), Vector2(0, -60), Vector2(60, 40)]:
			camera.global_position = origin
			camera.force_update_scroll()
			_move_mouse(point)
			_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
			assert(camera._middle_dragging)
			assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "中键拖动也不能限制鼠标活动范围")
			_move_mouse(point + displacement, displacement, MOUSE_BUTTON_MASK_MIDDLE)
			assert(camera.global_position.is_equal_approx(origin - displacement / scale_value))
			var before: Vector2 = camera.global_position
			camera._process(0.1)
			assert(camera.global_position.is_equal_approx(before))
			_mouse_button(MOUSE_BUTTON_MIDDLE, point + displacement, false)
			assert(not camera._middle_dragging)
			_move_mouse(point, -displacement)
			assert(camera.global_position.is_equal_approx(before))
		_check_drop_position(battle, ui)
	# 已从战场开始的拖动可经过 UI，松开即结束；从按钮上按中键则不能开始。
	var button: Control = ui.get_node("CardButtons/DrawButton")
	var ui_point := button.get_global_rect().get_center()
	_move_mouse(ui_point)
	_mouse_button(MOUSE_BUTTON_MIDDLE, ui_point, true)
	assert(not camera._middle_dragging)
	_mouse_button(MOUSE_BUTTON_MIDDLE, ui_point, false)
	_move_mouse(point)
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	var before_ui: Vector2 = camera.global_position
	_move_mouse(ui_point, Vector2(20, 10), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(before_ui - Vector2(10, 5)))
	_mouse_button(MOUSE_BUTTON_MIDDLE, ui_point, false)
	assert(not camera._middle_dragging)
	# 超大拖动到地图边界后反向应立即响应，不能积累看不见的位移。
	camera.zoom = Vector2.ONE
	camera.global_position = origin
	_move_mouse(point)
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	_move_mouse(point, Vector2(10000, 10000), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(-860, -1140)))
	_move_mouse(point, Vector2(-20, -20), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(-840, -1120)))
	_move_mouse(point, Vector2(-10000, -10000), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(2780, 2220)))
	_move_mouse(point, Vector2(20, 20), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(2760, 2200)))
	# 即使没有收到松开事件，下一次移动不含中键状态也必须停止拖动。
	_move_mouse(point, Vector2(30, 20))
	assert(not camera._middle_dragging)
	assert(camera.global_position.is_equal_approx(Vector2(2760, 2200)))
	camera.global_position = origin
	camera.force_update_scroll()


# 作用：测试滚轮方向、倍率限制、指针锚点、UI 和落点；battle 为战场，camera 为镜头，ui 为卡牌界面，没有返回值。
func _test_wheel(battle: Node2D, camera: Camera2D, ui: CanvasLayer) -> void:
	var point := Vector2(1100, 450)
	_move_mouse(point)
	var world_before := battle.get_canvas_transform().affine_inverse() * point
	_scroll(MOUSE_BUTTON_WHEEL_UP, point)
	assert(is_equal_approx(camera.zoom.x, 1.1))
	assert(camera.zoom.x == camera.zoom.y)
	assert((battle.get_canvas_transform().affine_inverse() * point).distance_to(world_before) < 0.01)
	_scroll(MOUSE_BUTTON_WHEEL_DOWN, point)
	assert(camera.zoom.is_equal_approx(Vector2.ONE), "反向滚轮应恢复原始倍率，实际 %s" % camera.zoom)
	# 滚轮松开和普通点击都不能改变倍率。
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_WHEEL_UP
	release.position = point
	camera._unhandled_input(release)
	assert(camera.zoom.is_equal_approx(Vector2.ONE))
	_scroll(MOUSE_BUTTON_LEFT, point)
	assert(camera.zoom.is_equal_approx(Vector2.ONE))
	release.button_index = MOUSE_BUTTON_LEFT
	get_viewport().push_input(release, true)
	# UI 必须先拿到滚轮；用真实滚动控件拦截，确认相机不抢 UI 的滚动。
	var blocker := ScrollContainer.new()
	blocker.position = Vector2(1000, 350)
	blocker.size = Vector2(300, 300)
	var tall_content := Control.new()
	tall_content.custom_minimum_size = Vector2(200, 1200)
	tall_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(tall_content)
	ui.add_child(blocker)
	await get_tree().process_frame
	_move_mouse(point)
	_scroll(MOUSE_BUTTON_WHEEL_UP, point)
	assert(camera.zoom.is_equal_approx(Vector2.ONE), "UI 滚动应拦截滚轮，实际 %s，控件矩形 %s" % [camera.zoom, blocker.get_global_rect()])
	ui.remove_child(blocker)
	blocker.free()
	for index in 40:
		_scroll(MOUSE_BUTTON_WHEEL_UP, point)
	assert(camera.zoom.is_equal_approx(Vector2.ONE * camera.max_zoom))
	# 放大后平移速度按屏幕距离保持一致，拖牌落点也仍对应世界中的同一个位置。
	camera.global_position = Vector2(960, 540)
	camera.pan(Vector2.RIGHT, 0.1)
	assert(is_equal_approx(camera.global_position.x, 980.0))
	_check_drop_position(battle, ui)
	camera.pan(Vector2.RIGHT, 100.0)
	assert(is_equal_approx(camera.global_position.x, 3420.0))
	for index in 60:
		_scroll(MOUSE_BUTTON_WHEEL_DOWN, point)
	assert(camera.zoom.is_equal_approx(Vector2.ONE * camera.min_zoom))
	assert(camera.global_position.is_equal_approx(Vector2(1820, 690)))
	_check_drop_position(battle, ui)
	# 原有测试和后续暂停检查从同一个开局视角开始。
	camera.zoom = Vector2.ONE
	camera.global_position = Vector2(960, 540)
	camera.force_update_scroll()


# 作用：验证缩放和平移后拖牌坐标正确；battle 为战场，ui 为固定 UI 层，没有返回值。
func _check_drop_position(battle: Node2D, ui: CanvasLayer) -> void:
	var drop_zone = ui.get_node("PlayerDeployDropZone")
	var world_point := Vector2(700, 500)
	var screen_point: Vector2 = battle.get_canvas_transform() * world_point
	var local_point: Vector2 = drop_zone.get_global_transform_with_canvas().affine_inverse() * screen_point
	assert(drop_zone._world_drop_position(local_point).distance_to(world_point) < 0.01)


# 作用：模拟切出窗口、隐藏战场和暂停，确认输入停止且鼠标不受限制；camera 为镜头，没有返回值。
func _test_focus_and_pause(camera: Camera2D) -> void:
	var point := Vector2(1100, 450)
	_move_mouse(point)
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	assert(camera._middle_dragging)
	# 移出窗口不一定失去焦点；窗口外松开中键后，回来不能继续旧拖动。
	camera.get_window().mouse_exited.emit()
	assert(camera._window_focused and not camera._middle_dragging)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_move_mouse(point, Vector2(60, 40), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, false)
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	assert(camera._middle_dragging)
	camera._on_window_focus_exited()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._middle_dragging)
	Input.action_press("camera_right")
	camera._process(1.0)
	_scroll(MOUSE_BUTTON_WHEEL_UP, Vector2(1100, 450))
	Input.action_release("camera_right")
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	assert(camera.zoom == Vector2.ONE)
	camera._on_window_focus_entered()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	# 回到窗口后不能继续上次未完成的拖动，必须重新按下中键。
	_move_mouse(point, Vector2(60, 40), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	camera.hide()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._middle_dragging)
	camera.show()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, true)
	assert(camera._middle_dragging)
	get_tree().paused = true
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._middle_dragging)
	Input.action_press("camera_right")
	camera._process(1.0)
	_scroll(MOUSE_BUTTON_WHEEL_UP, Vector2(1100, 450))
	Input.action_release("camera_right")
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	assert(camera.zoom == Vector2.ONE)
	get_tree().paused = false
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	_move_mouse(point, Vector2(60, 40), MOUSE_BUTTON_MASK_MIDDLE)
	assert(camera.global_position.is_equal_approx(Vector2(960, 540)))
	_mouse_button(MOUSE_BUTTON_MIDDLE, point, false)


# 作用：检查真实外壳的地图、卡组和牌堆暂停及顶部 HUD；没有参数，没有返回值。
func _test_session_panels() -> void:
	RunManager.start_new_run()
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(session)
	session._on_battle_requested("level_001")
	var camera = session.current_battle.get_node("Camera2D")
	camera._on_window_focus_entered()
	var top_button: Control = session.get_node("HUDLayer/RunHUD/TopButtons/MapButton")
	var top_before := top_button.get_global_transform_with_canvas()
	camera.pan(Vector2.RIGHT, 0.1)
	camera.zoom_at(1.0, Vector2(1100, 450))
	assert(top_button.get_global_transform_with_canvas().is_equal_approx(top_before))
	session._set_battle_map_visible(true)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._can_control_camera())
	session._set_battle_map_visible(false)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(camera._can_control_camera())
	session._on_deck_pressed()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._can_control_camera())
	session._close_deck()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(camera._can_control_camera())
	var ui = session.current_battle.get_node("CardUI")
	ui._open_pile("DrawButton")
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(not camera._can_control_camera())
	ui._close_pile()
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	assert(camera._can_control_camera())
	# 移出树后取消拖动，鼠标仍保持自由活动。
	session.content_root.remove_child(session.current_battle)
	assert(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE)
	session.current_battle.queue_free()
	session.current_battle = null
	session.queue_free()
	await get_tree().process_frame


# 作用：发送鼠标移动给实际视口；point 为视口坐标，relative 为本次位移，buttons 为按住的按钮掩码，没有返回值。
func _move_mouse(point: Vector2, relative: Vector2 = Vector2.ZERO, buttons: int = 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.relative = relative
	motion.button_mask = buttons
	get_viewport().push_input(motion, true)


# 作用：向真实视口按下或松开鼠标按钮；button 为按钮编号，point 为视口坐标，pressed 表示是否按下，没有返回值。
func _mouse_button(button: MouseButton, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	get_viewport().push_input(event, true)


# 作用：发送滚轮或按钮给实际视口；button 为按钮编号，point 为视口坐标，没有返回值。
func _scroll(button: MouseButton, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	event.position = point
	get_viewport().push_input(event, true)
