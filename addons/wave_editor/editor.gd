# 这玩意儿是干嘛的（核心逻辑）：把关卡草稿、战场操作、保存保护与实战入口组织成编辑器界面。
# 数据是咋流动的（数据流向）：按钮和拖动 → document 撤销事务 → preview 反馈 → 原 tres 文件。
# 为啥这么写（选型决策）：文档层独立于界面，批量操作与撤销走同一条路径，退出保护也能复用保存。
# 性能咋样（复杂度）：界面仅在编辑或选择变化时刷新；场景地形只在切换资源时重新加载。
@tool
extends VBoxContainer

const DOC = preload("res://addons/wave_editor/document.gd")
const SEQUENCE = preload("res://scripts/battle/wave_sequence.gd")
const PROPERTY_HELP = preload("res://addons/shared/script_property_help.gd")
var parameter_help: Dictionary = PROPERTY_HELP.descriptions(preload("res://data/levels/battle_level_config.gd"))
const EFFECT_KEYS := ["attack", "max_hp", "defence"]
var doc = DOC.new()
var initial_path := "res://data/levels/level_001.tres"
var round_list: ItemList
var unit_list: ItemList
var catalog: OptionButton
var levels: OptionButton
var level_name: LineEdit
var repeat: CheckBox
var loop_start: SpinBox
var loop_end: SpinBox
var effect_mode: OptionButton
var effect_kind: OptionButton
var effect_amount: SpinBox
var effect_hint: Label
var display_round := 0
var display_cycle := 0
var played_round := 0
var preview: Control
var status: Label
var title: Label
var terrain: Button
var log_list: ItemList
var undo_button: Button
var redo_button: Button
var scenes: Array[PackedScene] = []
var names: Array[String] = []
var open_dialog: FileDialog
var save_dialog: FileDialog
var terrain_dialog: FileDialog
var guard: ConfirmationDialog
var conflict: ConfirmationDialog
var recover_dialog: ConfirmationDialog
var pending := Callable()
var orphaned := false
var refreshing := false
var shown_terrain: PackedScene
var playback := -1
var cycle := 0
var total := 0
var records: Array[String] = []
var last_revision := -1

