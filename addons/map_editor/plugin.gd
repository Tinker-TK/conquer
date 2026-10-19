# 这玩意儿是干嘛的（核心逻辑）：在 Godot 顶部添加地图工坊，像波次编辑器一样编辑路线。
# 数据是咋流动的（数据流向）：启用插件 → 创建编辑面板 → 保存 JSON → 游戏读取地图。
# 为啥这么写（选型决策）：使用原生主屏幕，节点画布和属性区可以同时显示。
# 性能咋样（复杂度）：启用时创建一次，只在操作时更新，没有持续的游戏模拟。
@tool
extends EditorPlugin

var panel: Control

# 作用：引擎启用插件时建立主屏幕；没有参数，没有返回值。
func _enter_tree() -> void:
	panel = preload("res://addons/map_editor/editor.gd").new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)

# 作用：插件离开场景树时保存恢复副本并释放界面；没有参数，没有返回值。
func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.flush_input()
		panel.canvas.finish_drag()
		if panel.doc.is_dirty():
			panel.doc.write_recovery()
		panel.free()

# 作用：编辑器退出时报告未保存修改；for_scene 为待关闭场景，返回提示或空串。
func _get_unsaved_status(for_scene: String) -> String:
	if not is_instance_valid(panel) or not for_scene.is_empty():
		return ""
	panel.flush_input()
	panel.canvas.finish_drag()
	if not panel.doc.is_dirty():
		return ""
	if not panel.doc.write_recovery():
		return "地图恢复副本写入失败，请先另存为可写路径。"
	return "地图工坊有未保存修改；恢复副本已保留，下次打开可恢复。"

# 作用：Godot 保存全部或退出保存时保存地图；没有参数，没有返回值。
func _save_external_data() -> void:
	if is_instance_valid(panel):
		panel.save_on_exit()

# 作用：告诉 Godot 这是主屏幕；没有参数，返回 true。
func _has_main_screen() -> bool:
	return true

# 作用：提供顶部页签名称；没有参数，返回名称。
func _get_plugin_name() -> String:
	return "地图工坊"

# 作用：切换主屏幕时控制显示；visible 为是否显示，没有返回值。
func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		if not visible and panel.is_inside_tree() and is_instance_valid(panel.canvas):
			panel.flush_input()
			panel.canvas.finish_drag()
		elif visible and panel.is_inside_tree() and is_instance_valid(panel.canvas):
			panel._refresh_catalog()
		panel.visible = visible
