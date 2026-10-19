# 这玩意儿是干嘛的（核心逻辑）：读取游戏实际资源，导出策划配置合集的数据和字段说明。
# 数据是咋流动的（数据流向）：Godot 加载资源及默认值 → 导出字段和关联资源 → 本地 HTML 编辑器。
# 为啥这么写（选型决策）：由引擎读取默认值和枚举，避免页面展示的配置与游戏不一致。
# 性能咋样（复杂度）：仅工具启动时扫描指定数据目录，不参与游戏运行。
extends SceneTree

const PROPERTY_HELP = preload("res://addons/shared/script_property_help.gd")
var records: Dictionary = {}

# 作用：引擎启动后延迟导出，等待全局节点就绪；没有参数，没有返回值。
func _initialize() -> void:
	_export.call_deferred()

# 作用：遍历游戏配置并写到参数指定的 JSON 文件；没有参数，没有返回值。
func _export() -> void:
	for folder in ["cards", "units", "skills", "relics", "potions"]:
		var directory: String = "res://data/" + folder
		for file in DirAccess.get_files_at(directory):
			if file.ends_with(".tres"):
				_visit(load(directory.path_join(file)))
	var output := OS.get_cmdline_user_args()[0]
	var handle := FileAccess.open(output, FileAccess.WRITE)
	if handle == null:
		quit(1)
		return
	handle.store_string(JSON.stringify({"records": records.values(), "bindings": _scene_bindings()}, "\t"))
	handle.close()
	print("CONFIG_CATALOG_EXPORT_PASS")
	quit()

# 作用：收录 resource 的可编辑字段，并继续读取关联的技能或效果；没有返回值。
func _visit(resource: Resource) -> void:
	if resource == null or resource.get_script() == null:
		return
	var script_path: String = resource.get_script().resource_path
	if not (script_path.begins_with("res://data/") or script_path.begins_with("res://scripts/skills/")):
		return
	var key := resource.resource_path
	if records.has(key):
		return
	var record := {"id": key, "script": script_path, "fields": []}
	records[key] = record
	var descriptions: Dictionary = PROPERTY_HELP.descriptions(resource.get_script())
	# 只导出脚本向 Inspector 公开的字段，内置资源状态不会成为策划配置。
	for info in resource.get_property_list():
		if not (info.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (info.usage & PROPERTY_USAGE_EDITOR):
			continue
		var value: Variant = resource.get(info.name)
		var field := {"name": info.name, "type": info.type, "hint": info.hint, "hint_string": info.hint_string, "editable": true, "description": descriptions.get(str(info.name), "")}
		match typeof(value):
			TYPE_NIL:
				field.value = null
				field.editable = false
			TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
				field.value = value
			TYPE_STRING_NAME, TYPE_NODE_PATH:
				field.value = str(value)
			TYPE_VECTOR2:
				field.value = [value.x, value.y]
			TYPE_OBJECT:
				field.value = value.resource_path if value is Resource else str(value)
				field.editable = false
				if value is Resource:
					_visit(value)
			TYPE_ARRAY:
				field.value = []
				field.array_type = value.get_typed_builtin()
				for item in value:
					if item is Resource:
						field.value.append(item.resource_path)
						field.editable = false
						_visit(item)
					else:
						field.value.append(item)
				if field.array_type not in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
					field.editable = false
			_:
				field.value = str(value)
				field.editable = false
		record.fields.append(field)

# 作用：读取单位场景的技能和动画关联，用于检查策划输入的动画名和命中帧；没有参数，返回关联列表。
func _scene_bindings() -> Array:
	var result: Array = []
	for file in DirAccess.get_files_at("res://scenes/units"):
		if not file.ends_with(".tscn"):
			continue
		var scene_path := "res://scenes/units/" + file
		var packed := load(scene_path) as PackedScene
		var state := packed.get_state()
		var unit: Resource = null
		var frames: SpriteFrames = null
		# 只读打包场景，不实例化，不会运行单位的战斗逻辑。
		for node in state.get_node_count():
			for property in state.get_node_property_count(node):
				var key := state.get_node_property_name(node, property)
				if node == 0 and key == &"unit_data":
					unit = state.get_node_property_value(node, property)
				if state.get_node_name(node) == &"AnimatedSprite2D" and key == &"sprite_frames":
					frames = state.get_node_property_value(node, property)
		if unit == null or frames == null:
			continue
		var binding := {"scene": scene_path, "unit": unit.resource_path, "skills": [], "animations": {}}
		for skill in unit.get("skills"):
			if skill != null:
				binding.skills.append(skill.resource_path)
		var dodge: Variant = unit.get("dodge_skill")
		if dodge != null:
			binding.skills.append(dodge.resource_path)
		for animation in frames.get_animation_names():
			binding.animations[animation] = {"frames": frames.get_frame_count(animation), "loop": frames.get_animation_loop(animation)}
		result.append(binding)
	return result
