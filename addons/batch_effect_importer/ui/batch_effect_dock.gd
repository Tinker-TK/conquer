# 这玩意儿是干嘛的（核心逻辑）：提供批量导入特效、生成动画资源的编辑器界面。
# 数据是咋流动的（数据流向）：编辑器操作进入界面，再调用导入工具生成资源文件。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：仅编辑器使用，不进入正式游戏的战斗循环。
@tool
extends VBoxContainer
## 批量特效导入 Dock 面板。
## 功能:
##  1. 选择素材目录(序列帧文件夹)或精灵表图片
##  2. 批量重命名文件(前缀+序号)
##  3. 一键生成 SpriteFrames 动画资源
##  4. 创建 AnimatedSprite2D 节点/独立特效场景, 导入到当前场景

const Core := preload("res://addons/batch_effect_importer/importer_core.gd")

enum Mode { FRAMES, SHEET }

# ---- 控件 ----
var mode_option: OptionButton
var source_edit: LineEdit
var browse_button: Button
var scan_button: Button
var rename_button: Button
var import_button: Button

var prefix_edit: LineEdit
var start_spin: SpinBox
var digits_spin: SpinBox
var suffix_edit: LineEdit

var anim_name_edit: LineEdit
var fps_spin: SpinBox
var loop_check: CheckBox

var frames_dir_edit: LineEdit
var save_frames_check: CheckBox
var output_option: OptionButton   # 0=独立场景 1=插入当前场景 2=导入到选中节点
var sheet_cols_spin: SpinBox
var sheet_rows_spin: SpinBox
var use_sheet_frame_size_check: CheckBox
var frame_w_spin: SpinBox
var frame_h_spin: SpinBox
var row_anim_check: CheckBox
var anim_names_edit: TextEdit

var preview_list: ItemList
var log_edit: RichTextLabel

var file_dialog: FileDialog

var _scanned: Array[String] = []


func _ready() -> void:
	_build_ui()
	_log("插件就绪。选择素材后点“扫描素材”。")