# 作用：引擎创建面板后搭建所有操作区；没有参数，没有返回值。
func _ready() -> void:
	var files := HBoxContainer.new()
	add_child(files)
	levels = OptionButton.new()
	levels.custom_minimum_size.x = 160
	files.add_child(levels)
	levels.item_selected.connect(_choose_level)
	_button(files, "打开…", _open_dialog)
	_button(files, "新建", request_action.bind(_new_level))
	_button(files, "保存", save_current)
	_button(files, "另存为…", _save_as)
	_button(files, "重读", request_action.bind(_reload))
	undo_button = _button(files, "撤销", doc.undo)
	redo_button = _button(files, "重做", doc.redo)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	files.add_child(title)

	var properties := HBoxContainer.new()
	add_child(properties)
	level_name = LineEdit.new()
	level_name.placeholder_text = "关卡名称"
	level_name.tooltip_text = parameter_help.level_name
	level_name.custom_minimum_size.x = 180
	properties.add_child(level_name)
	level_name.text_submitted.connect(_rename)
	level_name.focus_exited.connect(_rename.bind(""))
	repeat = CheckBox.new()
	repeat.text = "循环波次"
	repeat.tooltip_text = parameter_help.repeat_waves
	properties.add_child(repeat)
	repeat.toggled.connect(_repeat_changed)
	terrain = Button.new()
	terrain.tooltip_text = parameter_help.battle_scene
	terrain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	terrain.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	terrain.set_drag_forwarding(Callable(), _can_drop_terrain, _drop_terrain)
	terrain.pressed.connect(_browse_terrain)
	properties.add_child(terrain)

	# 范围采用实际显示的一基波次号；结束 0 兼容旧资源的“循环到末波”。
	var loopbar := HBoxContainer.new()
	add_child(loopbar)
	_label(loopbar, "循环范围：第")
	loop_start = _number(loopbar, 1, 9999, 1)
	loop_start.tooltip_text = parameter_help.repeat_start
	_label(loopbar, "波 至 第")
	loop_end = _number(loopbar, 0, 9999, 0)
	loop_end.tooltip_text = parameter_help.repeat_end
	_label(loopbar, "波（0=末波）")
	_button(loopbar, "应用范围", _apply_repeat_range)
	_label(loopbar, "结束后回到起始波；范围之后的原始波次不再出场")

	var playbar := HBoxContainer.new()
	add_child(playbar)
	_button(playbar, "播放下一回合", _next)
	_button(playbar, "重置播放", _reset_playback)
	_button(playbar, "从当前回合启动实战", _launch)
	var hint := Label.new()
	hint.text = "  Ctrl/Shift 多选 · 空白处框选 · 滚轮缩放 · 中键平移"
	playbar.add_child(hint)

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 210
	split.add_child(left)
	var actions := HBoxContainer.new()
	left.add_child(actions)
	_button(actions, "+回合", doc.add_round)
	_button(actions, "复制", doc.add_round.bind(true))
	_button(actions, "删除", doc.delete_round)
	_button(actions, "↑", doc.move_round.bind(-1))
	_button(actions, "↓", doc.move_round.bind(1))
	round_list = ItemList.new()
	round_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(round_list)
	round_list.item_selected.connect(_select_round)
	var log_label := Label.new()
	log_label.text = "累计出场记录（最近 200 条）"
	left.add_child(log_label)
	log_list = ItemList.new()
	log_list.custom_minimum_size.y = 150
	left.add_child(log_list)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var monsters := HBoxContainer.new()
	right.add_child(monsters)
	var search := LineEdit.new()
	search.placeholder_text = "搜索怪物名称"
	search.custom_minimum_size.x = 130
	search.text_changed.connect(_filter)
	monsters.add_child(search)
	catalog = OptionButton.new()
	catalog.tooltip_text = "选择添加或替换到当前波次的敌方单位场景；基础属性与技能来自其 UnitData，波次增益只修改出场实例。"
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	monsters.add_child(catalog)
	_button(monsters, "添加", _add_unit)
	_button(monsters, "替换", _edit_units.bind("替换"))
	_button(monsters, "复制", _edit_units.bind("复制"))
	_button(monsters, "删除", _edit_units.bind("删除"))
	_button(monsters, "全选", _select_all)

	# 单次增益在每个新单位出场时固定加一次；循环成长仅在重复时按倍率累加。
	var effects_bar := HBoxContainer.new()
	right.add_child(effects_bar)
	_label(effects_bar, "单位增益：")
	effect_mode = OptionButton.new()
	effect_mode.add_item("循环成长")
	effect_mode.add_item("单次增益")
	effect_mode.tooltip_text = "单次增益：每次出场固定加一次；循环成长：首次不加，重复时累积。"
	effects_bar.add_child(effect_mode)
	effect_mode.item_selected.connect(_effect_kind_changed)
	effect_kind = OptionButton.new()
	effect_kind.tooltip_text = "选择对当前选中单位调整的属性：攻击、最大生命或防御；不会修改原始 UnitData 资源。"
	for key in EFFECT_KEYS:
		effect_kind.add_item(SEQUENCE.LABELS[key])
	effects_bar.add_child(effect_kind)
	effect_kind.item_selected.connect(_effect_kind_changed)
	effect_amount = _number(effects_bar, 0, 9999, 3)
	effect_amount.tooltip_text = "所选属性的增加点数。单次增益每次出场固定增加；循环成长按重复循环次数累加。0 清除当前模式下此属性的增益。"
	_button(effects_bar, "应用到选中", _apply_unit_effect)
	_button(effects_bar, "清除此效果", _clear_unit_effect)
	effect_hint = Label.new()
	effect_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	effects_bar.add_child(effect_hint)

	var assists := HBoxContainer.new()
	right.add_child(assists)
	var snap := CheckBox.new()
	snap.text = "网格吸附"
	snap.tooltip_text = "拖动波次单位时将位置吸附到网格；仅用于编辑摆放，不改变单位碰撞或寻路规则。"
	assists.add_child(snap)
	var spacing := SpinBox.new()
	spacing.min_value = 8
	spacing.max_value = 128
	spacing.step = 8
	spacing.value = 32
	spacing.tooltip_text = "摆放网格的间距，单位为战场本地像素；启用网格吸附后，单位位置按此间距对齐。"
	assists.add_child(spacing)
	var area := CheckBox.new()
	area.text = "敌方建议区域"
	area.tooltip_text = "显示敌方摆放建议区域与越界提示；只提供编辑辅助，不作为运行时强制部署边界。"
	area.button_pressed = true
	assists.add_child(area)
	_button(assists, "适应窗口", _fit)
	var legend := Label.new()
	legend.text = "绿：区域内   橙色 !：越界/重叠"
	assists.add_child(legend)
	preview = preload("res://addons/wave_editor/preview.gd").new()
	right.add_child(preview)
	snap.toggled.connect(_snap_changed)
	spacing.value_changed.connect(_grid_changed)
	area.toggled.connect(_area_changed)
	preview.selection_changed.connect(_picked)
	preview.drag_started.connect(doc.begin)
	preview.drag_finished.connect(_drag_finished)
	unit_list = ItemList.new()
	unit_list.select_mode = ItemList.SELECT_MULTI
	unit_list.custom_minimum_size.y = 110
	right.add_child(unit_list)
	unit_list.multi_selected.connect(_list_selected)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_build_dialogs()
	_load_catalog()
	doc.changed.connect(_refresh)
	doc.open(initial_path)
	_refresh()
	_scan_levels()
	if Engine.is_editor_hint() and FileAccess.file_exists(doc.recovery_path):
		recover_dialog.popup_centered()

