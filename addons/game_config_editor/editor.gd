# 这玩意儿是干嘛的（核心逻辑）：在 Godot 内提供像波次编辑器一样的游戏配置主屏幕。
# 数据是咋流动的（数据流向）：分类和表格输入 → 文档草稿 → 后台校验保存 → 更新编辑器资源目录。
# 为啥这么写（选型决策）：使用原生控件，保留 HTML 数据交换，同时复用已有的资源保存保护。
# 性能咋样（复杂度）：仅显示当前分类的行，编辑时更新标记；读写在后台线程运行，空闲不轮询。
@tool
extends VBoxContainer

const DOC = preload("res://addons/game_config_editor/document.gd")
const BRIDGE = preload("res://addons/game_config_editor/bridge.gd")
const LABELS = preload("res://addons/game_config_editor/labels.gd")
var doc = DOC.new()
var bridge = BRIDGE.new()
var auto_load := true
var category := "cards"
var selected_id := ""
var operation := ""
var first_read := true
var rebuilding := false
var table_pending := false
var categories: ItemList
var search: LineEdit
var grid: GridContainer
var scroll: ScrollContainer
var status: Label
var heading: Label
var details: Label
var references: HBoxContainer
var toolbar: Array[Button] = []
var document_buttons: Array[Button] = []
var save_button: Button
var undo_button: Button
var redo_button: Button
var cells: Dictionary = {}
var name_buttons: Dictionary = {}
var visible_rows: Array[Dictionary] = []
var column_keys: Array[String] = []
var row_dialog: ConfirmationDialog
var row_templates: OptionButton
var row_slug: LineEdit
var row_display: LineEdit
var column_dialog: ConfirmationDialog
var column_name: LineEdit
var column_label: LineEdit
var column_type: OptionButton
var column_default: LineEdit
var column_note: LineEdit
var import_dialog: FileDialog
var export_dialog: FileDialog
var python_dialog: FileDialog
var guard: ConfirmationDialog
var recovery: ConfirmationDialog
var message: AcceptDialog
var pending_action := Callable()

# 作用：面板进入编辑器时建立布局并读取配置；没有参数，没有返回值。
func _ready() -> void:
	set_process(false)
	bridge.python = bridge.default_python()
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if settings.has_setting("game_config_editor/python_executable"):
			bridge.python = settings.get_setting("game_config_editor/python_executable")
	var bar := HBoxContainer.new()
	add_child(bar)
	save_button = _button(bar, "保存并应用", _save)
	document_buttons.append(_button(bar, "校验", _check))
	_button(bar, "重读", _request.bind(_reload))
	_button(bar, "导入合集…", _request.bind(_import))
	document_buttons.append(_button(bar, "导出 HTML / JSON…", _export))
	undo_button = _button(bar, "撤销", _undo)
	redo_button = _button(bar, "重做", _redo)
	_button(bar, "使用说明", _help)
	_button(bar, "工具设置…", _python_settings)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 200
	split.add_child(left)
	var caption := Label.new()
	caption.text = "游戏配置分类"
	left.add_child(caption)
	categories = ItemList.new()
	categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	categories.item_selected.connect(_category_selected)
	left.add_child(categories)
	var hint := Label.new()
	hint.text = "黄色字：未保存\n每行一项配置\n横向滚动查看更多字段"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var actions := HBoxContainer.new()
	right.add_child(actions)
	heading = Label.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(heading)
	search = LineEdit.new()
	search.placeholder_text = "搜索名称、效果或路径"
	search.custom_minimum_size.x = 220
	search.text_changed.connect(_search_changed)
	actions.add_child(search)
	document_buttons.append(_button(actions, "+ 新增配置行", _new_row))
	document_buttons.append(_button(actions, "+ 新增字段列", _new_column))
	document_buttons.append(_button(actions, "修改清单", _diff))
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 3)
	scroll.add_child(grid)
	details = Label.new()
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(details)
	references = HBoxContainer.new()
	right.add_child(references)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	_build_dialogs()
	doc.changed.connect(_document_changed)
	_render_categories()
	_counts()
	status.text = "配置尚未载入，打开游戏配置页签后自动读取；也可点击“重读”或导入合集。"
	visibility_changed.connect(_ensure_loaded)
	_ensure_loaded.call_deferred()

# 作用：首次显示或初次读取失败后重新显示时读取配置，等待编辑器完成资源扫描。
func _ensure_loaded() -> void:
	if not auto_load or not is_node_ready() or not is_visible_in_tree() or _has_document() or bridge.is_busy():
		return
	if Engine.is_editor_hint():
		var files := EditorInterface.get_resource_filesystem()
		if files.is_scanning():
			status.text = "正在等待编辑器完成资源扫描…"
			if not files.filesystem_changed.is_connected(_ensure_loaded):
				files.filesystem_changed.connect(_ensure_loaded, CONNECT_DEFERRED | CONNECT_ONE_SHOT)
			return
	_reload()

