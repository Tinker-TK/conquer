# 在 2D 工具栏切换关卡 UI；偏好保存在本机编辑器设置中。
@tool
extends EditorPlugin

const PreviewVisibility = preload("res://addons/level_ui_preview/preview_visibility.gd")
const SETTINGS_SECTION := "level_ui_preview"

var preview := PreviewVisibility.new()
var button: Button
var refresh_pending := false


func _enter_tree() -> void:
	preview.hidden = EditorInterface.get_editor_settings().get_project_metadata(SETTINGS_SECTION, "hidden", true)
	button = Button.new()
	button.text = "隐藏关卡 UI"
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "仅隐藏编辑器里的 CardUI 和 GameOver；运行游戏无需恢复。\nCtrl+Alt+U 切换，取消勾选即可编辑 UI。"
	var key := InputEventKey.new()
	key.keycode = KEY_U
	key.ctrl_pressed = true
	key.alt_pressed = true
	button.shortcut = Shortcut.new()
	button.shortcut.events = [key]
	button.toggled.connect(_on_toggled)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, button)
	scene_changed.connect(_on_scene_changed)
	get_tree().tree_changed.connect(_queue_refresh)
	# 控件属性变化可能重置绘制状态，在绘制前重新应用预览隐藏。
	RenderingServer.frame_pre_draw.connect(preview.apply)
	_queue_refresh()


func _on_scene_changed(_scene: Node) -> void:
	_queue_refresh()


func _queue_refresh() -> void:
	if refresh_pending:
		return
	refresh_pending = true
	_refresh.call_deferred()


func _refresh() -> void:
	refresh_pending = false
	if not is_inside_tree():
		return
	preview.set_scene(EditorInterface.get_edited_scene_root())
	button.visible = not preview.items.is_empty()
	button.set_pressed_no_signal(preview.hidden)


func _on_toggled(value: bool) -> void:
	preview.set_hidden(value)
	EditorInterface.get_editor_settings().set_project_metadata(SETTINGS_SECTION, "hidden", value)


func _exit_tree() -> void:
	if get_tree().tree_changed.is_connected(_queue_refresh):
		get_tree().tree_changed.disconnect(_queue_refresh)
	if RenderingServer.frame_pre_draw.is_connected(preview.apply):
		RenderingServer.frame_pre_draw.disconnect(preview.apply)
	preview.restore()
	preview.items.clear()
	if is_instance_valid(button):
		remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, button)
		button.free()
