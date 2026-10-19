# 运行中的配置资源共用一份引用，避免校验、奖励快照和商品池重复加载依赖。
# 菜单读取路线时检查小型配置文件的内容；发生变化才清理缓存，当前本局快照保持独立。
@tool
extends RefCounted

static var _resources: Dictionary = {}
static var _revision := ""
static var _reload_dependencies := false


# 内容摘要也能识别同一秒内的保存；不在游戏帧循环中扫描。
static func refresh() -> String:
	if Engine.is_editor_hint():
		return ""
	var fingerprints: Array[String] = []
	_collect_fingerprints("res://data", fingerprints)
	_collect_fingerprints("res://scenes/levels", fingerprints)
	fingerprints.sort()
	var current := "\n".join(fingerprints).md5_text()
	if not _revision.is_empty() and current != _revision:
		_resources.clear()
		_reload_dependencies = true
	_revision = current
	return current


static func _collect_fingerprints(directory: String, result: Array[String]) -> void:
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["tres", "json", "gd", "tscn"]:
			var path := directory.path_join(file)
			result.append(path + ":" + FileAccess.get_md5(path))
	for child in DirAccess.get_directories_at(directory):
		_collect_fingerprints(directory.path_join(child), result)


static func resource(path: String) -> Resource:
	if Engine.is_editor_hint():
		return load(path)
	# 发行包可能只保留 .remap；没有源文件时使用固定的空摘要。
	var fingerprint := FileAccess.get_md5(path) if FileAccess.file_exists(path) else ""
	var cached: Dictionary = _resources.get(path, {})
	if not cached.is_empty() and cached.fingerprint == fingerprint:
		return cached.value
	# 编辑后读独立资源及依赖，避免替换仍在本局使用的旧配方。
	var mode := ResourceLoader.CACHE_MODE_IGNORE_DEEP if _reload_dependencies or not cached.is_empty() else ResourceLoader.CACHE_MODE_REUSE
	var value := ResourceLoader.load(path, "", mode)
	if value != null:
		_resources[path] = {"fingerprint": fingerprint, "value": value}
	return value


static func directory_fingerprint(paths: Array[String]) -> String:
	var entries: Array[String] = [_revision]
	for path in paths:
		entries.append(path + ":" + (FileAccess.get_md5(path) if FileAccess.file_exists(path) else ""))
	return "\n".join(entries).md5_text()