# 作用：区分尚未读取的空字典和已经通过格式检查的配置文档。
func _has_document() -> bool:
	return doc.data.get("format") == DOC.FORMAT and doc.data.get("records") is Array

# 作用：阻止快捷键或直接调用把尚未载入的空字典送入校验、保存或导出。
func _require_document() -> bool:
	if _has_document():
		return true
	_show_error("配置尚未载入，请点击“重读”读取实际游戏配置，或导入已有合集。")
	return false

# 作用：创建统一风格按钮；parent 为容器，text 为名称，action 为操作，返回按钮。
func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	toolbar.append(button)
	return button

# 作用：建立新行、新列、导入导出和草稿保护对话框；没有参数，没有返回值。
func _build_dialogs() -> void:
	message = AcceptDialog.new()
	message.title = "游戏配置"
	add_child(message)
	row_dialog = ConfirmationDialog.new()
	row_dialog.title = "新增配置行"
	row_dialog.ok_button_text = "创建行"
	var row_form := VBoxContainer.new()
	row_dialog.add_child(row_form)
	var hint := Label.new()
	hint.text = "复制现有模板创建独立资源。单位还会创建同名场景。\n新资源需要被卡组或关卡引用；效果明细会加入模板所在卡牌。"
	row_form.add_child(hint)
	row_templates = OptionButton.new()
	row_templates.tooltip_text = "选择新配置行复制的已有资源模板；单位还会复制相应场景，效果明细会追加到模板所属卡牌。"
	row_form.add_child(row_templates)
	row_slug = _line(row_form, "英文标识（例如 elite_knight）")
	row_display = _line(row_form, "显示名称（可选）")
	row_dialog.confirmed.connect(_confirm_row)
	add_child(row_dialog)
	column_dialog = ConfirmationDialog.new()
	column_dialog.title = "新增字段列"
	column_dialog.ok_button_text = "创建列"
	var column_form := VBoxContainer.new()
	column_dialog.add_child(column_form)
	var column_hint := Label.new()
	column_hint.text = "为同类资源增加导出字段；己方与敌方共用单位字段。\n字段负责保存数据；新增玩法需有脚本读取这个字段。"
	column_form.add_child(column_hint)
	column_name = _line(column_form, "英文配置名（例如 critical_rate）")
	column_label = _line(column_form, "中文列名")
	column_type = OptionButton.new()
	column_type.tooltip_text = "新导出字段的数据类型，决定检查器与表格如何输入和校验；整数不允许小数，开关只保存开启或关闭。"
	for text in ["整数", "小数", "文本", "开关"]:
		column_type.add_item(text)
	column_type.item_selected.connect(_column_type_changed)
	column_form.add_child(column_type)
	column_default = _line(column_form, "默认值")
	column_note = _line(column_form, "字段说明（可选）")
	column_dialog.confirmed.connect(_confirm_column)
	add_child(column_dialog)
	import_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _import_selected)
	export_dialog = _file_dialog(FileDialog.FILE_MODE_SAVE_FILE, _export_selected)
	python_dialog = _file_dialog(FileDialog.FILE_MODE_OPEN_FILE, _python_selected)
	python_dialog.filters = PackedStringArray(["*.exe ; Python 可执行文件"])
	guard = ConfirmationDialog.new()
	guard.title = "配置有未保存修改"
	guard.dialog_text = "先保存当前配置，再继续操作？"
	guard.ok_button_text = "保存并继续"
	guard.add_button("放弃修改", false, "discard")
	guard.confirmed.connect(_save)
	guard.custom_action.connect(_guard_discard)
	guard.canceled.connect(_cancel_pending)
	add_child(guard)
	recovery = ConfirmationDialog.new()
	recovery.title = "发现游戏配置草稿"
	recovery.dialog_text = "是否恢复上次未保存的编辑内容？原始配置仍会在保存时检查冲突。"
	recovery.ok_button_text = "恢复草稿"
	recovery.cancel_button_text = "放弃恢复"
	recovery.confirmed.connect(_recover)
	recovery.canceled.connect(doc.discard_recovery)
	add_child(recovery)

# 作用：创建表单输入框；parent 为容器，placeholder 为提示，返回输入框。
func _line(parent: Node, placeholder: String) -> LineEdit:
	var input := LineEdit.new()
	input.placeholder_text = placeholder
	input.tooltip_text = {
		"英文标识（例如 elite_knight）": "新资源的英文标识，作为文件名；使用小写字母、数字和下划线，单位会同时生成同名场景。",
		"显示名称（可选）": "新配置行在游戏界面中显示的名称，留空沿用模板名称；不会改变英文文件标识。",
		"英文配置名（例如 critical_rate）": "新字段在脚本和资源中的变量名；使用合法 snake_case 标识，不能与现有字段重名。",
		"中文列名": "此字段在配置表中显示的中文标题，不改变脚本保存的英文变量名。",
		"默认值": "新字段的脚本默认值，同时初始化同类资源的此字段；填写的值必须与所选数据类型一致。",
		"字段说明（可选）": "解释新字段的用途、单位和生效条件，保存后用于检查器与配置表的悬停提示。新增字段需由玩法脚本读取才会影响游戏。"
	}.get(placeholder, "")
	input.custom_minimum_size.x = 560
	parent.add_child(input)
	return input

