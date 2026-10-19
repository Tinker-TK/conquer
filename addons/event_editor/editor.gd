# 原生事件工坊：模板、奖励池、资源列表、保存保护与实际事件界面预览。
@tool
extends HSplitContainer
const REWARDS = preload("res://scripts/events/event_rewards.gd")
const PROPERTY_HELP = preload("res://addons/shared/script_property_help.gd")
var parameter_help: Dictionary = PROPERTY_HELP.descriptions(preload("res://data/events/event_definition.gd"))
var doc = preload("res://addons/event_editor/document.gd").new()
var event_list: ItemList
var paths: Array[String] = []
var inputs: Dictionary = {}
var template_input: OptionButton
var pools: Dictionary = {}
var status: Label
var file_label: Label
var preview: EventPanel
var save_dialog: FileDialog
var open_dialog: FileDialog
var discard_dialog: ConfirmationDialog
var pending_action: Callable
var refreshing := false
var rest_percent_input: SpinBox

func _ready() -> void:
	# 主屏幕父节点是容器，单设锚点不会分配剩余高度；表单与预览通过分隔条调整宽度。
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	add_theme_constant_override("autohide", 0)
	var library := VBoxContainer.new()
	library.name = "EventLibrary"
	library.custom_minimum_size.x = 280
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.size_flags_stretch_ratio = 0.2
	library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	library.add_theme_constant_override("separation", 8)
	add_child(library)
	_label(library, "事件工坊", 24)
	_button(library, "新建随机遗物事件", _guard.bind(_new.bind(0)))
	_button(library, "新建随机药水事件", _guard.bind(_new.bind(1)))
	_button(library, "新建两组选牌事件", _guard.bind(_new.bind(2)))
	_button(library, "新建篝火事件", _guard.bind(_new.bind(3)))
	_button(library, "新建路线抉择事件", _guard.bind(_new.bind(4)))
	_button(library, "打开事件资源…", _guard.bind(_open_dialog))
	_button(library, "刷新资源列表", _scan)
	_button(library, "恢复上次草稿", _guard.bind(_recover))
	_label(library, "已配置事件", 17)
	event_list = ItemList.new()
	event_list.custom_minimum_size.y = 140
	event_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_list.max_text_lines = 2
	library.add_child(event_list)
	event_list.item_selected.connect(func(index): _guard(_load.bind(paths[index])))
	var workspace := HSplitContainer.new()
	workspace.name = "Workspace"
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.size_flags_stretch_ratio = 0.8
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 12)
	workspace.add_theme_constant_override("autohide", 0)
	add_child(workspace)
	var form_scroll := ScrollContainer.new()
	form_scroll.name = "EventForm"
	form_scroll.custom_minimum_size.x = 460
	form_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form_scroll.size_flags_stretch_ratio = 1.5
	form_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(form_scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 8)
	form_scroll.add_child(form)
	file_label = _label(form, "", 14)
	file_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var toolbar := HBoxContainer.new()
	form.add_child(toolbar)
	_button(toolbar, "保存", save_current)
	_button(toolbar, "另存为", _save_as)
	_button(toolbar, "撤销", _undo)
	_button(toolbar, "重做", _redo)
	_line(form, "id", "事件编号 / 保存文件名")
	_line(form, "title", "事件标题")
	_label(form, "事件模板", 16).tooltip_text = parameter_help.template
	template_input = OptionButton.new()
	template_input.tooltip_text = parameter_help.template
	for text in ["获得随机遗物", "获得随机药水", "兵种五选一 + 效果五选一", "篝火 · 休憩 / 训练 / 强化", "路线抉择 · 自定义成本与复合效果"]:
		template_input.add_item(text)
	form.add_child(template_input)
	template_input.item_selected.connect(func(_index): apply_inputs())
	_label(form, "休憩整备 · 最大生命回复百分比（仅篝火）", 16).tooltip_text = parameter_help.rest_heal_percent
	rest_percent_input = SpinBox.new()
	rest_percent_input.tooltip_text = parameter_help.rest_heal_percent
	rest_percent_input.min_value = 0
	rest_percent_input.max_value = 100
	rest_percent_input.step = 0.1
	rest_percent_input.suffix = "%"
	form.add_child(rest_percent_input)
	rest_percent_input.value_changed.connect(func(_value): apply_inputs())
	_text(form, "description", "事件描述（最多 2000 字）", 150)
	_line(form, "illustration", "插图资源路径（res://…）")
	_line(form, "option_text", "奖励选项文字")
	_line(form, "leave_text", "离开选项文字")
	_text(form, "result_text", "领取奖励后的叙事", 90)
	_text(form, "route_config", "路线抉择配置（JSON：楼层、标签、条件与 choices）", 380)
	inputs.route_config.tooltip_text = "cost: gold / hp / max_hp；effects 支持复合结算；复制保留强化，取消不支付。保存与试玩前统一校验。"
	_label(form, "奖励池 · 勾选候选资源，全部不勾选时使用全目录", 15)
	for kind in ["relic", "potion", "unit", "effect"]:
		var box := VBoxContainer.new()
		form.add_child(box)
		var heading := _label(box, {"relic": "遗物池", "potion": "药水池", "unit": "兵种卡池 · 至少 5 种", "effect": "效果卡池 · 至少 5 种"}[kind], 17)
		heading.modulate = Color("#c9b47a")
		heading.tooltip_text = parameter_help.get(kind + "_pool", "")
		var checks: Array[CheckBox] = []
		for resource in REWARDS.pool([], kind):
			var check := CheckBox.new()
			check.text = resource.display_name if kind in ["relic", "potion"] else resource.card_name
			check.tooltip_text = resource.resource_path
			check.set_meta("path", resource.resource_path)
			check.toggled.connect(func(_value): apply_inputs())
			box.add_child(check)
			checks.append(check)
		pools[kind] = {"box": box, "checks": checks}
	var right := VBoxContainer.new()
	right.name = "EventPreview"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	workspace.add_child(right)
	_label(right, "事件界面预览", 22)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	right.add_child(viewport)
	preview = preload("res://scripts/map/event_panel.gd").new()
	preview.size = Vector2(1920, 1080)
	viewport.add_child(preview)
	var texture := TextureRect.new()
	texture.name = "EventImage"
	texture.custom_minimum_size = Vector2(320, 180)
	texture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture = viewport.get_texture()
	right.add_child(texture)
	var preview_hint := _label(right, "左侧插图 / 右侧叙事与选择 · 试玩使用真实卡面，不影响正式本局", 16)
	preview_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(right, "试玩当前事件", playtest).tooltip_text = "试玩使用当前事件草稿，不会影响正式本局。"
	status = _label(right, "", 17)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_dialog = FileDialog.new()
	save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	save_dialog.access = FileDialog.ACCESS_RESOURCES
	save_dialog.filters = PackedStringArray(["*.tres ; 事件资源"])
	save_dialog.current_dir = "res://data/events"
	save_dialog.file_selected.connect(_save_target)
	add_child(save_dialog)
	open_dialog = FileDialog.new()
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_RESOURCES
	open_dialog.filters = PackedStringArray(["*.tres ; 事件资源"])
	open_dialog.current_dir = "res://data/events"
	open_dialog.file_selected.connect(_load)
	add_child(open_dialog)
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.dialog_text = "当前修改尚未保存。草稿会保留，继续切换事件？"
	discard_dialog.confirmed.connect(_discard_confirmed)
	add_child(discard_dialog)
	doc.changed.connect(_refresh)
	_scan()
	if not paths.is_empty():
		_load(paths[0])

