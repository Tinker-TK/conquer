# 工坊正式路线 → 启动加载 / 主菜单新征途 → 真实地图，同时检查旧存档不受影响。
extends SceneTree

const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const TARGET := "user://map_direct_apply.json"
const SOURCE := "user://map_direct_source.json"
const LEGACY := "user://map_direct_legacy.json"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error(message)

func _fixture() -> Dictionary:
	return {"schema_version": 1, "mode": "fixed", "name": "正式路线", "floors": 3,
		"starting_ids": ["entry"], "locations": [
			{"id": "entry", "title": "补给", "type": 1, "event_id": "", "floor": 1,
				"map_pos": {"x": 0.5, "y": 0.93}, "next": ["rest", "treasure"],
				"event": {"description": "工坊的补给", "choices": [
					{"text": "领取补给", "heal": 0, "gold": 37}, {"text": "离开", "heal": 0, "gold": 0}]}},
			{"id": "rest", "title": "篝火", "type": 2, "event_id": "campfire", "floor": 2,
				"map_pos": {"x": 0.3, "y": 0.5}, "next": ["boss"]},
			{"id": "treasure", "title": "宝箱", "type": 4, "event_id": "", "floor": 2,
				"map_pos": {"x": 0.7, "y": 0.5}, "next": ["boss"]},
			{"id": "boss", "title": "首领", "type": 3, "event_id": "level_002", "floor": 3,
				"map_pos": {"x": 0.5, "y": 0.07}, "next": [],
				"battle_rewards": {"gold": 83, "potion_chance": 17.0, "relic_chance": 9.0}}
		]}

func _menu() -> Node:
	if is_instance_valid(current_scene):
		current_scene.free()
	var menu = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	return menu

func _wait_transition() -> void:
	var transition := root.get_node("SceneTransition")
	var deadline := Time.get_ticks_msec() + 15000
	while transition.busy:
		assert(Time.get_ticks_msec() < deadline, "真实新征途切场超时")
		await process_frame
	await process_frame

func _capture(name: String) -> void:
	if DisplayServer.get_name() == "headless" or not "--capture" in OS.get_cmdline_user_args():
		return
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png("res://.maintenance/" + name + ".png") == OK, "截图保存")

