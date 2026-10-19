# 这玩意儿是干嘛的（核心逻辑）：这是数据表格编辑器的主面板，像 Excel 一样管理 Resource 数据；脚本源码会在独立小窗口里打开，方便边看表格边修改。
# 数据是咋流动的（数据流向）：玩家从表格选中记录并打开脚本，文件内容读入 CodeEdit；编辑后由保存按钮或 Ctrl+S 写回原 .gd 文件，再通知 Godot 刷新资源目录。
# 为啥这么写（选型决策）：数据编辑继续留在 Dock，源码编辑改用 Godot 原生 Window；这样窗口能置顶、缩放且不阻塞主编辑器，也不用维护第二套外部编辑器通信。
# 性能咋样（复杂度）：只有切换脚本时读取一次文本、保存时写入一次文件；平时没有每帧扫描，正常项目中的脚本体积不会给编辑器带来明显负担。
@tool
extends VBoxContainer
## 数据表格编辑器 Dock 面板。
## 以类似 Excel 的表格管理 res://data 下各数据类型文件夹里的 .tres 数据。
## 所有修改先在内存中缓冲，点击【确认保存】才写入本地文件。

const Core := preload("res://addons/data_table_editor/core.gd")
const ResListEditor := preload("res://addons/data_table_editor/ui/resource_list_editor.gd")
const ResDropBox := preload("res://addons/data_table_editor/ui/resource_drop_box.gd")

# ---- 状态 ----
var _types: Array = []               # 数据类型文件夹名列表
var _current_type: String = ""
var _schema: Dictionary = {}         # detect_schema 结果
var _prop_names: Array = []          # 有序字段名
var _prop_by_name: Dictionary = {}   # name -> prop dict
var _records: Array = []             # 记录字典列表
var _selected: Dictionary = {}       # 当前选中记录
var _editors: Dictionary = {}        # 字段名 -> 编辑控件
var _extra_editors: Dictionary = {}  # 额外属性 key -> 编辑控件
var _rebuilding := false
var _next_record_id := 1             # 当前数据类型下一条新记录使用的永久 ID

# ---- 脚本编辑器状态 ----
var _script_rec: Dictionary = {}     # 正在编辑脚本的记录
var _script_file: String = ""
var _script_original: String = ""

# ---- 控件 ----
var _tab_container: TabContainer
var tree: Tree
var _editors_grid: GridContainer
var _editors_scroll: ScrollContainer
var _log_edit: RichTextLabel
var _empty_hint: Label

var _new_record_btn: Button
var _delete_btn: Button
var _script_btn: Button
var _refresh_btn: Button
var _save_btn: Button
var _add_type_btn: Button

var _new_type_dialog: AcceptDialog
var _new_type_edit: LineEdit
var _new_record_dialog: AcceptDialog
var _new_record_edit: LineEdit

# 脚本编辑窗口保持非模态和始终置顶，玩家仍然可以操作 Godot 主编辑器。
var _script_window: Window
var _script_path_label: Label
var _script_status_label: Label
var _script_code: CodeEdit


func _ready() -> void:
	_build_ui()
	_tab_container.tab_changed.connect(_on_tab_changed)
	_rebuild_tabs("")
	_log("数据表格编辑器就绪。所有修改请点击【确认保存】后才会写入本地文件。")


func _build_ui() -> void:
	var title := Label.new()
	title.text = "数据表格编辑器 (data/)"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	add_child(_hsep())

	# ---- 数据类型标签页 ----
	add_child(_label("数据类型（点击切换文件夹）"))
	_tab_container = TabContainer.new()
	_tab_container.tab_alignment = TabBar.ALIGNMENT_LEFT
	add_child(_tab_container)

	add_child(_hsep())

	# ---- 工具栏 ----
	var bar := HBoxContainer.new()
	_new_record_btn = Button.new()
	_new_record_btn.text = "新建数据"
	_new_record_btn.pressed.connect(_on_new_record)
	_delete_btn = Button.new()
	_delete_btn.text = "删除记录"
	_delete_btn.pressed.connect(_on_delete_record)
	_script_btn = Button.new()
	_script_btn.text = "✎ 脚本"
	_script_btn.tooltip_text = "在置顶小窗口中打开选中记录对应的脚本"
	_script_btn.pressed.connect(_on_script_btn)
	_refresh_btn = Button.new()
	_refresh_btn.text = "刷新"
	_refresh_btn.pressed.connect(_on_refresh)
	_save_btn = Button.new()
	_save_btn.text = "确认保存"
	_save_btn.pressed.connect(_on_save)
	_add_type_btn = Button.new()
	_add_type_btn.text = "＋新增类型"
	_add_type_btn.pressed.connect(_on_add_type)
	bar.add_child(_new_record_btn)
	bar.add_child(_delete_btn)
	bar.add_child(_script_btn)
	bar.add_child(_refresh_btn)
	bar.add_child(_save_btn)
	bar.add_child(_add_type_btn)
	add_child(bar)

	add_child(_hsep())

	# ---- 表格 ----
	var tree_hint := Label.new()
	tree_hint.text = "数据表格（每列对应一个参数；双击「脚本」列可在置顶小窗口中编辑源码）"
	tree_hint.add_theme_font_size_override("font_size", 12)
	tree_hint.modulate = Color(0.8, 0.8, 0.8)
	add_child(tree_hint)
	tree = Tree.new()
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tree.custom_minimum_size.y = 180
	tree.item_selected.connect(_on_item_selected)
	tree.item_activated.connect(_on_item_activated)
	add_child(tree)

	add_child(_hsep())

	# ---- 详情编辑 ----
	add_child(_label("编辑选中记录"))
	_editors_scroll = ScrollContainer.new()
	_editors_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editors_scroll.custom_minimum_size.y = 160
	_editors_grid = GridContainer.new()
	_editors_grid.columns = 2
	_editors_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editors_grid.add_theme_constant_override("h_separation", 12)
	_editors_grid.add_theme_constant_override("v_separation", 6)
	_editors_scroll.add_child(_editors_grid)
	add_child(_editors_scroll)

	add_child(_hsep())

	# ---- 日志 ----
	_log_edit = RichTextLabel.new()
	_log_edit.bbcode_enabled = true
	_log_edit.scroll_following = true
	_log_edit.custom_minimum_size.y = 70
	add_child(_log_edit)

	# ---- 对话框 ----
	_new_type_dialog = AcceptDialog.new()
	_new_type_dialog.title = "新增数据类型"
	_new_type_dialog.ok_button_text = "创建"
	_new_type_dialog.dialog_text = "输入新数据类型的文件夹名（会自动生成一个结构脚本）。"
	_new_type_edit = LineEdit.new()
	_new_type_edit.placeholder_text = "例如 itemdata"
	_new_type_dialog.add_child(_new_type_edit)
	_new_type_dialog.register_text_enter(_new_type_edit)
	_new_type_dialog.confirmed.connect(_on_new_type_confirmed)
	add_child(_new_type_dialog)

	_new_record_dialog = AcceptDialog.new()
	_new_record_dialog.title = "新建数据"
	_new_record_dialog.ok_button_text = "创建"
	_new_record_dialog.dialog_text = "输入新数据的文件名（不含扩展名，会自动生成 .tres）。"
	_new_record_edit = LineEdit.new()
	_new_record_edit.placeholder_text = "例如 new_soldier"
	_new_record_dialog.add_child(_new_record_edit)
	_new_record_dialog.register_text_enter(_new_record_edit)
	_new_record_dialog.confirmed.connect(_on_new_record_confirmed)
	add_child(_new_record_dialog)

	_build_script_window()


