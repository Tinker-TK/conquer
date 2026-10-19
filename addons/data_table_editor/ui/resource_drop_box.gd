# 这玩意儿是干嘛的（核心逻辑）：这是数据表里的单文件输入框，允许玩家拖入、浏览或清空一个 Resource、PackedScene 或 GDScript 路径。
# 数据是咋流动的（数据流向）：表格先把已有路径交给 set_path，控件进入场景树后再显示；玩家修改路径时通过 changed 信号把新值送回数据记录。
# 为啥这么写（选型决策）：用一个待显示字符串跨过 Godot 的节点初始化阶段，避免 LineEdit 尚未创建时就访问它；不需要额外的延迟调用或计时器。
# 性能咋样（复杂度）：每次选择记录只保存和显示一条短路径，拖拽时只检查少量文件扩展名，不会产生持续性能开销。
@tool
class_name ResourceDropBox
extends HBoxContainer
## 单个 Resource / PackedScene / GDScript 字段的拖拽配置框。
## 像 Godot 原生检查器一样，把资源、场景或脚本文件直接拖进来即可配置，
## 也支持手动输入路径、点「…」浏览选择、点「×」清空。

const Core := preload("res://addons/data_table_editor/core.gd")

signal changed(path: String)

var _edit: LineEdit
var _file_dialog: FileDialog
var _is_scene := false
var _is_script := false
var _pending_path := ""


## 当控件进入场景树时由 Godot 调用。没有参数，也没有返回值。
## 这里才创建 LineEdit，并把表格较早传入的待显示路径补上，避免访问空对象。
func _ready() -> void:
	custom_minimum_size.y = 28

	var hint := Label.new()
	hint.text = "⬇"
	hint.tooltip_text = "把资源、场景或脚本文件拖到此处"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)

	_edit = LineEdit.new()
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.placeholder_text = "拖入或输入 res:// 路径（留空 = 空）"
	_edit.text_submitted.connect(func(_t): changed.emit(_edit.text))
	_edit.focus_exited.connect(func(): changed.emit(_edit.text))
	add_child(_edit)
	_edit.text = _pending_path

	var browse := Button.new()
	browse.text = "…"
	browse.tooltip_text = "浏览选择"
	browse.pressed.connect(_on_browse)
	add_child(browse)

	var clear := Button.new()
	clear.text = "×"
	clear.tooltip_text = "清空"
	clear.pressed.connect(_on_clear)
	add_child(clear)

	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_RESOURCES
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_on_file_selected)
	add_child(_file_dialog)


## 设置这个输入框是否只接收场景。v 为 true 时接受 .tscn；没有返回值。
func set_is_scene(v: bool) -> void:
	_is_scene = v
	if v:
		_is_script = false


## 设置这个输入框是否只接收脚本。v 为 true 时接受 .gd；没有返回值。
func set_is_script(v: bool) -> void:
	_is_script = v
	if v:
		_is_scene = false


## 设置输入框要显示的资源路径。p 是 res:// 路径或空字符串；没有返回值。
## 表格可能在 _ready 之前调用本函数，所以先保存路径，等 LineEdit 创建后再安全地显示。
func set_path(p: String) -> void:
	_pending_path = p
	if is_instance_valid(_edit):
		_edit.text = p


## 点击浏览按钮时调用。没有参数，也没有返回值；根据当前用途只显示允许绑定的文件类型。
func _on_browse() -> void:
	if _is_script:
		_file_dialog.filters = PackedStringArray(["*.gd ; GDScript 脚本"])
	elif _is_scene:
		_file_dialog.filters = PackedStringArray(["*.tscn ; 场景文件"])
	else:
		_file_dialog.filters = PackedStringArray(["*.tres,*.res ; 资源文件"])
	_file_dialog.popup_centered_ratio(0.6)


func _on_file_selected(p: String) -> void:
	_edit.text = p
	changed.emit(p)


func _on_clear() -> void:
	_edit.text = ""
	changed.emit("")


func _can_drop_data(_at_position: Vector2, data) -> bool:
	return _first_accepted(Core.drag_paths(data)) != ""


func _drop_data(_at_position: Vector2, data) -> void:
	var p := _first_accepted(Core.drag_paths(data))
	if p == "":
		return
	_edit.text = p
	changed.emit(p)


## 从 paths 中寻找第一个符合当前用途的文件。paths 是拖入的文件路径；返回可接受路径，无匹配时返回空串。
func _first_accepted(paths: Array[String]) -> String:
	for p in paths:
		var ext := p.get_extension().to_lower()
		if _is_script:
			if ext == "gd":
				return p
		elif _is_scene:
			if ext == "tscn":
				return p
		else:
			if ext in ["tres", "res"]:
				return p
	return ""
