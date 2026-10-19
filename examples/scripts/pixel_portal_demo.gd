extends Control
## F6 独立展示；只实例化特效，无单位、地图、碰撞和传送行为。

const PORTAL := preload("res://scenes/effects/pixel_portal.tscn")
const PRESET_NAMES := ["青蓝传送门", "紫色奥术", "金色余烬", "绿色秘境"]
const LAYER_KEYS := ["ring_enabled", "interior_enabled", "fragments_enabled", "ground_enabled"]
const LAYER_NAMES := ["流动门环", "门内旋涡", "环绕碎片", "地面光斑"]
const ACCENT := Color("84cbd0")

class PortalStage extends Control:
	var effects: Array[PixelPortal] = []
	var zooms: Array[float] = []
	var checker := false

	func build(scales: Array[float], layer: int = -1) -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		zooms = scales
		for zoom in scales:
			var effect := PORTAL.instantiate() as PixelPortal
			add_child(effect)
			effects.append(effect)
			if layer >= 0:
				for i in 4:
					effect.set(LAYER_KEYS[i], i == layer)
		resized.connect(layout)
		layout()

	func layout() -> void:
		for i in effects.size():
			var zoom := minf(zooms[i], maxf(1.0, (size.y - 35.0) / 48.0))
			effects[i].scale = Vector2.ONE * zoom
			effects[i].position = Vector2(size.x * (i + 0.5) / effects.size(), size.y * 0.88)
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("11151f"))
		if checker:
			for y in range(0, int(size.y), 18):
				for x in range(0, int(size.x), 18):
					@warning_ignore("integer_division") # Intentional whole-number truncation; preserve existing results.
					if (x / 18 + y / 18) % 2 == 0:
						draw_rect(Rect2(x, y, minf(18, size.x - x), minf(18, size.y - y)), Color("191e29"))
		else:
			for x in range(0, int(size.x), 32):
				draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.4, 0.6, 0.7, 0.035))
			for y in range(0, int(size.y), 32):
				draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.4, 0.6, 0.7, 0.035))
		for effect in effects:
			draw_line(effect.position + Vector2(-size.x / effects.size() * 0.32, 0),
				effect.position + Vector2(size.x / effects.size() * 0.32, 0), Color(0.45, 0.7, 0.74, 0.12))

var _primary: Array[PixelPortal] = []
var _all: Array[PixelPortal] = []
var _stages: Array[PortalStage] = []
var _sliders: Dictionary = {}
var _checks: Dictionary = {}
var _palette_buttons: Array[Button] = []
var _duration_buttons: Array[Button] = []
var _pause_button: Button
var _timeline: HSlider
var _clock: Label
var _paused := false


func _ready() -> void:
	get_window().title = "像素传送门 · 独立预览"
	var bg := ColorRect.new()
	bg.color = Color("0a0e16")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	titles.add_child(_label("像素传送门", 38, Color("e4eef1")))
	titles.add_child(_label("椭圆门环  /  旋涡  /  环绕碎片  /  地面光斑    ·    六秒无缝循环", 18, Color("83949f")))
	var badge := _label("VFX STUDY   /   07", 17, ACCENT)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(badge)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 20)
	page.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	content.add_child(left)
	var heroes := HBoxContainer.new()
	heroes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	heroes.add_theme_constant_override("separation", 16)
	left.add_child(heroes)
	var hero := _card(heroes, "01  /  完整效果", "放大查看像素轮廓、亮线与循环衔接", [8.0], -1, 280)
	_primary.append_array(hero.effects)
	var sizes := _card(heroes, "02  /  尺寸与透明度", "1×  /  3×  /  5×    ·    棋盘格查看透明边缘", [1.0, 3.0, 5.0], -1, 280)
	sizes.checker = true
	_primary.append_array(sizes.effects)
	var transport := HBoxContainer.new()
	transport.add_theme_constant_override("separation", 14)
	left.add_child(transport)
	_pause_button = _button("暂停  /  空格")
	_pause_button.custom_minimum_size.x = 164
	_pause_button.pressed.connect(_toggle_pause)
	transport.add_child(_pause_button)
	_timeline = HSlider.new()
	_timeline.min_value = 0
	_timeline.max_value = 1
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(func(value: float):
		_set_paused(true)
		for effect in _all:
			effect.seek(value * effect.loop_duration))
	transport.add_child(_timeline)
	_clock = _label("0.00 / 6.00 s", 16, ACCENT)
	_clock.custom_minimum_size.x = 160
	_clock.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	transport.add_child(_clock)
	left.add_child(_label("四层拆解", 21, Color("d1dee5")))
	var layers := HBoxContainer.new()
	layers.add_theme_constant_override("separation", 14)
	layers.custom_minimum_size.y = 240
	left.add_child(layers)
	for i in 4:
		_card(layers, "%02d  /  %s" % [i + 1, LAYER_NAMES[i]], "", [3.7], i, 150)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 356
	sidebar.add_theme_stylebox_override("panel", _panel(Color("131c27")))
	content.add_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 12)
	scroll.add_child(controls)
	controls.add_child(_label("实时调整", 25, Color("e4eef1")))
	controls.add_child(_label("拖动时间轴可暂停并查看单帧", 15, Color("83949f")))
	var presets := GridContainer.new()
	presets.columns = 2
	presets.add_theme_constant_override("h_separation", 8)
	presets.add_theme_constant_override("v_separation", 8)
	controls.add_child(presets)
	for i in 4:
		var button := _button(PRESET_NAMES[i])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_palette.bind(i))
		presets.add_child(button)
		_palette_buttons.append(button)
	controls.add_child(_label("循环时长", 16, Color("c5d5df")))
	var durations := HBoxContainer.new()
	durations.add_theme_constant_override("separation", 8)
	controls.add_child(durations)
	for seconds in [3, 6, 12]:
		var button := _button("%d 秒" % seconds)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_duration.bind(float(seconds)))
		durations.add_child(button)
		_duration_buttons.append(button)
	_add_slider(controls, "播放速度", "playback_speed", 0, 2, 0.05, 1)
	_add_slider(controls, "门环宽度", "ring_width", 0.5, 4, 0.1, 2.3)
	_add_slider(controls, "轮廓流动", "distortion", 0, 2, 0.05, 0.7)
	_add_slider(controls, "旋涡强度", "swirl_strength", 0, 2, 0.05, 1)
	_add_slider(controls, "碎片数量", "fragment_count", 0, 20, 1, 10)
	_add_slider(controls, "像素颗粒", "pixel_size", 0.5, 3, 0.5, 1)
	controls.add_child(_label("显示图层", 18, ACCENT))
	for i in 4:
		_add_check(controls, LAYER_NAMES[i], LAYER_KEYS[i], true)
	_add_check(controls, "柔和光晕", "halo_enabled", false)
	var reset := _button("恢复默认  /  R")
	reset.pressed.connect(_reset)
	controls.add_child(reset)
	page.add_child(_label("空格 暂停/继续    R 恢复默认    1–4 切换配色    ·    参考《五星地牢》特效拆解 07    ·    独立预览", 16, Color("83949f")))
	_set_palette(0)
	_set_duration(6)
	print("PIXEL_PORTAL_DEMO_READY")
	if "--capture-portal-demo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		_set_paused(true)
		for effect in _all:
			effect.seek(2.4)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-portal")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pixel-portal/demo.png")
		print("PIXEL_PORTAL_DEMO_CAPTURED")
		get_tree().quit()


