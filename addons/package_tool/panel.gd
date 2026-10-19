@tool
extends AcceptDialog

const PACKAGER := "res://tools/packaging/package_game.py"
var platform_choice: OptionButton
var output_edit: LineEdit
var status_label: Label
var package_list: RichTextLabel
var start_button: Button
var open_button: Button
var choose_button: Button
var directory_dialog: FileDialog
var thread: Thread
var result_path := ""
var last_folder := ""
var last_progress := ""
var progress_elapsed := 0.0

func _ready() -> void:
	title = "一键打包测试版"
	get_ok_button().text = "关闭"
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	add_child(layout)
	var intro := Label.new()
	intro.text = "选择平台，点击开始。完成后把 ZIP 发给朋友即可。"
	layout.add_child(intro)
	platform_choice = OptionButton.new()
	platform_choice.add_item("Windows · 64 位", 0)
	platform_choice.add_item("Mac · Intel / Apple 芯片", 1)
	platform_choice.add_item("Windows + Mac · 两个都打包", 2)
	layout.add_child(platform_choice)
	var output_row := HBoxContainer.new()
	layout.add_child(output_row)
	var output_label := Label.new()
	output_label.text = "保存位置"
	output_row.add_child(output_label)
	output_edit = LineEdit.new()
	output_edit.text = ProjectSettings.globalize_path("res://builds")
	output_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	output_row.add_child(output_edit)
	choose_button = Button.new()
	choose_button.text = "选择目录…"
	choose_button.pressed.connect(func(): directory_dialog.popup_centered(Vector2i(900, 620)))
	output_row.add_child(choose_button)
	var hint := Label.new()
	hint.custom_minimum_size.x = 640
	hint.text = "每次生成独立文件夹，保留之前的包。Mac 首次打开说明会附在包内。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(hint)
	var actions := HBoxContainer.new()
	layout.add_child(actions)
	start_button = Button.new()
	start_button.text = "开始打包"
	start_button.pressed.connect(_start_build)
	actions.add_child(start_button)
	open_button = Button.new()
	open_button.text = "打开输出目录"
	open_button.disabled = true
	open_button.pressed.connect(func(): OS.shell_open(last_folder))
	actions.add_child(open_button)
	status_label = Label.new()
	status_label.custom_minimum_size.x = 640
	status_label.text = "准备就绪"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(status_label)
	package_list = RichTextLabel.new()
	package_list.selection_enabled = true
	package_list.custom_minimum_size = Vector2(640, 150)
	package_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(package_list)
	directory_dialog = FileDialog.new()
	directory_dialog.title = "选择打包输出目录"
	directory_dialog.access = FileDialog.ACCESS_FILESYSTEM
	directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	directory_dialog.dir_selected.connect(func(path: String): output_edit.text = path)
	add_child(directory_dialog)
	set_process(false)

func is_busy() -> bool:
	return thread != null

func _python() -> String:
	if OS.has_feature("windows"):
		var bundled := OS.get_environment("USERPROFILE").path_join(".cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe")
		if FileAccess.file_exists(bundled):
			return bundled
		return "python"
	return "python3"

func _start_build() -> void:
	if is_busy():
		return
	var output_root := output_edit.text.strip_edges()
	if output_root.is_empty():
		status_label.text = "请选择保存位置。"
		return
	# 保存场景和现有工坊的资源改动，随后让后台工具使用磁盘上的项目。
	if Engine.is_editor_hint():
		var edited_scene := EditorInterface.get_edited_scene_root()
		if edited_scene != null and edited_scene.scene_file_path.is_empty():
			status_label.text = "请先保存当前未命名场景后再打包。"
			return
		EditorInterface.save_all_scenes()
	var work := ProjectSettings.globalize_path("res://.maintenance/packaging")
	if DirAccess.make_dir_recursive_absolute(work) != OK:
		status_label.text = "无法创建打包工作目录。"
		return
	result_path = work.path_join("result-%s.json" % Time.get_ticks_usec())
	var targets := ["windows", "macos", "both"]
	var args := PackedStringArray([ProjectSettings.globalize_path(PACKAGER), "--platform", targets[platform_choice.selected], "--godot", OS.get_executable_path(), "--output", output_root, "--result", result_path])
	thread = Thread.new()
	var error := thread.start(_worker.bind(_python(), args))
	if error != OK:
		thread = null
		status_label.text = "无法启动打包任务：" + error_string(error)
		return
	last_progress = ""
	package_list.text = ""
	status_label.text = "正在准备打包…"
	_set_busy(true)
	set_process(true)

func _worker(python: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute(python, args, output, true, false)
	return {"code": code, "output": "\n".join(output).right(5000)}

func _read_result() -> Dictionary:
	if not FileAccess.file_exists(result_path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(result_path))
	return parsed if parsed is Dictionary else {}

func _process(_delta: float) -> void:
	progress_elapsed += _delta
	var progress := {}
	if progress_elapsed >= 0.25:
		progress_elapsed = 0.0
		progress = _read_result()
	if not progress.is_empty():
		var status := str(progress.get("status", ""))
		if status != last_progress:
			status_label.text = status
			last_progress = status
		last_folder = str(progress.get("folder", ""))
	if thread != null and not thread.is_alive():
		var execution: Dictionary = thread.wait_to_finish()
		thread = null
		_finish(execution, _read_result())

func _finish(execution: Dictionary, result: Dictionary) -> void:
	set_process(false)
	_set_busy(false)
	if not result.get("ok", false) or execution.code != 0:
		status_label.text = "打包未完成：" + str(result.get("error", "请确认本机有 Python 3，并检查导出模板。"))
		package_list.text = "\n".join(PackedStringArray(result.get("packages", []))) + "\n\n" + str(result.get("log", execution.output))
	else:
		status_label.text = "打包完成，可以发送以下 ZIP："
		package_list.text = "\n".join(PackedStringArray(result.get("packages", [])))
	last_folder = str(result.get("folder", last_folder))
	open_button.disabled = last_folder.is_empty() or not DirAccess.dir_exists_absolute(last_folder)

func _set_busy(busy: bool) -> void:
	start_button.disabled = busy
	platform_choice.disabled = busy
	output_edit.editable = not busy
	choose_button.disabled = busy

func shutdown() -> void:
	if thread != null:
		thread.wait_to_finish()
		thread = null
