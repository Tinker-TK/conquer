@tool
extends EditorPlugin
## 数据表格编辑器插件入口。
## 在编辑器右侧底部添加一个 Dock 面板，以类 Excel 表格管理 data/ 下的数据。

const DOCK_SCENE := preload("res://addons/data_table_editor/ui/data_table_dock.gd")

var dock: Control


func _enter_tree() -> void:
	dock = DOCK_SCENE.new()
	dock.name = "数据表格编辑器"
	add_control_to_dock(DockSlot.DOCK_SLOT_RIGHT_BL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
