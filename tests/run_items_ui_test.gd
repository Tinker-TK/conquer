# 这玩意儿是干嘛的（核心逻辑）：通过真实鼠标事件检查物品悬停说明、暂停阅读和药水施放。
# 数据是咋流动的（数据流向）：示例物品 → GameSession → 移动鼠标查看说明 → 点击药水和战场 → 库存变化。
# 为啥这么写（选型决策）：实际 UI 输入才能发现禁用按钮没有提示、说明框挡点击或库存刷新后残留旧说明。
# 性能咋样（复杂度）：仅手动测试，可选截图，不参与游戏。
extends Node


# 作用：Godot 初始化后启动；没有参数，没有返回值。
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(30.0, true).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


# 作用：在屏幕指定点发送完整左键点击；point 为视口坐标，没有返回值。
func _click(point: Vector2) -> void:
	await _hover(point)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_viewport().push_input(event, true)
	await get_tree().process_frame


# 作用：发送真实鼠标移动并等待 HUD 刷新；point 为视口坐标，没有返回值。
func _hover(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	await get_tree().process_frame


# 作用：按需保存真实渲染画面；name 为截图名，没有返回值，无显示运行时跳过。
func _capture(resource_name: String) -> void:
	if "--capture-items" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	var folder := "res://.maintenance/checks/item-tooltips"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	await RenderingServer.frame_post_draw
	var hud = get_tree().get_first_node_in_group("run_items_hud")
	assert(hud.item_tooltip.visible, "截图时悬停说明必须仍在显示")
	assert(get_viewport().get_texture().get_image().save_png(folder + "/" + resource_name + ".png") == OK)


# 作用：验证常驻入口、模态暂停和实际施放；没有参数，没有返回值。
func _run() -> void:
	RunManager.start_new_run(load("res://examples/data/run_items_example.tres"))
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	get_tree().root.add_child(session)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud = session.get_node("HUDLayer/RunHUD/RunItemsHUD")
	assert(get_tree().get_nodes_in_group("run_items_hud").size() == 1)
	assert(hud.relic_row.get_child_count() == 3 and hud.potion_row.get_child_count() == 3)
	# 地图中的遗物和禁用药水都必须立即显示说明，且不能因查看而消耗库存。
	var relic_button: Control = hud.relic_row.get_child(0)
	await _hover(relic_button.get_global_rect().get_center())
	assert(hud.item_tooltip.visible and hud.tooltip_title.text == "十抽引擎")
	assert("10" in hud.tooltip_effect.get_parsed_text() and "1" in hud.tooltip_effect.get_parsed_text())
	assert(hud.context_title.text == "能量")
	assert(hud.item_tooltip.position.y >= relic_button.get_global_rect().end.y, "首次悬停的说明应在遗物下方，不能挤到顶部")
	await _capture("map_relic")
	var button: Control = hud.potion_row.get_child(1)
	assert(button.disabled)
	await _hover(button.get_global_rect().get_center())
	assert(hud.item_tooltip.visible and hud.tooltip_title.text == "闪电药水")
	assert("20" in hud.tooltip_effect.get_parsed_text() and "4" in hud.tooltip_effect.get_parsed_text())
	assert("仅自动战斗阶段" in hud.tooltip_status.get_parsed_text())
	assert(hud.item_tooltip.get_global_rect().end.x <= get_viewport().get_visible_rect().end.x)
	assert(hud.item_tooltip.get_global_rect().end.y <= get_viewport().get_visible_rect().end.y)
	assert(RunManager.potions.size() == 3)
	await _capture("map_potion")
	await _hover(Vector2(1000, 800))
	assert(not hud.item_tooltip.visible)
	# 暂停查看卡组时仍能阅读物品，关闭面板后没有残留暂停。
	session.deck_button.pressed.emit()
	assert(get_tree().paused)
	await _hover(hud.potion_row.get_child(0).get_global_rect().get_center())
	assert(hud.item_tooltip.visible and hud.tooltip_title.text == "龙卷风药水")
	session.deck_view.close_requested.emit()
	assert(not get_tree().paused)
	await _hover(hud.relic_row.get_child(0).get_global_rect().get_center())
	RunManager.relic_draw_counts[&"draw_engine"] = 7
	RunManager.items_changed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert(hud.item_tooltip.visible and "7 / 10" in hud.tooltip_status.get_parsed_text(), "鼠标不动时库存刷新也应恢复悬停并更新计数")
	await _capture("relic_progress")
	RunManager.begin_battle("battle_a", "level_001")
	session._on_battle_requested("level_001")
	while SceneTransition.busy:
		await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var battle = session.current_battle
	assert(get_tree().get_nodes_in_group("run_items_hud").size() == 1)
	assert(hud.relic_row.get_child_count() == 3 and hud.potion_row.get_child_count() == 3)
	assert(hud.potion_row.get_child(0).disabled)
	for unit in battle.card_runtime.living_units():
		unit.set_physics_process(false)
	Global.game_phase = Global.GamePhase.AUTO_BATTLE
	await get_tree().process_frame
	button = hud.potion_row.get_child(1)
	await _hover(button.get_global_rect().get_center())
	assert(hud.item_tooltip.visible)
	assert("点击选择落点" in hud.tooltip_status.get_parsed_text())
	await _capture("battle_potion")
	await _click(button.get_global_rect().get_center())
	var items = battle.get_node("BattleItems")
	assert(items.potion != null and items.potion.kind == PotionDefinition.Kind.LIGHTNING)
	# 在世界点施放，真实 GUI 输入不应被透明控件吃掉。
	var point: Vector2 = battle.get_canvas_transform() * Vector2(900, 450)
	await _click(point)
	assert(items.committed and items.remaining_casts == 3)
	assert(RunManager.potions.size() == 2)
	assert(not hud.item_tooltip.visible)
	session._on_map_pressed()
	assert(get_tree().paused)
	assert(not items.try_cast(Vector2(900, 450)))
	session._on_map_pressed()
	assert(not get_tree().paused)
	await _hover(hud.potion_row.get_child(1).get_global_rect().get_center())
	assert(hud.item_tooltip.visible and hud.tooltip_title.text == "火焰药水")
	await _capture("battle_fire")
	Global.game_phase = Global.GamePhase.CARD_PLAY
	assert(items.potion == null)
	battle.battle_finished = true
	session.queue_free()
	await get_tree().process_frame
	print("RUN_ITEMS_UI_PASS: hover, disabled potions, pause, live progress, screen bounds, click-through, consumption")
	get_tree().quit()