## 在插件加载时创建脚本编辑小窗口。没有参数，也没有返回值。
## Window 设为非模态，避免打开源码后锁住 Godot；always_on_top 保证它不会被主编辑器盖住。
func _build_script_window() -> void:
	_script_window = Window.new()
	_script_window.title = "数据表格编辑器 - 脚本编辑"
	_script_window.size = Vector2i(900, 680)
	_script_window.min_size = Vector2i(720, 520)
	_script_window.always_on_top = true
	# Godot 不允许置顶窗口同时成为 transient；关闭 transient 后仍由 always_on_top 保持在主编辑器前方。
	_script_window.transient = false
	_script_window.exclusive = false
	_script_window.unresizable = false
	_script_window.visible = false
	_script_window.close_requested.connect(_on_script_window_close_requested)
	add_child(_script_window)

	# 用全窗口边距容器承载控件，缩放弹窗时代码区会自动跟随变大。
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_script_window.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	_script_path_label = Label.new()
	_script_path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_script_path_label.modulate = Color(0.75, 0.75, 0.75)
	_script_path_label.add_theme_font_size_override("font_size", 15)
	content.add_child(_script_path_label)

	# CodeEdit 自带行号、撤销和文本选择，比普通 TextEdit 更适合临时修改 GDScript。
	_script_code = CodeEdit.new()
	_script_code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_script_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_script_code.custom_minimum_size.y = 240
	_script_code.gutters_draw_line_numbers = true
	# 显式配色 + 等宽字体，保证代码清晰可见
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["Consolas", "Courier New", "DejaVu Sans Mono", "monospace"])
	_script_code.add_theme_font_override("font", mono)
	_script_code.add_theme_font_size_override("font_size", 18)
	_script_code.add_theme_color_override("font_color", Color(0.93, 0.93, 0.93))
	_script_code.add_theme_color_override("caret_color", Color(1.0, 1.0, 1.0))
	_script_code.add_theme_color_override("selection_color", Color(0.28, 0.45, 0.7, 0.8))
	_script_code.add_theme_color_override("line_number_color", Color(0.62, 0.66, 0.72))
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.09, 0.10, 0.12)
	bg.set_content_margin_all(4)
	_script_code.add_theme_stylebox_override("normal", bg)
	_script_code.add_theme_stylebox_override("focus", bg)
	_script_code.add_theme_stylebox_override("read_only", bg)
	_script_code.gui_input.connect(_on_script_code_input)
	content.add_child(_script_code)

	var hint := Label.new()
	hint.text = "提示：修改的是该记录对应的 .gd 脚本；Ctrl+S 保存。若改了 @export 字段，回到表格后点【刷新】更新列。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.modulate = Color(0.7, 0.8, 0.7)
	hint.add_theme_font_size_override("font_size", 14)
	content.add_child(hint)

	_script_status_label = Label.new()
	_script_status_label.text = ""
	_script_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_script_status_label.add_theme_font_size_override("font_size", 14)
	content.add_child(_script_status_label)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGNMENT_END
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.add_theme_font_size_override("font_size", 15)
	save_btn.pressed.connect(_on_script_save)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.add_theme_font_size_override("font_size", 15)
	close_btn.pressed.connect(_on_script_window_close_requested)
	btns.add_child(save_btn)
	btns.add_child(close_btn)
	content.add_child(btns)


# ============================================================
# 标签页 / 加载
# ============================================================

func _rebuild_tabs(select_folder: String) -> void:
	_rebuilding = true
	for c in _tab_container.get_children():
		_tab_container.remove_child(c)
		c.queue_free()
	_types = Core.list_types()
	for t in _types:
		var tab := Control.new()
		tab.name = t
		_tab_container.add_child(tab)
		_tab_container.set_tab_title(_tab_container.get_child_count() - 1, t)
	_rebuilding = false

	if _types.is_empty():
		_current_type = ""
		_schema = {}
		_prop_names = []
		_prop_by_name = {}
		_records = []
		_selected = {}
		_setup_tree_columns()
		_build_tree()
		_build_editors({})
		_log("data/ 下没有任何数据类型文件夹。点击【＋新增类型】创建。", true)
		return

	var idx := _types.find(select_folder)
	if idx < 0:
		idx = 0
	_tab_container.current_tab = idx
	_current_type = _types[idx]
	_load_current_type()


func _on_tab_changed(idx: int) -> void:
	if _rebuilding:
		return
	if idx < 0 or idx >= _types.size():
		return
	_current_type = _types[idx]
	_load_current_type()


