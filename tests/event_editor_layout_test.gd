# 在主屏幕容器内验证事件工坊铺满高度、可调整三栏宽度，以及不同窗口尺寸的布局。
extends SceneTree

var checks := 0
var failures: Array[String] = []
var host: VBoxContainer
var editor: Control
var report: Array[Dictionary] = []
const OUTPUT := "res://.maintenance/event-editor-layout"


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)


func settle() -> void:
	for i in 4:
		await process_frame


func drag_split(split: SplitContainer, distance: float) -> void:
	var point := split.get_drag_area_control().get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	var button := InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.pressed = true
	button.position = point
	root.push_input(button, true)
	motion = InputEventMouseMotion.new()
	motion.position = point + Vector2(distance, 0)
	motion.relative = Vector2(distance, 0)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(motion, true)
	button = InputEventMouseButton.new()
	button.button_index = MOUSE_BUTTON_LEFT
	button.position = motion.position
	root.push_input(button, true)
	await settle()


func inspect_layout(label: String, dimensions: Vector2i) -> void:
	root.size = dimensions
	await settle()
	var library: Control = editor.get_node("EventLibrary")
	var workspace: HSplitContainer = editor.get_node("Workspace")
	var form: ScrollContainer = workspace.get_node("EventForm")
	var preview: Control = workspace.get_node("EventPreview")
	check(absf(editor.get_global_rect().end.y - host.get_global_rect().end.y) < 1.0,
		label + " 工坊占满主屏幕剩余高度")
	check(absf(editor.size.y - library.size.y) < 1.0 and absf(editor.size.y - form.size.y) < 1.0,
		label + " 列表与表单使用完整工坊高度")
	check(library.size.x >= 280.0, label + " 事件列表宽度至少280")
	check(editor.event_list.size.y >= 200.0, label + " 已配置事件列表有足够可用高度")
	check(editor.event_list.get_global_rect().end.y >= editor.get_global_rect().end.y - 1.0,
		label + " 事件列表延伸到面板底部")
	check(form.size.x >= 460.0, label + " 配置区最小宽度460")
	check(preview.size.x >= 320.0, label + " 预览保留最小可读宽度")
	check(preview.get_global_rect().end.x <= host.get_global_rect().end.x + 1.0,
		label + " 三栏不越过窗口右边界")
	check(form.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED,
		label + " 编辑表单不需横向滚动")
	check(editor.inputs.description.size.x >= form.size.x - 30.0,
		label + " 描述输入框随配置区变宽")
	check(editor.doc.event != null and editor.preview.visible, label + " 事件与实际预览正常初始化")
	if dimensions.y > 1000:
		check(editor.event_list.size.y > editor.size.y * 0.6, label + " 高窗口不会只使用顶部一小块")
	if dimensions.x >= 1500:
		check(form.size.x > 600.0, label + " 宽窗口优先扩大配置区")
	var record := {"window": dimensions, "panel": editor.size, "library": library.size,
		"event_list": editor.event_list.size, "form": form.size, "preview": preview.size}
	report.append(record)
	print("EVENT_EDITOR_LAYOUT: ", record)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(OUTPUT.path_join(label + ".png")) == OK,
			label + " 保存布局截图")


func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 1400)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	host = VBoxContainer.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tabs := Label.new()
	tabs.text = "事件工坊 · 主编辑区"
	tabs.custom_minimum_size.y = 40
	host.add_child(tabs)
	# 模拟 EditorInterface 主屏幕的 VBox 分配方式，能发现只设锚点而缺少扩展标记的退化。
	editor = load("res://addons/event_editor/editor.gd").new()
	host.add_child(editor)
	editor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	editor._load("res://data/events/campfire.tres")
	await inspect_layout("tall", Vector2i(1600, 1400))
	var workspace: HSplitContainer = editor.get_node("Workspace")
	var form: Control = workspace.get_node("EventForm")
	var library: Control = editor.get_node("EventLibrary")
	var previous_width := form.size.x
	await drag_split(workspace, 80)
	check(form.size.x > previous_width + 50, "拖动配置/预览分隔条可以扩大配置区")
	previous_width = library.size.x
	await drag_split(editor, 60)
	check(library.size.x > previous_width + 40, "拖动列表分隔条可以扩大已配置事件列表")
	# 手动调整后缩小窗口仍须完整容纳三栏，滚动可到达表单末尾。
	await inspect_layout("narrow", Vector2i(1280, 720))
	var scroll: ScrollContainer = workspace.get_node("EventForm")
	editor.doc.new_event(2)
	await settle()
	var bar := scroll.get_v_scroll_bar()
	scroll.scroll_vertical = int(bar.max_value)
	await settle()
	check(scroll.scroll_vertical > 0, "窄窗口的长奖励池可向下滚动")
	var last_pool: Control = editor.pools.effect.box
	check(last_pool.get_global_rect().end.y <= scroll.get_global_rect().end.y + 1,
		"滚动到底可查看最后一组选项，不会被截断")
	# 把三栏恢复到默认比例，另存常见横屏下的可视结果。
	editor.split_offset = 0
	workspace.split_offset = 0
	editor._load("res://data/events/campfire.tres")
	scroll.scroll_vertical = 0
	await inspect_layout("wide", Vector2i(1920, 1080))
	var output := FileAccess.open(OUTPUT.path_join("layout.json"), FileAccess.WRITE)
	if output != null:
		output.store_string(JSON.stringify({"layouts": report, "checks": checks, "failures": failures}, "\t"))
	host.free()
	print("EVENT_EDITOR_LAYOUT_TEST: %d checks; %s" % [checks, "PASS" if failures.is_empty() else str(failures)])
	quit(0 if failures.is_empty() else 1)