# 作用：创建按钮；parent 是容器，text 是标题，action 是回调，返回按钮。
func _button(parent: Node, text: String, action: Callable) -> Button:
	var result := Button.new()
	result.text = text
	result.pressed.connect(action)
	parent.add_child(result)
	return result

# 作用：建立打开、保存与保护对话框；没有参数，没有返回值。
func _build_dialogs() -> void:
	open_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.tres ; 关卡配置", _opened)
	save_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.tres ; 新关卡文件", _saved_as)
	save_dialog.canceled.connect(_guard_cancel)
	terrain_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.tscn ; 战斗地形场景", _set_terrain)
	guard = ConfirmationDialog.new()
	guard.title = "关卡有未保存修改"
	guard.dialog_text = "是否先保存当前关卡？"
	guard.ok_button_text = "保存并继续"
	guard.add_button("放弃修改", false, "discard")
	guard.confirmed.connect(_guard_save)
	guard.custom_action.connect(_guard_discard)
	guard.canceled.connect(_guard_cancel)
	add_child(guard)
	conflict = ConfirmationDialog.new()
	conflict.title = "未保存成功"
	conflict.ok_button_text = "另存为新文件"
	conflict.add_button("重新读取磁盘", false, "reload")
	conflict.confirmed.connect(_save_as)
	conflict.custom_action.connect(_conflict_reload)
	conflict.canceled.connect(_guard_cancel)
	add_child(conflict)
	recover_dialog = ConfirmationDialog.new()
	recover_dialog.title = "发现未保存的波次草稿"
	recover_dialog.dialog_text = "是否恢复上次退出或保存冲突时保留的草稿？"
	recover_dialog.ok_button_text = "恢复草稿"
	recover_dialog.cancel_button_text = "放弃恢复草稿"
	recover_dialog.confirmed.connect(_recover)
	recover_dialog.canceled.connect(doc.discard_recovery)
	add_child(recover_dialog)

