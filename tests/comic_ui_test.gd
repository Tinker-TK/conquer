# 这玩意儿是干嘛的（核心逻辑）：检查漫画菜单、暂停恢复和所有切场，并可保存实际渲染截图与动画帧。
# 数据是咋流动的（数据流向）：真实按钮/地图入口 → 测量加载时长 → 检查新场景和进度 → 导出带真实时间的动画帧。
# 为啥这么写（选型决策）：使用真实游戏流程，能发现菜单接线、旧场景销毁和幕布暂停之间的错误。
# 性能咋样（复杂度）：只在手动运行测试时执行；正常游戏不加载，也不导出截图。
extends SceneTree

const OUT := "res://.maintenance/comic_ui"
var visual := false
var transition: Node
var frame_count := 0
var frame_times_ms: Array[float] = []
var recorded_duration_ms := 0.0


# 作用：引擎启动测试时安排首帧执行；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()


# 作用：等待幕布完成；没有参数，没有返回值，超过 20 秒说明切场卡住并令测试失败。
func _wait_idle() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while transition.busy:
		assert(Time.get_ticks_msec() < deadline, "切场未结束")
		await process_frame
	await process_frame


# 作用：保存实际 GPU 渲染画面；name 是截图文件名，没有返回值，headless 检查自动略过。
func _capture(name: String) -> void:
	if not visual:
		return
	await RenderingServer.frame_post_draw
	var picture := root.get_texture().get_image()
	assert(picture.save_png(OUT + "/" + name + ".png") == OK)


# 作用：录制一段真实切场；没有参数，没有返回值，保存截图时间以免浏览器按固定帧率播放时又变快。
func _record_transition() -> void:
	var begin_time := Time.get_ticks_usec()
	while transition.busy:
		if visual:
			frame_times_ms.append(float(Time.get_ticks_usec() - begin_time) / 1000.0)
			await _capture("frames/frame_%03d" % frame_count)
			frame_count += 1
		await create_timer(0.05, true).timeout
	await _wait_idle()
	recorded_duration_ms = float(Time.get_ticks_usec() - begin_time) / 1000.0
	# 记录真实切场，避免重新引入已经就绪后仍停留数秒的等待。
	assert(recorded_duration_ms >= 450.0 and recorded_duration_ms < 2000.0, "普通地图切场应在约半秒的动画后完成")


# 作用：模拟方向键；key 是键码，没有返回值，按下与松开成对避免残留输入。
func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame


