# 这玩意儿是干嘛的（核心逻辑）：自动检查路线导入、真实地图显示和按 Boss 终点通关。
# 数据是咋流动的（数据流向）：构造路线文件 → 主菜单导入 → 新局地图 → 模拟事件与战斗结算。
# 为啥这么写（选型决策）：使用游戏的真实菜单与地图，防止只验证 JSON 却漏掉游戏里的接线。
# 性能咋样（复杂度）：仅手动测试时执行几张小地图，正式游戏不加载此脚本。
extends SceneTree

const Config = preload("res://scripts/map/fixed_map_config.gd")
const TEST_PATH := "user://fixed_map_import_test.json"


# 作用：引擎启动测试时延迟到全局管理器就绪；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()


# 作用：生成不同长度的合法路线；count 为节点数，返回可导出的地图字典。
func _fixture(count: int) -> Dictionary:
	var nodes: Array = []
	for i in count:
		nodes.append({"id": "n%d" % i, "title": "节点 %d" % i,
			"type": 3 if i == count - 1 else 1, "event_id": "level_002" if i == count - 1 else "abandoned_camp",
			"floor": i + 1, "map_pos": {"x": 0.5, "y": 0.93 - float(i) / (count - 1) * 0.86},
			"next": [] if i == count - 1 else ["n%d" % (i + 1)]})
	return {"schema_version": 1, "mode": "fixed", "name": "测试路线", "floors": count,
		"starting_ids": ["n0"], "locations": nodes}


# 作用：把测试配置存为 JSON；data 为字典，没有返回值。
func _write_fixture(data: Dictionary) -> void:
	var file := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(data))
	file.close()