func _process(_delta: float) -> void:
	if _primary.is_empty() or _timeline == null:
		return
	var effect := _primary[0]
	var position_in_cycle := effect.get_cycle_position()
	_timeline.set_value_no_signal(position_in_cycle)
	_clock.text = "%.2f / %.2f s" % [position_in_cycle * effect.loop_duration, effect.loop_duration]


func _card(parent: Container, title: String, subtitle: String, scales: Array[float], layer: int, height: float) -> PortalStage:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel(Color("101822")))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title, 19, Color("d1dee5")))
	if not subtitle.is_empty():
		box.add_child(_label(subtitle, 15, Color("83949f")))
	var stage := PortalStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = height
	box.add_child(stage)
	stage.build(scales, layer)
	_stages.append(stage)
	_all.append_array(stage.effects)
	return stage


func _panel(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("263743")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.add_theme_font_size_override("font_size", 17)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("1c2d3b") if state == "normal" else Color("345a64")
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(state, style)
	return button


func _add_slider(parent: Container, title: String, property: String, low: float, high: float, step_size: float, initial: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_label := _label(title, 16, Color("c5d5df"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value_label := _label("%.2f" % initial, 16, ACCENT)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step_size
	slider.value = initial
	slider.custom_minimum_size.y = 22
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		for effect in _all:
			if property == "fragment_count":
				effect.set(property, int(value))
			else:
				effect.set(property, value))
	box.add_child(slider)
	_sliders[property] = slider


func _add_check(parent: Container, title: String, property: String, initial: bool) -> void:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_font_size_override("font_size", 16)
	check.toggled.connect(func(value: bool):
		for effect in _primary:
			effect.set(property, value))
	parent.add_child(check)
	_checks[property] = check


func _set_palette(index: int) -> void:
	for i in _palette_buttons.size():
		_palette_buttons[i].set_pressed_no_signal(i == index)
	for effect in _all:
		effect.palette_preset = index


func _set_duration(seconds: float) -> void:
	var position_in_cycle := _primary[0].get_cycle_position()
	for effect in _all:
		effect.loop_duration = seconds
		effect.seek(position_in_cycle * seconds)
	for i in _duration_buttons.size():
		_duration_buttons[i].set_pressed_no_signal([3, 6, 12][i] == int(seconds))


func _toggle_pause() -> void:
	_set_paused(not _paused)


func _set_paused(value: bool) -> void:
	_paused = value
	for effect in _all:
		effect.playing = not value
	_pause_button.text = "继续  /  空格" if value else "暂停  /  空格"


func _reset() -> void:
	var defaults := {"playback_speed": 1.0, "ring_width": 2.3, "distortion": 0.7,
		"swirl_strength": 1.0, "fragment_count": 10, "pixel_size": 1.0}
	for key in defaults:
		(_sliders[key] as HSlider).value = defaults[key]
	for key in _checks:
		(_checks[key] as CheckButton).button_pressed = key != "halo_enabled"
	_set_palette(0)
	_set_duration(6)
	for effect in _all:
		effect.restart()
	_set_paused(false)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_toggle_pause()
		KEY_R:
			_reset()
		KEY_1, KEY_2, KEY_3, KEY_4:
			_set_palette(event.keycode - KEY_1)
		_:
			return
	get_viewport().set_input_as_handled()
