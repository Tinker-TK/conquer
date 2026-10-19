extends Control
## F6 独立预览；示例内容只存在于该场景的离屏视口中。

const BOOK := preload("res://scenes/ui/pixel_book.tscn")
const PAGE_SCRIPT := preload("res://examples/scripts/book_demo_page.gd")
const STYLE := preload("res://scripts/ui/comic_style.gd")
const ACCENT := Color("eac49b")
const MUTED := Color("9687a5")
const WHITE := Color("f5e8df")

var book: PixelBook
var previous: Button
var next: Button
var pause: Button
var timeline: HSlider
var leaf_slider: HSlider
var curl_slider: HSlider
var duration_slider: HSlider
var squash_slider: HSlider
var travel_slider: HSlider
var zoom_slider: HSlider
var motion_button: CheckButton
var page_label: Label
var state_label: Label
var auto_button: CheckButton
var shadows_button: CheckButton
var _page_views: Array[SubViewport] = []
var _auto_wait := 0.0
var _auto_direction := 1
var _ready_for_input := false


class Stage extends Control:

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("21192f"))
		for y in range(0, int(size.y), 28):
			for x in range(0, int(size.x), 28):
				draw_rect(Rect2(x, y, 1, 1), Color("43354f"))
		var mid := size * Vector2(0.5, 0.56)
		for i in range(8, 0, -1):
			draw_set_transform(mid, 0, Vector2(1, 0.45))
			draw_circle(Vector2.ZERO, size.y * 0.35 + i * 15, Color(0.38, 0.26, 0.47, 0.014))
		draw_set_transform(Vector2.ZERO)


