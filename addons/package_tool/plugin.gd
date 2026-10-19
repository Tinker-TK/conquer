@tool
extends EditorPlugin

var button: Button
var panel: AcceptDialog

func _enter_tree() -> void:
	panel = preload("res://addons/package_tool/panel.gd").new()
	EditorInterface.get_base_control().add_child(panel)
	button = Button.new()
	button.text = "一键打包"
	button.tooltip_text = "选择 Windows 或 Mac，生成可发给朋友的 ZIP"
	button.pressed.connect(_show_panel)
	add_control_to_container(CONTAINER_TOOLBAR, button)
	add_tool_menu_item("一键打包…", _show_panel)

func _show_panel() -> void:
	panel.popup_centered(Vector2i(720, 460))

func _get_unsaved_status(for_scene: String) -> String:
	if for_scene.is_empty() and is_instance_valid(panel) and panel.is_busy():
		return "正在打包。关闭编辑器会等待当前打包完成；输出和日志会保留。"
	return ""

func _exit_tree() -> void:
	remove_tool_menu_item("一键打包…")
	if is_instance_valid(button):
		remove_control_from_container(CONTAINER_TOOLBAR, button)
		button.free()
	if is_instance_valid(panel):
		panel.shutdown()
		panel.free()
