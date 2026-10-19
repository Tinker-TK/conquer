# 这玩意儿是干嘛的（核心逻辑）：验证原生地图工坊的编辑、文件保护和游戏数据兼容。
# 数据是咋流动的（数据流向）：测试面板 → 模拟节点和属性操作 → 保存重读 → 共用地图校验器。
# 为啥这么写（选型决策）：测试真实面板与文档，保证 UI 编辑不是只改了显示文字。
# 性能咋样（复杂度）：仅手动运行，使用独立用户目录里的小 JSON 文件，正常游戏不加载。
extends SceneTree

var failures: Array[String] = []
var checks := 0
const DOC = preload("res://addons/map_editor/document.gd")
const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const TARGET := "user://map_editor_test.json"

# 作用：引擎初始化后安排测试；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()

# 作用：记录检查结果；passed 为是否通过，message 为检查含义，没有返回值。
func check(passed: bool, message: String) -> void:
	checks += 1
	if not passed:
		failures.append(message)
		push_error(message)

# 作用：执行真实编辑操作回归；没有参数，没有返回值。
func _run() -> void:
	# 本测试使用独立用户目录；关卡参数仅在内存补齐，不保存策划的正式资源。
	var configs: Array[Resource] = []
	var originals: Array = []
	for id in ["level_001", "level_002"]:
		var config: Resource = load(CONFIG.level_path(id))
		configs.append(config)
		originals.append(config.waves.duplicate())
		if config.waves.is_empty():
			config.waves.append(load("res://scenes/levels/waves/wave_01.tscn"))
	var editor = load("res://addons/map_editor/editor.gd").new()
	root.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await process_frame
	await process_frame
	var doc = editor.doc
	doc.new_map(true)
	editor._picked("floor_05_01")
	check(doc.node().type == 4 and editor.kind_input.get_item_text(4) == "宝箱", "工坊示例与类型列表支持宝箱")
	check(editor.treasure_hint.visible and not editor.event_box.visible and not editor.level_box.visible, "宝箱展示固定奖励规则，无需配置关卡或选项")
	editor._kind_changed(1)
	check(doc.node().event.choices.size() == 2 and editor.event_box.visible, "宝箱可切换为普通事件并补齐模板")
	editor._kind_changed(4)
	check(CONFIG.event_content(doc.node()).choices[0].effect.type == "random_relic", "转回宝箱恢复随机遗物规则")
	_test_event_bindings(editor)
	doc.new_map(true)
	check(CONFIG.validate(doc.data).is_empty(), "示例可在游戏内使用")
	var original: Dictionary = doc.data.duplicate(true)
	doc.add_node(1, 2, 0.7)
	var id: String = doc.selection
	check(id == "floor_02_03", "新节点统一编号且无重复")
	check(doc.node().event.choices.size() == 2, "事件默认可编辑")
	doc.undo()
	check(doc.data == original, "新增节点可撤销")
	doc.redo()
	check(not doc.find(id).is_empty(), "新增节点可重做")
	check(doc.connect_nodes("floor_01_01", id), "可以连接分支")
	check(not doc.connect_nodes(id, "floor_01_01"), "阻止反向连接")
	doc.selection = id
	check(doc.rename_node("custom_event"), "支持手动编号")
	check(doc.find("floor_01_01").next.has("custom_event"), "改名同步路线引用")
	doc.delete_node()
	check(not doc.find("floor_01_01").next.has("custom_event"), "删除清理入边")
	doc.undo()
	check(doc.find("floor_01_01").next.has("custom_event"), "撤销删除恢复入边")
	doc.new_map(true)
	editor._picked("floor_02_02")
	editor._choice_number(37, 0, "heal")
	editor._choice_text("自定义休息", 0)
	editor.description_input.text = "这是工坊配置的篝火。"
	editor._description_changed()
	check(doc.node().event.choices[0].heal == 37 and doc.node().event.choices[0].text == "自定义休息", "事件奖励和选项来自表单")
	check(doc.node().event.description == "这是工坊配置的篝火。", "描述提交到数据")
	check(doc.save(TARGET), "保存 JSON")
	check(not doc.is_dirty(), "保存清除未保存标记")
	var other = DOC.new()
	check(other.open(TARGET), "重读原生文件")
	check(other.data == doc.data, "JSON 无损回读事件和路线")
	check(CONFIG.read_file(TARGET).has("data"), "保存文件兼容游戏导入")
	doc.begin()
	doc.data.name = "变更名称"
	doc.commit()
	check(doc.write_recovery(), "草稿恢复副本可写")
	var recovered = DOC.new()
	check(recovered.recover() and recovered.data.name == "变更名称", "恢复包含未保存修改")
	var file := FileAccess.open(TARGET, FileAccess.WRITE)
	file.store_string("{}")
	file.close()
	check(not doc.save() and doc.is_dirty(), "外部修改不会被覆盖")
	var bad := {"schema_version": 1, "mode": "fixed", "name": "坏文件", "floors": 10, "locations": [{}], "starting_ids": []}
	check(not doc.draft_error(bad).is_empty(), "坏节点文件被拒绝")
	check(doc.save("user://map_editor_test_other.json"), "冲突后可以另存为")
	editor._mode_changed(2)
	check(editor.canvas.available().size() == 2, "试玩初始只开放出发点")
	editor.canvas.journey.append("floor_01_01")
	check(editor.canvas.available() == doc.find("floor_01_01").next, "试玩只开放当前节点后续路线")
	editor._mode_changed(0)
	doc.selection = "floor_02_02"
	editor._refresh()
	var start: Vector2 = editor.canvas.point(doc.node())
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = start
	editor.canvas._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = start + Vector2(-35, -100)
	editor.canvas._gui_input(motion)
	editor.canvas.finish_drag()
	check(doc.node().floor == 3, "拖动自动吸附更高层")
	doc.undo()
	check(doc.find("floor_02_02").floor == 2, "整次拖动可一步撤销")
	editor.description_input.grab_focus()
	editor.description_input.text = "尚未离开输入框的描述"
	editor.flush_input()
	check(doc.node().event.description == "尚未离开输入框的描述", "保存前提交仍有焦点的描述")
	editor.canvas.grab_focus()
	editor._launch()
	check(CONFIG.read_file("user://map_editor_playtest.json").has("data"), "实战快照通过游戏校验")
	var bootstrap = load("res://addons/map_editor/playtest.gd").new()
	root.add_child(bootstrap)
	await process_frame
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.get_script() == load("res://scripts/app/game_session.gd"), "实战入口打开真正 GameSession")
	check(root.get_node("RunManager").active_map.name == doc.data.name, "实战使用当前草稿地图")
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	bootstrap.queue_free()
	await process_frame
	# 布局截图仅在有图形渲染且显式请求时输出，自动检查可以纯 headless 运行。
	if OS.get_cmdline_user_args().has("--capture"):
		editor._scroll_to_start()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/map_editor_preview.png")
	editor.free()
	for i in configs.size():
		configs[i].waves.assign(originals[i])
	for path in [TARGET, "user://map_editor_test_other.json", DOC.RECOVERY, "user://map_editor_playtest.json"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("MAP_EDITOR_TEST: %d checks; %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)

# 真实事件工坊保存 → 地图绑定 → 更新同步 → JSON 回读，使用独立测试资源编号。
func _test_event_bindings(editor: Control) -> void:
	var rewards = load("res://scripts/events/event_rewards.gd")
	var doc = editor.doc
	doc.new_map(true)
	editor._picked("floor_02_01")
	for id in ["forgotten_reliquary", "wandering_alchemist", "crossroads_recruitment", "campfire"]:
		check(editor.event_ids.has(id), "事件节点列出已配置事件：" + id)
	var cards_index: int = editor.event_ids.find("crossroads_recruitment") + 1
	editor._event_binding_changed(cards_index)
	var content: Dictionary = rewards.content("crossroads_recruitment")
	check(doc.node().event_source == "catalog" and doc.node().event_id == "crossroads_recruitment", "事件节点保存工坊绑定编号")
	check(doc.node().event == content and doc.node().title == content.title, "绑定同步标题、插图、叙事及完整奖励池")
	check(not editor.description_input.editable and not editor.texts[0].editable and not editor.heals[0].editable and editor.choice_effects[0].disabled, "绑定事件内容在地图中只读")
	var history_size: int = doc.history.size()
	editor.description_input.text = "不能覆盖工坊文案"
	editor._description_changed()
	editor._choice_text("不能覆盖选项", 0)
	editor._choice_number(99, 0, "gold")
	editor._choice_effect(0, 0)
	editor._event_binding_changed(cards_index)
	editor._event_binding_changed(-1)
	editor._event_binding_changed(editor.event_ids.size() + 2)
	check(doc.node().event == content and doc.history.size() == history_size, "只读控件及无效选择不改写绑定或增加撤销记录")
	editor._event_binding_changed(0)
	check(not doc.node().has("event_source") and doc.node().event == content and editor.description_input.editable, "切回节点内编辑保留工坊快照和奖励池")
	doc.undo()
	check(doc.node().get("event_source", "") == "catalog", "解绑可撤销")
	doc.redo()
	check(not doc.node().has("event_source"), "解绑可重做")
	editor._picked("floor_02_02")
	editor._event_binding_changed(editor.event_ids.find("campfire") + 1)
	check(doc.node().event_id == "campfire" and doc.node().event.choices.size() == 4, "篝火节点也可绑定事件工坊配方")

	var event_doc = load("res://addons/event_editor/document.gd").new()
	event_doc.new_event(2)
	event_doc.event.id = "map_binding_test_" + str(Time.get_ticks_usec())
	event_doc.event.title = "地图绑定测试事件"
	event_doc.event.unit_pool.assign(rewards.pool([], "unit").slice(0, 5))
	event_doc.event.effect_pool.assign(rewards.pool([], "effect").slice(0, 5))
	var event_path: String = "res://data/events/" + event_doc.event.id + ".tres"
	var saved: bool = event_doc.save(event_path)
	check(saved, "事件工坊可保存新的测试配方")
	if not saved:
		return
	editor._picked("floor_02_01")
	history_size = doc.history.size()
	editor._refresh_catalog()
	check(editor.event_ids.has(event_doc.event.id) and doc.history.size() == history_size, "刷新列出新保存事件，无变化时不产生地图编辑")
	editor._event_binding_changed(editor.event_ids.find(event_doc.event.id) + 1)
	var previous: Dictionary = doc.node().event.duplicate(true)
	check(doc.save("user://map_editor_binding_test.json"), "工坊事件绑定可保存到地图 JSON")
	var restored = DOC.new()
	check(restored.open("user://map_editor_binding_test.json") and restored.find(doc.selection).event_source == "catalog" and restored.find(doc.selection).event == previous, "JSON 回读保留绑定及奖励池")
	check(CONFIG.read_file("user://map_editor_binding_test.json").has("data"), "绑定事件地图通过游戏导入校验")
	event_doc.event.title = "更新后的工坊事件"
	event_doc.event.description = "事件工坊保存的新描述。"
	event_doc.event.option_text = "领取更新后的奖励"
	event_doc.event.unit_pool.reverse()
	check(event_doc.save(), "事件工坊可修改并保存已绑定配方")
	history_size = doc.history.size()
	editor._refresh_catalog()
	check(doc.node().event == event_doc.event.to_content() and doc.node().title == event_doc.event.title and editor.description_input.text == event_doc.event.description, "刷新同步最新文案、标题和奖励池到预览及快照")
	check(doc.is_dirty() and doc.history.size() == history_size + 1, "同步变化记为一次可保存、可撤销编辑")
	doc.undo()
	check(doc.node().event == previous, "撤销同步恢复旧事件快照")
	doc.redo()
	check(doc.node().event == event_doc.event.to_content(), "重做同步恢复新事件快照")
	history_size = doc.history.size()
	editor._refresh_catalog()
	check(doc.history.size() == history_size, "再次刷新相同配方不增加撤销记录")
	editor._set_text("保留自定义地点名称", "title")
	event_doc.event.title = "再次更新的工坊标题"
	check(event_doc.save(), "工坊可再次保存标题")
	editor._refresh_catalog()
	check(doc.node().title == "保留自定义地点名称" and doc.node().event.title == event_doc.event.title, "同步配方保留用户自定义地图地点名称")
	DirAccess.remove_absolute(event_path)
	editor._refresh_catalog()
	check(editor.event_binding.get_item_text(editor.event_binding.selected).begins_with("缺失事件：") and editor.event_inspect_button.disabled, "资源删除后显示缺失事件提示")
	var missing_snapshot: Dictionary = doc.node().event.duplicate(true)
	editor._event_binding_changed(editor.event_binding.selected)
	check(doc.node().event == missing_snapshot, "缺失事件占位项不能覆盖已有快照")
	editor._event_binding_changed(0)
	check(not doc.node().has("event_source") and doc.node().event == missing_snapshot, "资源缺失时仍能解绑并保留完整配置")
	DirAccess.remove_absolute("user://map_editor_binding_test.json")