func _run() -> void:
	var run = root.get_node("RunManager")
	var transition := root.get_node("SceneTransition")
	var original_path: String = run.project_map_path
	var original_selection: Dictionary = run.selected_map.duplicate(true)
	var original_motion: bool = transition.reduced_motion
	transition.reduced_motion = true
	# 所有应用、恢复、导入与存档都写入隔离用户目录，不修改正式地图。
	run.project_map_path = TARGET
	run.use_default_map()
	var editor = load("res://addons/map_editor/editor.gd").new()
	editor.game_map_path = TARGET
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var doc = editor.doc
	doc.new_map()
	doc.data = _fixture()
	doc.normalize()
	doc.changed.emit()
	check(CONFIG.validate(doc.data).is_empty(), "工坊测试路线完整有效")
	check(doc.save(SOURCE), "保留原始地图文件")
	var source_text := FileAccess.get_file_as_string(SOURCE)
	var saved_text: String = doc.saved_text
	editor.name_input.text = "工坊应用 A"
	editor.name_input.grab_focus()
	editor.apply_game_button.pressed.emit()
	var applied := CONFIG.read_file(TARGET)
	check(applied.has("data") and applied.data.name == "工坊应用 A", "按钮包含未按回车的地图名称")
	check("已应用" in editor.status.text and editor.apply_game_button.text == "应用到游戏", "按钮接线并显示应用成功")
	check(doc.path == SOURCE and doc.saved_text == saved_text and doc.is_dirty(), "应用不清除草稿修改或切换原文件")
	check(FileAccess.get_file_as_string(SOURCE) == source_text, "应用不改写原始路线文件")
	var drag_start: Vector2 = editor.canvas.point(doc.find("rest"))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = drag_start
	editor.canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = drag_start + Vector2(-25, 0)
	editor.canvas._gui_input(motion)
	check(editor.canvas.dragging and editor.canvas.dragged, "实际画布拖动尚未提交")
	editor.apply_game_button.pressed.emit()
	var dragged := CONFIG.read_file(TARGET)
	check(not editor.canvas.dragging and dragged.data.locations[1].map_pos.x == doc.find("rest").map_pos.x, "应用按钮提交画布拖动后的坐标")
	var stable_text := FileAccess.get_file_as_string(TARGET)
	doc.data["test_extra"] = "x".repeat(CONFIG.MAX_BYTES)
	editor.apply_game_button.pressed.emit()
	check("2 MB" in editor.status.text and FileAccess.get_file_as_string(TARGET) == stable_text, "超过读取上限的路线不覆盖正式配置")
	doc.data.erase("test_extra")
	doc.begin()
	doc.find("entry").next.append("missing")
	doc.commit()
	editor.apply_game_button.pressed.emit()
	check("不能应用" in editor.status.text and FileAccess.get_file_as_string(TARGET) == stable_text, "无效路线不覆盖上次正式路线")
	doc.undo()
	# 无法创建临时文件时保留旧配置并提示真实写入错误。
	editor.game_map_path = "user://missing_directory/route.json"
	editor.apply_game_button.pressed.emit()
	check("失败" in editor.status.text and FileAccess.get_file_as_string(TARGET) == stable_text, "写入失败不改变正式路线")
	editor.game_map_path = TARGET
	var legacy: Dictionary = doc.data.duplicate(true)
	legacy.name = "旧导入路线"
	check(doc.write_json(LEGACY, JSON.stringify(legacy)) and run.import_fixed_map(LEGACY).is_empty(), "保留旧版本导入兼容")
	check(run.reload_map_selection().is_empty() and run.selected_map.name == "工坊应用 A", "项目正式路线优先于旧的用户导入")
	# 使用新的管理器实际执行 _ready，验证不依赖编辑器内存或主菜单导入。
	var fresh = load("res://autoload/run_manager.gd").new()
	fresh.project_map_path = TARGET
	root.add_child(fresh)
	check(fresh.selected_map.name == "工坊应用 A" and fresh.active_map.name == "工坊应用 A", "新的管理器启动时直接加载工坊路线")
	fresh.free()
	var preset := ConfigFile.new()
	check(preset.load("res://export_presets.cfg") == OK and "data/**/*.json" in str(preset.get_value("preset.0", "include_filter")), "发行配置包含项目正式路线 JSON")
	editor.apply_game_button.pressed.emit()
	await _capture("map-direct-apply-editor")
	editor.hide()
	var menu = _menu()
	check("工坊应用 A" in menu.route_status.text, "主菜单直接显示工坊正式路线")
	check(menu.menu_buttons[1] == menu.continue_button and not menu.panels.has("routes"), "第二行用于继续征途，主菜单不再包含路线工坊")
	menu._on_start_pressed()
	await _wait_transition()
	var game = current_scene
	check(game.scene_file_path == "res://scenes/app/game_session.tscn" and game.map_view.map_name == "工坊应用 A", "开始征途进入正式路线的真实游戏")
	check(game.map_view.node_views.size() == 4 and game.map_view.starting_ids == ["entry"], "游戏使用工坊节点与出发点")
	check(game.map_view.locations[0].next == ["rest", "treasure"] and run.map_terminal_ids == ["boss"], "分叉连线与 Boss 终点一致")
	check(run.active_map.locations[3].battle_rewards.gold == 83 and run.active_map.locations[3].battle_rewards.potion_chance == 17.0, "节点战斗奖励随正式路线载入")
	var gold_before: int = run.gold
	game.map_view._on_node_enter_requested(game.map_view.node_views.entry)
	game.map_view.event_panel._on_choice_pressed(0)
	game.map_view.event_panel._finish()
	check(run.gold == gold_before + 37 and run.completed_ids == ["entry"], "工坊事件在真实地图中结算并推进")
	check(run.save_run().is_empty(), "旧路线存档可保存")
	var saved_gold: int = run.gold
	var active_before: Dictionary = run.active_map.duplicate(true)
	editor._map_name("工坊应用 B")
	editor.apply_game_button.pressed.emit()
	check(run.active_map == active_before and run.completed_ids == ["entry"], "更新正式路线不改变运行中的本局")
	menu = _menu()
	check(run.selected_map.name == "工坊应用 B", "再次打开主菜单读取新正式路线")
	menu._on_continue_pressed()
	await _wait_transition()
	check(current_scene.map_view.map_name == "工坊应用 A" and run.gold == saved_gold and run.completed_ids == ["entry"], "继续存档保持旧路线、奖励和进度")
	menu = _menu()
	# 菜单已经打开时工坊再应用，开始按钮仍读取最新磁盘配置。
	editor._map_name("工坊应用 C")
	editor.apply_game_button.pressed.emit()
	menu._on_start_pressed()
	await _wait_transition()
	check(current_scene.map_view.map_name == "工坊应用 C" and run.completed_ids.is_empty() and run.gold == gold_before, "主菜单打开后应用的新地图用于下一局")
	await _capture("map-direct-apply-game")
	menu = _menu()
	var valid_text := FileAccess.get_file_as_string(TARGET)
	check(doc.write_json(TARGET, "{}"), "构造损坏的正式路线")
	var serial: int = run.run_serial
	var selected_before: Dictionary = run.selected_map.duplicate(true)
	menu._on_start_pressed()
	check(current_scene == menu and not menu.leaving and run.run_serial == serial and menu.route_error.visible, "损坏的正式路线阻止错误开局并提示原因")
	check(run.selected_map == selected_before, "读盘失败保持上次有效选择")
	check(doc.write_json(TARGET, valid_text) and run.reload_map_selection().is_empty(), "修复后重新读取成功")
	menu.free()
	current_scene = null
	editor.free()
	DirAccess.remove_absolute(TARGET)
	check(run.reload_map_selection().is_empty() and run.selected_map.name == "旧导入路线", "未应用正式路线时兼容旧导入")
	check(run.use_default_map().is_empty() and run.reload_map_selection().is_empty() and run.selected_map.is_empty(), "无正式路线及旧导入时使用内置地图")
	for path in [SOURCE, LEGACY, run.SAVE_PATH, doc.RECOVERY]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	run.project_map_path = original_path
	run.selected_map = original_selection
	transition.reduced_motion = original_motion
	await process_frame
	await process_frame
	print("MAP_DIRECT_APPLY_TEST: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