# 作用：创建合集文件选择器；mode 为打开或保存，action 为路径回调，返回选择器。
func _file_dialog(mode: FileDialog.FileMode, action: Callable) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = mode
	dialog.filters = PackedStringArray(["*.html ; HTML 配置合集", "*.json ; JSON 配置数据"])
	dialog.current_dir = ProjectSettings.globalize_path("res://docs")
	dialog.file_selected.connect(action)
	add_child(dialog)
	return dialog

# 作用：刷新左侧分类数量；没有参数，没有返回值。
func _render_categories() -> void:
	categories.clear()
	for key: String in LABELS.TITLES:
		var count := 0
		for row: Dictionary in doc.data.get("records", []):
			if doc.matches(row, key):
				count += 1
		categories.add_item("%s  (%d)" % [LABELS.TITLES[key], count])
		categories.set_item_metadata(categories.item_count - 1, key)
		if key == category:
			categories.select(categories.item_count - 1)

# 作用：切换分类；index 为分类序号，没有返回值。
func _category_selected(index: int) -> void:
	if not flush_input():
		_render_categories()
		return
	category = categories.get_item_metadata(index)
	search.text = ""
	_render_table()

# 作用：搜索条件变化时过滤当前分类；text 为搜索词，没有返回值。
func _search_changed(_text: String) -> void:
	for input: Control in cells.values():
		if input.get_meta("invalid", false):
			status.text = "请先修正红色输入框，再切换搜索结果。"
			return
	_render_table()

# 作用：创建当前分类的完整表格；没有参数，没有返回值。
func _render_table() -> void:
	if rebuilding:
		return
	rebuilding = true
	table_pending = false
	cells.clear()
	name_buttons.clear()
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	visible_rows.clear()
	column_keys.assign(LABELS.KEYS[category])
	var query := search.text.strip_edges().to_lower()
	for row: Dictionary in doc.data.get("records", []):
		if not doc.matches(row, category):
			continue
		for item: Dictionary in row.fields:
			if not column_keys.has(str(item.name)):
				column_keys.append(str(item.name))
		var unit_names := str(doc.value(row, "unit_name")) if category == "skills" else ""
		if query.is_empty() or (doc.title(row) + " " + unit_names + " " + str(row.id) + " " + JSON.stringify(row.fields)).to_lower().contains(query):
			visible_rows.append(row)
	grid.columns = column_keys.size() + 1
	_header("配置项 / 路径", "每行对应一个 Godot 资源", 260)
	for key in column_keys:
		var sample: Dictionary = {}
		for row in visible_rows:
			sample = doc.field(row, key)
			if not sample.is_empty():
				break
		_header(_field_label(sample, key), key, _width(key), str(sample.get("description", "")))
	for row in visible_rows:
		var box := VBoxContainer.new()
		box.custom_minimum_size.x = 260
		grid.add_child(box)
		var name := Button.new()
		name.text = doc.title(row) + (" · 待创建" if doc.is_new(row.id) else "")
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name.pressed.connect(_select_record.bind(str(row.id)))
		box.add_child(name)
		name_buttons[str(row.id)] = name
		var path := Label.new()
		path.text = str(row.id).replace("res://data/", "")
		path.tooltip_text = row.id
		path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(path)
		for key in column_keys:
			_cell(row, key)
	rebuilding = false
	_counts()
	_select_record(selected_id)

# 作用：创建一列表头；text 为中文名称，note 为英文名，width 为宽度，description 为参数说明。
func _header(text: String, note: String, width: int, description: String = "") -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = width
	grid.add_child(box)
	var title := Label.new()
	title.text = text
	title.tooltip_text = note + ("\n" + description if not description.is_empty() else "")
	box.add_child(title)
	var code := Label.new()
	code.text = note
	code.tooltip_text = title.tooltip_text
	code.add_theme_color_override("font_color", Color(0.6, 0.7, 0.75))
	code.add_theme_font_size_override("font_size", 11)
	box.add_child(code)
	var kind := "units" if category in ["allies", "enemies"] else category
	for column: Dictionary in doc.data.get("pending_columns", []):
		if column.family == kind and column.name == note:
			var remove := Button.new()
			remove.text = "移除新列"
			remove.pressed.connect(_remove_column.bind(kind, note))
			box.add_child(remove)

# 作用：决定字段宽度；key 为英文名，返回表格宽度。
func _width(key: String) -> int:
	if category == "skills" and key == "unit_name":
		return 260
	return 260 if key.contains("description") or key.contains("discription") or key in ["skills", "effects", "on_hit_effect", "dodge_skill"] else 165

# 作用：获取中文字段名；item 为字段，key 为英文名，返回可读名称。
func _field_label(item: Dictionary, key: String) -> String:
	return str(item.get("label", LABELS.FIELDS.get(key, key)))

