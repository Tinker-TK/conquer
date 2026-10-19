@tool
class_name ResourceListEditor
extends VBoxContainer
## 资源数组编辑器：像 Godot 原生检查器一样，用拖拽来配置 Array[Resource] 类型字段
## （例如 unitdata 的 skills: Array[SkillBase]）。
## 直接持有并修改目标数组的引用，任何增删/移动都会立即写回数组并发出 changed 信号。

const Core := preload("res://addons/data_table_editor/core.gd")

signal changed

var _array: Array = []
var _content: VBoxContainer
var _file_dialog: FileDialog


func _ready() -> void:
	custom_minimum_size.y = 64
	_content = VBoxContainer.new()
	add_child(_content)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_file_dialog.filters = PackedStringArray(["*.tres,*.res ; 资源文件"])
	_file_dialog.files_selected.connect(_on_files_selected)
	add_child(_file_dialog)

	_rebuild()


## 绑定要编辑的数组（资源对象上的类型化数组，按引用持有）。
func set_array(arr: Array) -> void:
	_array = arr
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()

	var hint := Label.new()
	hint.text = "⬇ 从 FileSystem 拖入 .tres/.res 资源到此处添加（或点下方「＋ 添加」）"
	hint.modulate = Color(0.6, 0.6, 0.6)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(hint)

	if _array != null:
		for i in _array.size():
			_content.add_child(_make_row(i))

	var add := Button.new()
	add.text = "＋ 添加"
	add.tooltip_text = "打开文件选择器批量添加资源"
	add.pressed.connect(_on_add_clicked)
	_content.add_child(add)


func _make_row(index: int) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var lbl := Label.new()
	lbl.text = _display(_array[index])
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	var up := Button.new()
	up.text = "↑"
	up.tooltip_text = "上移"
	up.pressed.connect(_on_move.bind(index, -1))
	var down := Button.new()
	down.text = "↓"
	down.tooltip_text = "下移"
	down.pressed.connect(_on_move.bind(index, 1))
	var del := Button.new()
	del.text = "×"
	del.tooltip_text = "移除"
	del.pressed.connect(_on_remove.bind(index))
	row.add_child(up)
	row.add_child(down)
	row.add_child(del)
	return row


func _display(r) -> String:
	if r is Resource:
		return r.resource_path if r.resource_path != "" else "<%s>" % r.get_class()
	return str(r)


func _on_remove(index: int) -> void:
	_array.remove_at(index)
	_rebuild()
	changed.emit()


func _on_move(index: int, delta: int) -> void:
	var ni := index + delta
	if ni < 0 or ni >= _array.size():
		return
	var tmp = _array[index]
	_array[index] = _array[ni]
	_array[ni] = tmp
	_rebuild()
	changed.emit()


func _on_add_clicked() -> void:
	_file_dialog.popup_centered_ratio(0.6)


func _on_files_selected(paths: PackedStringArray) -> void:
	for p in paths:
		_add_path(p)
	_rebuild()
	changed.emit()


## 把一条资源路径追加进数组；类型不匹配时数组本身会拒绝（保持类型安全）。
func _add_path(p: String) -> bool:
	if p.get_extension().to_lower() not in ["tres", "res"]:
		return false
	if not ResourceLoader.exists(p):
		return false
	var r = load(p)
	if r == null or not (r is Resource):
		return false
	_array.append(r)
	return true


func _can_drop_data(_at_position: Vector2, data) -> bool:
	return Core.drag_paths(data).size() > 0


func _drop_data(_at_position: Vector2, data) -> void:
	for p in Core.drag_paths(data):
		_add_path(p)
	_rebuild()
	changed.emit()
