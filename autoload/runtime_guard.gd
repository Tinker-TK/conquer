# 不引用 Global 或领域类型，确保依赖脚本编译失败时仍能完成启动诊断。
extends Node


static func startup_errors(root: Node) -> Array[String]:
	var errors: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var key := String(property.name)
		if not key.begins_with("autoload/"):
			continue
		var path := String(ProjectSettings.get_setting(key)).trim_prefix("*")
		if not path.ends_with(".gd"):
			continue
		var node_name := key.trim_prefix("autoload/")
		var node := root.get_node_or_null(NodePath(node_name))
		var script: Script = node.get_script() if node != null else null
		if script == null or not script.can_instantiate():
			errors.append("%s 自动加载脚本不可用：%s" % [node_name, path])
	var global := root.get_node_or_null("Global")
	if global != null and global.get_script() != null:
		var has_phase := false
		for property: Dictionary in global.get_property_list():
			if property.name == "game_phase" and property.type == TYPE_INT:
				has_phase = true
		if not has_phase or not global.has_method("is_card_play_phase"):
			errors.append("Global 缺少阶段属性或阶段查询接口。")
	var bus := root.get_node_or_null("SignalBus")
	if bus != null and not bus.has_signal("phase_change"):
		errors.append("SignalBus 缺少 phase_change 信号。")
	return errors


func _ready() -> void:
	var errors := startup_errors(get_tree().root)
	if not errors.is_empty():
		push_error("RUNTIME_STARTUP_FAILED: " + "；".join(errors))
		get_tree().paused = true
		get_tree().quit(1)