func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _line(parent: Node, key: String, label: String) -> void:
	_label(parent, label, 16).tooltip_text = parameter_help.get(key, "")
	var input := LineEdit.new()
	input.tooltip_text = parameter_help.get(key, "")
	input.max_length = 250 if key == "illustration" else 80
	parent.add_child(input)
	inputs[key] = input
	input.text_submitted.connect(func(_text): apply_inputs())
	input.focus_exited.connect(apply_inputs)

func _text(parent: Node, key: String, label: String, height: int) -> void:
	_label(parent, label, 16).tooltip_text = parameter_help.get(key, "")
	var input := TextEdit.new()
	input.tooltip_text = parameter_help.get(key, "")
	input.custom_minimum_size.y = height
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(input)
	inputs[key] = input
	input.focus_exited.connect(apply_inputs)

func _scan() -> void:
	paths.clear()
	event_list.clear()
	for event in REWARDS.catalog():
		paths.append(event.resource_path)
		event_list.add_item(event.title)
		event_list.set_item_tooltip(event_list.item_count - 1, event.id + "\n" + event.resource_path)

func _refresh() -> void:
	if doc.event == null:
		return
	refreshing = true
	for key in inputs:
		if key == "route_config":
			inputs[key].text = JSON.stringify({"min_floor": doc.event.min_floor, "max_floor": doc.event.max_floor, "rarity": doc.event.rarity, "tags": doc.event.tags, "requires": doc.event.requires, "choices": doc.event.choices}, "  ")
			inputs[key].visible = doc.event.template == EventDefinition.Template.CUSTOM
		else:
			inputs[key].text = doc.event.illustration.resource_path if key == "illustration" and doc.event.illustration != null else "" if key == "illustration" else doc.event.get(key)
	template_input.select(doc.event.template)
	rest_percent_input.set_value_no_signal(doc.event.rest_heal_percent)
	rest_percent_input.editable = doc.event.template == EventDefinition.Template.CAMPFIRE
	for kind in pools:
		var resource_pool: Array = doc.event.get(kind + "_pool")
		for resource in REWARDS.pool([], kind) + resource_pool:
			_ensure_pool_resource(kind, resource)
		var chosen: Array[String] = []
		for resource in resource_pool:
			chosen.append(resource.resource_path if resource != null else "")
		pools[kind].box.visible = (kind == "relic" and doc.event.template == 0) or (kind == "potion" and doc.event.template == 1) or (kind in ["unit", "effect"] and doc.event.template == 2)
		for check in pools[kind].checks:
			check.set_pressed_no_signal(chosen.has(check.get_meta("path")))
	file_label.text = ("* " if doc.is_dirty() else "") + (doc.path if not doc.path.is_empty() else "未保存事件")
	var issue: String = doc.event.validate()
	status.text = "✓ 配置检查通过 · 保存后可在地图工坊绑定" if issue.is_empty() else issue
	preview.open_content(doc.event.to_content(), null, true)
	refreshing = false