# 作用：建立项目文件选择器；mode 为模式，filter 为类型，action 为回调，返回对话框。
func _file_dialog(mode: FileDialog.FileMode, filter: String, action: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_RESOURCES
	dialog.file_mode = mode
	dialog.filters = PackedStringArray([filter])
	dialog.current_dir = "res://data/levels"
	dialog.file_selected.connect(action)
	add_child(dialog)
	return dialog

# 作用：读取现有敌方怪物目录；没有参数，没有返回值。
func _load_catalog() -> void:
	for file in DirAccess.get_files_at("res://scenes/units"):
		if not file.ends_with(".tscn"):
			continue
		var scene := load("res://scenes/units/" + file) as PackedScene
		var unit := scene.instantiate()
		if unit is UnitBase and unit.unit_data != null and unit.unit_data.unit_team == "team_b":
			scenes.append(scene)
			names.append(unit.unit_data.unit_name + " (" + file.get_basename() + ")")
		unit.free()
	_filter("")

# 作用：按中英文名称过滤怪物；query 为关键词，没有返回值。
func _filter(query: String) -> void:
	catalog.clear()
	for i in names.size():
		if query.is_empty() or names[i].to_lower().contains(query.to_lower()):
			catalog.add_item(names[i], i)

# 作用：取得搜索结果对应场景；没有参数，返回场景或空。
func _chosen_scene() -> PackedScene:
	return scenes[catalog.get_selected_id()] if catalog.selected >= 0 else null

# 作用：扫描常用关卡目录；没有参数，没有返回值。
func _scan_levels() -> void:
	levels.clear()
	for file in DirAccess.get_files_at("res://data/levels"):
		if file.ends_with(".tres"):
			levels.add_item(file)
			levels.set_item_metadata(levels.item_count - 1, "res://data/levels/" + file)
	_sync_level_choice()

# 作用：保持下拉框与实际草稿一致；没有参数，没有返回值。
func _sync_level_choice() -> void:
	levels.select(-1)
	for i in levels.item_count:
		if levels.get_item_metadata(i) == doc.path:
			levels.select(i)

# 作用：选择常用关卡前检查未保存修改；index 为选项，没有返回值。
func _choose_level(index: int) -> void:
	var path: String = levels.get_item_metadata(index)
	_sync_level_choice()
	request_action(_open_path.bind(path))

# 作用：显示打开对话框；没有参数，没有返回值。
func _open_dialog() -> void:
	open_dialog.popup_centered_ratio(0.65)

# 作用：处理选定关卡；path 为路径，没有返回值。
func _opened(path: String) -> void:
	request_action(_open_path.bind(path))

# 作用：真正切换关卡；path 为路径，没有返回值。
func _open_path(path: String) -> void:
	if not doc.open(path):
		status.text = doc.error
	else:
		_reset_playback()
	_sync_level_choice()

# 作用：创建空白草稿；没有参数，没有返回值。
func _new_level() -> void:
	_reset_playback()
	doc.new_level()
	doc.write_recovery()
	_sync_level_choice()

# 作用：重新读取当前磁盘关卡；没有参数，没有返回值。
func _reload() -> void:
	if not doc.path.is_empty():
		_open_path(doc.path)

# 作用：有未保存修改时拦住切换或关闭；action 为继续操作，没有返回值。
func request_action(action: Callable) -> void:
	preview.finish_drag()
	if doc.is_dirty():
		pending = action
		guard.popup_centered()
	else:
		action.call()

# 作用：保存成功后才继续原操作；没有参数，没有返回值。
func _guard_save() -> void:
	if save_current():
		_continue_pending()

# 作用：用户明确放弃后继续；action 为按钮标识，没有返回值。
func _guard_discard(action: String) -> void:
	if action == "discard":
		guard.hide()
		doc.discard_recovery()
		_continue_pending()

# 作用：取消切换或恢复被禁用的插件；没有参数，没有返回值。
func _guard_cancel() -> void:
	pending = Callable()
	if orphaned:
		doc.write_recovery()
		EditorInterface.set_plugin_enabled.call_deferred("wave_editor", true)
		queue_free()

# 作用：运行等待的动作；没有参数，没有返回值。
func _continue_pending() -> void:
	var action := pending
	pending = Callable()
	if action.is_valid():
		action.call()

# 作用：保存当前文档；没有参数，返回是否已经保存成功。
func save_current() -> bool:
	preview.finish_drag()
	if doc.path.is_empty():
		_save_as()
		return false
	if not doc.save():
		status.text = doc.error
		conflict.dialog_text = doc.error
		conflict.popup_centered()
		doc.write_recovery()
		return false
	status.text = "已保存：" + doc.path
	_scan_filesystem()
	return true

# 作用：显示另存为窗口；没有参数，没有返回值。
func _save_as() -> void:
	save_dialog.current_file = "level_new.tres"
	save_dialog.popup_centered_ratio(0.65)

# 作用：另存为成功后继续等待操作；path 为新文件路径，没有返回值。
func _saved_as(path: String) -> void:
	if doc.save(path):
		status.text = "已保存：" + path
		_scan_filesystem()
		_scan_levels()
		_continue_pending()
	else:
		status.text = doc.error
		conflict.dialog_text = doc.error
		conflict.popup_centered()

# 作用：冲突时通过保护对话框重新读取；action 为按钮标识，没有返回值。
func _conflict_reload(action: String) -> void:
	if action == "reload":
		conflict.hide()
		request_action(_reload)

# 作用：通知 Godot 更新资源；没有参数，没有返回值。
func _scan_filesystem() -> void:
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if filesystem != null and not filesystem.is_scanning():
			filesystem.scan()

# 作用：恢复磁盘草稿；没有参数，没有返回值。
func _recover() -> void:
	if doc.recover():
		_reset_playback()
		status.text = "已恢复草稿；保存时仍检查原文件是否被外部修改。"
		_sync_level_choice()

# 作用：编辑器退出前保存或保留恢复副本；没有参数，没有返回值。
func save_on_exit() -> void:
	preview.finish_drag()
	if doc.is_dirty() and (doc.path.is_empty() or not doc.save()):
		if doc.write_recovery():
			push_warning("波次草稿未写入目标文件，已保留恢复副本：" + doc.recovery_path)
		else:
			push_error("关卡与恢复副本均无法保存，请取消退出并另存为可写路径。")

# 作用：禁用插件时延后释放，直到用户完成保存决定；没有参数，没有返回值。
func close_for_disable() -> void:
	orphaned = true
	hide()
	request_action(queue_free)

# 作用：改名提交到撤销历史；value 为回车输入或空，没有返回值。
func _rename(_value: String) -> void:
	if not refreshing and doc.config != null:
		doc.set_field("level_name", level_name.text)

# 作用：修改循环规则；value 为开关，没有返回值。
func _repeat_changed(value: bool) -> void:
	if not refreshing and doc.config != null:
		doc.set_field("repeat_waves", value)

# 作用：浏览地形文件；没有参数，没有返回值。
func _browse_terrain() -> void:
	terrain_dialog.current_dir = "res://scenes/levels/battles"
	terrain_dialog.popup_centered_ratio(0.65)

# 作用：判断拖入数据是否包含场景；position 为鼠标位置，data 为 Godot 拖拽数据，返回是否接收。
func _can_drop_terrain(_position: Vector2, data: Variant) -> bool:
	return not _terrain_path(data).is_empty()

# 作用：提取拖拽场景路径；data 为拖拽数据，返回路径或空。
func _terrain_path(data: Variant) -> String:
	if not data is Dictionary:
		return ""
	if data.get("type") == "files" and data.files.size() == 1 and str(data.files[0]).ends_with(".tscn"):
		return data.files[0]
	if data.get("type") == "resource" and data.get("resource") is PackedScene:
		return data.resource.resource_path
	return ""

# 作用：接受拖入地形；position 为鼠标位置，data 为拖拽数据，没有返回值。
func _drop_terrain(_position: Vector2, data: Variant) -> void:
	_set_terrain(_terrain_path(data))

# 作用：验证并设置地形；path 为场景路径，没有返回值。
func _set_terrain(path: String) -> void:
	var scene := load(path) as PackedScene
	if scene == null:
		status.text = "请选择 .tscn 战斗场景。"
		return
	var root := scene.instantiate()
	var valid := root.has_node("Level") and root.has_node("Entities/TeamB") and root.has_node("BattleRoundManager") and root.has_method("configure_level")
	root.free()
	if not valid:
		status.text = "地形需要继承 battle_scene，并保留 Level、TeamB 和回合管理器。"
		return
	doc.set_field("battle_scene", scene)

# 作用：刷新文档界面；没有参数，没有返回值。
func _refresh() -> void:
	if preview == null or doc.config == null:
		return
	refreshing = true
	if last_revision != doc.revision:
		_reset_playback()
		last_revision = doc.revision
	title.text = ("● " if doc.is_dirty() else "") + (doc.path if not doc.path.is_empty() else "未命名关卡")
	title.tooltip_text = title.text
	level_name.text = doc.config.level_name
	repeat.button_pressed = doc.config.repeat_waves
	loop_start.value = doc.config.repeat_start
	loop_end.value = doc.config.repeat_end
	terrain.text = "地形：" + (doc.config.battle_scene.resource_path.get_file() if doc.config.battle_scene != null else "拖入 battle_001.tscn 或点击选择")
	if shown_terrain != doc.config.battle_scene:
		shown_terrain = doc.config.battle_scene
		preview.load_terrain(shown_terrain)
		preview.fit()
	round_list.clear()
	for i in doc.rounds.size():
		var count: int = doc.rounds[i].get_child_count()
		var tag := ""
		if doc.config.repeat_waves:
			var end: int = doc.rounds.size() if doc.config.repeat_end == 0 else doc.config.repeat_end
			if i + 1 > end:
				tag = " · 不出场"
			elif i + 1 >= doc.config.repeat_start:
				tag = " · 循环"
		round_list.add_item("第 %d 回合 · %s%s" % [i + 1, "%d 怪物" % count if count else "空回合", tag])
	if doc.current >= 0:
		round_list.select(doc.current)
	# 编辑后的范围如果越界，明确显示错误，保存和播放均会拦截。
	var range_error: String = SEQUENCE.validate_range(doc.rounds.size(), doc.config.repeat_waves, doc.config.repeat_start, doc.config.repeat_end)
	_show_units()
	undo_button.disabled = not doc.history.has_undo()
	redo_button.disabled = not doc.history.has_redo()
	undo_button.tooltip_text = doc.history.get_current_action_name()
	status.text = ("● 未保存 · " if doc.is_dirty() else "已保存 · ") + "橙色为站位建议警告，不强制限制保存。"
	if not range_error.is_empty():
		status.text = range_error
	refreshing = false

# 作用：切换回合；index 为零基回合编号，没有返回值。
func _select_round(index: int) -> void:
	preview.finish_drag()
	doc.current = index
	display_round = index + 1
	display_cycle = 0
	doc.selection.clear()
	_show_units()

# 作用：同步当前回合清单与站位提示；没有参数，没有返回值。
func _show_units() -> void:
	preview.dragging = false
	preview.boxing = false
	preview.units.clear()
	unit_list.clear()
	if doc.current >= 0:
		preview.units.assign(doc.rounds[doc.current].get_children())
	var warnings: Array[String] = preview.analyze()
	for i in preview.units.size():
		var unit: Node = preview.units[i]
		var name: String = unit.unit_data.unit_name if unit.unit_data != null else str(unit.name)
		unit_list.add_item("#%d %s  %s  %s  %s" % [i + 1, name, unit.position, warnings[i], SEQUENCE.describe(unit, display_cycle)])
	_picked(doc.selection)
	preview.queue_redraw()

# 作用：同步多选列表；indices 为怪物编号，没有返回值。
func _picked(indices: PackedInt32Array) -> void:
	doc.selection = indices.duplicate()
	preview.selection = indices.duplicate()
	unit_list.deselect_all()
	for i in indices:
		if i >= 0 and i < unit_list.item_count:
			unit_list.select(i, false)
	_refresh_effect_selection()
	preview.queue_redraw()

# 作用：清单选择变化后同步预览；index 为编号，selected 为状态，没有返回值。
func _list_selected(_index: int, _selected: bool) -> void:
	_picked(unit_list.get_selected_items())

# 作用：选择当前所有怪物；没有参数，没有返回值。
func _select_all() -> void:
	var selected := PackedInt32Array()
	for i in preview.units.size():
		selected.append(i)
	_picked(selected)

# 作用：添加搜索选中的怪物；没有参数，没有返回值。
func _add_unit() -> void:
	doc.add_unit(_chosen_scene())

# 作用：批量编辑选择项；kind 为删除、替换或复制，没有返回值。
func _edit_units(kind: String) -> void:
	if kind != "替换" or _chosen_scene() != null:
		doc.edit_units(kind, _chosen_scene())

# 作用：拖动结束提交一个撤销步骤；modified 为坐标是否改变，没有返回值。
func _drag_finished(modified: bool) -> void:
	if modified:
		doc.commit("拖动站位")
	else:
		doc.before = {}
	_show_units()

# 作用：设置吸附；value 为开关，没有返回值。
func _snap_changed(value: bool) -> void:
	preview.snapping = value
	preview.queue_redraw()

# 作用：设置网格大小；value 为像素间隔，没有返回值。
func _grid_changed(value: float) -> void:
	preview.grid = value
	preview.queue_redraw()

# 作用：显示建议区域；value 为开关，没有返回值。
func _area_changed(value: bool) -> void:
	preview.show_area = value
	preview.queue_redraw()

# 作用：恢复视图全景；没有参数，没有返回值。
func _fit() -> void:
	preview.fit()

# 作用：按循环规则展示下一回合并累计记录；没有参数，没有返回值。
func _next() -> void:
	if doc.rounds.is_empty():
		return
	var range_error: String = SEQUENCE.validate_range(doc.rounds.size(), doc.config.repeat_waves, doc.config.repeat_start, doc.config.repeat_end)
	if not range_error.is_empty():
		status.text = range_error
		return
	var entry := SEQUENCE.resolve(played_round + 1, doc.rounds.size(), doc.config.repeat_waves, doc.config.repeat_start, doc.config.repeat_end)
	if entry.index < 0:
		status.text = "有限波次播放结束；累计出场 %d 个怪物。" % total
		return
	played_round += 1
	playback = entry.index
	cycle = entry.cycle
	_select_round(playback)
	display_round = played_round
	display_cycle = cycle
	_show_units()
	round_list.select(playback)
	var counts := {}
	var growth: Array[String] = []
	for unit in doc.rounds[playback].get_children():
		var name: String = unit.unit_data.unit_name if unit.unit_data != null else str(unit.name)
		counts[name] = counts.get(name, 0) + 1
		var detail := SEQUENCE.describe(unit, cycle)
		if not detail.is_empty():
			growth.append("#%d %s" % [unit.get_index() + 1, detail])
	var count: int = doc.rounds[playback].get_child_count()
	total += count
	var descriptions: Array[String] = []
	for name in counts:
		descriptions.append("%s×%d" % [name, counts[name]])
	var line := "实际第%d回合 ← 第%d波 / 已重复%d次：%s；累计%d" % [played_round, playback + 1, cycle, "空回合" if count == 0 else "，".join(descriptions), total]
	if not growth.is_empty():
		line += " | " + "；".join(growth)
	records.append(line)
	if records.size() > 200:
		records.pop_front()
	log_list.clear()
	for record in records:
		log_list.add_item(record)
		log_list.set_item_tooltip(log_list.item_count - 1, record)
	log_list.select(log_list.item_count - 1)
	log_list.ensure_current_is_visible()
	status.text = line

# 作用：清空播放游标与累计记录；没有参数，没有返回值。
func _reset_playback() -> void:
	playback = -1
	cycle = 0
	played_round = 0
	display_cycle = 0
	display_round = doc.current + 1
	total = 0
	records.clear()
	if log_list != null:
		log_list.clear()

# 作用：启动独立测试场景，使用当前草稿；没有参数，没有返回值。
func _launch() -> void:
	preview.finish_drag()
	var output: Resource = doc.output()
	var error: String = doc.validate(output)
	if not error.is_empty() or doc.current < 0:
		status.text = error
		return
	if Engine.is_editor_hint() and EditorInterface.is_playing_scene():
		status.text = "请先停止正在运行的游戏，再启动当前回合。"
		return
	# 测试快照在 user://，既不覆盖正式关卡，也不把前面回合的存活单位虚构出来。
	var start_round := maxi(1, display_round)
	output.set_meta("wave_editor_start_round", start_round)
	var result := ResourceSaver.save(output, "user://wave_editor_playtest.tres")
	if result != OK:
		status.text = "无法写入实战快照：" + error_string(result)
		return
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://addons/wave_editor/playtest.tscn")
	status.text = "从第 %d 回合开始全新实战；使用当前草稿和初始牌组，不继承前面回合的存活单位。" % start_round

# 作用：面板可见时处理快捷键，文本输入框保留自己的撤销；event 为输入，没有返回值。
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	if event.ctrl_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed:
				doc.redo()
			else:
				doc.undo()
		elif event.keycode == KEY_Y:
			doc.redo()
		elif event.keycode == KEY_S:
			save_current()
		elif event.keycode == KEY_A:
			_select_all()
		elif event.keycode == KEY_D:
			_edit_units("复制")
		else:
			return
		get_viewport().set_input_as_handled()

# 作用：面板释放时清理树外节点；没有参数，没有返回值。
func _exit_tree() -> void:
	if is_instance_valid(preview):
		preview.units.clear()
	doc.history.clear_history()
	doc.history.free()
	doc.clear_nodes()
# 作用：添加短说明文字；parent 为容器、text 为文字，没有返回值。
func _label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)