## 读取当前数据文件夹并重建表格。没有参数，也没有返回值。
## 切换标签或点刷新都会调用它；重建完成后把表格滚回顶部，保证 ID 最小的第一条数据不会藏在旧滚动位置上方。
func _load_current_type() -> void:
	_schema = Core.detect_schema(_current_type)
	_prop_names = []
	_prop_by_name = {}
	for prop in _schema.props:
		_prop_names.append(prop["name"])
		_prop_by_name[prop["name"]] = prop

	_records = []
	for path in Core.list_records(_current_type):
		var rec = Core.load_record(path, _schema)
		if rec.get("error", "") != "":
			_log(rec["error"], true)
		_records.append(rec)
	_prepare_record_ids()

	_selected = {}
	_setup_tree_columns()
	_build_tree()
	# Tree 的滚动范围要等到本帧布局完成才会计算正确，因此延后重置，避免第一行被旧位置遮住。
	call_deferred("_reset_tree_scroll_to_top")
	_build_editors({})

	if _schema.error != "":
		_log("[警告] %s" % _schema.error, true)
	_log("已加载类型 [%s]：%d 条记录，%d 个字段（%s）" % [
		_current_type, _records.size(), _prop_names.size(),
		_schema.get("script_path", "")])


## 把数据表纵向滚动条移动到第一行。没有参数，也没有返回值。
## 仅在完整重载类型后调用；如果不复位，切换标签会沿用上一张表的位置，ID 1 这类首行就会看起来像“没有读取到”。
func _reset_tree_scroll_to_top() -> void:
	# 使用 Tree 自己提供的滚动接口，不直接访问内部滚动条；不同 Godot 版本的内部滚动条接口并不完全一致。
	var root := tree.get_root()
	if root == null:
		return
	var first_item := root.get_first_child()
	if first_item != null:
		tree.scroll_to_item(first_item)


## 为当前类型准备稳定 ID。没有参数，也没有返回值。
## 已有 ID 原样保留；旧记录缺少或重复 ID 时按当前稳定顺序补发新号，最后统一按 ID 升序排列。
func _prepare_record_ids() -> void:
	# 早期版本曾让不同文件夹共用一串编号。只有当前类型还没有自己的计数器、且最小 ID 大于 1 时，
	# 才把旧全局号压缩为本类型的 1、2、3……；已有计数器的类型即使删除了 ID 1 也绝不重排。
	if not Core.has_record_id_counter(_current_type):
		_migrate_legacy_global_ids()

	var used_ids := {}
	var missing_records: Array = []
	var largest_id := 0
	for rec in _records:
		var row_id := int(rec.get("row_id", 0))
		if row_id > 0 and not used_ids.has(row_id):
			used_ids[row_id] = true
			largest_id = maxi(largest_id, row_id)
		else:
			missing_records.append(rec)

	# 计数文件负责记住已经发放到哪里；与现存最大 ID 取较大值，避免旧项目迁移时产生重复号。
	_next_record_id = maxi(Core.read_next_record_id(_current_type), largest_id + 1)
	var assigned_count := 0
	for rec in missing_records:
		if rec.get("res") == null:
			continue
		_assign_record_id(rec, _next_record_id, true)
		_next_record_id += 1
		assigned_count += 1
	_sort_records_by_id()
	if assigned_count > 0:
		_log("已为 %d 条旧数据补发永久 ID；点击【确认保存】后写入文件。" % assigned_count)


## 将旧版错误的全局 ID 迁移成当前文件夹独立的 ID。没有参数；返回 true 表示本次确实重排了旧编号。
## 只迁移“所有现存编号都从大于 1 开始”的典型旧数据，正常类型删除早期记录后出现的 ID 空洞不会被改动。
func _migrate_legacy_global_ids() -> bool:
	var numbered_records: Array = []
	for rec in _records:
		if rec.get("res") != null and int(rec.get("row_id", 0)) > 0:
			numbered_records.append(rec)
	if numbered_records.is_empty():
		return false

	# 原全局 ID 的大小仍代表原来的创建先后，因此先按旧号排序再从 1 开始补号。
	numbered_records.sort_custom(func(a, b):
		return int(a.get("row_id", 0)) < int(b.get("row_id", 0))
	)
	if int(numbered_records[0].get("row_id", 0)) <= 1:
		return false

	for index in numbered_records.size():
		_assign_record_id(numbered_records[index], index + 1, true)
	_log("已将 [%s] 的旧全局 ID 迁移为独立编号 1-%d；点击【确认保存】后写入文件。" % [
		_current_type, numbered_records.size()
	])
	return true


## 给 rec 分配 row_id。pending 表示该 ID 尚未写盘；没有返回值。
## ID 同时放进 Resource 元数据，ResourceSaver 保存时会自动写成 metadata/_data_table_id。
func _assign_record_id(rec: Dictionary, row_id: int, pending: bool) -> void:
	rec["row_id"] = row_id
	rec["id_pending"] = pending
	var res: Resource = rec.get("res")
	if res != null:
		res.set_meta(Core.RECORD_ID_META, row_id)


## 按永久 ID 排列当前记录。没有参数，也没有返回值；ID 相同时再按文件名排序保证结果稳定。
func _sort_records_by_id() -> void:
	_records.sort_custom(func(a, b):
		var aid := int(a.get("row_id", 0))
		var bid := int(b.get("row_id", 0))
		if aid == bid:
			return str(a.get("base_name", "")) < str(b.get("base_name", ""))
		return aid < bid
	)


## 根据当前数据类型建立表格列。没有参数，也没有返回值。
## ID 固定放在第一列，文件列和前两个常用字段保留足够宽度，避免名称只显示一半导致选错记录。
func _setup_tree_columns() -> void:
	tree.columns = _prop_names.size() + 4
	tree.set_column_title(0, "ID")
	tree.set_column_expand(0, false)
	tree.set_column_custom_minimum_width(0, 72)
	tree.set_column_title(1, "文件")
	tree.set_column_expand(1, true)
	tree.set_column_custom_minimum_width(1, _preferred_tree_column_width(1, 220))
	for i in _prop_names.size():
		tree.set_column_title(i + 2, _prop_names[i])
		tree.set_column_expand(i + 2, true)
		# 前两个数据字段通常是中文名和英文名，是查找记录时最常看的信息，因此给予更完整的展示空间。
		var minimum_width := _preferred_tree_column_width(i + 2, 200) if i < 2 else 100
		tree.set_column_custom_minimum_width(i + 2, minimum_width)
	var sc := _script_col_index()
	var st := _status_col_index()
	tree.set_column_title(sc, "脚本")
	tree.set_column_expand(sc, false)
	tree.set_column_custom_minimum_width(sc, 110)
	tree.set_column_title(st, "状态")
	tree.set_column_custom_minimum_width(st, 64)


