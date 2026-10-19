# 这玩意儿是干嘛的（核心逻辑）：整理目录后让 Godot 真正加载资源，找出文本检查发现不了的断链。
# 数据是咋流动的（数据流向）：递归扫描项目 → 加载脚本和场景 → 检查可实例化 → 输出检查结果。
# 为啥这么写（选型决策）：实际资源加载同时验证 UID、继承与脚本类型，比只查字符串更可靠。
# 性能咋样（复杂度）：只在手动验证时逐个检查，不进入正式游戏流程。
extends SceneTree

var checked := 0
var failures: Array[String] = []


# 作用：Godot 初始化后延迟执行，等待自动加载完成；没有参数，没有返回值。
func _initialize() -> void:
	_run.call_deferred()


# 作用：运行全部资源检查；没有参数，没有返回值。
func _run() -> void:
	_scan("res://")
	# 数据表插件依赖“每个配置目录内有资源结构脚本”，搬家后也必须能识别。
	var core = load("res://addons/data_table_editor/core.gd")
	var expected := {"units": "UnitData", "skills": "SkillBase", "cards": "CardDefinition",
		"card_effects": "CardEffect", "levels": "BattleLevelConfig", "run": "RunStartData",
		"relics": "RelicDefinition", "potions": "PotionDefinition"}
	for folder in expected:
		var schema: Dictionary = core.detect_schema(folder)
		if schema.class_name != expected[folder] or not schema.error.is_empty():
			failures.append("数据表结构识别失败：" + folder)
	print("RESOURCE_LOAD_CHECK: ", checked, " resources; failures=", failures)
	quit(0 if failures.is_empty() else 1)


# 作用：递归加载可用资源；path 为待检查目录，没有返回值。
func _scan(path: String) -> void:
	# 原画工具、备份等带 .gdignore 的内容不属于游戏资源。
	if FileAccess.file_exists(path.path_join(".gdignore")):
		return
	for folder in DirAccess.get_directories_at(path):
		if not folder.begins_with("."):
			_scan(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		if file.get_extension() not in ["gd", "tscn", "tres", "gdshader"]:
			continue
		var resource_path := path.path_join(file)
		var resource := load(resource_path)
		checked += 1
		if resource == null:
			failures.append(resource_path)
		elif resource is Script and not resource.can_instantiate():
			failures.append(resource_path)
		elif resource is PackedScene:
			# 不加入运行树，只验证场景装配，避免启动界面和战斗逻辑。
			var instance: Node = resource.instantiate()
			if instance == null:
				failures.append(resource_path)
			else:
				instance.free()
