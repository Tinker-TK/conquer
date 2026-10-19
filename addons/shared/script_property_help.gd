@tool
extends RefCounted
## 将脚本的原生参数文档同步给配置工具；只读取源码，不实例化游戏对象。


## 获取脚本及其基类的参数说明，子类同名说明优先；script 为结构脚本。
static func descriptions(script: Script) -> Dictionary:
	var result: Dictionary = {}
	while script != null:
		result.merge(from_source(script.source_code), false)
		script = script.get_base_script()
	return result


## 从源码读取紧邻成员或导出注解的 ## 文档，兼容独占一行的导出注解。
static func from_source(source: String) -> Dictionary:
	var result: Dictionary = {}
	var notes: Array[String] = []
	var member := RegEx.new()
	member.compile("(?:^|\\s)var\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for raw_line in source.split("\n"):
		var line := raw_line.strip_edges()
		if line.begins_with("##"):
			notes.append(line.substr(2).strip_edges())
			continue
		var found := member.search(line)
		if found != null and not notes.is_empty():
			result[found.get_string(1)] = " ".join(notes).replace("[br]", "\n")
		elif line.begins_with("@") and not line.begins_with("@export_group") and not line.begins_with("@export_subgroup") and not line.begins_with("@export_category"):
			continue
		notes.clear()
	return result