## 估算某一列完整显示所需的宽度。column_index 是表格列号，minimum_width 是保底宽度；返回限制在合理范围内的像素宽度。
## 宽度只在加载/刷新数据类型时计算一次，并限制到 420px，既方便辨认又不会被一条超长路径撑坏整个表格。
func _preferred_tree_column_width(column_index: int, minimum_width: int) -> int:
	var longest_length := tree.get_column_title(column_index).length()
	for rec in _records:
		if rec.get("deleted", false):
			continue
		var text := ""
		if column_index == 1:
			text = str(rec.get("base_name", ""))
		elif column_index >= 2 and column_index - 2 < _prop_names.size():
			var prop_name: String = _prop_names[column_index - 2]
			var res = rec.get("res")
			if res != null:
				text = Core.display_value(_prop_by_name[prop_name], res.get(prop_name))
		longest_length = maxi(longest_length, text.length())
	return clampi(longest_length * 12 + 40, minimum_width, 420)


## 用当前记录重建数据表。没有参数，也没有返回值。
## Tree 的根节点专门作为隐藏容器；每条数据都放在它下面，避免第一条记录被 Godot 当成隐藏根节点而消失。
func _build_tree() -> void:
	tree.clear()
	var hidden_root := tree.create_item()
	for rec in _records:
		if rec.get("deleted", false):
			rec["_item"] = null
			continue
		# 所有记录（包括 ID 1 的 archer）都必须成为隐藏根节点的子项，才能出现在可见列表中。
		var item := tree.create_item(hidden_root)
		item.set_metadata(0, rec)
		rec["_item"] = item
		_refresh_item(rec)
	# 恢复选中
	if not _selected.is_empty() and not _selected.get("deleted", false):
		var item: TreeItem = _selected.get("_item")
		if item != null:
			item.select(0)


func _script_col_index() -> int:
	return _prop_names.size() + 2


func _status_col_index() -> int:
	return _prop_names.size() + 3


func _refresh_item(rec: Dictionary) -> void:
	var item: TreeItem = rec.get("_item")
	if item == null:
		return
	item.set_text(0, str(rec.get("row_id", 0)))
	item.set_tooltip_text(0, "创建序号：%s" % rec.get("row_id", 0))
	item.set_text(1, rec["base_name"])
	item.set_tooltip_text(1, rec["base_name"])
	var res = rec.get("res")
	for i in _prop_names.size():
		var nm: String = _prop_names[i]
		var val = res.get(nm) if res != null else null
		var display_text := Core.display_value(_prop_by_name[nm], val)
		item.set_text(i + 2, display_text)
		# 无论列宽如何，鼠标停留都能看到完整值，长资源路径也不会只能靠猜。
		var description: String = _prop_by_name[nm].get("description", "")
		item.set_tooltip_text(i + 2, display_text + ("\n" + description if not description.is_empty() else ""))
	# 脚本列：显示脚本文件名，链接色提示可点击
	var sp: String = rec.get("script_path", "")
	if sp == "":
		item.set_text(_script_col_index(), "—")
	else:
		item.set_text(_script_col_index(), sp.get_file())
		item.set_custom_color(_script_col_index(), Color(0.45, 0.75, 1.0))
		item.set_tooltip_text(_script_col_index(), "双击打开脚本编辑器\n" + sp)
	item.set_text(_status_col_index(), _status_text(rec))


func _status_text(rec: Dictionary) -> String:
	if rec.get("deleted", false):
		return "已删除"
	if rec.get("is_new", false):
		return "新建"
	if rec.get("dirty", false):
		return "已修改"
	if rec.get("id_pending", false):
		return "待保存ID"
	return ""


func _on_item_selected() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	var rec = item.get_metadata(0)
	_selected = rec
	_build_editors(rec)


func _on_item_activated() -> void:
	var item := tree.get_selected()
	if item == null:
		return
	if tree.get_selected_column() != _script_col_index():
		return
	var rec = item.get_metadata(0)
	_open_script_editor(rec)


func _on_script_btn() -> void:
	if _selected.is_empty():
		_log("请先在表格中选中一条记录。", true)
		return
	_open_script_editor(_selected)


# ============================================================
# 脚本编辑窗口
# ============================================================

## 打开某条记录对应的脚本。rec 是表格记录字典；没有返回值。
## 如果另一个脚本还有未保存内容，就保留原窗口，防止一次双击把玩家刚写的代码覆盖掉。
func _open_script_editor(rec: Dictionary) -> void:
	var sp: String = rec.get("script_path", "")
	if sp == "":
		_log("该记录没有对应的脚本。", true)
		return
	if not FileAccess.file_exists(sp):
		_log("脚本文件不存在: " + sp, true)
		return
	if _script_dirty() and _script_file != sp:
		_set_script_status("当前脚本还有未保存的修改，请先保存或关闭后再打开其他脚本。", true)
		_focus_script_window()
		return
	if _script_file == sp and _script_window.visible:
		_focus_script_window()
		return

	# 只有确认可以切换时才读取新文件，避免丢失 CodeEdit 中尚未写盘的文字。
	var src := Core.read_text_file(sp)
	_script_rec = rec
	_script_file = sp
	_script_original = src
	_script_path_label.text = sp
	_script_window.title = "脚本编辑 - " + sp.get_file()
	_script_code.text = src
	_script_code.clear_undo_history()
	_script_code.set_v_scroll(0)
	_set_script_status("已打开脚本，可以直接修改；按 Ctrl+S 保存。")
	_focus_script_window()


## 把脚本窗口显示到 Godot 主编辑器前面。没有参数，也没有返回值。
## 已显示时只重新取得焦点，避免每次双击都把玩家调整好的窗口位置重置。
func _focus_script_window() -> void:
	if _script_window.visible:
		_script_window.grab_focus()
	else:
		_script_window.popup_centered(Vector2i(900, 680))
	_script_code.grab_focus()


