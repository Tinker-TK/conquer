# 这玩意儿是干嘛的（核心逻辑）：在 Godot 顶部加入游戏配置页签，和波次编辑器并列。
# 数据是咋流动的（数据流向）：启用插件 → 原生配置面板 → 独立草稿 → 经过保护的资源写回。
# 为啥这么写（选型决策）：主屏幕能容纳横向表格；保存全部和退出提醒使用 Godot 原生接口。
# 性能咋样（复杂度）：插件启用时建立一次界面；关闭时等待已有读写任务并保存恢复草稿。
@tool
extends EditorPlugin

var panel: Control

# 作用：Godot 启用插件时创建主屏幕；没有参数，没有返回值。
func _enter_tree() -> void:
	panel = preload("res://addons/game_config_editor/editor.gd").new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_make_visible(false)

# 作用：Godot 禁用或关闭插件时保留草稿并释放面板；没有参数，没有返回值。
func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.shutdown()
		panel.free()

# 作用：Godot 关闭项目前报告未保存内容；for_scene 为关闭的场景，返回提醒或空字符串。
func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or not is_instance_valid(panel):
		return ""
	panel.flush_input()
	if panel.bridge.is_busy():
		return "游戏配置工具正在读写，请等待完成；草稿会保留。"
	if not panel.doc.is_dirty():
		return ""
	if not panel.doc.write_recovery():
		return "游戏配置草稿恢复文件写入失败。请取消退出，先导出 HTML 或 JSON。"
	return "游戏配置有未保存修改；退出保存会校验并应用，冲突或无效配置会保留草稿供下次恢复。"

# 作用：Godot 保存全部或确认退出保存时应用配置；没有参数，没有返回值。
func _save_external_data() -> void:
	if is_instance_valid(panel):
		panel.save_on_exit()

# 作用：声明这是主屏幕插件；没有参数，返回 true。
func _has_main_screen() -> bool:
	return true

# 作用：提供顶部页签名称；没有参数，返回名称。
func _get_plugin_name() -> String:
	return "游戏配置"

# 作用：Godot 切换页签时控制显示；visible 为是否可见，没有返回值。
func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		if not visible and panel.is_inside_tree():
			panel.flush_input()
		panel.visible = visible