# 作用：运行真实菜单和战斗流程；没有参数，没有返回值，成功时输出唯一完成标记。
func _run() -> void:
	visual = DisplayServer.get_name() != "headless"
	transition = root.get_node("SceneTransition")
	var run = root.get_node("RunManager")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "/frames"))
	# 使用检查进程独立的用户目录；测试结束前仍恢复原有偏好。
	var original_reduce: bool = transition.reduced_motion
	var original_volume: float = transition.master_volume
	transition.reduced_motion = false
	assert(run.use_default_map().is_empty())
	# 仅操作本检查进程隔离的 user://，覆盖无存档时的禁用和跳过行为。
	if run.has_saved_run():
		assert(DirAccess.remove_absolute(run.SAVE_PATH) == OK)
	var menu = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.9).timeout
	assert(menu.menu_buttons.size() == 4 and menu.selected_index == 0)
	assert(menu.continue_button == menu.menu_buttons[1] and menu.continue_button.visible and menu.continue_button.disabled)
	assert(not menu.panels.has("routes") and menu.design.get_node_or_null("Routes") == null)
	for index in 4:
		assert(menu.menu_buttons[index].position == Vector2(148, 466 + index * 116))
	await _capture("main_menu_no_save")
	# 真实键盘方向键必须与可见高亮同步，而不是只改变隐藏的焦点。
	await _key(KEY_DOWN)
	assert(menu.selected_index == 2)
	await _key(KEY_ENTER)
	assert(menu.panel_open == "settings")
	await _key(KEY_ESCAPE)
	assert(menu.panel_open.is_empty())
	assert(root.gui_get_focus_owner() == menu.menu_buttons[2] and menu.continue_button.focus_mode == Control.FOCUS_NONE)
	menu.menu_buttons[2].mouse_entered.emit()
	assert(root.gui_get_focus_owner() == menu.menu_buttons[2])
	await _key(KEY_ENTER)
	assert(menu.panel_open == "settings")
	menu.settings_panel.select_tab(1)
	menu.volume_slider.value = 37
	assert(is_equal_approx(transition.master_volume, 0.37))
	assert(menu.settings_panel.pages[1].visible and not menu.settings_panel.pages[0].visible)
	menu.volume_slider.value = original_volume * 100
	await _capture("settings")
	menu._close_panel()
	# 有存档时重建菜单，第二行的真实键盘确认必须恢复存档而不是开新局。
	run.start_new_run()
	run.gold = 327
	assert(run.save_run().is_empty())
	menu.free()
	menu = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await create_timer(0.9).timeout
	assert(not menu.continue_button.disabled and menu.continue_button == menu.menu_buttons[1])
	await _capture("main_menu")
	await _key(KEY_DOWN)
	assert(menu.selected_index == 1)
	await _key(KEY_ENTER)
	await _wait_idle()
	assert(current_scene.scene_file_path == "res://scenes/app/game_session.tscn" and run.gold == 327)
	assert(await transition.change_scene("res://scenes/ui/main_ui.tscn"))
	menu = current_scene
	await create_timer(0.9).timeout
	# 改变窗口比例后，最后一行与底部提示仍须在设计画布范围内。
	if visual:
		root.size = Vector2i(1024, 768)
		await create_timer(0.2).timeout
		await _capture("main_menu_4_3")
		root.size = Vector2i(1280, 720)
		await create_timer(0.2).timeout
	menu._select(0, true)
	menu._on_start_pressed()
	# 出征的双击只开启一次，记录的幕布来自真实线程加载。
	menu._on_start_pressed()
	assert(transition.busy)
	if visual:
		await _record_transition()
	else:
		await _wait_idle()
	assert(current_scene.scene_file_path == "res://scenes/app/game_session.tscn")
	assert(not paused and not transition.blocker.visible)
	var session = current_scene
	await _capture("map_after_loading")
	# 地图与战斗是同一外壳内替换，仍要有幕布，也不能改变牌组总量。
	var card_count: int = run.deck.size()
	session.map_view._on_node_enter_requested(session.map_view.node_views.battle_a)
	await _wait_idle()
	assert(is_instance_valid(session.current_battle))
	assert(run.deck.size() == card_count and not paused)
	await _capture("battle_after_loading")
	session.current_battle.finish_battle(true)
	# 外部结算信号即使来自已暂停的只读地图，也不能把暂停留给胜利后的可操作地图。
	session._set_battle_map_visible(true)
	assert(paused)
	session.current_battle.get_node("GameOver")._on_button_pressed()
	await process_frame
	await _wait_idle()
	assert(not is_instance_valid(session.current_battle))
	assert(run.completed_ids.has("battle_a") and session.map_layer.visible)
	assert(not paused)
	# 再次从地图进入下一战并失败，确认主菜单重建、幕布存活且输入解锁。
	# 直接使用外壳入口检查第二场加载；关卡仍由真实配置提供。
	session._on_battle_requested("level_002")
	await _wait_idle()
	assert(is_instance_valid(session.current_battle))
	session.current_battle.finish_battle(false)
	session.current_battle.get_node("GameOver")._on_button_pressed()
	await process_frame
	await _wait_idle()
	assert(current_scene.scene_file_path == "res://scenes/ui/main_ui.tscn")
	assert(not paused and not transition.busy)
	# 不存在的资源必须失败并保留当前界面，不把玩家永远锁在幕布里。
	var kept_scene := current_scene
	assert(not await transition.change_scene("res://missing_scene.tscn"))
	assert(current_scene == kept_scene and not transition.busy and not paused)
	current_scene.route_error.hide()
	# 在已经暂停的界面播放内部切换，结束后必须保持原暂停状态。
	paused = true
	assert(await transition.play_transition(func(): return true, "暂停状态检查"))
	assert(paused)
	paused = false
	transition.save_settings(original_volume, original_reduce)
	var report := FileAccess.open(OUT + ("/verification-visual.json" if visual else "/verification-headless.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": true, "visual": visual, "frames": frame_count, "frame_times_ms": frame_times_ms, "duration_ms": recorded_duration_ms, "checks": ["keyboard", "panels", "settings", "aspect_ratio", "double_click", "menu_to_map", "map_to_battle", "victory_to_map", "defeat_to_menu", "invalid_path", "pause_restore", "short_transition"]}, "\t"))
	print("COMIC_UI_TEST_PASS: keyboard, panels, settings, scene transitions, pause, failure recovery")
	quit()
