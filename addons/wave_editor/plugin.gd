# 这玩意儿是干嘛的（核心逻辑）：在 Godot 顶部增加波次编辑器入口。
# 数据是咋流动的（数据流向）：插件启用 → 创建面板 → 操作面板保存关卡资源。
# 为啥这么写（选型决策）：主屏幕有足够空间同时放回合列表和战场。
# 性能咋样（复杂度）：启用时创建一次；退出或禁用时检查草稿，完成保存决定后释放。
@tool
extends EditorPlugin

var panel: Control

# 作用：引擎启用插件时创建主屏幕；没有参数，没有返回值。
func _enter_tree() -> void:
	panel = preload("res://addons/wave_editor/editor.gd").new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)

# 作用：引擎关闭插件时释放面板；没有参数，没有返回值。
func _exit_tree() -> void:
	if is_instance_valid(panel) and not panel.orphaned:
		panel.free()

# 作用：禁用插件时保留面板直到保存决定结束；没有参数，没有返回值。
func _disable_plugin() -> void:
	if is_instance_valid(panel):
		panel.preview.finish_drag()
	if is_instance_valid(panel) and panel.doc.is_dirty():
		panel.doc.write_recovery()
		panel.reparent(EditorInterface.get_base_control())
		panel.close_for_disable()

# 作用：Godot 退出项目时询问未保存状态；for_scene 为关闭场景路径，返回提醒文字或空。
func _get_unsaved_status(for_scene: String) -> String:
	if is_instance_valid(panel):
		panel.preview.finish_drag()
	if not for_scene.is_empty() or not is_instance_valid(panel) or not panel.doc.is_dirty():
		return ""
	if not panel.doc.write_recovery():
		return "波次草稿的恢复副本写入失败。请取消退出，先另存为可写路径。"
	return "波次编辑器有未保存修改：%s。未命名或发生磁盘冲突的草稿会保留恢复副本，下次启用时可恢复。" % (panel.doc.path if not panel.doc.path.is_empty() else "新关卡")

# 作用：Godot 保存全部或确认退出保存时写入关卡；没有参数，没有返回值。
func _save_external_data() -> void:
	if is_instance_valid(panel):
		panel.save_on_exit()

# 作用：告诉引擎这是主屏幕插件；没有参数，返回 true。
func _has_main_screen() -> bool:
	return true

# 作用：提供顶部入口名称；没有参数，返回显示名称。
func _get_plugin_name() -> String:
	return "波次编辑器"

# 作用：引擎切换顶部页签时控制显示；visible 为是否显示，没有返回值。
func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		panel.visible = visible