# 作用：创建整数输入；parent 为容器、minimum/maximum 为范围、initial 为默认值，返回输入控件。
func _number(parent: Node, minimum: int, maximum: int, initial: int) -> SpinBox:
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = 1
	field.value = initial
	field.custom_minimum_size.x = 85
	parent.add_child(field)
	return field

# 作用：应用有效循环范围；没有参数，没有返回值。
func _apply_repeat_range() -> void:
	var first := int(loop_start.value)
	var last := int(loop_end.value)
	var error: String = SEQUENCE.validate_range(doc.rounds.size(), true, first, last)
	if not error.is_empty():
		status.text = error
		return
	doc.set_repeat_range(first, last)

# 作用：按当前模式把增益应用到所选单位；没有参数，没有返回值。
func _apply_unit_effect() -> void:
	var key: String = EFFECT_KEYS[effect_kind.selected]
	if effect_mode.selected == 1:
		doc.set_spawn_effect(key, int(effect_amount.value))
	else:
		doc.set_cycle_effect(key, int(effect_amount.value))

# 作用：只清除当前模式的当前属性，保留其他增益；没有参数，没有返回值。
func _clear_unit_effect() -> void:
	var key: String = EFFECT_KEYS[effect_kind.selected]
	if effect_mode.selected == 1:
		doc.set_spawn_effect(key, 0)
	else:
		doc.set_cycle_effect(key, 0)