func _build_ui() -> void:
	var title := Label.new()
	title.text = "批量特效导入 → AnimatedSprite2D"
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	add_child(_hsep())

	# ---- 模式 ----
	add_child(_label("素材类型"))
	mode_option = OptionButton.new()
	mode_option.tooltip_text = "选择素材组织方式：序列帧模式按图片文件生成动画，精灵表模式按行列网格拆分同一张大图。"
	mode_option.add_item("序列帧文件夹(多张图片)", Mode.FRAMES)
	mode_option.add_item("精灵表(一张大图按网格拆)", Mode.SHEET)
	mode_option.item_selected.connect(_on_mode_changed)
	add_child(mode_option)

	# ---- 源路径 ----
	add_child(_label("素材路径 (res:// 或绝对路径)"))
	var source_row := HBoxContainer.new()
	source_edit = LineEdit.new()
	source_edit.tooltip_text = "素材来源路径。序列帧模式填写待扫描的图片文件夹，精灵表模式填写单张图片路径；可使用 res:// 或绝对路径。"
	source_edit.placeholder_text = "res://assets/effect"
	source_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browse_button = Button.new()
	browse_button.text = "浏览"
	browse_button.pressed.connect(_on_browse)
	source_row.add_child(source_edit)
	source_row.add_child(browse_button)
	add_child(source_row)

	# 精灵表参数(默认隐藏)
	var sheet_row := HBoxContainer.new()
	sheet_cols_spin = _make_spin("列数", 1, 64, 5)
	sheet_rows_spin = _make_spin("行数", 1, 64, 4)
	sheet_row.add_child(sheet_cols_spin)
	sheet_row.add_child(sheet_rows_spin)
	use_sheet_frame_size_check = CheckBox.new()
	use_sheet_frame_size_check.text = "自定义单帧尺寸"
	use_sheet_frame_size_check.tooltip_text = "按指定像素宽高拆分精灵表；关闭时按整图尺寸与行列数计算单帧大小。"
	use_sheet_frame_size_check.toggled.connect(_on_custom_frame_size_toggled)
	sheet_row.add_child(use_sheet_frame_size_check)
	frame_w_spin = _make_spin("宽", 1, 4096, 192)
	frame_h_spin = _make_spin("高", 1, 4096, 192)
	frame_w_spin.visible = false
	frame_h_spin.visible = false
	sheet_row.add_child(frame_w_spin)
	sheet_row.add_child(frame_h_spin)
	sheet_row.name = "SheetRow"
	add_child(sheet_row)
	_sheet_row.visible = false

	# 每行一个动画(精灵表模式, 默认隐藏)
	row_anim_check = CheckBox.new()
	row_anim_check.text = "每行是一个动画(行数=动画数, 列数=每动画帧数)"
	row_anim_check.tooltip_text = "开启后精灵表的每一行生成一段独立动画；关闭则按扫描顺序把所有网格帧放进同一动画。"
	row_anim_check.toggled.connect(_on_row_anim_toggled)
	row_anim_check.visible = false
	add_child(row_anim_check)

	anim_names_edit = TextEdit.new()
	anim_names_edit.tooltip_text = "每行填写一个动画名称，从上到下对应精灵表的各行。留空使用自动名称；仅在每行独立动画模式下使用。"
	anim_names_edit.placeholder_text = "每行一个动画名, 从上到下对应每一行\n留空则自动命名为 前缀_01, 前缀_02 ..."
	anim_names_edit.custom_minimum_size.y = 80
	anim_names_edit.visible = false
	add_child(anim_names_edit)

	add_child(_hsep())

	# ---- 批量重命名 ----
	add_child(_label("批量重命名"))
	var prefix_row := HBoxContainer.new()
	prefix_edit = LineEdit.new()
	prefix_edit.tooltip_text = "执行批量重命名时，放在每个帧文件序号前的文字，如 explosion；也用于自动生成动画名称。"
	prefix_edit.placeholder_text = "前缀, 如 explosion"
	prefix_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prefix_row.add_child(prefix_edit)
	start_spin = _make_spin("起始", 0, 99999, 1)
	digits_spin = _make_spin("位数", 1, 6, 3)
	suffix_edit = LineEdit.new()
	suffix_edit.tooltip_text = "执行批量重命名时，放在序号后、扩展名前的文字；留空不添加后缀。"
	suffix_edit.placeholder_text = "后缀(可选)"
	suffix_edit.custom_minimum_size.x = 80
	prefix_row.add_child(start_spin)
	prefix_row.add_child(digits_spin)
	prefix_row.add_child(suffix_edit)
	add_child(prefix_row)

	add_child(_hsep())

	# ---- 动画参数 ----
	add_child(_label("动画参数"))
	var anim_row := HBoxContainer.new()
	anim_name_edit = LineEdit.new()
	anim_name_edit.tooltip_text = "导入生成的动画名称，留空默认使用素材文件夹名称。每行独立动画模式使用上方各行动画名。"
	anim_name_edit.placeholder_text = "动画名, 默认取文件夹名"
	anim_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anim_row.add_child(anim_name_edit)
	fps_spin = _make_spin("FPS", 1, 240, 12)
	anim_row.add_child(fps_spin)
	loop_check = CheckBox.new()
	loop_check.text = "循环"
	loop_check.tooltip_text = "生成动画播放到最后一帧后是否回到第一帧。一次性命中或召唤特效通常应关闭循环，以便收到播放完成信号。"
	loop_check.button_pressed = true
	anim_row.add_child(loop_check)
	add_child(anim_row)

	add_child(_hsep())

	# ---- 输出 ----
	add_child(_label("输出"))
	var out_row := HBoxContainer.new()
	frames_dir_edit = LineEdit.new()
	frames_dir_edit.tooltip_text = "生成 SpriteFrames 和独立特效场景的项目输出目录，使用 res:// 路径；不会改变原始素材目录。"
	frames_dir_edit.text = "res://assets/animations/generated"
	frames_dir_edit.placeholder_text = "SpriteFrames 保存目录"
	frames_dir_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	out_row.add_child(frames_dir_edit)
	add_child(out_row)

	save_frames_check = CheckBox.new()
	save_frames_check.text = "保存 SpriteFrames 为 .tres 资源"
	save_frames_check.tooltip_text = "将生成的动画帧配置另存为可复用的 .tres 资源；关闭时不单独保存这一份 SpriteFrames 文件。"
	save_frames_check.button_pressed = true
	add_child(save_frames_check)

	output_option = OptionButton.new()
	output_option.tooltip_text = "选择导入结果：新建独立 .tscn、在当前场景选中节点下添加特效，或将动画合并到当前选中的 AnimatedSprite2D。"
	output_option.add_item("创建独立特效场景 (.tscn)", 0)
	output_option.add_item("插入到当前打开的场景(选中节点下)", 1)
	output_option.add_item("导入到当前选中的 AnimatedSprite2D(合并动画)", 2)
	add_child(output_option)

	add_child(_hsep())

	# ---- 按钮 ----
	var btn_row := HBoxContainer.new()
	scan_button = Button.new()
	scan_button.text = "① 扫描素材"
	scan_button.pressed.connect(_on_scan)
	rename_button = Button.new()
	rename_button.text = "② 批量重命名"
	rename_button.pressed.connect(_on_rename)
	import_button = Button.new()
	import_button.text = "③ 导入到 AnimatedSprite2D"
	import_button.pressed.connect(_on_import)
	btn_row.add_child(scan_button)
	btn_row.add_child(rename_button)
	btn_row.add_child(import_button)
	add_child(btn_row)

	# ---- 预览 ----
	add_child(_label("扫描结果"))
	preview_list = ItemList.new()
	preview_list.custom_minimum_size.y = 140
	preview_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(preview_list)

	# ---- 日志 ----
	log_edit = RichTextLabel.new()
	log_edit.bbcode_enabled = true
	log_edit.scroll_following = true
	log_edit.custom_minimum_size.y = 90
	log_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(log_edit)

	# ---- 文件对话框 ----
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	file_dialog.dir_selected.connect(_on_dir_selected)
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