## 检查窗口里的源码是否和最后一次读取/保存的内容不同。没有参数；返回 true 表示存在未保存修改。
func _script_dirty() -> bool:
	return _script_file != "" and _script_code.text != _script_original


## 更新弹窗底部的提示。message 是提示文字，is_error 表示是否使用警告颜色；没有返回值。
func _set_script_status(message: String, is_error: bool = false) -> void:
	_script_status_label.text = message
	_script_status_label.modulate = Color(1.0, 0.45, 0.45) if is_error else Color(0.55, 0.85, 0.6)


## 保存按钮和 Ctrl+S 共用的写盘入口。没有参数，也没有返回值。
## 写盘后会主动重载 Godot 缓存的 Script，让已经在主编辑器打开的同一脚本立刻换成新内容。
func _on_script_save() -> void:
	if _script_file == "":
		return
	var cur := _script_code.text
	if cur == _script_original:
		_set_script_status("当前内容没有变化，无需保存。")
		return
	var err := Core.write_text_file(_script_file, cur)
	if err != OK:
		_log("脚本保存失败: %s (%s)" % [_script_file, error_string(err)], true)
		_set_script_status("保存失败：%s" % error_string(err), true)
		return
	# 先记录这次已写入磁盘的文本；即使新代码有语法错误，也不能再把它误判成“未保存”。
	_script_original = cur

	# load() 会拿到 Godot 当前缓存的 Script；仅扫描目录不会替换它，所以必须显式 reload()。
	# keep_state 设为 true，能尽量保留编辑器里已挂载该脚本的 Resource / 工具节点状态。
	var saved_script := load(_script_file) as Script
	if saved_script == null:
		_log("脚本已写入，但 Godot 无法加载：%s。请检查语法错误。" % _script_file, true)
		_set_script_status("已写入磁盘，但 Godot 无法加载脚本；请检查语法错误。", true)
		return
	var reload_err := saved_script.reload(true)
	if reload_err != OK:
		_log("脚本已写入，但 Godot 重载失败：%s" % error_string(reload_err), true)
		_set_script_status("已写入磁盘，但重载失败：%s；请修正语法后再次保存。" % error_string(reload_err), true)
		return

	# 更新文件列表并扫描变更，让文件系统、脚本类列表和已打开的脚本页都收到这次外部写盘通知。
	var file_system := EditorInterface.get_resource_filesystem()
	file_system.update_file(_script_file)
	file_system.scan()
	_log("已保存并重载脚本: " + _script_file)
	if _schema.get("script_path", "") == _script_file:
		# 结构脚本的导出字段可能变化，延后到本次按钮回调结束后重建表格，避免正在遍历控件时删除控件。
		call_deferred("_load_current_type")
		_log("已修改并重载结构脚本，表格列会自动刷新。")
		_set_script_status("保存并重载成功；结构字段与表格列正在自动刷新。")
	else:
		_set_script_status("保存并重载成功，Godot 内置脚本编辑器已同步更新。")


## 由弹窗右上角关闭按钮或底部“关闭”按钮触发。没有参数，也没有返回值。
## 有未保存内容时拒绝关闭，让玩家先保存，避免误操作丢代码。
func _on_script_window_close_requested() -> void:
	if _script_dirty():
		_log("脚本有未保存的修改，请先点【保存】或 Ctrl+S。", true)
		_set_script_status("脚本还有未保存的修改，请先点【保存】或按 Ctrl+S。", true)
		_script_window.grab_focus()
		return
	_script_window.hide()


## CodeEdit 收到键盘输入时由 Godot 调用。event 是本次输入事件；没有返回值。
## 只接管 Ctrl+S，其余按键继续交给代码编辑框处理。
func _on_script_code_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_S and event.ctrl_pressed:
		_on_script_save()
		_script_code.accept_event()


# ============================================================
# 详情编辑面板
# ============================================================

func _build_editors(rec: Dictionary) -> void:
	for c in _editors_grid.get_children():
		_editors_grid.remove_child(c)
		c.queue_free()
	_editors = {}
	_extra_editors = {}

	if rec.is_empty() or rec.get("res") == null:
		var hint := Label.new()
		hint.text = "在表格中选中一条记录进行编辑。"
		hint.modulate = Color(0.7, 0.7, 0.7)
		_editors_grid.add_child(hint)
		return

	# ---- 对应脚本（该行记录使用的 .gd）----
	var sl := Label.new()
	sl.text = "对应脚本"
	sl.tooltip_text = "该记录使用的 .gd 脚本，点击右侧按钮可打开置顶编辑窗口"
	_editors_grid.add_child(sl)
	var sp: String = rec.get("script_path", "")
	var sbox := HBoxContainer.new()
	sbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 脚本路径使用专门的拖拽框；从 FileSystem 拖入 .gd 后只修改内存记录，仍由“确认保存”统一写盘。
	var script_drop := ResDropBox.new()
	script_drop.set_is_script(true)
	script_drop.set_path(sp)
	script_drop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	script_drop.tooltip_text = "从 FileSystem 拖入继承当前数据结构的 .gd 脚本"
	script_drop.changed.connect(func(path): _commit_record_script_path(rec, script_drop, path))
	sbox.add_child(script_drop)
	var open_btn := Button.new()
	open_btn.text = "打开/编辑"
	open_btn.disabled = sp == ""
	open_btn.tooltip_text = "在置顶小窗口中打开该记录对应的脚本"
	open_btn.pressed.connect(_open_script_editor.bind(rec))
	sbox.add_child(open_btn)
	_editors_grid.add_child(sbox)

	if _prop_names.is_empty():
		var hint := Label.new()
		hint.text = "该类型没有 @export 字段。请在结构脚本（%s）中定义 @export var。" % _schema.get("script_path", "")
		hint.modulate = Color(0.85, 0.75, 0.4)
		_editors_grid.add_child(hint)

	var res: Resource = rec["res"]
	for nm in _prop_names:
		var prop: Dictionary = _prop_by_name[nm]
		var val = res.get(nm)
		_add_prop_row(rec, prop, val)

	if rec.get("extra", []).size() > 0:
		_add_grid_label("额外属性（脚本未声明，原样保留）", Color(0.6, 0.75, 1.0))
		for e in rec["extra"]:
			_add_extra_row(rec, e)


