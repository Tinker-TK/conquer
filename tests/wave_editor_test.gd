# 这玩意儿是干嘛的（核心逻辑）：测试撤销、文件保护、多关卡、批量编排和真实回合起点。
# 数据是咋流动的（数据流向）：临时资源 → 模拟面板和鼠标 → 保存重读 → 运行正式刷怪逻辑。
# 为啥这么写（选型决策）：只写 user:// 测试文件，不修改制作中的关卡。
# 性能咋样（复杂度）：手动执行一次，检查几十种操作后退出。
extends SceneTree

var failures: Array[String] = []
var checks := 0
var temporary := "user://wave_editor_test.tres"
var alternate := "user://wave_editor_test_new.tres"
var recovery := "user://wave_editor_test_recovery.tres"

# 作用：引擎启动后安排测试；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()

# 作用：记录断言；condition 为结果，message 为失败原因，没有返回值。
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

# 作用：发送一次组拖动；preview 为预览，from/to 为屏幕坐标，没有返回值。
func drag(preview: Control, from: Vector2, to: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = from
	preview._gui_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = to
	preview._gui_input(motion)
	press.pressed = false
	press.position = to
	preview._gui_input(press)

# 作用：执行功能回归测试；没有参数，没有返回值。
func _run() -> void:
	if Engine.is_editor_hint():
		# Godot 的资源 UID 只服务于 res://，编辑器模式使用可清理的项目内夹具。
		temporary = "res://tests/wave_editor_fixture_tmp.tres"
	for path in [temporary, alternate, recovery]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	var original := (load("res://data/levels/level_001.tres") as Resource).duplicate()
	# 正式关卡可以正处于空白制作状态，测试显式建立自己的三回合夹具。
	var waves: Array[PackedScene] = []
	for i in 3:
		waves.append(load("res://scenes/levels/waves/wave_01.tscn"))
	original.waves = waves
	check(ResourceSaver.save(original.duplicate(), temporary) == OK, "创建测试关卡")
	var original_uid := ResourceUID.create_id()
	check(ResourceSaver.set_uid(temporary, original_uid) == OK, "建立测试资源身份")
	var editor = load("res://addons/wave_editor/editor.gd").new()
	editor.initial_path = temporary
	editor.doc.recovery_path = recovery
	root.add_child(editor)
	editor.size = Vector2(1450, 900)
	await process_frame
	var doc = editor.doc
	check(doc.rounds.size() == original.waves.size(), "读取全部回合")
	check(editor.scenes.size() > 0, "怪物目录")
	check(not doc.is_dirty(), "读取后干净")
	check(editor.preview.viewport.get_child_count() == 1, "真实地形")
	check(not editor.preview.polygons.is_empty(), "敌方导航区域")
	var count: int = doc.rounds[0].get_child_count()
	var old: Vector2 = doc.rounds[0].get_child(0).position
	var shared: Vector2 = doc.rounds[1].get_child(0).position
	var p = editor.preview
	editor._select_round(0)
	# 大地图全景会把多只单位压进同一个 24 像素拾取半径，先放大再验证指定单位拖动。
	p.zoom_at(8.0, p.screen(old))
	drag(p, p.screen(old), p.screen(Vector2(-333, 123)))
	check(doc.rounds[0].get_child(0).position == Vector2(-333, 123), "鼠标坐标转换")
	check(doc.rounds[1].get_child(0).position == shared, "共享场景独立编辑")
	check(doc.is_dirty(), "拖动产生未保存状态")
	doc.undo()
	check(doc.rounds[0].get_child(0).position == old and not doc.is_dirty(), "撤销拖动恢复保存点")
	doc.redo()
	check(doc.rounds[0].get_child(0).position == Vector2(-333, 123), "重做拖动")

	doc.add_round(true)
	check(doc.current == 1 and doc.rounds[1].get_child_count() == count, "复制回合")
	doc.undo()
	check(doc.rounds.size() == original.waves.size(), "撤销复制回合")
	doc.redo()
	doc.delete_round()
	check(doc.rounds.size() == original.waves.size(), "删除回合")
	doc.undo()
	check(doc.rounds.size() == original.waves.size() + 1, "撤销删除回合")
	doc.redo()
	editor._select_round(0)
	doc.add_round()
	doc.move_round(1)
	check(doc.current == 2 and doc.rounds[2].get_child_count() == 0, "新增并排序空回合")
	doc.undo()
	check(doc.current == 1 and doc.rounds[1].get_child_count() == 0, "撤销排序")
	doc.redo()
	check(doc.save(), "原子保存原路径：" + doc.error)
	# Godot 只在编辑器模式把 UID 写入磁盘，因此此断言在编辑器回归中执行。
	if Engine.is_editor_hint():
		check(ResourceLoader.get_resource_uid(temporary) == original_uid, "保存保持原关卡 UID")
		check(FileAccess.get_file_as_string(temporary).get_slice("\n", 0).contains(ResourceUID.id_to_text(original_uid)), "UID 实际写入磁盘头部")
	check(not doc.is_dirty(), "保存点标记")
	doc.undo()
	check(doc.is_dirty(), "保存后撤销变脏")
	doc.redo()
	check(not doc.is_dirty(), "重做回到保存点")
	var saved := ResourceLoader.load(temporary, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.waves[2] == null, "空回合保存为 null")
	var wave: Node = saved.waves[0].instantiate()
	check(wave.get_child(0).position == Vector2(-333, 123), "保存保留拖动坐标")
	check(wave.get_child(0).get_node_or_null("SkillManager") != null, "保留单位内部节点")
	wave.free()

	editor._select_round(0)
	editor._picked(PackedInt32Array([0, 1]))
	doc.edit_units("复制")
	check(doc.rounds[0].get_child_count() == count + 2, "批量复制")
	check(doc.selection.size() == 2, "复制后保留选择")
	doc.undo()
	check(doc.rounds[0].get_child_count() == count, "撤销批量复制")
	doc.redo()
	doc.edit_units("替换", editor.scenes[0])
	check(doc.rounds[0].get_child_count() == count + 2, "批量替换数量不变")
	doc.undo()
	doc.redo()
	doc.edit_units("删除")
	check(doc.rounds[0].get_child_count() == count, "批量删除")
	doc.undo()
	check(doc.rounds[0].get_child_count() == count + 2, "撤销批量删除")
	doc.redo()
	doc.add_unit(editor.scenes[0])
	check(doc.rounds[0].get_child_count() == count + 1, "添加怪物")
	doc.undo()
	check(doc.rounds[0].get_child_count() == count, "撤销添加")
	editor._filter("完全不存在的怪物")
	check(editor.catalog.item_count == 0, "搜索无结果")
	editor._filter("orc")
	check(editor.catalog.item_count > 0 and editor.catalog.item_count < editor.scenes.size(), "英文搜索")
	editor._filter("")

	# 改变视图不会修改草稿；网格吸附仅改变整组位移，不破坏组内相对位置。
	editor._picked(PackedInt32Array([0, 1]))
	var first: Vector2 = doc.rounds[0].get_child(0).position
	var relative: Vector2 = doc.rounds[0].get_child(1).position - first
	p.zoom_at(1.6, p.size / 2)
	p.pan += Vector2(20, -25)
	p.update_view()
	check(p.local_point(p.screen(first)).distance_to(first) < 0.001, "缩放平移可逆")
	p.snapping = true
	drag(p, p.screen(first), p.screen(first + Vector2(57, 39)))
	var world: Vector2 = p.team_transform * doc.rounds[0].get_child(0).position
	check(world.distance_to(world.snapped(Vector2(32, 32))) < 0.001, "世界网格吸附")
	check((doc.rounds[0].get_child(1).position - doc.rounds[0].get_child(0).position).distance_to(relative) < 0.001, "组拖动保持相对站位")
	doc.undo()
	check(doc.rounds[0].get_child(0).position == first, "组拖动一次撤销")
	p.snapping = false
	p.fit()
	doc.begin()
	doc.rounds[0].get_child(1).position = doc.rounds[0].get_child(0).position
	doc.commit("测试重叠")
	check(p.analyze()[0].contains("重叠"), "重叠检测")
	doc.undo()
	doc.begin()
	doc.rounds[0].get_child(0).position = Vector2(-9999, -9999)
	doc.commit("测试越界")
	check(p.analyze()[0].contains("超出"), "越界检测")
	doc.undo()

	# 播放记录区分空回合与循环，并保留累计数量。
	editor._reset_playback()
	editor._next()
	editor._next()
	editor._next()
	check(editor.records[2].contains("空回合"), "播放空回合")
	editor._next()
	var accumulated: int = editor.total
	editor._next()
	check(editor.total == accumulated, "有限播放停止")
	doc.set_field("repeat_waves", true)
	for i in range(doc.rounds.size() + 1):
		editor._next()
	check(editor.cycle == 1 and editor.playback == 0, "循环回合记录")
	check(editor.total > accumulated, "累计出场数量")
	doc.undo()

	# 外部文件发生变化必须保持它原样，草稿另存后仍可撤销。
	var external := FileAccess.get_file_as_string(temporary) + "\n; external change\n"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	file.store_string(external)
	file.close()
	check(not doc.save(), "外部修改阻止覆盖")
	check(FileAccess.get_file_as_string(temporary) == external, "冲突保留外部内容")
	check(doc.write_recovery(), "冲突草稿恢复副本")
	var recovered = load("res://addons/wave_editor/document.gd").new()
	recovered.recovery_path = recovery
	check(recovered.recover() and recovered.is_dirty(), "恢复脏草稿")
	check(not recovered.save(), "恢复仍检测原指纹冲突")
	recovered.clear_nodes()
	recovered.history.clear_history()
	recovered.history.free()
	check(doc.save(alternate), "冲突后另存为新路径：" + doc.error)
	check(not doc.is_dirty() and doc.path == alternate, "另存为切换保存目标")
	check(not FileAccess.file_exists(recovery), "成功保存删除恢复草稿")
	doc.undo()
	check(doc.is_dirty(), "另存为后撤销产生脏状态")
	doc.redo()

	# 取消关卡切换不能丢失草稿；明确放弃后才打开另一关。
	doc.add_round()
	var previous_count: int = doc.rounds.size()
	editor.request_action(editor._open_path.bind("res://data/levels/level_002.tres"))
	check(editor.guard.visible and doc.rounds.size() == previous_count, "切换关卡出现未保存提醒")
	editor.guard.hide()
	editor._guard_cancel()
	check(doc.rounds.size() == previous_count, "取消保留编辑")
	editor.request_action(editor._open_path.bind("res://data/levels/level_002.tres"))
	editor._guard_discard("discard")
	check(doc.path.ends_with("level_002.tres") and doc.config.repeat_waves, "打开其它既有关卡")
	check(not doc.history.has_undo(), "不同关卡历史隔离")
	editor._new_level()
	check(doc.path.is_empty() and doc.is_dirty(), "新建关卡草稿")
	editor._set_terrain("res://scenes/levels/battles/battle_001.tscn")
	check(doc.config.battle_scene != null, "设置新关卡地形")
	doc.undo()
	check(doc.config.battle_scene == null, "地形支持撤销")
	doc.redo()
	check(editor._can_drop_terrain(Vector2.ZERO, {"type": "files", "files": ["res://scenes/levels/battles/battle_001.tscn"]}), "接收文件面板地形拖拽")
	doc.add_unit(editor.scenes[0])
	doc.add_round()
	doc.add_unit(editor.scenes[1])
	doc.add_round()
	editor._select_round(1)
	# 未配置天气的继承战场应默认晴天，走实际快照和实战入口验证。
	editor._set_terrain("res://scenes/levels/battles/battle_009.tscn")
	check(doc.config.weather_settings == null and doc.config.snow_weather_settings == null, "新关卡未配置天气")
	if not Engine.is_editor_hint():
		editor._launch()
	else:
		var play_config: Resource = doc.output()
		play_config.set_meta("wave_editor_start_round", 2)
		ResourceSaver.save(play_config, "user://wave_editor_playtest.tres")
	var snapshot := load("user://wave_editor_playtest.tres") as Resource
	check(snapshot.get_meta("wave_editor_start_round", 0) == 2, "实战快照起始回合")

	if "--capture" in OS.get_cmdline_user_args():
		editor._open_path("res://data/levels/level_002.tres")
		editor._next()
		editor._next()
		editor.size = Vector2(1450, 900)
		await process_frame
		await RenderingServer.frame_post_draw
		print("LAYOUT: ", editor.size, " min=", editor.get_combined_minimum_size(), " preview=", p.size)
		root.get_texture().get_image().save_png("user://wave_editor_preview.png")
	if not Engine.is_editor_hint():
		var runner = load("res://addons/wave_editor/playtest.gd").new()
		root.add_child(runner)
		await process_frame
		check(runner.battle.get_node("BattleRoundManager").current_round == 2, "真实战斗从第2回合开始")
		check(runner.battle.get_node("Entities/TeamB").last_round == 2, "真实刷怪接收第2回合")
		check(runner.battle.get_node("Entities/TeamB").get_child_count() == 1, "未生成前面回合怪物")
		check(not runner.battle.get_node("RainWeather").settings.enabled, "未配置天气的波次实战默认不下雨")
		check(not runner.battle.get_node("SnowWeather").settings.enabled, "未配置天气的波次实战默认不下雪")
		root.remove_child(runner)
		runner.free()
	# 禁用插件后仍须保留面板，保存冲突或取消不能悄悄释放草稿。
	doc.open(temporary)
	doc.add_round()
	editor.close_for_disable()
	check(editor.orphaned and editor.guard.visible, "禁用插件保留保存确认")
	var changed_file := FileAccess.open(temporary, FileAccess.READ_WRITE)
	changed_file.seek_end()
	changed_file.store_string("\n; second external change\n")
	changed_file.close()
	editor.guard.hide()
	editor._guard_save()
	check(editor.conflict.visible and doc.is_dirty(), "禁用期间保存冲突仍保留草稿")
	editor.conflict.hide()
	# 测试中不真正改变宿主插件启用状态，只验证取消会清除待执行的关闭动作。
	editor.orphaned = false
	editor._guard_cancel()
	check(not editor.pending.is_valid(), "取消关闭清除待执行动作")
	if Engine.is_editor_hint():
		var plugin = load("res://addons/wave_editor/plugin.gd").new()
		plugin.panel = editor
		check(not plugin._get_unsaved_status("").is_empty(), "项目退出未保存提醒")
		check(plugin._get_unsaved_status("res://unrelated.tscn").is_empty(), "关闭无关场景不提醒")
		plugin.free()
	editor.save_on_exit()
	check(FileAccess.file_exists(recovery), "退出保存冲突保留恢复副本")
	editor.free()
	for path in [temporary, alternate, recovery, "user://wave_editor_playtest.tres"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	print("WAVE_EDITOR_TEST: ", checks, " checks; ", "PASS" if failures.is_empty() else str(failures))
	quit(0 if failures.is_empty() else 1)