# 作用：创建一个格子的原生输入控件；row 为配置行，key 为字段名，没有返回值。
func _cell(row: Dictionary, key: String) -> void:
	var item: Dictionary = doc.field(row, key)
	var control: Control
	if item.is_empty() or not item.get("editable", false):
		var text := Label.new()
		text.text = "—" if item.is_empty() else _display(item.value)
		text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		control = text
	elif int(item.type) == TYPE_INT and int(item.hint) == PROPERTY_HINT_ENUM:
		var option := OptionButton.new()
		for choice: Array in _options(row, item):
			option.add_item(str(choice[1]), int(choice[0]))
		option.select(option.get_item_index(int(item.value)))
		option.item_selected.connect(_enum_changed.bind(option, str(row.id), key))
		control = option
	elif int(item.type) == TYPE_BOOL:
		var toggle := CheckBox.new()
		toggle.button_pressed = bool(item.value)
		toggle.text = "启用"
		toggle.toggled.connect(_bool_changed.bind(str(row.id), key))
		control = toggle
	elif key.contains("description") or key.contains("discription"):
		var text := TextEdit.new()
		text.text = str(item.value)
		text.custom_minimum_size.y = 65
		text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		text.focus_exited.connect(_input_changed.bind(text, str(row.id), key))
		control = text
	else:
		var input := LineEdit.new()
		if int(item.type) == TYPE_INT:
			input.text = str(int(item.value))
		else:
			input.text = JSON.stringify(item.value) if int(item.type) in [TYPE_ARRAY, TYPE_VECTOR2] else str(item.value)
		input.text_submitted.connect(_text_submitted.bind(input, str(row.id), key))
		input.focus_exited.connect(_input_changed.bind(input, str(row.id), key))
		control = input
	control.custom_minimum_size.x = _width(key)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.tooltip_text = key + "\n" + _display(item.get("value")) + "\n" + str(item.get("description", ""))
	control.set_meta("resource_id", row.id)
	control.set_meta("field", key)
	var input_key := str(row.id) + "|" + key
	if doc.data.get("editor_inputs", {}).has(input_key) and (control is LineEdit or control is TextEdit):
		control.set("text", doc.data.editor_inputs[input_key])
		control.set_meta("invalid", true)
	control.gui_input.connect(_cell_input.bind(str(row.id), key))
	grid.add_child(control)
	cells[str(row.id) + "|" + key] = control
	_mark(control, item)

# 作用：解释枚举选项；row 为资源，item 为字段，返回数值与中文名列表。
func _options(row: Dictionary, item: Dictionary) -> Array:
	var choices: Array = []
	var number := -1
	for entry: String in str(item.get("hint_string", "")).split(",", false):
		var parts := entry.rsplit(":", true, 1)
		number = int(parts[1]) if parts.size() > 1 else number + 1
		var name := parts[0]
		var translated: String = LABELS.ENUMS.get(name.to_upper().replace(" ", "_"), name)
		if doc.family(row) == "card_effects" and item.name == "kind" and LABELS.EFFECTS.has(number):
			translated = LABELS.EFFECTS[number]
		choices.append([number, translated])
	return choices

# 作用：把引用或数组显示成名称；source 为字段值，返回可读字符串。
func _display(source: Variant) -> String:
	if source is Array:
		var parts: PackedStringArray = []
		for item in source:
			parts.append(_display(item))
		return "、".join(parts)
	if source is String:
		var row: Dictionary = doc.record(source)
		return doc.title(row) if not row.is_empty() else source
	return str(source) if source != null else "空"

# 作用：枚举选项改变时提交值；index 为选项号，input 为下拉框，id/key 为格子路径，没有返回值。
func _enum_changed(index: int, input: OptionButton, id: String, key: String) -> void:
	if not rebuilding and not bridge.is_busy():
		doc.set_value(id, key, input.get_item_id(index))

# 作用：开关改变时提交值；enabled 为开关值，id/key 为格子路径，没有返回值。
func _bool_changed(enabled: bool, id: String, key: String) -> void:
	if not rebuilding and not bridge.is_busy():
		doc.set_value(id, key, enabled)

# 作用：回车时提交格子；text 为输入文本，input 为控件，id/key 为格子路径，没有返回值。
func _text_submitted(_text: String, input: Control, id: String, key: String) -> void:
	_input_changed(input, id, key)

# 作用：失去焦点时解析格子；input 为输入控件，id/key 为格子路径，没有返回值。
func _input_changed(input: Control, id: String, key: String) -> void:
	if rebuilding or bridge.is_busy() or not is_instance_valid(input):
		return
	var item: Dictionary = doc.field(doc.record(id), key)
	if item.is_empty():
		return
	var parsed: Variant = doc.parse(item, str(input.get("text")))
	if not doc.error.is_empty():
		status.text = doc.error + "（" + key + "，该格尚未提交）"
		input.set_meta("invalid", true)
		doc.data.editor_inputs[id + "|" + key] = str(input.get("text"))
		doc.write_recovery()
		_counts()
		input.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
		return
	input.set_meta("invalid", false)
	doc.data.editor_inputs.erase(id + "|" + key)
	doc.set_value(id, key, parsed)
	doc.write_recovery()
	_counts()
	_mark(input, item)