# 作用：切换增益模式或属性后读取选中单位配置；index 为下拉编号，没有返回值。
func _effect_kind_changed(_index: int) -> void:
	_refresh_effect_selection()

# 作用：显示当前模式的已有增益和生效规则；没有参数，没有返回值。
func _refresh_effect_selection() -> void:
	if effect_mode == null or effect_kind == null or effect_amount == null:
		return
	var single := effect_mode.selected == 1
	var metadata: StringName = SEQUENCE.SPAWN_META if single else SEQUENCE.EFFECT_META
	var rule := "每次出场固定加一次" if single else "首次不加，循环累积"
	effect_hint.tooltip_text = rule + "；输入 0 只清除当前模式的当前属性。"
	var selected: PackedInt32Array = doc.selection
	if selected.is_empty():
		effect_hint.text = "选择单位后设置；" + rule
		return
	var key: String = EFFECT_KEYS[effect_kind.selected]
	var first: int = SEQUENCE.effects(preview.units[selected[0]], metadata).get(key, 0)
	var mixed := false
	for index in selected:
		mixed = mixed or int(SEQUENCE.effects(preview.units[index], metadata).get(key, 0)) != first
	effect_amount.value = first
	effect_hint.text = "选中%d个%s；%s" % [selected.size(), "（原值不同）" if mixed else "", rule]
	var end: int = doc.rounds.size() if doc.config.repeat_end == 0 else doc.config.repeat_end
	if not single and (not doc.config.repeat_waves or doc.current + 1 < doc.config.repeat_start or doc.current + 1 > end):
		effect_hint.text += "（此波当前不参与循环）"
