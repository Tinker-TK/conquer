# 这玩意儿是干嘛的（核心逻辑）：让 Godot 配置面板使用已有的校验和备份工具，读取和保存实际资源。
# 数据是咋流动的（数据流向）：草稿 JSON → 本机 Python 工具 → Godot 回读验证 → JSON 结果返回面板。
# 为啥这么写（选型决策）：沿用 HTML 工具的同一套保存规则，避免两套工具对配置产生不同解释。
# 性能咋样（复杂度）：工具在工作线程执行，读取和保存期间界面仍可响应，空闲时不启动进程。
@tool
extends RefCounted

var python := ""
var thread: Thread
var temporary: Array[String] = []
var project_path := ProjectSettings.globalize_path("res://")
var godot_path := OS.get_executable_path()

# 作用：寻找本机可用 Python；没有参数，返回默认路径或 python 命令。
func default_python() -> String:
	var bundled := OS.get_environment("USERPROFILE").path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
	return bundled if FileAccess.file_exists(bundled) else "python"

# 作用：判断是否有读写任务尚未完成；没有参数，返回忙碌状态。
func is_busy() -> bool:
	return thread != null

# 作用：开始后台读写；command 是 editor-read/check/apply，document 是草稿，返回是否成功启动。
func start(command: String, document: Dictionary = {}) -> bool:
	if is_busy():
		return false
	var args := _arguments(command, document)
	if args.is_empty():
		return false
	thread = Thread.new()
	var started := thread.start(_worker.bind(args))
	if started != OK:
		thread = null
		_cleanup()
		return false
	return true

# 作用：获取后台结果；wait 为是否等待完成，返回结果或空字典。
func finish(wait: bool = false) -> Dictionary:
	if thread == null or (thread.is_alive() and not wait):
		return {}
	var result: Dictionary = thread.wait_to_finish()
	thread = null
	_cleanup()
	return result

# 作用：在保存全部或退出保存时等待写完；command 为命令，document 为草稿，返回结果。
func run_sync(command: String, document: Dictionary) -> Dictionary:
	var args := _arguments(command, document)
	if args.is_empty():
		return {"ok": false, "error": "临时草稿写入失败，请导出合集。"}
	var result := _worker(args)
	_cleanup()
	return result

# 作用：建立进程参数和临时文件；command 为命令，document 为草稿，返回独立参数列表。
func _arguments(command: String, document: Dictionary) -> PackedStringArray:
	var folder := ProjectSettings.globalize_path("user://game_config_bridge")
	DirAccess.make_dir_recursive_absolute(folder)
	var key := str(Time.get_ticks_usec())
	var output := folder.path_join(key + "_result.json")
	var args := PackedStringArray([project_path.path_join("tools/config_catalog/catalog.py"), command])
	if command != "editor-read":
		var input := folder.path_join(key + "_draft.json")
		var file := FileAccess.open(input, FileAccess.WRITE)
		if file == null:
			return PackedStringArray()
		file.store_string(JSON.stringify(document))
		file.close()
		temporary.append(input)
		args.append(input)
	args.append_array(["--result", output, "--project", project_path, "--godot", godot_path])
	temporary.append(output)
	return args

# 作用：执行本机工具；args 为独立参数列表，返回可显示的结果，在线程中不触碰界面。
func _worker(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute(python if not python.is_empty() else default_python(), args, output, true, false)
	var result_path := args[args.find("--result") + 1]
	if FileAccess.file_exists(result_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
		if parsed is Dictionary and parsed.has("ok"):
			return parsed
	return {"ok": false, "error": "配置工具执行失败（%s）。请检查 Python 路径。\n%s" % [code, "\n".join(output).right(4000)]}

# 作用：读写完成后清理本工具临时文件；没有参数，没有返回值。
func _cleanup() -> void:
	for path in temporary:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	temporary.clear()