# 作用：给改过的格子加标记；input 为控件，item 为字段，没有返回值。
func _mark(input: Control, item: Dictionary) -> void:
	if input.get_meta("invalid", false):
		input.add_theme_color_override("font_color", Color(1, 0.4, 0.35))
	elif not item.is_empty() and not doc.same_value(item.get("value"), item.get("base")):
		input.add_theme_color_override("font_color", Color(1.0, 0.77, 0.32))
	else:
		input.remove_theme_color_override("font_color")

# 作用：识别 Excel 连续格子的粘贴；event 是键盘输入，id/key 是起点，没有返回值。
func _cell_input(event: InputEvent, id: String, key: String) -> void:
	if bridge.is_busy() or not event is InputEventKey or not event.pressed or not event.ctrl_pressed or event.keycode != KEY_V:
		return
	var text := DisplayServer.clipboard_get()
	if text.contains("\t") or text.contains("\n"):
		_paste_tsv(id, key, text)
		get_viewport().set_input_as_handled()

# 作用：解析并一次提交多行多列；id/key 为起点，text 为 Excel 文本，返回是否全部有效。
func _paste_tsv(id: String, key: String, text: String) -> bool:
	if not flush_input():
		return false
	var start_row := -1
	for i in visible_rows.size():
		if visible_rows[i].id == id:
			start_row = i
	var start_column := column_keys.find(key)
	if start_row < 0 or start_column < 0:
		return false
	var lines := text.replace("\r", "").trim_suffix("\n").split("\n")
	var edits: Array = []
	for i in lines.size():
		if start_row + i >= visible_rows.size():
			break
		var parts := lines[i].split("\t")
		var row: Dictionary = visible_rows[start_row + i]
		for j in parts.size():
			if start_column + j >= column_keys.size():
				break
			var name := column_keys[start_column + j]
			var item: Dictionary = doc.field(row, name)
			if not item.get("editable", false):
				continue
			var next: Variant = null
			if int(item.type) == TYPE_BOOL:
				if parts[j] not in ["true", "false", "启用", "开启", "关闭"]:
					_show_error("粘贴的开关值无效。整块数据未提交。")
					return false
				next = parts[j] in ["true", "启用", "开启"]
			elif int(item.type) == TYPE_INT and int(item.hint) == PROPERTY_HINT_ENUM:
				for choice: Array in _options(row, item):
					if str(choice[0]) == parts[j] or str(choice[1]) == parts[j]:
						next = choice[0]
				if next == null:
					_show_error("粘贴的枚举值无效。整块数据未提交。")
					return false
			else:
				next = doc.parse(item, parts[j])
				if not doc.error.is_empty():
					_show_error(doc.error + " 整块数据未提交。")
					return false
			edits.append({"id": row.id, "name": name, "value": next})
	doc.set_values(edits)
	status.text = "已粘贴 %d 个可编辑格子；可一次撤销。" % edits.size()
	return true

# 作用：取消尚未保存的字段列；kind 为资源类别，name 为字段，没有返回值。
func _remove_column(kind: String, name: String) -> void:
	if not bridge.is_busy() and flush_input():
		doc.remove_column(kind, name)

# 作用：取消尚未保存的资源行；id 为资源路径，没有返回值。
func _remove_row(id: String) -> void:
	if not bridge.is_busy() and flush_input():
		doc.remove_row(id)

# 作用：处理草稿变化；structure 指是否涉及行列结构，没有返回值。
func _document_changed(structure: bool) -> void:
	_render_categories()
	_counts()
	if structure and not table_pending:
		table_pending = true
		_render_table.call_deferred()
	elif not structure:
		for id: String in name_buttons:
			name_buttons[id].text = doc.title(doc.record(id)) + (" · 待创建" if doc.is_new(id) else "")
		for key: String in cells:
			var parts := key.split("|", true, 1)
			_mark(cells[key], doc.field(doc.record(parts[0]), parts[1]))
		_select_record(selected_id)
	if doc.is_dirty():
		status.text = "● 有未保存修改。保存时会校验、备份并用 Godot 回读验证。"

# 作用：刷新表格统计与按钮状态；没有参数，没有返回值。
func _counts() -> void:
	if not is_instance_valid(heading):
		return
	heading.text = "%s · %d 行 · %d 项待保存" % [LABELS.TITLES[category], visible_rows.size(), doc.change_count()] if _has_document() else "%s · 尚未载入" % LABELS.TITLES[category]
	for button in toolbar:
		button.disabled = bridge.is_busy()
	for button in document_buttons:
		button.disabled = bridge.is_busy() or not _has_document()
	save_button.disabled = bridge.is_busy() or not _has_document() or not doc.is_dirty()
	undo_button.disabled = bridge.is_busy() or doc.past.is_empty()
	redo_button.disabled = bridge.is_busy() or doc.future.is_empty()
	for input: Control in cells.values():
		var item: Dictionary = doc.field(doc.record(str(input.get_meta("resource_id"))), str(input.get_meta("field")))
		var editable: bool = item.get("editable", false) and not bridge.is_busy()
		if input is LineEdit or input is TextEdit:
			input.set("editable", editable)
		elif input is BaseButton:
			input.disabled = not editable