## 修改一条数据记录绑定的脚本。rec 是记录，editor 是拖拽框，path 是新脚本路径；没有返回值。
## 这里只修改内存中的 Resource 和脏状态，真正写入 .tres 仍由玩家点击“确认保存”完成。
func _commit_record_script_path(rec: Dictionary, editor: ResourceDropBox, path: String) -> void:
	var old_path: String = rec.get("script_path", "")
	var new_path := path.strip_edges()
	if new_path == old_path:
		return

	# 数据必须始终保留合法脚本；清空或输入非 .gd 路径时恢复旧值，避免保存出无法加载的资源。
	if new_path == "" or new_path.get_extension().to_lower() != "gd":
		_log("对应脚本只能绑定一个 .gd 文件，不能留空。", true)
		editor.set_path(old_path)
		return
	if not FileAccess.file_exists(new_path):
		_log("脚本文件不存在: " + new_path, true)
		editor.set_path(old_path)
		return

	# 如果旧脚本还在置顶窗口里修改，先要求玩家保存，避免脚本绑定和正在编辑的内容对不上。
	if _script_dirty() and _script_file == old_path:
		_log("当前绑定脚本还有未保存修改，请先保存或关闭脚本窗口。", true)
		_set_script_status("请先保存当前脚本，再拖入新的绑定脚本。", true)
		editor.set_path(old_path)
		_focus_script_window()
		return

	var candidate := load(new_path) as Script
	var schema_script := load(_schema.get("script_path", "")) as Script
	if candidate == null:
		_log("无法加载脚本: " + new_path, true)
		editor.set_path(old_path)
		return
	if schema_script != null and not _script_inherits_from(candidate, schema_script):
		_log("脚本类型不兼容：必须继承 %s" % _schema.get("script_path", ""), true)
		editor.set_path(old_path)
		return

	# 通过继承检查后替换 Resource 的脚本，并刷新表格“脚本/状态”两列供玩家立即确认。
	var res: Resource = rec.get("res")
	res.set_script(candidate)
	rec["script_path"] = new_path
	rec["dirty"] = true
	_refresh_item(rec)
	_log("已修改 [%s] 的对应脚本为 %s（尚未写盘）。" % [rec.get("base_name", ""), new_path])


## 判断 candidate 是否等于或继承 expected。两个参数都是脚本；返回 true 表示可以安全绑定到当前数据类型。
func _script_inherits_from(candidate: Script, expected: Script) -> bool:
	var current: Script = candidate
	while current != null:
		if current == expected:
			return true
		current = current.get_base_script()
	return false


func _add_grid_label(text: String, color: Color = Color(1, 1, 1)) -> void:
	var l := Label.new()
	l.text = text
	l.modulate = color
	_editors_grid.add_child(l)
	_editors_grid.add_child(Control.new())


func _add_prop_row(rec: Dictionary, prop: Dictionary, val) -> void:
	var nm: String = prop["name"]
	var kind := _prop_editor_kind(prop)

	# 标签
	var l := Label.new()
	l.text = nm
	l.tooltip_text = "类型: %s" % _describe_prop(prop)
	var description: String = prop.get("description", "")
	if not description.is_empty():
		l.tooltip_text += "\n" + description
	_editors_grid.add_child(l)

	match kind:
		"enum":
			var opt := OptionButton.new()
			var entries := Core.enum_entries(prop)
			var sel := -1
			var iv := int(val)
			for e in entries:
				opt.add_item(e["name"])
				opt.set_item_metadata(opt.item_count - 1, e["value"])
				if int(e["value"]) == iv:
					sel = opt.item_count - 1
			if entries.is_empty():
				opt.add_item(str(iv))
				opt.set_item_metadata(0, iv)
				sel = 0
			elif sel == -1:
				opt.add_item("值:%d" % iv)
				opt.set_item_metadata(opt.item_count - 1, iv)
				sel = opt.item_count - 1
			opt.selected = sel
			opt.item_selected.connect(func(_i): _commit_enum(nm))
			_editors_grid.add_child(opt)
			_editors[nm] = opt

		"bool":
			var cb := CheckBox.new()
			cb.button_pressed = bool(val)
			cb.toggled.connect(func(_p): _commit_bool(nm))
			_editors_grid.add_child(cb)
			_editors[nm] = cb

		"int":
			var sb := _make_spin(-999999999, 999999999, 1, float(val))
			sb.value_changed.connect(func(_v): _commit_int(nm))
			_editors_grid.add_child(sb)
			_editors[nm] = sb

		"float":
			var sb := _make_spin(-999999999.0, 999999999.0, 0.1, float(val))
			sb.value_changed.connect(func(_v): _commit_float(nm))
			_editors_grid.add_child(sb)
			_editors[nm] = sb

		"string":
			var le := LineEdit.new()
			le.text = str(val)
			le.text_submitted.connect(func(_t): _commit_string(nm))
			le.focus_exited.connect(func(): _commit_string(nm))
			_editors_grid.add_child(le)
			_editors[nm] = le

		"scene", "resource":
			var box := ResDropBox.new()
			box.set_is_scene(kind == "scene")
			box.set_path(val.resource_path if val is Resource else "")
			box.changed.connect(func(p): _commit_resource_path(nm, p))
			_editors_grid.add_child(box)
			_editors[nm] = box

		"resource_array":
			var rle := ResListEditor.new()
			rle.set_array(val)
			rle.changed.connect(func(): _mark_dirty(nm))
			_editors_grid.add_child(rle)
			_editors[nm] = rle

		"int_array", "float_array", "string_array", "plain_array":
			var le := LineEdit.new()
			le.text = _array_to_text(kind, val)
			le.text_submitted.connect(func(_t): _commit_array(nm, kind))
			le.focus_exited.connect(func(): _commit_array(nm, kind))
			_editors_grid.add_child(le)
			_editors[nm] = le

		_:
			var rl := Label.new()
			rl.text = Core.display_value(prop, val)
			rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_editors_grid.add_child(rl)
	if _editors.has(nm):
		var editor: Control = _editors[nm]
		editor.tooltip_text = l.tooltip_text
		if editor is SpinBox:
			editor.get_line_edit().tooltip_text = l.tooltip_text