# ============ 辅助构建 ============

func _hsep() -> HSeparator:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 6)
	return s


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 13)
	return l


func _make_spin(label_text: String, minv: float, maxv: float, val: float) -> SpinBox:
	var sb := SpinBox.new()
	sb.tooltip_text = {
		"列数": "精灵表横向格子数，每列对应一帧；与行数或自定义单帧尺寸共同决定裁切网格。",
		"行数": "精灵表纵向格子数；每行独立动画模式下也是生成的动画数量。",
		"宽": "自定义单帧的像素宽度，只在精灵表自定义尺寸模式下使用。",
		"高": "自定义单帧的像素高度，只在精灵表自定义尺寸模式下使用。",
		"起始": "批量重命名序号的起始数字，之后按扫描顺序递增。",
		"位数": "批量重命名序号最少显示的位数，不足时在左侧补 0，如 3 位将 1 显示为 001。",
		"FPS": "生成动画每秒播放的帧数，越大播放越快；总播放时长约为帧数除以 FPS。"
	}.get(label_text, "")
	sb.min_value = minv
	sb.max_value = maxv
	sb.value = val
	sb.suffix = " " + label_text
	sb.custom_minimum_size.x = 90
	return sb


var _sheet_row: HBoxContainer:
	get:
		return get_node_or_null("SheetRow") as HBoxContainer


func _on_mode_changed(index: int) -> void:
	var is_sheet := index == Mode.SHEET
	if _sheet_row:
		_sheet_row.visible = is_sheet
	row_anim_check.visible = is_sheet
	anim_names_edit.visible = is_sheet and row_anim_check.button_pressed


func _on_row_anim_toggled(pressed: bool) -> void:
	anim_names_edit.visible = mode_option.selected == Mode.SHEET and pressed


func _on_custom_frame_size_toggled(pressed: bool) -> void:
	frame_w_spin.visible = pressed
	frame_h_spin.visible = pressed


# ============ 浏览 ============

func _on_browse() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR if mode_option.selected == Mode.FRAMES else FileDialog.FILE_MODE_OPEN_FILE
	if mode_option.selected == Mode.SHEET:
		file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp,*.tga ; 图片文件"])
	file_dialog.popup_centered_ratio(0.6)


func _on_dir_selected(dir: String) -> void:
	source_edit.text = _to_res_path(dir)


func _on_file_selected(path: String) -> void:
	source_edit.text = _to_res_path(path)


# ============ 扫描 ============

func _on_scan() -> void:
	_scanned.clear()
	preview_list.clear()
	var src := source_edit.text.strip_edges()
	if src.is_empty():
		_log("[错误] 请先填写素材路径", true)
		return
	if mode_option.selected == Mode.FRAMES:
		_scanned = Core.scan_image_files(src, true)
	else:
		if src.get_extension().to_lower() in Core.SUPPORTED_EXTS:
			_scanned = [src]
		else:
			_log("[错误] 精灵表模式请选择一张图片", true)
			return
	if _scanned.is_empty():
		_log("[警告] 未找到图片文件", true)
		return
	for p in _scanned:
		preview_list.add_item(p)
	if mode_option.selected == Mode.SHEET and row_anim_check.button_pressed:
		var cols := int(sheet_cols_spin.value)
		var rows := int(sheet_rows_spin.value)
		var names := _parse_anim_names()
		_log("精灵表按行拆分: %d 行 = %d 个动画, 每动画 %d 帧:" % [rows, rows, cols])
		for r in rows:
			var n: String = names[r] if r < names.size() and names[r] != "" else "自动_%02d" % (r + 1)
			_log("  动画 %02d: %s" % [r + 1, n])
	else:
		_log("扫描到 %d 个文件" % _scanned.size())