# 作用：显示选中资源及关联入口；id 为资源路径，没有返回值。
func _select_record(id: String) -> void:
	selected_id = id
	for child in references.get_children():
		child.queue_free()
	var row: Dictionary = doc.record(id)
	if row.is_empty():
		details.text = "点击行名称查看资源路径与关联配置。"
		return
	details.text = "%s\n资源：%s\n脚本：%s" % [doc.title(row), row.id, row.script]
	var inspector := Button.new()
	inspector.text = "在检查器中打开"
	inspector.pressed.connect(_inspect.bind(str(row.file)))
	references.add_child(inspector)
	if doc.is_new(id):
		var remove := Button.new()
		remove.text = "移除尚未保存的新行"
		remove.pressed.connect(_remove_row.bind(id))
		references.add_child(remove)
	var found: Array[String] = []
	for item: Dictionary in row.fields:
		if item.get("editable", false):
			continue
		var paths: Array = item.value if item.value is Array else [item.value]
		for path in paths:
			if path is String and not doc.record(path).is_empty() and not found.has(path):
				found.append(path)
	for path in found.slice(0, 6):
		var link := Button.new()
		link.text = doc.title(doc.record(path)) + " ↗"
		link.pressed.connect(_jump.bind(path))
		references.add_child(link)

# 作用：跳到关联配置所在表；id 为资源路径，没有返回值。
func _jump(id: String) -> void:
	if not flush_input():
		return
	var row: Dictionary = doc.record(id)
	category = doc.family(row)
	if category == "units":
		category = "allies" if doc.value(row, "unit_team") == "team_a" else "enemies"
	selected_id = id
	search.text = id
	_render_categories()
	_render_table()

# 作用：在 Godot 检查器中定位现有资源；path 为资源文件，没有返回值。
func _inspect(path: String) -> void:
	if not FileAccess.file_exists(path):
		_show_error("请先保存新增配置，再打开资源。")
	elif Engine.is_editor_hint():
		EditorInterface.edit_resource(load(path))

# 作用：确保当前输入已提交且没有无效格子；没有参数，返回是否可继续保存。
func flush_input() -> bool:
	var focus := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	if focus != null and is_ancestor_of(focus) and focus.has_meta("resource_id"):
		if focus is LineEdit or focus is TextEdit:
			_input_changed(focus, str(focus.get_meta("resource_id")), str(focus.get_meta("field")))
		focus.release_focus()
	for input: Control in cells.values():
		if input.get_meta("invalid", false):
			_show_error("还有无效格子未提交，请修正红色输入框后继续。")
			return false
	return true

# 作用：打开新增行表单；没有参数，没有返回值。
func _new_row() -> void:
	if not _require_document() or not flush_input():
		return
	row_templates.clear()
	for row: Dictionary in doc.data.get("records", []):
		if doc.matches(row, category) and not doc.is_new(row.id):
			row_templates.add_item(doc.title(row) + " · " + str(row.id).get_file())
			row_templates.set_item_metadata(row_templates.item_count - 1, row.id)
	if row_templates.item_count == 0:
		_show_error("此类资源没有可复制的模板。")
		return
	row_slug.text = ""
	row_display.text = ""
	row_display.visible = category != "card_effects"
	row_dialog.popup_centered(Vector2i(620, 240))

# 作用：确认创建新行；没有参数，没有返回值。
func _confirm_row() -> void:
	var id: String = doc.add_row(row_templates.get_item_metadata(row_templates.selected), row_slug.text.strip_edges(), row_display.text.strip_edges())
	if id.is_empty():
		_show_error(doc.error)
	else:
		selected_id = id
		search.text = ""

# 作用：打开新增字段表单；没有参数，没有返回值。
func _new_column() -> void:
	if not _require_document() or not flush_input():
		return
	column_name.text = ""
	column_label.text = ""
	column_note.text = ""
	column_type.select(0)
	column_default.text = "0"
	column_dialog.popup_centered(Vector2i(620, 350))

# 作用：字段类型切换时调整默认值；index 为类型号，没有返回值。
func _column_type_changed(index: int) -> void:
	column_default.text = ["0", "0", "", "false"][index]