func _add_extra_row(rec: Dictionary, extra: Dictionary) -> void:
	var key: String = extra["key"]
	var kind: String = extra["kind"]
	var l := Label.new()
	l.text = key + " *"
	l.modulate = Color(0.6, 0.75, 1.0)
	l.tooltip_text = "脚本未声明的额外属性"
	_editors_grid.add_child(l)

	if kind == "opaque":
		var rl := Label.new()
		rl.text = extra["raw"]
		rl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_editors_grid.add_child(rl)
		return

	var le := LineEdit.new()
	le.text = str(extra["value"])
	le.text_submitted.connect(func(_t): _commit_extra(key))
	le.focus_exited.connect(func(): _commit_extra(key))
	_editors_grid.add_child(le)
	_extra_editors[key] = le


# ============================================================
# 编辑器提交（内存缓冲，不写盘）
# ============================================================

func _has_selection() -> bool:
	return not _selected.is_empty() and _selected.get("res") != null


func _commit_enum(nm: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var opt: OptionButton = _editors[nm]
	Core.set_value(_selected["res"], _prop_by_name[nm], int(opt.get_item_metadata(opt.selected)))
	_mark_dirty(nm)


func _commit_bool(nm: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var cb: CheckBox = _editors[nm]
	Core.set_value(_selected["res"], _prop_by_name[nm], cb.button_pressed)
	_mark_dirty(nm)


func _commit_int(nm: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var sb: SpinBox = _editors[nm]
	Core.set_value(_selected["res"], _prop_by_name[nm], int(sb.value))
	_mark_dirty(nm)


func _commit_float(nm: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var sb: SpinBox = _editors[nm]
	Core.set_value(_selected["res"], _prop_by_name[nm], sb.value)
	_mark_dirty(nm)


func _commit_string(nm: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var le: LineEdit = _editors[nm]
	Core.set_value(_selected["res"], _prop_by_name[nm], le.text)
	_mark_dirty(nm)


func _commit_resource_path(nm: String, p: String) -> void:
	if not _has_selection():
		return
	var t := p.strip_edges()
	if t == "":
		Core.set_value(_selected["res"], _prop_by_name[nm], null)
		_mark_dirty(nm)
		return
	if not ResourceLoader.exists(t):
		_log("资源不存在: " + t, true)
		return
	var r = load(t)
	if r == null:
		_log("加载失败: " + t, true)
		return
	Core.set_value(_selected["res"], _prop_by_name[nm], r)
	_mark_dirty(nm)


func _commit_array(nm: String, kind: String) -> void:
	if not _has_selection() or not _editors.has(nm):
		return
	var le: LineEdit = _editors[nm]
	var vals := _text_to_array(kind, le.text)
	if vals == null:
		return
	Core.set_value(_selected["res"], _prop_by_name[nm], vals)
	_mark_dirty(nm)


func _commit_extra(key: String) -> void:
	if not _has_selection() or not _extra_editors.has(key):
		return
	var le: LineEdit = _extra_editors[key]
	var extra = _find_extra(key)
	if extra == null:
		return
	var t := le.text.strip_edges()
	match extra["kind"]:
		"int":
			if t.is_valid_int():
				extra["value"] = t.to_int()
		"float":
			if t.is_valid_float():
				extra["value"] = t.to_float()
		"bool":
			extra["value"] = t.to_lower() in ["true", "1", "yes"]
		"string":
			extra["value"] = le.text
	_selected["dirty"] = true
	_refresh_item(_selected)


func _mark_dirty(_nm: String) -> void:
	if _selected.is_empty():
		return
	_selected["dirty"] = true
	_refresh_item(_selected)


func _find_extra(key: String):
	for e in _selected.get("extra", []):
		if e["key"] == key:
			return e
	return null


# ============================================================
# 工具栏动作
# ============================================================

func _on_new_record() -> void:
	if _current_type == "":
		_log("请先选择数据类型。", true)
		return
	if _schema.get("script_path", "") == "":
		_log(_schema.get("error", "无法确定数据结构。"), true)
		return
	_new_record_edit.text = ""
	_new_record_dialog.popup_centered()


func _on_new_record_confirmed() -> void:
	var base := _sanitize_base_name(_new_record_edit.text)
	if base == "":
		base = "new_record"
	base = _unique_base(base)
	var rec = Core.new_record(_current_type, _schema, base)
	_assign_record_id(rec, _next_record_id, true)
	_next_record_id += 1
	_records.append(rec)
	_sort_records_by_id()
	_selected = rec
	_build_tree()
	_build_editors(rec)
	var item: TreeItem = rec.get("_item")
	if item != null:
		item.select(0)
	_log("已新建数据 [%s]（尚未写入磁盘）。" % base)


func _on_delete_record() -> void:
	if _selected.is_empty():
		_log("请先在表格中选中要删除的记录。", true)
		return
	var base: String = _selected["base_name"]
	if _selected.get("is_new", false):
		_records.erase(_selected)
		_selected = {}
	else:
		_selected["deleted"] = true
	_build_tree()
	_build_editors({})
	_log("已标记删除 [%s]（点击【确认保存】后才会删除文件）。" % base)


func _on_refresh() -> void:
	_log("刷新中…")
	_load_current_type()


func _on_save() -> void:
	var saved := 0
	var deleted := 0
	var failed := 0
	var to_remove: Array = []
	for rec in _records:
		if rec.get("deleted", false):
			Core.delete_record_file(rec["path"])
			deleted += 1
			to_remove.append(rec)
		elif rec.get("dirty", false) or rec.get("id_pending", false):
			var r = Core.save_record(rec, _schema)
			if r["ok"]:
				saved += 1
			else:
				failed += 1
				_log(r["error"], true)
	for rec in to_remove:
		_records.erase(rec)

	# 即使中间出现保存失败，也推进计数器而不复用已经发放过的号码；最多只会留下安全的编号空档。
	var counter_error := Core.write_next_record_id(_current_type, _next_record_id)
	if counter_error != OK:
		failed += 1
		_log("ID 计数器保存失败: %s" % error_string(counter_error), true)

	EditorInterface.get_resource_filesystem().scan()
	_log("确认保存完成：保存 %d 条，删除 %d 条，失败 %d 条。" % [saved, deleted, failed])
	_load_current_type()


func _on_add_type() -> void:
	_new_type_edit.text = ""
	_new_type_dialog.popup_centered()


func _on_new_type_confirmed() -> void:
	var name := _new_type_edit.text.strip_edges()
	var err := Core.create_type(name)
	if err != "":
		_log(err, true)
		return
	EditorInterface.get_resource_filesystem().scan()
	_log("已新增数据类型 [%s]，并生成结构脚本。" % name)
	_rebuild_tabs(name)


# ============================================================
# 类型判断与转换
# ============================================================

## 根据字段反射信息选择详情编辑控件。prop 是结构脚本的字段描述；返回编辑器类别名称。
## 资源数组必须走拖拽列表而不是文本框，否则玩家只是切换焦点就可能把技能 Resource 引用变成无效文本。
func _prop_editor_kind(prop: Dictionary) -> String:
	var hint: int = prop["hint"]
	var type: int = prop["type"]
	if hint == PROPERTY_HINT_ENUM:
		return "enum"
	match type:
		TYPE_BOOL:
			return "bool"
		TYPE_INT:
			return "int"
		TYPE_FLOAT:
			return "float"
		TYPE_STRING:
			return "string"
		TYPE_OBJECT:
			return "scene" if prop["hint_string"] == "PackedScene" else "resource"
		TYPE_ARRAY:
			var hs: String = prop["hint_string"]
			if hs.begins_with("2:"):
				return "int_array"
			if hs.begins_with("3:"):
				return "float_array"
			if hs.begins_with("4:"):
				return "string_array"
			# Godot 不同版本给类型化数组的 hint_string 格式可能不同；同时检查源码注解，
			# 才不会把 Array[SkillBase] 误当作普通文本数组，进而在失焦保存时清空技能引用。
			if hs.begins_with("24") or _is_resource_array_annotation(str(prop.get("annotation", ""))):
				return "resource_array"
			return "plain_array"
	return "readonly"


## 判断 Array[...] 的元素类型是否为 Resource。annotation 是结构脚本中读取到的类型注解；返回 true 表示应使用资源拖拽列表。
## 全局脚本类和 Godot 原生 Resource 子类都会识别，避免随着 Godot 的 hint_string 格式变化而把资源当文本处理。
func _is_resource_array_annotation(annotation: String) -> bool:
	if not annotation.begins_with("Array[") or not annotation.ends_with("]"):
		return false
	var element_type := annotation.trim_prefix("Array[").trim_suffix("]").strip_edges()
	if element_type == "":
		return false

	# Resource、PackedScene 等 Godot 内置资源类可以直接通过 ClassDB 判断继承关系。
	if ClassDB.class_exists(element_type):
		return element_type == "Resource" or ClassDB.is_parent_class(element_type, "Resource")

	# SkillBase、UnitData 这类项目脚本类不在 ClassDB 中，需要从 Godot 登记的全局类列表读取其基类。
	for global_class in ProjectSettings.get_global_class_list():
		if str(global_class.get("class", "")) != element_type:
			continue
		var base_type := str(global_class.get("base", ""))
		return base_type == "Resource" or (ClassDB.class_exists(base_type) and ClassDB.is_parent_class(base_type, "Resource"))
	return false


func _describe_prop(prop: Dictionary) -> String:
	match _prop_editor_kind(prop):
		"enum":
			return "枚举: " + ", ".join(Core.enum_options(prop))
		"scene":
			return "PackedScene"
		"resource":
			var hs: String = prop["hint_string"]
			return hs if hs != "" else "Resource"
		"int_array":
			return "Array[int]"
		"float_array":
			return "Array[float]"
		"string_array":
			return "Array[String]"
		"resource_array":
			return "Array[Resource]"
		_:
			return _prop_editor_kind(prop)


func _array_to_text(kind: String, val) -> String:
	if not (val is Array):
		return ""
	var parts: Array[String] = []
	match kind:
		"resource_array":
			for e in val:
				parts.append(e.resource_path if e is Resource else str(e))
		_:
			for e in val:
				parts.append(str(e))
	return ", ".join(parts)


func _text_to_array(kind: String, text: String) -> Variant:
	var out: Array = []
	match kind:
		"int_array":
			for tok in text.split(","):
				var t := tok.strip_edges()
				if t == "":
					continue
				if not t.is_valid_int():
					_log("数组含非法整数: " + t, true)
					return null
				out.append(t.to_int())
		"float_array":
			for tok in text.split(","):
				var t := tok.strip_edges()
				if t == "":
					continue
				if not t.is_valid_float():
					_log("数组含非法小数: " + t, true)
					return null
				out.append(t.to_float())
		"string_array", "plain_array":
			for tok in text.split(","):
				var t := tok.strip_edges()
				if t != "":
					out.append(t)
		"resource_array":
			for tok in text.split(","):
				var t := tok.strip_edges()
				if t == "":
					continue
				if not ResourceLoader.exists(t):
					_log("资源不存在: " + t, true)
					return null
				out.append(load(t))
	return out


# ============================================================
# 工具
# ============================================================

func _sanitize_base_name(s: String) -> String:
	var t := s.get_file().get_basename()
	var re := RegEx.new()
	re.compile("[\\\\/:*?\"<>|\\s]+")
	return re.sub(t, "_", true)


func _unique_base(base: String) -> String:
	var folder_path := Core.DATA_DIR.path_join(_current_type)
	var candidate := base
	var i := 2
	while FileAccess.file_exists(folder_path.path_join(candidate + ".tres")):
		candidate = base + "_" + str(i)
		i += 1
	return candidate


func _hsep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 6)
	return s


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


func _make_spin(minv: float, maxv: float, step: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = minv
	sb.max_value = maxv
	sb.step = step
	sb.value = val
	sb.allow_greater = true
	sb.allow_lesser = true
	sb.custom_minimum_size.x = 140
	return sb


func _log(msg: String, is_error := false) -> void:
	if _log_edit == null:
		return
	var line := ("[color=#ff8888]" if is_error else "[color=#a8d8a8]") + msg + "[/color]"
	_log_edit.append_text(line + "\n")
