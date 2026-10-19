# 使用真正的工坊按钮、Boss 奖励、幕间地图和存档检查三幕征途。
extends SceneTree

const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const PATHS: Array[String] = ["user://three_act_1.json", "user://three_act_2.json", "user://three_act_3.json"]
var run
var editor
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error(message)

func _fixture(act: int) -> Dictionary:
	return {"schema_version": 1, "mode": "fixed", "name": "第%d幕 · 测试路线" % act,
		"floors": 2, "starting_ids": ["entry"], "locations": [
			{"id": "entry", "title": "补给", "type": 1, "event_id": "", "floor": 1,
				"map_pos": {"x": 0.5, "y": 0.93}, "next": ["boss"],
				"event": {"description": "本幕补给", "choices": [
					{"text": "领取", "heal": 0, "gold": act * 7}, {"text": "离开", "heal": 0, "gold": 0}]}},
			{"id": "boss", "title": "首领", "type": 3, "event_id": "level_002", "floor": 2,
				"map_pos": {"x": 0.5, "y": 0.07}, "next": [],
				"battle_rewards": {"gold": act * 19, "potion_chance": 0.0, "relic_chance": 0.0}}
		]}

func _apply(act: int) -> void:
	editor.doc.new_map()
	editor.doc.data = _fixture(act)
	editor.doc.normalize()
	editor.doc.changed.emit()
	editor.apply_act_input.select(act - 1)
	editor.apply_game_button.pressed.emit()

func _settle() -> void:
	await process_frame
	await process_frame
	var transition := root.get_node("SceneTransition")
	var deadline := Time.get_ticks_msec() + 15000
	while transition.busy:
		assert(Time.get_ticks_msec() < deadline, "幕间切换未结束")
		await process_frame
	await process_frame

func _menu() -> Node:
	if is_instance_valid(current_scene):
		current_scene.free()
	var menu = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	return menu

func _carry() -> Dictionary:
	var state: Resource = run.create_save_data()
	return {"hp": run.hp, "max_hp": run.max_hp, "gold": run.gold,
		"cards": state.card_states, "relics": run.relics.map(func(item): return item.id),
		"potions": run.potions.map(func(item): return item.id), "draws": run.relic_draw_counts.duplicate(true),
		"defence": run.base_defence, "energy": run.bonus_energy_max, "removals": run.shop_removal_count}

func _boss_rewards(game: Node) -> Node:
	game.map_view._on_node_enter_requested(game.map_view.node_views.entry)
	game.map_view.event_panel._on_choice_pressed(0)
	game.map_view.event_panel._finish()
	game.map_view._on_node_enter_requested(game.map_view.node_views.boss)
	await _settle()
	check(is_instance_valid(game.current_battle), "Boss 使用真实地图战斗入口")
	game.current_battle.finish_battle(true)
	await process_frame
	return game.current_battle.get_node("GameOver")