func apply_inputs() -> bool:
	if refreshing or doc.event == null:
		return false
	var image_path: String = inputs.illustration.text.strip_edges()
	if not image_path.is_empty() and (not image_path.begins_with("res://") or not ResourceLoader.exists(image_path) or not load(image_path) is Texture2D):
		status.text = "插图路径无效，请指定项目中的图片。"
		return false
	var updated: EventDefinition = doc.event.duplicate(false)
	for key in inputs:
		if key not in ["illustration", "route_config"]:
			updated.set(key, inputs[key].text.substr(0, 2000))
	updated.illustration = load(image_path) if not image_path.is_empty() else null
	updated.template = template_input.selected
	if updated.template == EventDefinition.Template.CUSTOM:
		var parser := JSON.new()
		if parser.parse(inputs.route_config.text) != OK or not parser.data is Dictionary:
			status.text = "路线配置 JSON 有误，请检查括号、逗号与字段。"
			return false
		var config: Dictionary = parser.data
		if not config.get("choices") is Array or not config.get("tags", []) is Array or not config.get("requires", []) is Array:
			status.text = "choices、tags、requires 必须是数组。"
			return false
		for item in config.choices:
			if not item is Dictionary:
				status.text = "每个选项都必须是 JSON 对象。"
				return false
		for item in config.get("tags", []) + config.get("requires", []):
			if not item is String:
				status.text = "标签与条件必须是字符串。"
				return false
		updated.choices = []
		updated.choices.assign(config.choices)
		updated.tags = []
		updated.tags.assign(config.get("tags", []))
		updated.requires = []
		updated.requires.assign(config.get("requires", []))
		updated.min_floor = int(config.get("min_floor", 2))
		updated.max_floor = int(config.get("max_floor", 9))
		updated.rarity = str(config.get("rarity", "common"))
		var issue := updated.validate()
		if not issue.is_empty():
			status.text = issue
			return false
	updated.rest_heal_percent = rest_percent_input.value
	for kind in pools:
		var chosen: Array[Resource] = []
		for check in pools[kind].checks:
			if check.button_pressed:
				chosen.append(load(check.get_meta("path")))
		updated.set(kind + "_pool", chosen)
	if updated.id == doc.event.id and updated.to_content() == doc.event.to_content():
		return true
	doc.begin()
	doc.event = updated
	doc.commit()
	return true

func _guard(action: Callable) -> void:
	if not apply_inputs():
		return
	if doc.is_dirty():
		pending_action = action
		discard_dialog.popup_centered()
	else:
		action.call()

func _new(template: int) -> void:
	doc.new_event(template)

func _load(path: String) -> void:
	if not doc.open(path):
		status.text = doc.error

func _open_dialog() -> void:
	open_dialog.popup_centered_ratio(0.7)

func _recover() -> void:
	if not doc.recover():
		status.text = doc.error

func _undo() -> void:
	apply_inputs()
	doc.undo()

func _redo() -> void:
	doc.redo()

func save_current() -> void:
	if not apply_inputs():
		return
	if doc.path.is_empty() or doc.path == doc.RECOVERY:
		_save_as()
	else:
		_save_target(doc.path)

func _save_as() -> void:
	if not apply_inputs():
		return
	if doc.event != null:
		save_dialog.current_file = doc.event.id + ".tres"
		save_dialog.popup_centered_ratio(0.7)

func _save_target(path: String) -> void:
	if doc.save(path):
		_scan()
		if Engine.is_editor_hint():
			EditorInterface.get_resource_filesystem().scan()
	else:
		status.text = doc.error

func playtest() -> void:
	if not apply_inputs():
		return
	var issue: String = doc.event.validate()
	if not issue.is_empty():
		status.text = issue
		return
	var error := ResourceSaver.save(doc.event, "user://event_editor_preview.tres")
	if error != OK:
		status.text = "试玩快照保存失败：" + error_string(error)
		return
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://addons/event_editor/playtest.tscn")

func _discard_confirmed() -> void:
	if not doc.recover_save():
		status.text = "草稿保存失败，当前事件已保留，请先保存。"
		return
	pending_action.call()

# 额外路径的候选也显式显示，编辑其他字段时不会静默丢失自定义池。
func _ensure_pool_resource(kind: String, resource: Resource) -> void:
	if resource == null or resource.resource_path.is_empty():
		return
	for check in pools[kind].checks:
		if check.get_meta("path") == resource.resource_path:
			return
	var check := CheckBox.new()
	check.text = resource.resource_path.get_file()
	check.tooltip_text = resource.resource_path
	check.set_meta("path", resource.resource_path)
	check.toggled.connect(func(_value): apply_inputs())
	pools[kind].box.add_child(check)
	pools[kind].checks.append(check)