# 作用：确认创建新字段；没有参数，没有返回值。
func _confirm_column() -> void:
	var dtype: String = ["int", "float", "text", "bool"][column_type.selected]
	var initial: Variant = column_default.text
	if dtype == "bool":
		if initial not in ["true", "false"]:
			_show_error("开关默认值只能填写 true 或 false。")
			return
		initial = initial == "true"
	elif dtype in ["int", "float"]:
		initial = doc.parse({"type": TYPE_INT if dtype == "int" else TYPE_FLOAT}, str(initial))
		if not doc.error.is_empty():
			_show_error(doc.error)
			return
	var kind := "units" if category in ["allies", "enemies"] else category
	if not doc.add_column({"family": kind, "name": column_name.text.strip_edges(), "label": column_label.text.strip_edges(), "dtype": dtype, "default": initial, "description": column_note.text.strip_edges()}):
		_show_error(doc.error)

# 作用：撤销草稿操作；没有参数，没有返回值。
func _undo() -> void:
	if flush_input():
		doc.undo()

# 作用：重做草稿操作；没有参数，没有返回值。
func _redo() -> void:
	if flush_input():
		doc.redo()

# 作用：重读磁盘上的游戏实际配置；没有参数，没有返回值。
func _reload() -> void:
	_run_tool("editor-read")

# 作用：校验当前修改但不保存；没有参数，没有返回值。
func _check() -> void:
	if flush_input():
		_run_tool("editor-check")

# 作用：应用全部已编辑格子；没有参数，没有返回值。
func _save() -> void:
	if flush_input():
		_run_tool("editor-apply")

# 作用：启动后台读取或保存；command 为工具命令，没有返回值。
func _run_tool(command: String) -> void:
	if bridge.is_busy():
		return
	if command != "editor-read" and not _require_document():
		return
	operation = command
	if not bridge.start(command, doc.data):
		_show_error("工具未能启动，请检查临时文件目录或工具设置。")
		return
	status.text = {"editor-read": "正在读取实际游戏配置…", "editor-check": "正在校验配置…", "editor-apply": "正在校验、备份并应用配置…"}[command]
	set_process(true)
	_counts()

# 作用：后台工作完成时接收结果；delta 为帧间时间，没有返回值，空闲时此回调关闭。
func _process(_delta: float) -> void:
	var result: Dictionary = bridge.finish()
	if not result.is_empty():
		set_process(false)
		_finish_tool(result)

# 作用：显示工具结果并刷新资源；result 为结果字典，没有返回值。
func _finish_tool(result: Dictionary) -> bool:
	if not result.get("ok", false):
		_cancel_pending()
		_show_error(str(result.get("error", "工具执行失败。")))
		_counts()
		return false
	if operation in ["editor-read", "editor-apply"] and not result.has("data"):
		_cancel_pending()
		_show_error("配置工具没有返回配置数据，请点击“重读”重试。")
		_counts()
		return false
	if result.has("data"):
		if not result.data is Dictionary or not doc.open(result.data):
			_cancel_pending()
			_show_error(doc.error if result.data is Dictionary else "配置工具返回的配置数据格式无效。")
			_counts()
			return false
		if operation == "editor-apply":
			doc.discard_recovery()
			_refresh_resources(result.get("changes", []))
	status.text = str(result.get("message", "操作完成。"))
	if result.has("backup"):
		status.text += "\n备份：" + str(result.backup)
	_counts()
	if first_read and operation == "editor-read":
		first_read = false
		if FileAccess.file_exists(doc.recovery_path):
			recovery.popup_centered()
	if pending_action.is_valid() and operation == "editor-apply":
		var action := pending_action
		pending_action = Callable()
		action.call_deferred()
	return true

# 作用：保存后让编辑器发现改动及新资源；changes 为写回清单，没有返回值。
func _refresh_resources(changes: Array) -> void:
	if not Engine.is_editor_hint():
		return
	var files := EditorInterface.get_resource_filesystem()
	var paths: Array[String] = []
	for item: Dictionary in changes:
		var path := str(item.id).get_slice("::", 0)
		if not item.get("schema", false) and FileAccess.file_exists(path) and not paths.has(path):
			paths.append(path)
			ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)
	files.scan()

# 作用：需要丢弃旧草稿的操作先提示保存；action 为后续操作，没有返回值。
func _request(action: Callable) -> void:
	if not flush_input():
		return
	if doc.is_dirty():
		pending_action = action
		guard.popup_centered()
	else:
		action.call()

# 作用：用户明确放弃修改后继续；action 为对话框按钮标识，没有返回值。
func _guard_discard(action: StringName) -> void:
	if action == &"discard":
		guard.hide()
		doc.discard_recovery()
		var next := pending_action
		pending_action = Callable()
		if next.is_valid():
			next.call()

# 作用：取消离开操作；没有参数，没有返回值。
func _cancel_pending() -> void:
	pending_action = Callable()

# 作用：恢复上次草稿；没有参数，没有返回值。
func _recover() -> void:
	_import_selected(doc.recovery_path)

# 作用：选择要导入的合集；没有参数，没有返回值。
func _import() -> void:
	import_dialog.popup_centered(Vector2i(950, 650))