func _shot(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.maintenance/three-act-" + name + ".png") == OK, "实际界面截图")

func _run() -> void:
	run = root.get_node("RunManager")
	if "--verify-three-act" in OS.get_cmdline_user_args():
		check(run.load_saved_run().is_empty(), "新进程读取三幕存档")
		check(run.current_act == 2 and run.active_act_maps.size() == 3 and run.active_map.name == _fixture(2).name, "跨进程恢复第二幕和三幕快照")
		check(run.hp == 85 and run.max_hp == 122 and run.gold == 237 and run.deck[0].attack_points == 3 and run.deck[0].upgrade_count == 1, "跨进程恢复资源与永久强化")
		check(run.relics.size() == 1 and run.potions.size() == 1 and run.active_act_maps[2].locations[1].battle_rewards.gold == 57, "跨进程恢复物品与后续幕奖励")
		print("THREE_ACT_RESTART_PASS: %d checks; failures=%s" % [checks, failures])
		quit(0 if failures.is_empty() else 1)
		return
	var transition := root.get_node("SceneTransition")
	var original_paths: Array[String] = run.project_map_paths.duplicate()
	var original_selection: Dictionary = run.selected_map.duplicate(true)
	var original_act_selection: Array[Dictionary] = run.selected_act_maps.duplicate(true)
	var original_motion: bool = transition.reduced_motion
	var original_fps: int = root.get_node("GameSettings").video.fps
	var had_save := FileAccess.file_exists(run.SAVE_PATH)
	var original_save := FileAccess.get_file_as_bytes(run.SAVE_PATH) if had_save else PackedByteArray()
	transition.reduced_motion = true
	root.get_node("GameSettings").set_video("fps", 0)
	run.project_map_paths.assign(PATHS)
	for path in PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	editor = load("res://addons/map_editor/editor.gd").new()
	editor.game_map_paths.assign(PATHS)
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	check(editor.apply_act_input.item_count == 3, "工坊提供第一、第二、第三幕选择")
	_apply(3)
	check(FileAccess.file_exists(PATHS[2]) and not FileAccess.file_exists(PATHS[0]), "先应用第三幕仅写入第三幕")
	check("第3幕" in editor.status.text, "应用成功提示对应幕")
	check(not run.reload_map_selection().is_empty(), "缺少第一幕时不能从第三幕开始")
	_apply(1)
	_apply(2)
	var before: Array[String] = []
	for path in PATHS:
		before.append(FileAccess.get_sha256(path))
	editor.doc.begin()
	editor.doc.find("entry").next.append("missing")
	editor.doc.commit()
	editor.apply_game_button.pressed.emit()
	for index in 3:
		check(FileAccess.get_sha256(PATHS[index]) == before[index], "无效应用不会覆盖任何幕")
	editor.doc.undo()
	_apply(3)
	await _shot("workshop")
	editor.hide()
	check(run.reload_map_selection().is_empty() and run.selected_act_maps.size() == 3, "一次读取三幕正式路线")
	var fresh = load("res://autoload/run_manager.gd").new()
	fresh.project_map_paths.assign(PATHS)
	root.add_child(fresh)
	check(fresh.current_act == 1 and fresh.active_act_maps.size() == 3 and fresh.active_map.name == _fixture(1).name, "管理器启动从第一幕开始并冻结三幕")
	fresh.free()
	var menu = _menu()
	check(run.selected_act_maps.size() == 3 and "三幕征途" in menu.route_status.text, "主菜单保留三幕配置与当前路线")
	check(not menu.panels.has("routes") and menu.menu_buttons[1] == menu.continue_button, "主菜单工坊入口已替换为继续征途")
	menu._on_start_pressed()
	await _settle()
	var game = current_scene
	check(run.current_act == 1 and not run.run_cleared, "正常开始征途进入第一幕")
	check(not run.advance_act().is_empty() and run.current_act == 1, "未通关本幕不能提前进入下一幕")
	run.max_hp = 110
	run.hp = 73
	run.gold = 211
	run.base_defence = 3
	run.bonus_energy_max = 2
	run.shop_removal_count = 2
	run.relic_draw_counts["draw_engine"] = 8
	run.add_relic(load("res://data/relics/traveler_amulet.tres"))
	run.add_potion(load("res://data/potions/fire.tres"))
	run.deck[0].upgrade_count = 1
	run.deck[0].attack_points = 3
	var result = await _boss_rewards(game)
	check(run.current_act == 1 and not run.chapter_cleared and not run.run_cleared, "Boss 胜利后先处理奖励，不提前跳幕")
	check(result.reward_session.claim(0) and result.reward_session.claim(1, 0), "第一幕领取金币和卡牌奖励")
	var carry_before: Dictionary = _carry()
	var cards_before: Array = run.deck.duplicate()
	var serial: int = run.run_serial
	run.begin_shop("entry", "res://data/shops/caravan.json")
	var old_map = game.map_view
	result._on_button_pressed()
	await _settle()
	check(run.current_act == 2 and game.map_view.map_name == _fixture(2).name, "第一幕奖励继续后自动进入第二幕")
	check(not is_instance_valid(old_map) and not is_instance_valid(game.current_battle), "旧地图和旧战斗完整释放")
	check(_carry() == carry_before and run.deck == cards_before and run.run_serial == serial, "跨幕保留全部资源、独立牌实例和强化")
	check(run.completed_ids.is_empty() and run.current_id.is_empty() and run.shop_visits.is_empty(), "跨幕清理进度和同名节点的商店缓存")
	check(game.map_view._can_enter("entry") and not run.chapter_cleared and not run.run_cleared, "新幕的同名起点可以进入")
	check("第2幕" in game.get_node("HUDLayer/RunHUD/BisicUI/ChapterBanner/Charpter").text, "顶部标题正确显示第二幕")
	await _shot("act-2")
	check(run.save_run().is_empty(), "第二幕可保存整局快照")
	check("\nversion = 2" in FileAccess.get_file_as_string(run.SAVE_PATH), "新存档显式保存版本号")
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "--script", "res://tests/three_act_test.gd", "--", "--no-mcp-server", "--verify-three-act"], output, true)
	check(code == 0 and "THREE_ACT_RESTART_PASS" in "\n".join(output) and "failures=[]" in "\n".join(output), "独立引擎进程恢复三幕征途")
	# 编辑已配置的后续幕，不改变本局与存档冻结的第三幕。
	_apply(3)
	editor._map_name("修改后的第三幕")
	editor.doc.begin()
	editor.doc.find("boss").battle_rewards.gold = 999
	editor.doc.commit()
	editor.apply_game_button.pressed.emit()
	check(run.active_act_maps[2].name == _fixture(3).name and run.active_act_maps[2].locations[1].battle_rewards.gold == 57, "后续幕保持开局冻结的路线与奖励")
	for path in PATHS:
		DirAccess.remove_absolute(path)
	menu = _menu()
	run.gold = 1
	menu._on_continue_pressed()
	await _settle()
	game = current_scene
	check(run.current_act == 2 and game.map_view.map_name == _fixture(2).name and _carry() == carry_before, "项目路线文件删除后仍可从存档恢复第二幕和资源")
	check(run.active_act_maps[2].name == _fixture(3).name, "存档保留第三幕路线快照")
	result = await _boss_rewards(game)
	check(result.reward_session.claim(0), "第二幕金币可领取")
	result.reward_session.skip_cards()
	carry_before = _carry()
	result._on_button_pressed()
	await _settle()
	check(run.current_act == 3 and game.map_view.map_name == _fixture(3).name and _carry() == carry_before, "第二幕打通后自动进入第三幕并保留奖励")
	check(not run.run_cleared and not game.completion_panel.visible, "进入第三幕仍未整局通关")
	check(game.map_view._can_enter("entry") and run.map_terminal_ids == ["boss"], "第三幕起点与 Boss 独立生效")
	result = await _boss_rewards(game)
	check(result.reward_session.claim(0) and result.reward_session.offers[0].amount == 57, "第三幕仍使用存档冻结的 Boss 金币")
	result.reward_session.skip_cards()
	check(not run.run_cleared, "第三幕奖励完成前不结束整局")
	carry_before = _carry()
	result._on_button_pressed()
	await _settle()
	check(run.current_act == 3 and run.chapter_cleared and run.run_cleared, "第三幕 Boss 完成后整局通关")
	check(game.completion_panel.visible and game.completion_panel.completed and not game.completion_panel.retry_button.visible, "通关显示胜利面板且不提供第四幕")
	check(_carry() == carry_before and not run.advance_act().is_empty() and run.current_act == 3, "结束征途保留最终奖励且无法继续跳幕")
	await _shot("victory")
	game._on_deck_pressed()
	game._on_settings_pressed()
	check(not game.deck_open and not game.pause_menu.opened, "胜利面板阻止背景操作")
	game.completion_panel.menu_button.pressed.emit()
	await _settle()
	check(current_scene.scene_file_path == "res://scenes/ui/main_ui.tscn" and not paused, "通关可正常返回主菜单")
	# 下一幕未配置或损坏时保留幕完成状态；补齐后可重试。
	_apply(1)
	run.reload_map_selection()
	run.start_new_run()
	run.complete_location("boss")
	current_scene.free()
	game = load("res://scenes/app/game_session.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	check(not game._advance_to_next_act() and run.current_act == 1 and not run.run_cleared, "第二幕未配置不会误判征途通关")
	check(game.completion_panel.visible and "第2幕尚未配置" in game.completion_panel.description.text, "缺失下一幕显示明确提示")
	_apply(2)
	check(editor.doc.write_json(PATHS[1], "{}"), "构造损坏的第二幕文件")
	check(not run.advance_act().is_empty() and run.current_act == 1, "损坏的下一幕不能推进")
	_apply(2)
	game.completion_panel.retry_button.pressed.emit()
	await _settle()
	check(run.current_act == 2 and not game.completion_panel.visible, "应用第二幕后通过实际按钮重试进入")
	run.complete_location("boss")
	check(not run.run_cleared and not run.advance_act().is_empty(), "第二幕完成且第三幕缺失时仍未整局通关")
	_apply(3)
	check(run.advance_act().is_empty() and run.current_act == 3, "补齐第三幕后可继续第三幕")
	# v1 存档升级为独立单幕，不引入项目新三幕配置。
	current_scene.free()
	current_scene = null
	run.use_default_map()
	run.start_new_run()
	run.active_map = _fixture(1)
	run.map_terminal_ids.assign(["boss"])
	run.completed_ids.assign(["entry"])
	run.current_id = "entry"
	var legacy: Resource = run.create_save_data()
	legacy.version = 1
	for key in run.ACT_SAVE_KEYS:
		legacy.state.erase(key)
	check(ResourceSaver.save(legacy, run.SAVE_PATH) == OK, "构造旧版本存档")
	check(not "\nversion =" in FileAccess.get_file_as_string(run.SAVE_PATH), "真实旧存档省略默认版本号")
	check(run.load_saved_run().is_empty() and run.current_act == 1 and run.active_act_maps.size() == 1 and run.completed_ids == ["entry"], "旧存档升级后保持原路线和进度")
	var invalid: Resource = run.create_save_data()
	invalid.state.current_act = 4
	ResourceSaver.save(invalid, run.SAVE_PATH)
	check(not run.load_saved_run().is_empty() and run.current_act == 1, "坏幕编号存档被拒绝且不修改本局")
	for path in PATHS + [editor.doc.RECOVERY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	editor.free()
	if had_save:
		var file := FileAccess.open(run.SAVE_PATH, FileAccess.WRITE)
		file.store_buffer(original_save)
		file.close()
	else:
		DirAccess.remove_absolute(run.SAVE_PATH)
	run.project_map_paths.assign(original_paths)
	run.selected_map = original_selection
	run.selected_act_maps.assign(original_act_selection)
	transition.reduced_motion = original_motion
	root.get_node("GameSettings").set_video("fps", original_fps)
	await process_frame
	print("THREE_ACT_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