# ============ 批量重命名 ============

func _on_rename() -> void:
	if _scanned.is_empty():
		_log("[提示] 请先扫描素材", true)
		return
	var prefix := prefix_edit.text.strip_edges()
	var suffix := suffix_edit.text.strip_edges()
	var res := Core.rename_files_batch(
		_scanned,
		prefix,
		int(start_spin.value),
		int(digits_spin.value),
		suffix
	)
	_log("重命名完成: 成功 %d 个, 失败 %d 个, 跳过 %d 个" % [res.renamed.size(), res.failed.size(), res.skipped])
	if res.failed.size() > 0:
		_log("失败列表: %s" % str(res.failed), true)
	if res.renamed.size() > 0:
		EditorInterface.get_resource_filesystem().scan()
		_scanned = res.renamed
		preview_list.clear()
		for p in _scanned:
			preview_list.add_item(p)
		_log("已刷新文件系统, 新文件名:")
		for p in res.renamed:
			_log("  - " + p.get_file())


# ============ 导入 ============

func _on_import() -> void:
	if _scanned.is_empty():
		_log("[提示] 请先扫描素材", true)
		return

	# 确保纹理已导入(阻塞式重导入, 避免 load 返回 null)
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.get_resource_filesystem().reimport_files(PackedStringArray(_scanned))

	var fps := float(fps_spin.value)
	var loop := loop_check.button_pressed

	var frames: SpriteFrames = null
	var anim_names: Array = []

	if mode_option.selected == Mode.SHEET:
		var fs := Vector2i.ZERO
		if use_sheet_frame_size_check.button_pressed:
			fs = Vector2i(int(frame_w_spin.value), int(frame_h_spin.value))
		var cols := int(sheet_cols_spin.value)
		var rows := int(sheet_rows_spin.value)
		if row_anim_check.button_pressed:
			# 每行一个动画: 行数=动画数, 列数=每动画帧数
			var names := _parse_anim_names()
			var prefix := _get_prefix()
			if prefix.is_empty():
				prefix = anim_name_edit.text.strip_edges()
			if prefix.is_empty():
				prefix = _scanned[0].get_file().get_basename()
			frames = Core.build_sprite_frames_from_sheet_rows(
				_scanned[0], names, cols, rows, fps, loop, fs, prefix
			)
			# 按行顺序记录实际动画名(get_animation_names 是字典序, 会打乱行顺序)
			anim_names = []
			for r in rows:
				if r < names.size() and names[r] != "":
					anim_names.append(names[r])
				else:
					anim_names.append("%s_%02d" % [prefix, r + 1])
			_log("已构建 %d 个动画: %s" % [anim_names.size(), ", ".join(anim_names)])
		else:
			var anim_name := _guess_anim_name()
			frames = Core.build_sprite_frames_from_sheet(_scanned[0], anim_name, cols, rows, fps, loop, fs)
			anim_names = [anim_name]
			_log("已构建动画 [%s] 帧数: %d" % [anim_name, frames.get_frame_count(anim_name)])
	else:
		var anim_name := _guess_anim_name()
		frames = Core.build_sprite_frames_from_files(_scanned, anim_name, fps, loop)
		anim_names = [anim_name]
		_log("已构建动画 [%s] 帧数: %d" % [anim_name, frames.get_frame_count(anim_name)])

	if frames == null:
		_log("[错误] 构建 SpriteFrames 失败", true)
		return

	# 保存 SpriteFrames 资源
	if save_frames_check.button_pressed:
		var base := _get_prefix()
		if base.is_empty():
			base = _guess_anim_name()
		var out_dir := _get_out_dir()
		DirAccess.make_dir_recursive_absolute(out_dir)
		var tres_path := out_dir.path_join(base + ".tres")
		var err := ResourceSaver.save(frames, tres_path)
		if err == OK:
			_log("已保存 SpriteFrames: %s" % tres_path)
		else:
			_log("[错误] 保存失败: %s (%s)" % [tres_path, error_string(err)], true)

	# 输出方式
	if output_option.selected == 0:
		_create_standalone_scene(frames, anim_names)
	elif output_option.selected == 1:
		_insert_into_current_scene(frames, anim_names)
	else:
		_import_into_selected_node(frames, anim_names)