# 作用：安全读取 JSON 或 HTML 中的配置数据；path 为文件路径，没有返回值。
func _import_selected(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if not text.strip_edges().begins_with("{"):
		var regex := RegEx.new()
		regex.compile('(?s)<script id="catalog-data" type="application/json">(.*?)</script>')
		var found := regex.search(text)
		if found == null:
			_show_error("文件中没有配置合集数据。")
			return
		text = found.get_string(1)
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary or not doc.open(parsed):
		_show_error("配置合集格式无效。")
		return
	doc.write_recovery()
	status.text = "已导入草稿。点击校验或保存并应用，核对当前游戏配置后再写回。"

# 作用：选择导出位置；没有参数，没有返回值。
func _export() -> void:
	if _require_document() and flush_input():
		export_dialog.current_file = "游戏配置表.html"
		export_dialog.popup_centered(Vector2i(950, 650))

# 作用：保存可继续编辑的合集；path 为导出文件路径，没有返回值。
func _export_selected(path: String) -> void:
	if not _require_document():
		return
	var text := JSON.stringify(doc.data, "\t")
	if path.get_extension().to_lower() == "html":
		text = FileAccess.get_file_as_string("res://tools/config_catalog/catalog.sheet.html").replace("__CATALOG_DATA__", text.replace("<", "\\u003c"))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_show_error("导出文件无法写入。")
		return
	file.store_string(text)
	file.close()
	status.text = "已导出：" + path

# 作用：显示当前修改清单；没有参数，没有返回值。
func _diff() -> void:
	if not _require_document() or not flush_input():
		return
	var lines: PackedStringArray = []
	for row: Dictionary in doc.data.get("pending_rows", []):
		lines.append("新增行：" + str(row.id))
	for column: Dictionary in doc.data.get("pending_columns", []):
		lines.append("新增列：" + str(column.label) + " / " + str(column.name))
	for row: Dictionary in doc.data.get("records", []):
		for item: Dictionary in row.fields:
			if not doc.same_value(item.get("value"), item.get("base")):
				lines.append("%s · %s：%s → %s" % [doc.title(row), _field_label(item, item.name), str(item.get("base")), str(item.value)])
	message.dialog_text = "没有待保存修改。" if lines.is_empty() else "\n".join(lines.slice(0, 120))
	message.popup_centered(Vector2i(900, 650))

# 作用：显示策划使用说明；没有参数，没有返回值。
func _help() -> void:
	message.dialog_text = "每个分类是一张表，每行一项配置。格子回车或移开焦点提交；黄色字代表修改。\n新增配置行复制模板；新增字段列给同类资源增加导出字段。\n保存并应用会校验、自动备份并由 Godot 回读；保存成功后重新运行场景。\n新单位、新卡牌仍需被卡组或关卡引用；卡牌效果明细会加入所属卡牌。\nHTML / JSON 可在本面板与原配置合集之间导入导出。\n未保存草稿可撤销、重做，并在下次打开时恢复。\nCtrl+S 保存；输入框外 Ctrl+Z 撤销、Ctrl+Y 重做。"
	message.popup_centered(Vector2i(800, 340))

# 作用：选择本机 Python 路径；没有参数，没有返回值。
func _python_settings() -> void:
	python_dialog.current_dir = bridge.python.get_base_dir()
	python_dialog.popup_centered(Vector2i(950, 650))

# 作用：保存工具路径设置；path 为 Python 可执行文件，没有返回值。
func _python_selected(path: String) -> void:
	bridge.python = path
	if Engine.is_editor_hint():
		EditorInterface.get_editor_settings().set_setting("game_config_editor/python_executable", path)
	status.text = "工具路径已更新。点击重读读取游戏配置。"

# 作用：显示错误并保留草稿；text 为错误说明，没有返回值。
func _show_error(text: String) -> void:
	status.text = text
	message.dialog_text = text
	message.popup_centered(Vector2i(850, 380))

# 作用：保存全部或确认退出保存时同步写回；没有参数，返回是否成功。
func save_on_exit() -> bool:
	if bridge.is_busy():
		_finish_tool(bridge.finish(true))
	if not flush_input():
		return false
	if not doc.is_dirty():
		return true
	operation = "editor-apply"
	var result: Dictionary = bridge.run_sync(operation, doc.data)
	return _finish_tool(result)

# 作用：插件关闭前等待读写并保留草稿；没有参数，没有返回值。
func shutdown() -> void:
	if bridge.is_busy():
		_finish_tool(bridge.finish(true))
	flush_input()
	if doc.is_dirty():
		doc.write_recovery()

# 作用：处理可见面板快捷键；event 为键盘事件，没有返回值。
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or bridge.is_busy() or not event is InputEventKey or not event.pressed or event.echo or not event.ctrl_pressed:
		return
	if event.keycode == KEY_S:
		_save()
	elif event.keycode == KEY_Z and not event.shift_pressed:
		_undo()
	elif event.keycode == KEY_Y or (event.keycode == KEY_Z and event.shift_pressed):
		_redo()
	else:
		return
	get_viewport().set_input_as_handled()
