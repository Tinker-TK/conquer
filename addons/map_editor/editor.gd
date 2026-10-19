# 这玩意儿是干嘛的（核心逻辑）：在 Godot 内组织地图画布、节点属性、文件保存与实战入口。
# 数据是咋流动的（数据流向）：按钮和属性输入 → document 事务 → canvas 重画 → JSON 或实战快照。
# 为啥这么写（选型决策）：采用原生主屏幕与可换行工具栏，直接选项目里的战斗关卡，窄窗口也能显示完整按钮。
# 性能咋样（复杂度）：修改时刷新列表与画布，最多 500 个节点，事件表单不会每帧重建。
@tool
extends VBoxContainer

const CONFIG = preload("res://scripts/map/fixed_map_config.gd")
const EVENT_REWARDS = preload("res://scripts/events/event_rewards.gd")
const FIELD_HELP := {
	"地图名称": "当前固定路线地图的显示名称；保存到地图配置，不改变节点编号或连线。",
	"层数": "地图总层数，节点所在层需在此范围内；减少层数前需检查高层节点，路线只能连接到更高层。",
	"唯一编号（如 floor_03_01）": "当前地点在地图中的唯一编号，用于路线连接与完成状态记录；改名会同步更新关联路线。",
	"显示名称 / 事件标题": "当前地点在地图列表或事件面板中的显示标题，不改变地点的实际类型。",
	"所在层": "当前地点的层号，从 1 开始；不能超过地图总层数，路线的目标必须位于更高层。",
	"金币数量（必定奖励）": "完成此战斗节点后必定获得的金币点数；只覆盖当前节点，不改写奖励模板资源。",
	"随机药水奖励概率（%）": "此战斗胜利后额外掉落药水的概率；25 表示 25%，0 不掉落，100 必定掉落。",
	"随机遗物奖励概率（%）": "此战斗胜利后额外掉落有效且尚未持有遗物的概率；0 不掉落，100 必定尝试掉落，候选池为空时不提供遗物。",
	"回血": "选择此事件选项时回复的固定玩家生命点数，与百分比回复共同计算，最终不超过最大生命。0 表示无固定回复。",
	"金币": "选择此事件选项时获得的金币数量；0 表示此选项不提供金币。",
	"最大生命回复百分比（%）": "选择此事件选项时按玩家最大生命计算的回复百分比，30 表示回复 30%；与固定回血共同计算，不超过生命上限。"
}
var event_binding: OptionButton
var event_ids: Array[String] = []
var event_paths: Array[String] = []
var event_hint: Label
var event_inspect_button: Button
var doc = preload("res://addons/map_editor/document.gd").new()
var canvas: Control
var scroll: ScrollContainer
var node_list: ItemList
var inspector: VBoxContainer
var name_input: LineEdit
var floors_input: SpinBox
var id_input: LineEdit
var title_input: LineEdit
var kind_input: OptionButton
var floor_input: SpinBox
var start_input: CheckBox
var level_input: OptionButton
var level_box: VBoxContainer
var reward_box: VBoxContainer
var reward_binding: OptionButton
var reward_paths: Array[String] = []
var reward_gold: SpinBox
var reward_potion: SpinBox
var reward_relic: SpinBox
var reward_dialog: FileDialog
var event_box: VBoxContainer
var treasure_hint: Label
var description_input: TextEdit
var texts: Array[LineEdit] = []
var heals: Array[SpinBox] = []
var heal_percents: Array[SpinBox] = []
var choice_boxes: Array[VBoxContainer] = []
var choice_effects: Array[OptionButton] = []
var golds: Array[SpinBox] = []
var outgoing: VBoxContainer
var status: Label
var file_title: Label
var check_label: Label
var undo_button: Button
var redo_button: Button
var routes: OptionButton
var mode_input: OptionButton
var open_dialog: FileDialog
var save_dialog: FileDialog
var guard: ConfirmationDialog
var pending := Callable()
var refreshing := false
var level_ids: Array[String] = []
var route_paths: Array[String] = []
# 项目里的正式路线快照；测试可指定独立路径，避免覆盖策划配置。
var game_map_paths: Array[String] = CONFIG.game_map_paths()
var game_map_path: String:
	get: return game_map_paths[0]
	set(value): game_map_paths[0] = value
var apply_game_button: Button
var apply_act_input: OptionButton
var route_seed_input: LineEdit
var route_difficulty_input: OptionButton