func _ready() -> void:
	get_window().title = "书本翻页 · 独立预览"
	_build_ui()
	for i in 8:
		var view := SubViewport.new()
		view.size = Vector2i(180, 230)
		view.transparent_bg = true
		view.gui_disable_input = true
		view.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(view)
		var page := Node2D.new()
		page.set_script(PAGE_SCRIPT)
		page.page_index = i
		view.add_child(page)
		_page_views.append(view)
		book.page_textures.append(view.get_texture())
	book.spread_changed.connect(_refresh)
	book.turn_started.connect(func(_direction: int): _refresh(book.spread_index))
	book.turn_finished.connect(func(_committed: bool): _auto_wait = 0.0; _refresh(book.spread_index))
	book.progress_changed.connect(func(value: float): timeline.set_value_no_signal(value))
	await get_tree().process_frame
	_ready_for_input = true
	_refresh(0)
	print("BOOK_FLIP_DEMO_READY")
	if "--capture-book-demo" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/book-flip")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/book-flip/demo.png")
		book.preview_turn(1)
		book.seek_turn(0.43)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://.maintenance/book-flip/demo-turn.png")
		print("BOOK_FLIP_DEMO_CAPTURED")
		get_tree().quit()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color("15101f")
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 46)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 20)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("书页之间", 38, WHITE))
	titles.add_child(_label("像素书本翻页实验   /   点击翻页，或按住纸面拖动", 18, MUTED))
	var badge := _label("MOTION STUDY   /   01", 18, ACCENT)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(badge)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	layout.add_child(body)
	var main := VBoxContainer.new()
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	body.add_child(main)
	var stage := Stage.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(480, 370)
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.resized.connect(stage.queue_redraw)
	main.add_child(stage)
	book = BOOK.instantiate() as PixelBook
	stage.add_child(book)
	book.offset_top = 44
	book.offset_bottom = -20
	var stage_note := _label("TRAVELER'S JOURNAL", 16, MUTED)
	stage_note.position = Vector2(22, 16)
	stage_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_note)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 12)
	main.add_child(transport)
	previous = _button("←  上一页", transport, func(): book.turn_previous())
	pause = _button("暂停  /  空格", transport, _toggle_pause)
	next = _button("下一页  →", transport, func(): book.turn_next())
	page_label = _label("01 — 02  /  08", 19, ACCENT)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transport.add_child(page_label)
	var scrub := HBoxContainer.new()
	scrub.add_theme_constant_override("separation", 14)
	main.add_child(scrub)
	scrub.add_child(_label("翻页进度", 16, MUTED))
	timeline = HSlider.new()
	timeline.max_value = 1.0
	timeline.step = 0.001
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.value_changed.connect(_scrub)
	scrub.add_child(timeline)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 350
	sidebar.add_theme_stylebox_override("panel", _panel(Color("241b30")))
	body.add_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 15)
	scroll.add_child(controls)
	controls.add_child(_label("纸面的运动", 25, WHITE))
	controls.add_child(_label("弯曲 · 挤压 · 平移 · 缩放 · 回弹", 15, MUTED))
	controls.add_child(HSeparator.new())
	duration_slider = _slider(controls, "翻页时长", 0.3, 2.5, 0.05, 0.85, "%.2f 秒", func(value: float): book.turn_duration = value)
	curl_slider = _slider(controls, "书页弯曲", 0.0, 1.4, 0.05, 0.8, "%.2f", func(value: float): book.curl_strength = value)
	leaf_slider = _slider(controls, "同时翻动的纸张", 1, 5, 1, 3, "%.0f 张", func(value: float): book.leaf_count = int(value))
	motion_button = CheckButton.new()
	motion_button.text = "整本书随翻页运动"
	motion_button.button_pressed = true
	motion_button.toggled.connect(func(value: bool): book.motion_enabled = value)
	controls.add_child(motion_button)
	squash_slider = _slider(controls, "整体挤压", 0, 0.45, 0.01, 0.30, "%.2f", func(value: float): book.squash_amount = value)
	travel_slider = _slider(controls, "平移幅度", 0, 48, 1, 32, "%.0f 像素", func(value: float): book.travel_distance = value)
	zoom_slider = _slider(controls, "缩放幅度", 0, 0.30, 0.01, 0.18, "%.2f", func(value: float): book.zoom_amount = value)
	shadows_button = CheckButton.new()
	shadows_button.text = "书脊与动态投影"
	shadows_button.button_pressed = true
	shadows_button.toggled.connect(func(value: bool): book.shadows_enabled = value)
	controls.add_child(shadows_button)
	auto_button = CheckButton.new()
	auto_button.text = "自动往返翻页"
	auto_button.toggled.connect(func(_value: bool): _auto_wait = 0.0)
	controls.add_child(auto_button)
	controls.add_child(HSeparator.new())
	state_label = _label("等待翻页", 17, ACCENT)
	controls.add_child(state_label)
	var note := _label("点击左右页翻动\n按住纸面向另一侧拖动\n拖动不足时松手，纸页会回弹\n\n← / →   上一页 / 下一页\n空格       暂停 / 继续\nR             恢复默认", 16, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(note)
	_button("回到当前跨页", controls, func(): book.finish_turn(false))
	_button("恢复默认  /  R", controls, _reset)
	layout.add_child(_label("独立预览场景    ·    示例内容：旅人手记    ·    参考 DetFantasia 书本菜单动画", 16, MUTED))
	var theme_override := Theme.new()
	theme_override.default_font = STYLE.chinese()
	theme_override.default_font_size = 17
	theme = theme_override


func _process(delta: float) -> void:
	if not _ready_for_input:
		return
	if book.turning:
		state_label.text = ("拖动中" if book.dragging else ("已暂停" if book.paused else "翻动中")) + "   %03d%%" % roundi(book.progress * 100.0)
	else:
		state_label.text = "第 %d 跨页  /  共 %d 跨页" % [book.spread_index + 1, book.get_spread_count()]
	if auto_button.button_pressed and not book.turning:
		_auto_wait += delta
		if _auto_wait >= 1.6:
			if not book.can_turn(_auto_direction):
				_auto_direction *= -1
			if _auto_direction > 0:
				book.turn_next()
			else:
				book.turn_previous()
			_auto_wait = 0.0


func _input(event: InputEvent) -> void:
	if not _ready_for_input or not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT: book.turn_previous()
		KEY_RIGHT: book.turn_next()
		KEY_SPACE: _toggle_pause()
		KEY_R: _reset()
		_: return
	get_viewport().set_input_as_handled()


func _toggle_pause() -> void:
	if not book.turning:
		return
	if book.paused:
		book.finish_turn(true)
	else:
		book.paused = true
	pause.text = "继续  /  空格" if book.paused else "暂停  /  空格"


func _scrub(value: float) -> void:
	if not _ready_for_input:
		return
	auto_button.button_pressed = false
	if not book.turning:
		if not book.preview_turn(1 if book.can_turn(1) else -1):
			return
	book.seek_turn(value)
	pause.text = "继续  /  空格"


func _refresh(index: int) -> void:
	previous.disabled = not book.can_turn(-1)
	next.disabled = not book.can_turn(1)
	page_label.text = "%02d — %02d  /  %02d" % [index * 2 + 1, index * 2 + 2, book.page_textures.size()]
	pause.text = "暂停  /  空格"
	if not book.turning:
		timeline.set_value_no_signal(0)


func _reset() -> void:
	auto_button.button_pressed = false
	shadows_button.button_pressed = true
	duration_slider.value = 0.85
	curl_slider.value = 0.8
	leaf_slider.value = 3
	motion_button.button_pressed = true
	squash_slider.value = 0.30
	travel_slider.value = 32
	zoom_slider.value = 0.18
	_auto_direction = 1
	_auto_wait = 0.0
	book.reset()


func _slider(parent: Control, title: String, minimum: float, maximum: float, step_value: float, initial: float, format_string: String, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(title, 17, WHITE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label := _label(format_string % initial, 16, ACCENT)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_value
	slider.value = initial
	slider.value_changed.connect(func(value: float): value_label.text = format_string % value; callback.call(value))
	parent.add_child(slider)
	return slider


func _label(value: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _button(value: String, parent: Control, callback: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size = Vector2(142, 46)
	result.add_theme_color_override("font_color", WHITE)
	result.add_theme_color_override("font_disabled_color", Color("65576f"))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var color := Color("392a45")
		if state in ["hover", "focus"]:
			color = Color("60455e")
		elif state == "pressed":
			color = Color("886170")
		elif state == "disabled":
			color = Color("211929")
		var box := _panel(color)
		box.content_margin_left = 16
		box.content_margin_right = 16
		box.content_margin_top = 10
		box.content_margin_bottom = 10
		result.add_theme_stylebox_override(state, box)
	result.pressed.connect(callback)
	parent.add_child(result)
	return result


func _panel(color: Color) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(8)
	result.set_content_margin_all(22)
	return result
