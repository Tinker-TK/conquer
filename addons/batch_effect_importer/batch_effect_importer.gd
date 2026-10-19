@tool
extends EditorPlugin
## 批量特效导入插件入口。
## 在编辑器右侧底部添加一个 Dock 面板，负责批量重命名素材、
## 生成 SpriteFrames、并把动画导入到 AnimatedSprite2D。

const DOCK_SCENE := preload("res://addons/batch_effect_importer/ui/batch_effect_dock.gd")

var dock: Control


func _enter_tree() -> void:
	dock = DOCK_SCENE.new()
	dock.name = "批量特效导入"
	add_control_to_dock(DockSlot.DOCK_SLOT_RIGHT_BR, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