# 作用：Godot 创建编辑器时搭建界面并恢复文件；没有参数，没有返回值。
func _ready() -> void:
	# 按钮保留文字所需宽度，空间不足时整项换行，不把按钮压成没有文字的窄条。
	var files := HFlowContainer.new()
	add_child(files)
	routes = OptionButton.new()
	routes.fit_to_longest_item = false
	routes.custom_minimum_size.x = 180
	files.add_child(routes)
	routes.item_selected.connect(_choose_route)
	_button(files, "打开…", _browse_open)
	_button(files, "新建", _request.bind(_new_map.bind(false)))
	_button(files, "示例", _request.bind(_new_map.bind(true)))
	_button(files, "保存", save_current)
	_button(files, "另存为…", _browse_save)
	apply_act_input = OptionButton.new()
	for act in CONFIG.ACT_COUNT:
		apply_act_input.add_item("应用到第%d幕" % (act + 1))
	apply_act_input.tooltip_text = "选择当前路线对应的幕；三幕分别保存，不会互相覆盖。"
	files.add_child(apply_act_input)
	apply_game_button = _button(files, "应用到游戏", _apply_to_game)
	apply_game_button.tooltip_text = "将当前路线应用到左侧选择的幕。游戏按第一、第二、第三幕依次推进，并随项目导出。未保存修改也会包含在本次应用中；继续存档沿用本局路线快照。"
	undo_button = _button(files, "撤销", _undo)
	redo_button = _button(files, "重做", _redo)
	file_title = Label.new()
	file_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	file_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(file_title)
	var settings := HFlowContainer.new()
	add_child(settings)
	# 标签与输入框作为同一项换行，避免层数标签和它的输入框分散到两行。
	var name_group := HBoxContainer.new()
	settings.add_child(name_group)
	name_input = _line(name_group, "地图名称")
	name_input.custom_minimum_size.x = 220
	name_input.max_length = 80
	_bind_line(name_input, _map_name)
	var floor_group := HBoxContainer.new()
	settings.add_child(floor_group)
	floors_input = _spin(floor_group, "层数", 2, 30)
	floors_input.value_changed.connect(_floors_changed)
	mode_input = OptionButton.new()
	mode_input.tooltip_text = "选择画布操作：选择模式可拖动节点，连接模式从起点连接到更高层，路线试玩只沿当前可达节点前进。"
	for item in ["选择 / 拖动", "连接路线", "路线试玩"]:
		mode_input.add_item(item)
	settings.add_child(mode_input)
	mode_input.item_selected.connect(_mode_changed)
	_button(settings, "重新出发", _restart)
	_button(settings, "启动此路线实战", _launch)
	route_seed_input = LineEdit.new()
	route_seed_input.placeholder_text = "地图种子（留空随机）"
	route_seed_input.max_length = 64
	route_seed_input.custom_minimum_size.x = 195
	settings.add_child(route_seed_input)
	route_difficulty_input = OptionButton.new()
	var generation: Dictionary = load("res://scripts/map/route_generation_config.gd").read_file()
	if not generation.has("error"):
		for difficulty in generation.data.difficulties:
			route_difficulty_input.add_item(str(difficulty))
	settings.add_child(route_difficulty_input)
	_button(settings, "生成随机路线", func(): _request(_generate_random_route))
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 205
	split.add_child(left)
	_label(left, "添加节点（点击画布空白处）")
	for i in 8:
		_button(left, ["＋ 战斗", "＋ 事件", "＋ 篝火", "＋ Boss", "＋ 宝箱", "＋ 商店", "＋ 精英", "＋ 随机事件"][i], _add_mode.bind(i))
	node_list = ItemList.new()
	node_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(node_list)
	node_list.item_selected.connect(_list_picked)
	_button(left, "删除选中节点 / 路线", _delete)
	var main := HSplitContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(main)
	scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(scroll)
	canvas = preload("res://addons/map_editor/canvas.gd").new()
	canvas.doc = doc
	scroll.add_child(canvas)
	canvas.picked.connect(_picked)
	canvas.placed.connect(_placed)
	canvas.edge_picked.connect(_edge_picked)
	var side_scroll := ScrollContainer.new()
	side_scroll.custom_minimum_size.x = 310
	main.add_child(side_scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side_scroll.add_child(side)
	inspector = VBoxContainer.new()
	side.add_child(inspector)
	_build_inspector()
	_label(side, "路线检查")
	check_label = _label(side, "")
	check_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status = _label(self, "选择：拖动节点吸附层级；连线：先源节点再更高层节点；Delete 删除，Ctrl+Z 撤销。")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	open_dialog = _dialog(FileDialog.FILE_MODE_OPEN_FILE, _opened)
	save_dialog = _dialog(FileDialog.FILE_MODE_SAVE_FILE, _saved_as)
	save_dialog.canceled.connect(func(): pending = Callable())
	reward_dialog = FileDialog.new()
	reward_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	reward_dialog.access = FileDialog.ACCESS_RESOURCES
	reward_dialog.filters = PackedStringArray(["*.tres ; 战斗奖励配置"])
	reward_dialog.current_dir = "res://data/battle_rewards"
	reward_dialog.file_selected.connect(_load_reward_config)
	add_child(reward_dialog)
	guard = ConfirmationDialog.new()
	guard.title = "地图有未保存修改"
	guard.dialog_text = "先保存当前地图再继续？"
	guard.ok_button_text = "保存并继续"
	guard.add_button("放弃修改", false, "discard")
	guard.confirmed.connect(save_current)
	guard.custom_action.connect(_discard)
	guard.canceled.connect(func(): pending = Callable())
	add_child(guard)
	doc.changed.connect(_refresh)
	_scan_catalog()
	# 优先恢复草稿；没有草稿时打开项目里的第一份路线，不改动磁盘原文件。
	if FileAccess.file_exists(doc.RECOVERY) and doc.recover():
		status.text = "已恢复上次未保存的地图草稿。"
	elif not route_paths.is_empty() and doc.open(route_paths[0]):
		status.text = "已打开：" + doc.path
	else:
		doc.new_map(true)
	_refresh()
	_scroll_to_start.call_deferred()

# 作用：创建文字标签；parent 为容器，text 为文字，返回标签。
func _label(parent: Node, text: String) -> Label:
	var item := Label.new()
	item.text = text
	parent.add_child(item)
	return item

# 作用：创建按钮；parent 为容器，text 为文字，action 为操作，返回按钮。
func _button(parent: Node, text: String, action: Callable) -> Button:
	var item := Button.new()
	item.text = text
	parent.add_child(item)
	item.pressed.connect(action)
	return item

# 作用：创建单行输入框；parent 为容器，text 为标签，返回输入框。
func _line(parent: Node, text: String) -> LineEdit:
	_label(parent, text).tooltip_text = FIELD_HELP.get(text, "")
	var item := LineEdit.new()
	item.tooltip_text = FIELD_HELP.get(text, "")
	item.max_length = 80
	parent.add_child(item)
	return item

# 作用：创建整数输入；parent 为容器，text 为标题，low/high 为范围，返回输入框。
func _spin(parent: Node, text: String, low: int, high: int) -> SpinBox:
	_label(parent, text).tooltip_text = FIELD_HELP.get(text, "")
	var item := SpinBox.new()
	item.tooltip_text = FIELD_HELP.get(text, "")
	item.min_value = low
	item.max_value = high
	item.step = 1
	parent.add_child(item)
	return item

# 作用：按回车或离开输入框时提交；input 为输入框，action 为回调，没有返回值。
func _bind_line(input: LineEdit, action: Callable) -> void:
	input.text_submitted.connect(func(_text): action.call(input.text))
	input.focus_exited.connect(func(): action.call(input.text))

# 作用：建立节点属性区；没有参数，没有返回值。
func _build_inspector() -> void:
	id_input = _line(inspector, "唯一编号（如 floor_03_01）")
	_bind_line(id_input, _rename_id)
	title_input = _line(inspector, "显示名称 / 事件标题")
	_bind_line(title_input, _set_text.bind("title"))
	kind_input = OptionButton.new()
	kind_input.tooltip_text = "地点类型决定进入战斗、事件、篝火、Boss、宝箱或商店，并控制可编辑的关联内容；改变类型后需检查原有绑定是否仍适用。"
	for name in ["战斗", "事件", "篝火", "Boss", "宝箱", "商店", "精英", "随机事件"]:
		kind_input.add_item(name)
	inspector.add_child(kind_input)
	kind_input.item_selected.connect(_kind_changed)
	floor_input = _spin(inspector, "所在层", 1, 30)
	floor_input.value_changed.connect(_floor_changed)
	start_input = CheckBox.new()
	start_input.text = "设为出发点"
	start_input.tooltip_text = "将此地点设为新一局可选择的出发点之一；地图可配置多个起点，之后沿所选地点的出站路线前进。"
	inspector.add_child(start_input)
	start_input.toggled.connect(_start_changed)
	level_box = VBoxContainer.new()
	inspector.add_child(level_box)
	_label(level_box, "战斗关卡（项目资源）")
	level_input = OptionButton.new()
	level_input.tooltip_text = "当前战斗或 Boss 节点加载的 BattleLevelConfig；其中配置战场、波次、玩家能量、抽牌、天气与河流。"
	level_box.add_child(level_input)
	level_input.item_selected.connect(_level_changed)
	_button(level_box, "刷新关卡列表", _refresh_catalog)
	_button(level_box, "在检查器打开关卡", _inspect_level)
	reward_box = VBoxContainer.new()
	inspector.add_child(reward_box)
	_label(reward_box, "战斗胜利奖励")
	reward_binding = OptionButton.new()
	reward_binding.tooltip_text = "选择当前节点的胜利奖励模板。加载后可独立覆盖本节点的金币和掉落概率，不修改模板原资源。"
	reward_binding.fit_to_longest_item = false
	reward_box.add_child(reward_binding)
	reward_binding.item_selected.connect(_reward_binding_changed)
	_button(reward_box, "加载奖励配置…", func(): reward_dialog.popup_centered_ratio(0.6))
	_button(reward_box, "刷新奖励配置列表", _refresh_catalog)
	_button(reward_box, "在检查器打开奖励配置", _inspect_rewards)
	var reward_hint := _label(reward_box, "加载模板后可单独调整当前节点。\n金币和卡牌三选一必定出现；\n药水、遗物按以下百分比掉落。")
	reward_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reward_gold = _spin(reward_box, "金币数量（必定奖励）", 1, 9999)
	reward_potion = _spin(reward_box, "随机药水奖励概率（%）", 0, 100)
	reward_relic = _spin(reward_box, "随机遗物奖励概率（%）", 0, 100)
	reward_potion.step = 0.1
	reward_relic.step = 0.1
	reward_gold.value_changed.connect(_reward_number.bind("gold"))
	reward_potion.value_changed.connect(_reward_number.bind("potion_chance"))
	reward_relic.value_changed.connect(_reward_number.bind("relic_chance"))
	treasure_hint = Label.new()
	treasure_hint.text = "打开宝箱后获得一件随机遗物。\n自动排除已拥有及停用的遗物；\n无需配置事件或战斗关卡。"
	treasure_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(treasure_hint)
	event_box = VBoxContainer.new()
	inspector.add_child(event_box)
	_label(event_box, "事件工坊已配置事件")
	event_binding = OptionButton.new()
	event_binding.fit_to_longest_item = false
	event_binding.tooltip_text = "选择事件工坊已保存的事件，绑定其标题、描述、选项、插图及奖励池；切回地图工坊时自动刷新。"
	event_box.add_child(event_binding)
	event_binding.item_selected.connect(_event_binding_changed)
	_button(event_box, "刷新事件列表", _refresh_catalog)
	event_inspect_button = _button(event_box, "在检查器打开绑定事件", _inspect_event)
	event_hint = _label(event_box, "")
	event_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label(event_box, "事件描述")
	description_input = TextEdit.new()
	description_input.tooltip_text = "进入当前事件地点时显示的剧情说明；修改文字不会自动改变选项奖励或事件效果。"
	description_input.custom_minimum_size.y = 125
	description_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	event_box.add_child(description_input)
	description_input.focus_exited.connect(_description_changed)
	for i in 8:
		var choice_box := VBoxContainer.new()
		event_box.add_child(choice_box)
		choice_boxes.append(choice_box)
		var input := _line(choice_box, "选项 %d · 按钮文字" % (i + 1))
		input.tooltip_text = "此事件选项按钮的显示文字，需为实际使用的选项填写非空文案；实际奖励由下方回血、金币和效果类型决定。"
		texts.append(input)
		_bind_line(input, _choice_text.bind(i))
		var row := HBoxContainer.new()
		choice_box.add_child(row)
		var heal := _spin(row, "回血", 0, 9999)
		var gold := _spin(row, "金币", 0, 9999)
		var percent := _spin(choice_box, "最大生命回复百分比（%）", 0, 100)
		percent.step = 0.1
		heal_percents.append(percent)
		percent.value_changed.connect(_choice_number.bind(i, "heal_percent"))
		var effect := OptionButton.new()
		effect.tooltip_text = "此选项的额外事件行为：普通奖励按回血和金币结算，训练针对兵种卡，强化针对非兵种卡；已有其它事件效果可保留。"
		for label in ["普通奖励 / 离开", "训练兵种卡", "强化非兵种卡", "其它事件效果（保留）"]:
			effect.add_item(label)
		choice_box.add_child(effect)
		choice_effects.append(effect)
		effect.item_selected.connect(_choice_effect.bind(i))
		heals.append(heal)
		golds.append(gold)
		heal.value_changed.connect(_choice_number.bind(i, "heal"))
		gold.value_changed.connect(_choice_number.bind(i, "gold"))
	outgoing = VBoxContainer.new()
	inspector.add_child(outgoing)

# 作用：创建 JSON 文件窗口；mode 为打开/保存，action 为所选路径回调，返回窗口。
func _dialog(mode: int, action: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray(["*.json ; 固定地图 JSON"])
	dialog.current_dir = ProjectSettings.globalize_path("res://data/levels")
	dialog.file_selected.connect(action)
	add_child(dialog)
	return dialog

# 作用：扫描项目地图和战斗关卡；没有参数，没有返回值。
func _scan_catalog() -> void:
	level_ids.clear()
	route_paths.clear()
	reward_paths.clear()
	for path in EVENT_REWARDS.resource_paths("res://data/battle_rewards"):
		if load(path) is BattleRewardConfig:
			reward_paths.append(path)
	for file in DirAccess.get_files_at("res://data/levels"):
		if file.ends_with(".json"):
			route_paths.append("res://data/levels/" + file)
		elif file.begins_with("level_") and file.ends_with(".tres"):
			level_ids.append(file.get_basename())
	routes.clear()
	for path in route_paths:
		routes.add_item(path.get_file())

# 作用：刷新项目资源菜单及已绑定事件快照；没有参数，没有返回值。
func _refresh_catalog() -> void:
	flush_input()
	_scan_catalog()
	doc.refresh_event_bindings()
	_refresh()

# 作用：更新界面与校验结果，信号回填时不提交修改；没有参数，没有返回值。
func _refresh() -> void:
	if doc.data.is_empty() or not is_instance_valid(canvas):
		return
	refreshing = true
	name_input.text = doc.data.name
	floors_input.value = doc.data.floors
	file_title.text = ("* " if doc.is_dirty() else "") + (doc.path if not doc.path.is_empty() else "未命名地图")
	undo_button.disabled = doc.history.is_empty()
	redo_button.disabled = doc.future.is_empty()
	node_list.clear()
	for node in doc.data.locations:
		node_list.add_item("%02d · %s · %s" % [int(node.floor), node.id, node.title])
		if node.id == doc.selection:
			node_list.select(node_list.item_count - 1)
	var node: Dictionary = doc.node()
	inspector.visible = not node.is_empty() and canvas.mode != 2
	if not node.is_empty():
		id_input.text = node.id
		title_input.text = node.title
		kind_input.select(int(node.type))
		floor_input.max_value = doc.data.floors
		floor_input.value = node.floor
		start_input.button_pressed = doc.data.starting_ids.has(node.id)
		var battle := int(node.type) in [0, 3, 6]
		level_box.visible = battle
		reward_box.visible = battle
		event_box.visible = int(node.type) in [1, 2]
		treasure_hint.visible = int(node.type) in [4, 5, 7]
		treasure_hint.text = "问号房进入后抽取事件、战斗、宝箱或商店；首次结果随存档保留。\n候选内容位于节点 unknown_options，可编辑导出的 JSON。" if int(node.type) == 7 else "商店出售征召牌、功能牌、遗物和药水，并提供付费删牌。\n商品与价格：data/shops/caravan.json" if int(node.type) == 5 else "打开宝箱后获得一件随机遗物。"
		level_input.clear()
		for id in level_ids:
			level_input.add_item(id)
		var current := str(node.get("event_id", ""))
		var index := level_ids.find(current)
		if index < 0:
			level_input.add_item("未找到：" + current)
			index = level_input.item_count - 1
		level_input.select(index)
		if battle:
			_refresh_rewards(node)
		if int(node.type) in [1, 2]:
			event_binding.clear()
			event_binding.add_item("节点内编辑（保留当前内容）")
			event_ids.clear()
			event_paths.clear()
			for definition in EVENT_REWARDS.catalog():
				event_ids.append(definition.id)
				event_paths.append(definition.resource_path)
				event_binding.add_item(definition.title + " / " + definition.id)
				event_binding.set_item_tooltip(event_binding.item_count - 1, definition.resource_path)
			event_binding.add_item("第一章随机奇遇池 · 同局不重复")
			event_binding.set_item_disabled(event_binding.item_count - 1, int(node.type) != 1)
			var bound: bool = node.get("event_source", "inline") == "catalog"
			var binding_index: int = event_ids.find(str(node.get("event_id", "")))
			var random_event: bool = not str(node.get("event_pool", "")).is_empty()
			event_inspect_button.disabled = not bound or binding_index < 0
			if random_event:
				event_binding.select(event_ids.size() + 1)
				event_hint.text = "按楼层与稀有度抽取，同局不重复；进入节点后揭晓。事件文案与效果在事件工坊编辑。"
			elif bound and binding_index < 0:
				event_binding.add_item("缺失事件：" + str(node.get("event_id", "")))
				event_binding.set_item_disabled(event_binding.item_count - 1, true)
				event_binding.select(event_binding.item_count - 1)
				event_hint.text = "绑定事件已不存在，请重新选择工坊事件，或切回节点内编辑保留快照。"
			else:
				event_binding.select(binding_index + 1 if bound else 0)
				event_hint.text = "描述、选项和奖励来自事件工坊。切回此页或刷新列表会同步已保存配置；选择节点内编辑可保留当前内容。" if bound else "可选择事件工坊已保存的随机遗物、随机药水、两组选牌或篝火事件。"
			description_input.editable = not bound
			for input in texts:
				input.editable = not bound
			for input in heals + golds + heal_percents:
				input.editable = not bound
			description_input.text = node.event.description
			for i in 8:
				choice_boxes[i].visible = i < node.event.choices.size()
				if i >= node.event.choices.size():
					continue
				var choice: Dictionary = node.event.choices[i]
				texts[i].text = choice.text
				heals[i].value = choice.get("heal", 0)
				golds[i].value = choice.get("gold", 0)
				heal_percents[i].value = choice.get("heal_percent", 0)
				var effect_type: String = choice.get("effect", {}).get("type", "")
				var effect_index := ["", "train_unit", "enhance_card"].find(effect_type)
				choice_effects[i].select(effect_index if effect_index >= 0 else 3)
				choice_effects[i].disabled = bound
	for child in outgoing.get_children():
		outgoing.remove_child(child)
		child.queue_free()
	if not node.is_empty():
		_label(outgoing, "通往的节点")
		for id in node.next:
			# 路线编号可能很长，仅这些列表按钮省略末尾；工具栏动作始终显示全名。
			var route_button := _button(outgoing, "× 删除路线 → " + id, _remove_edge.bind(node.id, id))
			route_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			route_button.tooltip_text = route_button.text
	var issue := CONFIG.validate(doc.data)
	check_label.text = "✓ 路线检查通过" if issue.is_empty() else issue
	canvas.refresh()
	refreshing = false

# 作用：更新地图名称；text 为输入，没有返回值。
func _map_name(text: String) -> void:
	if refreshing or doc.data.is_empty() or doc.data.name == text:
		return
	doc.begin()
	doc.data.name = text
	doc.commit()

# 作用：修改地图层数且保护已有节点；value 为层数，没有返回值。
func _floors_changed(value: float) -> void:
	if refreshing or doc.data.is_empty() or int(value) == int(doc.data.floors):
		return
	for node in doc.data.locations:
		if int(node.floor) > int(value):
			status.text = "不能缩减到已有节点所在层以下。"
			_refresh()
			return
	doc.begin()
	doc.data.floors = int(value)
	doc.commit()

# 作用：修改唯一编号并维护引用；text 为编号，没有返回值。
func _rename_id(text: String) -> void:
	if refreshing or doc.node().is_empty() or text == doc.selection:
		return
	if not doc.rename_node(text.strip_edges()):
		status.text = doc.error
		_refresh()

# 作用：修改节点文本；text 为输入，key 为字段，没有返回值。
func _set_text(text: String, key: String) -> void:
	if refreshing or doc.node().is_empty() or doc.node().get(key) == text:
		return
	doc.begin()
	doc.node()[key] = text
	doc.commit()

# 作用：切换节点类型，保留已有事件编辑内容；kind 为类型，没有返回值。
func _kind_changed(kind: int) -> void:
	if refreshing or doc.node().is_empty():
		return
	doc.begin()
	doc.node().type = kind
	if kind != 1:
		doc.node().erase("event_pool")
	if kind in [0, 3, 6] and CONFIG.level_path(str(doc.node().get("event_id", ""))).is_empty():
		doc.node().event_id = "level_002" if kind == 3 else "level_elite_mid" if kind == 6 else "level_001"
	if kind == 7 and not doc.node().has("unknown_options"):
		doc.node().unknown_options = CONFIG.default_unknown_options()
	if kind == 6:
		doc.node().reward_config = "res://data/battle_rewards/elite.tres"
	doc.commit()

# 作用：改变节点层级；value 为层数，没有返回值。
func _floor_changed(value: float) -> void:
	if refreshing or doc.node().is_empty() or int(doc.node().floor) == int(value):
		return
	doc.begin()
	doc.node().floor = int(value)
	doc.commit()

# 作用：设置出发点；enabled 为勾选状态，没有返回值。
func _start_changed(enabled: bool) -> void:
	if refreshing or doc.node().is_empty():
		return
	doc.begin()
	doc.data.starting_ids.erase(doc.selection)
	if enabled:
		doc.data.starting_ids.append(doc.selection)
	doc.commit()

# 作用：选择真实战斗资源；index 为关卡列表项，没有返回值。
func _level_changed(index: int) -> void:
	if not refreshing and index >= 0 and index < level_ids.size():
		_set_text(level_ids[index], "event_id")

# 作用：在 Godot 检查器打开当前关卡；没有参数，没有返回值。
func _inspect_level() -> void:
	if Engine.is_editor_hint() and not doc.node().is_empty():
		var path := CONFIG.level_path(str(doc.node().get("event_id", "")))
		if not path.is_empty() and ResourceLoader.exists(path):
			EditorInterface.edit_resource(load(path))

func _refresh_rewards(node: Dictionary) -> void:
	reward_binding.clear()
	reward_binding.add_item("当前节点数值 / 恢复关卡默认" if node.has("battle_rewards") else "沿用关卡默认奖励")
	var bound := str(node.get("reward_config", ""))
	if not bound.is_empty() and not reward_paths.has(bound):
		reward_paths.append(bound)
	for path in reward_paths:
		var config := load(path) as BattleRewardConfig if ResourceLoader.exists(path) else null
		reward_binding.add_item((config.display_name + " / " + path.get_file()) if config != null else "缺失：" + path.get_file())
	reward_binding.select(reward_paths.find(bound) + 1 if not bound.is_empty() else 0)
	var content := CONFIG.battle_reward_content(node)
	reward_gold.value = content.gold
	reward_potion.value = content.potion_chance
	reward_relic.value = content.relic_chance

func _reward_binding_changed(index: int) -> void:
	if refreshing or doc.node().is_empty():
		return
	if index > 0 and index <= reward_paths.size():
		_load_reward_config(reward_paths[index - 1])
	elif index == 0:
		doc.begin()
		doc.node().erase("reward_config")
		doc.node().erase("battle_rewards")
		doc.commit()

func _load_reward_config(path: String) -> void:
	if doc.node().is_empty() or int(doc.node().type) not in [0, 3]:
		return
	var issue := CONFIG.battle_reward_error({"reward_config": path})
	if not issue.is_empty():
		status.text = issue
		return
	var config := load(path) as BattleRewardConfig
	doc.begin()
	doc.node().reward_config = path
	doc.node().battle_rewards = config.to_content()
	doc.commit()
	status.text = "已加载奖励配置，可在当前节点单独调整。"

func _reward_number(value: float, key: String) -> void:
	if refreshing or doc.node().is_empty() or int(doc.node().type) not in [0, 3]:
		return
	var content := CONFIG.battle_reward_content(doc.node())
	if is_equal_approx(float(content[key]), value):
		return
	content[key] = int(value) if key == "gold" else value
	doc.begin()
	doc.node().battle_rewards = content
	doc.commit()

func _inspect_rewards() -> void:
	if Engine.is_editor_hint() and not doc.node().is_empty():
		var path := str(doc.node().get("reward_config", CONFIG.DEFAULT_REWARDS))
		if ResourceLoader.exists(path):
			EditorInterface.edit_resource(load(path))

# 作用：提交事件描述；没有参数，没有返回值。
func _description_changed() -> void:
	if refreshing or not _has_inline_event() or doc.node().event.description == description_input.text:
		return
	doc.begin()
	doc.node().event.description = description_input.text.substr(0, 2000)
	doc.commit()

# 作用：修改选项文字；text 为文字，index 为选项序号，没有返回值。
func _choice_text(text: String, index: int) -> void:
	if refreshing or not _has_inline_event() or index < 0 or index >= doc.node().event.choices.size() or doc.node().event.choices[index].text == text:
		return
	doc.begin()
	doc.node().event.choices[index].text = text
	doc.commit()

# 作用：修改选项奖励；value 为数量，index 为选项，key 为 heal/gold，没有返回值。
func _choice_number(value: float, index: int, key: String) -> void:
	if refreshing or not _has_inline_event() or index < 0 or index >= doc.node().event.choices.size() or doc.node().event.choices[index].get(key, 0) == value:
		return
	doc.begin()
	doc.node().event.choices[index][key] = value if key == "heal_percent" else int(value)
	doc.commit()


func _choice_effect(value: int, index: int) -> void:
	if refreshing or not _has_inline_event() or index < 0 or index >= doc.node().event.choices.size() or value == 3:
		return
	doc.begin()
	var choice: Dictionary = doc.node().event.choices[index]
	choice.erase("effect")
	if value > 0:
		choice.effect = {"type": "train_unit" if value == 1 else "enhance_card"}
		choice.erase("leave")
	doc.commit()

# 作用：切换添加节点模式；kind 为类型，没有返回值。
func _add_mode(kind: int) -> void:
	_mode_changed(0)
	canvas.add_kind = kind
	status.text = "点击地图空白处添加 " + ["战斗", "事件", "篝火", "Boss", "宝箱", "商店", "精英", "随机事件"][kind]

# 作用：在画布所选位置创建节点；kind 为类型，floor 为层，x 为比例，没有返回值。
func _placed(kind: int, floor: int, x: float) -> void:
	doc.add_node(kind, floor, x)
	canvas.add_kind = -1
	status.text = "已添加：" + doc.selection

# 作用：处理节点点击、连线和试玩；id 为编号或空，没有返回值。
func _picked(id: String) -> void:
	if canvas.mode == 2:
		status.text = "已走过 %d 站：%s" % [canvas.journey.size(), " → ".join(canvas.journey)]
		if not id.is_empty() and doc.find(id).next.is_empty():
			status.text += " · 到达终点"
		return
	doc.selection = id
	canvas.selected_edge = []
	if canvas.mode == 1 and not id.is_empty():
		if canvas.source.is_empty():
			canvas.source = id
			status.text = "已选择源节点，请点击更高层目标。"
		elif doc.connect_nodes(canvas.source, id):
			canvas.source = ""
			status.text = "路线已连接。"
		else:
			status.text = doc.error
	_refresh()

# 作用：从列表定位节点；index 为行号，没有返回值。
func _list_picked(index: int) -> void:
	if index < doc.data.locations.size() and canvas.mode != 2:
		var id: String = doc.data.locations[index].id
		_picked(id)
		scroll.scroll_vertical = maxi(0, int(canvas.point(doc.find(id)).y - scroll.size.y * 0.5))

# 作用：选中画布中的路线；from/to 为编号，没有返回值。
func _edge_picked(from: String, to: String) -> void:
	doc.selection = ""
	canvas.selected_edge = [from, to]
	status.text = "选中路线：%s → %s；Delete 删除。" % [from, to]
	_refresh()

# 作用：移除一条出边；from/to 为编号，没有返回值。
func _remove_edge(from: String, to: String) -> void:
	doc.disconnect_nodes(from, to)
	canvas.selected_edge = []
	canvas.queue_redraw()

# 作用：删除选中节点或路线；没有参数，没有返回值。
func _delete() -> void:
	if canvas.mode == 2:
		return
	canvas.finish_drag()
	if canvas.selected_edge.size() == 2:
		_remove_edge(canvas.selected_edge[0], canvas.selected_edge[1])
	else:
		doc.delete_node()

# 作用：设置选择、连线、试玩模式；mode 为模式序号，没有返回值。
func _mode_changed(mode: int) -> void:
	canvas.finish_drag()
	canvas.mode = mode
	canvas.source = ""
	canvas.add_kind = -1
	canvas.selected_edge = []
	canvas.journey.clear()
	mode_input.select(mode)
	if mode == 2:
		status.text = "点击金色节点开始探索；试玩不会修改配置。"
	_refresh()

# 作用：重新从试玩起点出发；没有参数，没有返回值。
func _restart() -> void:
	canvas.journey.clear()
	canvas.queue_redraw()
	_scroll_to_start()

# 作用：滚动到地图底部；没有参数，没有返回值。
func _scroll_to_start() -> void:
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

# 作用：撤销并清除临时试玩状态；没有参数，没有返回值。
func _undo() -> void:
	canvas.finish_drag()
	canvas.source = ""
	canvas.journey.clear()
	doc.undo()

# 作用：重做并清除临时试玩状态；没有参数，没有返回值。
func _redo() -> void:
	canvas.finish_drag()
	canvas.source = ""
	canvas.journey.clear()
	doc.redo()

# 作用：新建前替换当前草稿；example 为是否用示例，没有返回值。
func _new_map(example: bool) -> void:
	doc.new_map(example)
	_mode_changed(0)
	_scroll_to_start.call_deferred()

# 作用：替换地图前保护修改；action 为待执行操作，没有返回值。
func _request(action: Callable) -> void:
	canvas.finish_drag()
	if doc.is_dirty():
		pending = action
		guard.popup_centered()
	else:
		action.call()

# 作用：放弃草稿后继续已请求操作；action 为对话框按钮编号，没有返回值。
func _discard(action: String) -> void:
	if action == "discard":
		guard.hide()
		_continue()

# 作用：完成保存或放弃后执行操作；没有参数，没有返回值。
func _continue() -> void:
	var action := pending
	pending = Callable()
	if action.is_valid():
		action.call()

# 作用：打开文件选择窗口；没有参数，没有返回值。
func _browse_open() -> void:
	open_dialog.popup_centered_ratio(0.65)

# 作用：选中文件后经过保存保护再打开；path 为路径，没有返回值。
func _opened(path: String) -> void:
	_request(_load_file.bind(path))

# 作用：读取已有路线；path 为路径，没有返回值。
func _load_file(path: String) -> void:
	if doc.open(path):
		_mode_changed(0)
		status.text = "已打开：" + path
		_scroll_to_start.call_deferred()
	else:
		status.text = doc.error

# 作用：打开项目路线菜单项；index 为行号，没有返回值。
func _choose_route(index: int) -> void:
	if index < route_paths.size():
		_request(_load_file.bind(route_paths[index]))

# 作用：显示另存为窗口；没有参数，没有返回值。
func _browse_save() -> void:
	save_dialog.current_file = "map_new.json"
	save_dialog.popup_centered_ratio(0.65)

# 作用：保存当前文件或询问新路径；没有参数，没有返回值。
func save_current() -> void:
	flush_input()
	canvas.finish_drag()
	if doc.path.is_empty():
		_browse_save()
	elif doc.save():
		_after_save()
	else:
		status.text = doc.error

# 作用：另存为后更新文件状态；path 为路径，没有返回值。
func _saved_as(path: String) -> void:
	flush_input()
	if doc.save(path):
		_after_save()
	else:
		status.text = doc.error

# 作用：保存完成后更新 Godot 文件系统和待执行操作；没有参数，没有返回值。
func _after_save() -> void:
	status.text = "已保存：" + doc.path + "；点击“应用到游戏”即可用于新征途。"
	_scan_catalog()
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if not filesystem.is_scanning():
			filesystem.scan()
	_continue()

# 作用：校验并更新项目正式路线，游戏开局直接读取；没有参数，没有返回值。
func _apply_to_game() -> void:
	flush_input()
	canvas.finish_drag()
	var text := JSON.stringify(doc.data, "\t", true, true)
	if text.to_utf8_buffer().size() > CONFIG.MAX_BYTES:
		status.text = "不能应用到游戏：路线文件不能超过 2 MB。"
		return
	var result := CONFIG.parse_text(text)
	if result.has("error"):
		status.text = "不能应用到游戏：" + str(result.error)
		return
	var act := apply_act_input.selected
	if not doc.write_json(game_map_paths[act], text):
		status.text = "应用到游戏失败：" + doc.error
		return
	if Engine.is_editor_hint():
		var filesystem := EditorInterface.get_resource_filesystem()
		if not filesystem.is_scanning():
			filesystem.scan()
	status.text = "已应用“%s”到第%d幕。新征途按三幕依次推进；继续存档沿用本局路线。后续修改需再次应用。" % [doc.data.name, act + 1]
	if game_map_paths == CONFIG.game_map_paths():
		var generation: Dictionary = load("res://scripts/map/route_generation_config.gd").read_file()
		if not generation.has("error") and generation.data.enabled:
			status.text += " 当前新局采用随机路线；使用此固定路线请将 route_rules.json 的 enabled 设为 false，或直接启动此路线实战。"

# 作用：编辑器退出保存时保存或保留恢复副本；没有参数，没有返回值。
func save_on_exit() -> void:
	flush_input()
	canvas.finish_drag()
	if doc.is_dirty() and (doc.path.is_empty() or not doc.save()):
		if not doc.write_recovery():
			push_error(doc.error)

# 作用：用当前路线快照启动真实新局；没有参数，没有返回值。
func _launch() -> void:
	flush_input()
	canvas.finish_drag()
	var issue := CONFIG.validate(doc.data)
	if not issue.is_empty():
		status.text = "不能启动实战：" + issue
		return
	if Engine.is_editor_hint() and EditorInterface.is_playing_scene():
		status.text = "请先停止正在运行的游戏。"
		return
	if not doc.write_json("user://map_editor_playtest.json", JSON.stringify(doc.data)):
		status.text = doc.error
		return
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://addons/map_editor/playtest.tscn")
	status.text = "正在启动当前路线的新局实战，使用独立快照。"

# 作用：保存或退出前提交仍有焦点的输入，防止漏掉未按回车的文字；没有参数，没有返回值。
func flush_input() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus == name_input:
		_map_name(name_input.text)
	elif focus == id_input:
		_rename_id(id_input.text)
	elif focus == title_input:
		_set_text(title_input.text, "title")
	elif focus == description_input:
		_description_changed()
	else:
		for i in texts.size():
			if focus == texts[i]:
				_choice_text(texts[i].text, i)
		for spin in [floors_input, floor_input, reward_gold, reward_potion, reward_relic] + heals + golds + heal_percents:
			if focus == spin.get_line_edit() and spin.get_line_edit().text.is_valid_float():
				spin.value = spin.get_line_edit().text.to_float()

# 作用：面板显示时响应编辑快捷键；event 为键盘输入，没有返回值。
func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed or event.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	if event.ctrl_pressed or event.meta_pressed:
		if event.keycode == KEY_Z:
			if event.shift_pressed:
				_redo()
			else:
				_undo()
		elif event.keycode == KEY_S:
			save_current()
		else:
			return
	elif event.keycode == KEY_DELETE:
		_delete()
	elif event.keycode == KEY_ESCAPE:
		_mode_changed(0)
	else:
		return
	get_viewport().set_input_as_handled()

# 绑定工坊配方；切回节点内编辑时保留快照，奖励字段不会丢失。
func _event_binding_changed(index: int) -> void:
	if refreshing or doc.node().is_empty() or int(doc.node().type) not in [1, 2] or index < 0 or index > event_ids.size() + 1:
		return
	if index == event_ids.size() + 1:
		if int(doc.node().type) != 1:
			return
		doc.begin()
		doc.node().event_pool = "res://data/events/pools/act1.json"
		doc.node().event_source = "catalog"
		doc.node().event_id = ""
		doc.node().event = load("res://scripts/events/event_pool.gd").fallback()
		doc.node().title = "旅途奇遇"
		doc.commit()
		return
	if index == 0:
		if doc.node().get("event_source", "inline") != "catalog":
			return
		doc.begin()
		# 解绑前读取最新保存内容；资源缺失时仍保留节点原有快照。
		var content: Dictionary = EVENT_REWARDS.content(str(doc.node().get("event_id", "")))
		if not content.is_empty():
			doc.node().event = content
		doc.node().erase("event_source")
		doc.node().erase("event_pool")
	else:
		var id := event_ids[index - 1]
		var content: Dictionary = EVENT_REWARDS.content(id)
		var issue := CONFIG.event_error(content)
		if not issue.is_empty():
			status.text = "无法绑定事件 %s：%s" % [id, issue]
			_refresh()
			return
		if doc.node().get("event_source", "inline") == "catalog" and doc.node().get("event_id", "") == id and doc.node().event == content:
			return
		doc.begin()
		doc.node().erase("event_pool")
		doc.node().event_source = "catalog"
		doc.node().event_id = id
		doc.node().event = content
		doc.node().title = content.title
	doc.commit()

func _has_inline_event() -> bool:
	var node: Dictionary = doc.node()
	return not node.is_empty() and int(node.type) in [1, 2] and node.has("event") and node.get("event_source", "inline") != "catalog"

func _inspect_event() -> void:
	if not Engine.is_editor_hint() or doc.node().is_empty() or doc.node().get("event_source", "inline") != "catalog":
		return
	var index := event_ids.find(str(doc.node().get("event_id", "")))
	if index >= 0 and ResourceLoader.exists(event_paths[index]):
		EditorInterface.edit_resource(ResourceLoader.load(event_paths[index], "", ResourceLoader.CACHE_MODE_REPLACE))


func _generate_random_route() -> void:
	var generation: Dictionary = load("res://scripts/map/route_generation_config.gd").read_file()
	if generation.has("error"):
		status.text = str(generation.error)
		return
	var seed_text := route_seed_input.text.strip_edges().to_upper()
	if seed_text.is_empty():
		var source_rng := RandomNumberGenerator.new()
		source_rng.randomize()
		seed_text = "%08X%08X" % [source_rng.randi(), source_rng.randi()]
	var difficulty := route_difficulty_input.get_item_text(route_difficulty_input.selected) if route_difficulty_input.item_count > 0 else str(generation.data.difficulty)
	if not generation.data.difficulties.has(difficulty):
		status.text = "难度档已修改，请重新打开地图工坊。"
		return
	var generated: Dictionary = load("res://scripts/map/procedural_map_generator.gd").new().generate(seed_text, apply_act_input.selected + 1, generation.data, difficulty, generation.encounters)
	var issue := CONFIG.validate(generated)
	if not issue.is_empty():
		status.text = issue
		return
	doc.new_map()
	doc.data = generated
	doc.normalize()
	doc.changed.emit()
	route_seed_input.text = seed_text
	status.text = "已生成第%d幕 · 种子 %s · %s" % [apply_act_input.selected + 1, seed_text, difficulty]