# 作用：运行导入和通关回归；没有参数，没有返回值，失败时由断言报告具体位置。
func _run() -> void:
	var run = root.get_node("RunManager")
	# 保存测试目录里的原选择，结束时恢复，避免测试改变人工测试留下的配置。
	var had_file := FileAccess.file_exists(run.IMPORTED_MAP_PATH)
	var saved_bytes := FileAccess.get_file_as_bytes(run.IMPORTED_MAP_PATH) if had_file else PackedByteArray()
	var original_selection: Dictionary = run.selected_map.duplicate(true)
	var short := _fixture(4)
	short.locations[0].event_id = ""
	short.locations[0].title = "自定义补给站"
	short.locations[0].event = {"description": "领取配置的补给。", "choices": [
		{"text": "领取", "heal": 99, "gold": 7}, {"text": "跳过", "heal": 0, "gold": 0}]}
	short.locations[1].type = 2
	short.locations[1].event = {"description": "自定义篝火", "choices": [
		{"text": "休息", "heal": 12, "gold": 0}, {"text": "离开", "heal": 0, "gold": 0}]}
	short.floors = 12
	short.locations[1].next = ["n2", "n3"]
	short.locations[2].floor = 8
	short.locations[3].floor = 12
	assert(Config.validate(short).is_empty())
	# 地图直接读取关卡文件，旧的间接编号不再接受。
	var session = load("res://scenes/app/game_session.tscn").instantiate()
	assert(session.resolve_level("level_001") == load("res://data/levels/level_001.tres"))
	assert(session.resolve_level("level_002") == load("res://data/levels/level_002.tres"))
	assert(session.resolve_level("battle_01") == null)
	assert(session.resolve_level("level_missing") == null)
	session.free()
	var direct := short.duplicate(true)
	direct.locations[3].event_id = "level_002"
	assert(Config.validate(direct).is_empty())
	direct.locations[3].event_id = "level_missing"
	assert("找不到战斗关卡" in Config.validate(direct))
	direct.locations[3].event_id = "level_../../invalid"
	assert(not Config.validate(direct).is_empty())
	var broken_event := short.duplicate(true)
	broken_event.locations[0].event.choices[0].heal = -1
	assert(not Config.validate(broken_event).is_empty())
	broken_event = short.duplicate(true)
	broken_event.locations[0].event.choices.clear()
	assert(not Config.validate(broken_event).is_empty())
	assert(Config.parse_text("{").has("error"))
	var bad := short.duplicate(true)
	bad.locations[1].next = ["missing"]
	assert(not Config.validate(bad).is_empty())
	bad = short.duplicate(true)
	bad.locations[1].next = ["n0"]
	assert(not Config.validate(bad).is_empty())
	bad = short.duplicate(true)
	bad.starting_ids = ["n3"]
	assert(not Config.validate(bad).is_empty())
	bad = short.duplicate(true)
	bad.locations[3].type = 0
	assert(not Config.validate(bad).is_empty())
	bad = short.duplicate(true)
	bad.locations[0].id = "n1"
	assert(not Config.validate(bad).is_empty())
	bad = short.duplicate(true)
	bad.locations[0].map_pos.x = 2
	assert(not Config.validate(bad).is_empty())

	# 走真实主菜单的回调，验证导入成功后文案、持久化与新局副本一致。
	_write_fixture(short)
	var menu = load("res://scenes/ui/main_ui.tscn").instantiate()
	root.add_child(menu)
	menu._on_route_selected(ProjectSettings.globalize_path(TEST_PATH))
	assert("测试路线" in menu.route_status.text)
	assert(FileAccess.file_exists(run.IMPORTED_MAP_PATH))
	assert(Config.read_file(run.IMPORTED_MAP_PATH).has("data"))
	run.start_new_run()
	assert(run.active_map.locations.size() == 4)
	_write_fixture(bad)
	assert(not run.import_fixed_map(TEST_PATH).is_empty())
	assert(run.selected_map.locations.size() == 4)
	assert(Config.read_file(run.IMPORTED_MAP_PATH).data.locations.size() == 4)

	# 成功导入另一张地图也只影响下局，当前地图仍保持四节点路线。
	_write_fixture(_fixture(12))
	assert(run.import_fixed_map(TEST_PATH).is_empty())
	assert(run.active_map.locations.size() == 4)
	menu.queue_free()
	var map = load("res://scenes/map/map.tscn").instantiate()
	root.add_child(map)
	await process_frame
	await process_frame
	assert(map.locations.size() == 4 and map.node_views.size() == 4)
	assert(map.floor_count == 12 and map.map_name == "测试路线")
	assert(map.locations[0].map_pos is Vector2)
	assert(map._can_enter("n0") and not map._can_enter("n3"))
	# 普通事件结算会更新 RunManager，之后只能走当前节点配置的出边。
	run.hp = run.max_hp - 5
	var gold_before: int = run.gold
	map._on_node_enter_requested(map.node_views.n0)
	assert(map.event_panel.title_label.text == "自定义补给站")
	assert(map.event_panel.description_label.text == "领取配置的补给。")
	assert("领取" in map.event_panel.choice_1.text)
	map.event_panel._on_choice_pressed(0)
	assert(not run.completed_ids.has("n0"))
	map.event_panel._finish()
	assert(run.hp == run.max_hp and run.gold == gold_before + 7)
	map._on_event_resolved(0)
	assert(run.gold == gold_before + 7)

	assert(map._can_enter("n1") and not map._can_enter("n3"))
	run.hp = run.max_hp - 20
	map._on_node_enter_requested(map.node_views.n1)
	map.event_panel._on_choice_pressed(0)
	assert(run.hp == run.max_hp - 8 and run.gold == gold_before + 7)
	map.event_panel._finish()
	assert(map._can_enter("n2") and map._can_enter("n3"))
	run.begin_battle("n3", "level_002")
	run.complete_battle()
	map.resume_after_battle()
	assert(run.chapter_cleared and run.completed_ids.size() == 3)
	assert("通关" in map.status_label.text and not map._can_enter("n2"))
	map.queue_free()
	await process_frame

	# 十二站长路线完成第十站仍不能通关，必须击败配置里的最后一个 Boss。
	run.start_new_run()
	for i in 12:
		run.complete_location("n%d" % i)
		assert(run.chapter_cleared == (i == 11))
	assert(run.use_default_map().is_empty())
	run.start_new_run()
	assert(run.active_map.is_empty() and not run.chapter_cleared)
	var fallback = load("res://scenes/map/map.tscn").instantiate()
	root.add_child(fallback)
	await process_frame
	assert(fallback.locations.size() == 19 and fallback._can_enter("battle_a"))
	fallback.queue_free()
	await process_frame

	# 恢复测试前的选择；临时文件只属于这次测试，可以直接清理。
	if had_file:
		var restore := FileAccess.open(run.IMPORTED_MAP_PATH, FileAccess.WRITE)
		restore.store_buffer(saved_bytes)
		restore.close()
	run.selected_map = original_selection
	DirAccess.remove_absolute(TEST_PATH)
	print("FIXED_MAP_IMPORT_PASS: validation, menu, persistence, atomic rejection, snapshot, routes, short/long completion, fallback")
	quit()
