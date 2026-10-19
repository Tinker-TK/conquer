# 这玩意儿是干嘛的（核心逻辑）：自动检查初始数据、卡组查看和从下往上的十层地图通关。
# 数据是咋流动的（数据流向）：模拟按钮 → 检查牌组、暂停与进度 → 输出测试结果。
# 为啥这么写（选型决策）：用真实场景验证接口，不依赖屏幕坐标。
# 性能咋样（复杂度）：只在手动测试时运行，正常游戏不加载。
extends Node

@onready var root := get_tree().root


# 作用：Godot 启动测试后在首帧运行；没有参数，没有返回值。
func _ready() -> void:
	_run.call_deferred()


# 作用：验证整条十站路线和本局数据；没有参数，没有返回值。
func _run() -> void:
	var run = root.get_node("RunManager")
	var start_data = load("res://data/run/run_start_data.tres").duplicate(true)
	# 隔离可配置的开局赠送遗物，血量/路线烟测使用无遗物的配方。
	start_data.starting_relics.clear()
	start_data.starting_potions.clear()
	run.selected_map = {}
	run.start_new_run(start_data)
	assert(run.hp == start_data.starting_hp and run.max_hp == start_data.max_hp and run.gold == start_data.starting_gold)
	assert(run.deck.size() == start_data.cards.size())
	var expected_hp: int = run.hp
	var expected_gold: int = run.gold
	var first_card = run.deck[0]
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(session)
	get_tree().current_scene = session
	await get_tree().process_frame
	await get_tree().process_frame
	var map = session.map_view
	assert(map.locations.size() == 19)
	# 开局应显示底部起点，而不是顶部 Boss。
	var bar: VScrollBar = map.scroll_container.get_v_scroll_bar()
	assert(map.scroll_container.scroll_vertical > 0)
	assert(absf(float(map.scroll_container.scroll_vertical) - (bar.max_value - bar.page)) <= 1.0)
	assert(session.get_node("HUDLayer/RunHUD/BisicUI/Hp/Hp").text == "%s/%s" % [run.hp, run.max_hp])
	assert(session.get_node("HUDLayer/RunHUD/BisicUI/GlodCoin/GlodCoinNumber").text == str(run.gold))
	# 所有边都只能前进一层；终点只存在于第十层，排除任何可跳关的路线。
	for location in map.locations:
		if location["next"].is_empty():
			assert(location["floor"] == 10)
		for next_id in location["next"]:
			var next = map._get_location(next_id)
			assert(next["floor"] == location["floor"] + 1)
			assert(next["map_pos"].y < location["map_pos"].y)

	# 尚未进入战斗也能查看完整牌组，而且没有新建或消耗真实卡牌。
	session.deck_button.pressed.emit()
	assert(session.deck_open and get_tree().paused)
	assert(session.deck_view.grid.get_child_count() == start_data.cards.size())
	var preview = session.deck_view.grid.get_child(0).get_child(0)
	assert(preview.card_instance == first_card)
	assert(preview._get_drag_data(Vector2.ZERO) == null)
	session.deck_view.close_requested.emit()
	assert(not get_tree().paused and not session.deck_open)

	var next_id: String = "battle_a"
	for floor_index in range(10):
		assert(map._can_enter(next_id))
		map.node_views[next_id]._on_pressed()
		await get_tree().create_timer(0.6).timeout
		var phase_script := root.get_node("Global").get_script() as Script
		if phase_script == null or not phase_script.can_instantiate():
			push_error("GAME_SESSION_SMOKE: Global 自动加载脚本初始化失败，停止测试以免逐帧重复报错。")
			get_tree().quit(1)
			return
		if is_instance_valid(session.current_battle):
			var battle = session.current_battle
			var manager = battle.hand_manager
			var innate_count: int = run.deck.filter(func(card: CardInstance): return card.definition.starts_in_hand).size()
			assert(manager.hand.size() == mini(manager.draw_per_turn + innate_count, run.deck.size()))
			assert(manager.hand.size() + manager.draw_pile.size() == run.deck.size())
			# 新战斗继承玩家剩余 HP，不能回满；金币和总牌组也继续保留。
			assert(run.hp == expected_hp)
			if floor_index == 0:
				# 从战斗和只读地图分别打开卡组，关闭后必须恢复各自的暂停状态。
				first_card.cost_increase = 2
				var timer: Timer = battle.battle_round_manager.battle_time
				timer.start(10.0)
				session.deck_button.pressed.emit()
				assert(session.deck_view.grid.get_child(0).get_child(0).get_node("CostIcon/CostLabel").text == str(first_card.definition.card_cost + 2))
				var remaining := timer.time_left
				await get_tree().create_timer(0.1).timeout
				assert(is_equal_approx(remaining, timer.time_left))
				assert(not battle.can_process())
				session.deck_view.close_requested.emit()
				assert(not get_tree().paused)
				session.map_button.pressed.emit()
				session.deck_button.pressed.emit()
				assert(first_card.cost_increase == 2, "战斗中查看地图不能重置加费")
				session.deck_view.close_requested.emit()
				assert(get_tree().paused and session.inspecting_map)
				session.map_button.pressed.emit()
				assert(not get_tree().paused)
				# 改动本局数值确认 HUD 同步，下一节点也继承这份剩余生命。
				run.hp -= 5
				run.gold += 11
				expected_hp -= 5
				expected_gold += 11
				assert(session.get_node("HUDLayer/RunHUD/BisicUI/Hp/Hp").text == "%s/%s" % [expected_hp, run.max_hp])
				assert(session.get_node("HUDLayer/RunHUD/BisicUI/GlodCoin/GlodCoinNumber").text == str(expected_gold))
			battle.finish_battle(true)
			assert(first_card.get_cost() == first_card.definition.card_cost)
			battle.get_node("GameOver")._on_button_pressed()
			await get_tree().process_frame
			await get_tree().process_frame
			if floor_index == 0:
				# 回到地图再点击牌库，原牌实例和卡面费用都已恢复，尚未进入下一场。
				assert(not is_instance_valid(session.current_battle))
				session.deck_button.pressed.emit()
				assert(session.deck_view.grid.get_child(0).get_child(0).get_node("CostIcon/CostLabel").text == str(first_card.definition.card_cost))
				session.deck_view.close_requested.emit()
		else:
			assert(map.event_panel.visible)
			# 普通事件与四选项篝火都以最后一项离开，不消耗训练或强化。
			map.event_panel._on_choice_pressed(map.event_panel.session.event.choices.size() - 1)
		assert(run.completed_ids.size() == floor_index + 1)
		assert(run.chapter_cleared == (floor_index == 9))
		assert(run.hp == expected_hp and run.gold == expected_gold)
		assert(run.deck.size() == start_data.cards.size() and run.deck[0] == first_card)
		if floor_index < 9:
			next_id = map._get_location(next_id)["next"][0]

	assert(not map._can_enter("boss"))
	assert("通关" in map.status_label.text)
	# 新局恢复初始值，上一局牌的实例和地图进度都不带过去。
	run.start_new_run(start_data)
	assert(run.hp == start_data.starting_hp and run.max_hp == start_data.max_hp and run.gold == start_data.starting_gold)
	assert(run.completed_ids.is_empty() and not run.chapter_cleared)
	assert(run.deck.size() == start_data.cards.size() and run.deck[0] != first_card)
	print("GAME_SESSION_SMOKE_PASS: stats, deck, pause, all routes 10 floors, reset")
	get_tree().quit()