## 把动画导入到当前场景中已选中的 AnimatedSprite2D 节点(合并, 不新建节点)。
func _import_into_selected_node(frames: SpriteFrames, anim_names: Array) -> void:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.is_empty():
		_log("[错误] 请先在场景树中选中一个 AnimatedSprite2D 节点", true)
		return
	var node := selection[0]
	if not node is AnimatedSprite2D:
		_log("[错误] 选中的节点不是 AnimatedSprite2D: %s" % node.name, true)
		return
	var as2d := node as AnimatedSprite2D
	var target: SpriteFrames = as2d.sprite_frames
	if target == null:
		target = SpriteFrames.new()
	Core.merge_sprite_frames(target, frames)
	as2d.sprite_frames = target
	if anim_names.size() > 0:
		as2d.animation = str(anim_names[0])
		if as2d.autoplay.is_empty():
			as2d.autoplay = str(anim_names[0])
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(as2d)
	_log("已将 %d 个动画合并进 AnimatedSprite2D [%s]: %s" % [anim_names.size(), as2d.name, ", ".join(anim_names)])


func _guess_anim_name() -> String:
	var n := anim_name_edit.text.strip_edges()
	if n != "":
		return n
	var src := source_edit.text.strip_edges().trim_suffix("/")
	if mode_option.selected == Mode.SHEET:
		return src.get_file().get_basename()
	return src.get_file()


## 从 anim_names_edit 解析每行动画名(过滤空行)。
func _parse_anim_names() -> Array:
	var names: Array = []
	var text := anim_names_edit.text
	for line in text.split("\n"):
		var t := line.strip_edges()
		if t != "":
			names.append(t)
	return names


## 重命名前缀(用于自动动画名/保存文件名), 可为空。
func _get_prefix() -> String:
	return prefix_edit.text.strip_edges()


func _get_out_dir() -> String:
	var out_dir := frames_dir_edit.text.strip_edges()
	if out_dir.is_empty():
		out_dir = "res://assets/animations/generated"
	if not out_dir.begins_with("res://"):
		out_dir = "res://" + out_dir.trim_prefix("/")
	return out_dir


func _create_standalone_scene(frames: SpriteFrames, anim_names: Array) -> void:
	var out_dir := _get_out_dir()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var base := _get_prefix()
	if base.is_empty():
		base = _guess_anim_name()
	var scene := Core.make_effect_scene(frames, str(anim_names[0]) if anim_names.size() > 0 else base, base)
	var scene_path := out_dir.path_join(base + ".tscn")
	var err := ResourceSaver.save(scene, scene_path)
	if err == OK:
		_log("已创建特效场景: %s" % scene_path)
		# 在编辑器中打开新场景预览
		EditorInterface.open_scene_from_path(scene_path)
	else:
		_log("[错误] 场景保存失败: %s (%s)" % [scene_path, error_string(err)], true)


func _insert_into_current_scene(frames: SpriteFrames, anim_names: Array) -> void:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		_log("[错误] 当前没有打开的场景, 请先在编辑器打开一个场景", true)
		return
	var parent: Node = scene_root
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.size() > 0:
		parent = selection[0]
	var base := _get_prefix()
	if base.is_empty():
		base = _guess_anim_name()
	var node := Core.make_animated_sprite_2d(frames, str(anim_names[0]) if anim_names.size() > 0 else base, base)
	parent.add_child(node)
	node.owner = scene_root
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)
	_log("已将 AnimatedSprite2D [%s] 添加到 %s (%d 个动画)" % [node.name, parent.name, anim_names.size()])


# ============ 工具 ============

func _to_res_path(p: String) -> String:
	var proj := ProjectSettings.globalize_path("res://")
	var normalized := p.replace("\\", "/")
	if normalized.begins_with(proj):
		return "res://" + normalized.trim_prefix(proj)
	return normalized


func _log(msg: String, is_error := false) -> void:
	if log_edit == null:
		return
	var line := ("[color=#ff8888]" if is_error else "[color=#a8d8a8]") + msg + "[/color]"
	log_edit.append_text(line + "\n")
