@tool
extends EditorPlugin
var panel: Control

func _enter_tree() -> void:
	panel = preload("res://addons/event_editor/editor.gd").new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.hide()

func _exit_tree() -> void:
	if is_instance_valid(panel):
		panel.apply_inputs()
		panel.doc.recover_save()
		panel.free()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "事件工坊"

func _make_visible(visible: bool) -> void:
	if is_instance_valid(panel):
		if not visible:
			panel.apply_inputs()
		else:
			panel._scan()
		panel.visible = visible

func _get_unsaved_status(for_scene: String) -> String:
	if not is_instance_valid(panel) or not for_scene.is_empty():
		return ""
	panel.apply_inputs()
	if not panel.doc.is_dirty():
		return ""
	return "事件工坊有未保存修改，草稿已保留。" if panel.doc.recover_save() else "事件草稿保存失败，请先保存事件。"

func _save_external_data() -> void:
	if is_instance_valid(panel) and panel.doc.is_dirty():
		panel.apply_inputs()
		if not panel.doc.path.is_empty() and panel.doc.path != panel.doc.RECOVERY:
			panel._save_target(panel.doc.path)
		else:
			panel.doc.recover_save()
