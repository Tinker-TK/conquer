# 这玩意儿是干嘛的（核心逻辑）：验证原生游戏配置面板、撤销和后台桥接能正确工作。
# 数据是咋流动的（数据流向）：读取真实资源 → 编辑独立草稿 → 导出导入与只读校验 → 核对原资源未改变。
# 为啥这么写（选型决策）：测试不应用实际游戏配置，临时合集和恢复文件全部放到测试专用路径。
# 性能咋样（复杂度）：手动运行一次，检查多种编辑操作后退出，不进入游戏运行流程。
extends SceneTree

var failures: Array[String] = []
var checks := 0

# 作用：Godot 初始化后安排测试；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()

# 作用：记录验证结果；condition 为结果，text 为说明，没有返回值。
func check(condition: bool, text: String) -> void:
	checks += 1
	if not condition:
		failures.append(text)
		push_error(text)

# 作用：执行原生界面与数据回归；没有参数，没有返回值。
func _run() -> void:
	var help = load("res://addons/shared/script_property_help.gd")
	var source_help: Dictionary = help.from_source("## 网格大小。[br]单位为像素。\n@export_range(1, 8, 1)\nvar grid_size := 2\n## 不应跨过普通注释。\n# 内部注释\n@export var untouched := 1\n")
	check(source_help.get("grid_size", "") == "网格大小。\n单位为像素。", "说明解析兼容多行导出注解和换行标签")
	check(not source_help.has("untouched"), "普通注释隔开的文档不错误绑定到下一字段")
	var inherited_help: Dictionary = help.descriptions(load("res://scripts/skills/arrow_attack.gd"))
	check(inherited_help.get("attack_rate", "").contains("倍率") and inherited_help.get("projectile_trajectory", "").contains("抛物线"), "技能子类同时继承基础参数说明与自身说明")
	var panel = load("res://addons/game_config_editor/editor.gd").new()
	panel.auto_load = false
	panel.doc.recovery_path = "user://game_config_editor_test_recovery.json"
	root.add_child(panel)
	panel.size = Vector2(1450, 850)
	await process_frame
	var result: Dictionary = panel.bridge.run_sync("editor-read", {})
	check(result.get("ok", false), "本机桥接读取实际配置：" + str(result.get("error", "")))
	if not result.get("ok", false):
		panel.shutdown()
		panel.free()
		quit(1)
		return
	var doc = panel.doc
	check(doc.open(result.data), "加载实际配置快照")
	await process_frame
	check(doc.data.records.size() > 100 and not doc.is_dirty(), "包含实际资源且读取后无修改")
	var undocumented: Array[String] = []
	for row: Dictionary in doc.data.records:
		for field: Dictionary in row.fields:
			if str(field.get("description", "")).is_empty():
				undocumented.append(str(row.id) + ":" + str(field.name))
	check(undocumented.is_empty(), "实际配置快照的所有字段均带说明：" + str(undocumented))
	check(doc.record("res://data/cards/round_add.tres").is_empty() and doc.record("res://data/cards/round_reduce.tres").is_empty(), "已删除卡牌不进入配置目录")
	var effect_row: Dictionary = doc.record("res://data/cards/copy_ally.tres::Resource_27uql")
	var effect_options: Array = panel._options(effect_row, doc.field(effect_row, "kind"))
	check(not effect_options.any(func(option: Array): return int(option[0]) == 5), "删除的效果编号不出现在选项中")
	check(effect_options.any(func(option: Array): return int(option[0]) == 6 and option[1] == "复制友军") and effect_options.any(func(option: Array): return int(option[0]) == 17 and option[1] == "立即获得能量"), "保留的效果编号与名称正确对应")
	check(panel.categories.item_count == 7, "七个配置分类")
	for category in ["cards", "card_effects", "allies", "enemies", "skills", "relics", "potions"]:
		panel.category = category
		panel._render_table()
		check(not panel.visible_rows.is_empty(), "分类表格：" + category)
		check(panel.grid.get_child_count() == (panel.visible_rows.size() + 1) * (panel.column_keys.size() + 1), "每项资源占一行：" + category)
	panel.category = "skills"
	panel._render_table()
	check(panel.column_keys.slice(0, 3) == ["unit_name", "skill_name", "unlock_upgrade_levels"], "技能表依次显示单位名称、技能名称、解锁强化等级数组")
	var skill_id := "res://data/skills/soldier_power_attack.tres"
	var skill_row: Dictionary = doc.record(skill_id)
	check(str(doc.value(skill_row, "unit_name")).contains("士兵"), "技能单位名称来自实际技能引用")
	check(doc.title(skill_row) == doc.value(skill_row, "skill_name"), "单位关联列不改变技能行名称")
	check(panel.cells[skill_id + "|unit_name"] is Label and not doc.field(skill_row, "unit_name").editable, "技能关联单位列只读，避免修改显示名称造成假关联")
	var shared_unit: Dictionary = doc.record("res://data/units/soldier.tres").duplicate(true)
	shared_unit.id = "res://data/units/skill_unlock_shared_test.tres"
	doc.field(shared_unit, "unit_name").value = "共享技能测试单位"
	doc.data.records.append(shared_unit)
	check(doc.skill_unit_names(skill_id).has("士兵") and doc.skill_unit_names(skill_id).has("共享技能测试单位"), "共享技能显示全部关联单位")
	doc.data.records.erase(shared_unit)
	check(doc.skill_unit_names("res://data/skills/knight_dodge_attack.tres").has("骑士"), "单位关联包含防守反击技能")
	check(not doc.record("res://data/units/soldier.tres").fields.any(func(item: Dictionary): return item.name == "card_upgrade_level"), "运行时强化等级不作为单位配置列导出")
	var aura_id := "res://data/skills/knight_templar_protection_aura.tres"
	var aura_row: Dictionary = doc.record(aura_id)
	check(not doc.skill_unit_names(aura_id).has("圣殿骑士") and doc.title(aura_row) == "庇护光环", "原庇护光环保留为通用配置，圣殿骑士已替换嘲讽")
	var taunt_id := "res://data/skills/knight_templar_taunt_upgraded.tres"
	var taunt_row: Dictionary = doc.record(taunt_id)
	check(doc.skill_unit_names(taunt_id).has("圣殿骑士") and doc.title(taunt_row) == "嘲讽攻击", "嘲讽技能关联圣殿骑士")
	check(doc.value(taunt_row, "taunt_radius") == 200.0 and doc.value(taunt_row, "taunt_duration") == 5.0 and doc.value(taunt_row, "defence_per_attacker") == 1, "强化嘲讽默认参数正确")
	check(panel.cells[taunt_id + "|taunt_duration"] is LineEdit and doc.field(taunt_row, "defence_per_attacker").editable, "嘲讽持续时间与每敌防御可以配置")
	var dash_id := "res://data/skills/lancer_dash_attack_enhance.tres"
	var dash_row: Dictionary = doc.record(dash_id)
	check(doc.value(dash_row, "dash_count") == 2 and doc.value(dash_row, "dash_speed") == 600.0 and doc.value(dash_row, "unlock_upgrade_levels") == [1], "骑兵强化冲锋参数为两段与600速度")
	check(doc.field(dash_row, "dash_count").editable and panel.cells[dash_id + "|dash_speed"] is LineEdit and panel.cells[dash_id + "|dash_pause"] is LineEdit, "冲锋次数、速度和间隔可在技能表配置")
	var wolf_id := "res://data/skills/were_wolf_five_attack_upgraded.tres"
	var wolf_row: Dictionary = doc.record(wolf_id)
	check(doc.skill_unit_names(wolf_id).has("狼人") and doc.value(wolf_row, "cast_range") == 450.0 and doc.value(wolf_row, "stun_seconds") == 2.0, "强化狼人五连斩击关联450距离和2秒眩晕")
	check(doc.value(wolf_row, "refresh_on_target_kill") == true and doc.value(wolf_row, "pounce_seconds") == 0.3 and doc.field(wolf_row, "refresh_on_target_kill").editable and panel.cells[wolf_id + "|melee_range"] is LineEdit, "狼人扑击时长、近战距离、斩杀刷新可在技能表配置")
	check(doc.field(aura_row, "aura_radius").editable and doc.value(aura_row, "aura_radius") == 200.0 and panel.cells[aura_id + "|aura_radius"] is LineEdit, "光环半径可在原生技能表中编辑")
	check(doc.field(aura_row, "aura_attack_bonus").editable and doc.value(aura_row, "aura_attack_bonus") == 2 and doc.value(aura_row, "unlock_upgrade_levels") == [1], "技能配置显示攻击加成及强化解锁等级")
	var unlock_input: LineEdit = panel.cells[skill_id + "|unlock_upgrade_levels"]
	var combo_id := "res://data/skills/swords_man_consecutive_attack.tres"
	var combo_row: Dictionary = doc.record(combo_id)
	check(not doc.skill_unit_names(combo_id).has("剑士") and doc.title(combo_row) == "愈战愈勇", "旧连续命中资源保留，但不再装配到正式剑士")
	var seventh_id := "res://data/skills/swords_man_seventh_strike_upgraded.tres"
	var seventh_row: Dictionary = doc.record(seventh_id)
	check(doc.skill_unit_names(seventh_id).has("剑士") and doc.value(seventh_row, "damage_trigger_count") == 7 and doc.value(seventh_row, "true_damage_base_percent") == 5.0, "剑士强化七伤参数为7次伤害和5%基数")
	check(panel.cells[seventh_id + "|true_damage_base_percent"] is LineEdit and doc.field(seventh_row, "damage_trigger_count").editable, "七伤计数与百分比基数可以在技能表配置")
	check(doc.value(combo_row, "attack_bonus_per_hit") == 1 and doc.field(combo_row, "attack_bonus_per_hit").editable and panel.cells[combo_id + "|attack_bonus_per_hit"] is LineEdit, "每次命中攻击加成可以在原生技能表编辑")
	check(panel.cells[combo_id + "|attack_bonus_per_hit"].tooltip_text.contains("切换目标") and doc.value(combo_row, "unlock_upgrade_levels") == [0, 1], "被动参数说明和默认强化等级正确")
	check(unlock_input.text == "[1]" and unlock_input.tooltip_text.contains("[0] 强化后失效"), "斩击仅强化后解锁，数组说明包含精确匹配与替换规则")
	check(doc.value(skill_row, "soldier_branch") == "slash" and panel.cells[skill_id + "|soldier_branch"] is LineEdit, "斩击分支可在技能表中查看和配置")
	check(doc.field(skill_row, "unlock_upgrade_levels").type == TYPE_ARRAY and doc.field(skill_row, "unlock_upgrade_levels").array_type == TYPE_INT, "正式导出为可编辑整数数组")
	unlock_input.text = "[0]"
	unlock_input.text_submitted.emit(unlock_input.text)
	check(doc.value(skill_row, "unlock_upgrade_levels") == [0], "解锁强化等级可通过原生格子编辑为仅未强化时生效")
	var unlock_checked: Dictionary = panel.bridge.run_sync("editor-check", doc.data)
	check(unlock_checked.get("ok", false), "解锁等级数组通过正式保存校验")
	for text in ["0", "[", "[-1]", "[100]", "[1.5]", "[true]", '["1"]']:
		unlock_input.text = text
		unlock_input.text_submitted.emit(text)
		check(unlock_input.get_meta("invalid", false) and doc.value(doc.record(skill_id), "unlock_upgrade_levels") == [0], "非法数组输入不改变有效草稿：" + text)
	unlock_input.text = "[1,2]"
	unlock_input.text_submitted.emit(unlock_input.text)
	check(not unlock_input.get_meta("invalid", true) and doc.value(doc.record(skill_id), "unlock_upgrade_levels") == [1, 2], "修正数组可继续编辑")
	for invalid_value in [-1, [-1], [100], [1.5], [true], ["1"]]:
		doc.set_value(skill_id, "unlock_upgrade_levels", invalid_value)
		var unlock_invalid: Dictionary = panel.bridge.run_sync("editor-check", doc.data)
		check(not unlock_invalid.get("ok", true), "正式写回拒绝非法强化数组：" + str(invalid_value))
		doc.undo()
	doc.set_value(skill_id, "unlock_upgrade_levels", [])
	unlock_checked = panel.bridge.run_sync("editor-check", doc.data)
	check(unlock_checked.get("ok", false), "空数组可保存为始终不生效：" + str(unlock_checked.get("error", unlock_checked.get("message", ""))))
	doc.open(result.data)
	panel._render_table()
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.maintenance/skill-level-array-config.png")
	panel.search.text = "士兵"
	panel._render_table()
	check(panel.visible_rows.any(func(row: Dictionary): return row.id == skill_id), "可用单位名称搜索技能")
	panel.search.text = ""
	panel.category = "allies"
	panel._render_table()
	var id := "res://data/units/soldier.tres"
	var original_hash := FileAccess.get_sha256(id)
	var old_hp: int = int(doc.value(doc.record(id), "max_hp"))
	var input: LineEdit = panel.cells[id + "|max_hp"]
	check(input.tooltip_text.contains("最大生命"), "可编辑单元格显示参数用途")
	var hp_header = panel.grid.get_child(panel.column_keys.find("max_hp") + 1)
	check(hp_header.get_child(0).tooltip_text.contains("最大生命"), "表头显示参数用途")
	check(panel.cells[id + "|skills"].tooltip_text.contains("Priority") and panel.cells[id + "|skills"].tooltip_text.contains("驻场被动"), "只读关联资源单元格也显示主动技能和被动用途")
	check(input.text == str(old_hp), "整数字段显示为整数")
	input.focus_exited.emit()
	check(not doc.is_dirty() and not input.get_meta("invalid", false), "未改动的整数输入移开焦点不会报错")
	input.text = str(old_hp + 17)
	input.text_submitted.emit(input.text)
	check(doc.value(doc.record(id), "max_hp") == old_hp + 17, "原生单元格回车提交")
	check(doc.is_dirty() and not doc.past.is_empty(), "产生撤销历史与未保存标记")
	doc.undo()
	check(doc.value(doc.record(id), "max_hp") == old_hp and not doc.is_dirty(), "撤销恢复原始数值")
	doc.redo()
	check(doc.value(doc.record(id), "max_hp") == old_hp + 17, "重做恢复编辑值")
	await process_frame
	input = panel.cells[id + "|max_hp"]
	input.text = "不是整数"
	input.text_submitted.emit(input.text)
	check(input.get_meta("invalid", false), "无效输入显示错误而不改草稿")
	check(doc.data.editor_inputs.has(id + "|max_hp"), "无效原始输入保存到恢复草稿")
	check(doc.value(doc.record(id), "max_hp") == old_hp + 17, "无效输入保留上次有效值")
	doc.open(doc.data)
	await process_frame
	input = panel.cells[id + "|max_hp"]
	check(input.text == "不是整数" and input.get_meta("invalid", false), "恢复保留无效输入原文和红色状态")
	input.text = str(old_hp + 17)
	input.text_submitted.emit(input.text)
	check(not input.get_meta("invalid", true), "修正输入后可继续")
	check(doc.data.editor_inputs.is_empty(), "修正输入清除未提交标记")
	var before_paste: Dictionary = doc.data.duplicate(true)
	check(panel._paste_tsv(id, "max_hp", str(old_hp + 27) + "\t31"), "粘贴 Excel 连续格子")
	check(doc.value(doc.record(id), "max_hp") == old_hp + 27 and doc.value(doc.record(id), "attack") == 31, "整块粘贴对应字段")
	doc.undo()
	check(doc.data == before_paste, "整块粘贴一次撤销")
	await process_frame
	check(not panel._paste_tsv(id, "max_hp", "200\t不是整数"), "粘贴无效块被拒绝")
	check(doc.data == before_paste, "失败粘贴没有部分修改")
	panel.message.hide()
	var new_id: String = doc.add_row(id, "editor_test_unit", "面板测试单位")
	check(not new_id.is_empty() and doc.is_new(new_id), "新增单位配置行")
	check(doc.value(doc.record(new_id), "unit_english_name") == "editor_test_unit", "新单位使用独立英文标识")
	doc.undo()
	check(doc.record(new_id).is_empty(), "撤销新增行")
	doc.redo()
	check(not doc.record(new_id).is_empty(), "重做新增行")
	var column := {"family": "units", "name": "editor_test_points", "label": "测试点数", "dtype": "int", "default": 2, "description": "面板测试，不写回实际项目"}
	check(doc.add_column(column), "新增字段列")
	check(doc.value(doc.record(id), "editor_test_points") == 2 and doc.value(doc.record(new_id), "editor_test_points") == 2, "新列包含原有和新增单位")
	check(doc.value(doc.record("res://data/units/bat.tres"), "editor_test_points") == 2, "单位字段双方共用")
	check(not doc.add_column(column), "拒绝重复字段")
	await process_frame
	var checked: Dictionary = panel.bridge.run_sync("editor-check", doc.data)
	check(checked.get("ok", false), "原生草稿通过正式写回校验：" + str(checked.get("error", "")))
	check(not FileAccess.file_exists(new_id), "校验不创建游戏资源")
	panel._run_tool("editor-check")
	check(panel.bridge.is_busy() and panel.save_button.disabled, "后台工作时禁止重复保存")
	var wait_until := Time.get_ticks_msec() + 10000
	while panel.bridge.is_busy() and Time.get_ticks_msec() < wait_until:
		await create_timer(0.05).timeout
	check(not panel.bridge.is_busy() and panel.status.text.contains("校验通过"), "线程结果回到原生面板")
	var json_path := "user://game_config_editor_test.json"
	var html_path := "user://game_config_editor_test.html"
	doc.set_value(skill_id, "unlock_upgrade_levels", [0])
	panel._export_selected(json_path)
	panel._export_selected(html_path)
	check(FileAccess.file_exists(json_path) and FileAccess.file_exists(html_path), "导出 JSON 和 HTML")
	var exported: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	check(exported.pending_rows.size() == 1 and exported.pending_columns.size() == 1, "导出保存新增行与新增列")
	doc.set_value(id, "max_hp", old_hp)
	panel._import_selected(html_path)
	check(doc.value(doc.record(id), "max_hp") == old_hp + 17, "导入 HTML 恢复编辑数据")
	check(doc.value(doc.record(skill_id), "unlock_upgrade_levels") == [0], "HTML 导出导入保留强化等级数组")
	check(doc.data.pending_rows.size() == 1, "导入 HTML 恢复新增行")
	doc.set_value(id, "max_hp", -3)
	var invalid: Dictionary = panel.bridge.run_sync("editor-check", doc.data)
	check(not invalid.get("ok", true), "保存工具拒绝非法血量")
	check(FileAccess.get_sha256(id) == original_hash, "测试没有改变实际游戏数值")
	doc.set_value(id, "max_hp", old_hp + 17)
	check(doc.write_recovery(), "写入可恢复草稿")
	var recovery: Variant = JSON.parse_string(FileAccess.get_file_as_string(doc.recovery_path))
	check(recovery.pending_rows.size() == 1, "恢复草稿保留未保存新行")
	doc.remove_row(new_id)
	check(doc.record(new_id).is_empty(), "移除尚未应用的新行")
	doc.remove_column("units", "editor_test_points")
	check(doc.field(doc.record(id), "editor_test_points").is_empty(), "移除尚未应用的新列")
	# 清空测试草稿后关闭；不触发任何实际配置应用。
	doc.open(result.data)
	doc.discard_recovery()
	panel.shutdown()
	panel.free()
	for path in [json_path, html_path]:
		DirAccess.remove_absolute(path)
	await process_frame
	print("GAME_CONFIG_EDITOR_TEST: ", checks, " checks; failures=", failures)
	quit(0 if failures.is_empty() else 1)
