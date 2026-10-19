extends Control
## F6 独立预览；所有路径、配色、时钟调整仅存在于本场景。

const Ribbon := preload("res://scripts/effects/pixel_soul_ribbon.gd")
const EFFECT_SCENE := preload("res://scenes/effects/pixel_soul_ribbon.tscn")
const ACCENT := Color("79b6b7")
const PRESET_NAMES := ["青色灵魂", "金色能量", "紫色奥术"]

class RibbonStage extends Control:
	signal path_edited
	var effect: Ribbon
	var hero := false
	var _dragging := -1

	func build(scene: PackedScene, main: bool) -> void:
		hero = main
		mouse_filter = Control.MOUSE_FILTER_STOP if hero else Control.MOUSE_FILTER_IGNORE
		effect = scene.instantiate() as Ribbon
		add_child(effect)
		effect.looping = hero
		effect.playing = hero
		resized.connect(layout)
		layout()

	func layout() -> void:
		if effect == null:
			return
		var margin := 96.0 if hero else 34.0
		var zoom := minf((size.x - margin * 2.0) / 760.0, (size.y - 65.0) / 330.0)
		effect.scale = Vector2.ONE * maxf(zoom, 0.05)
		effect.position = Vector2(margin, size.y * 0.78)
		queue_redraw()

	func _screen_point(point: Vector2) -> Vector2:
		return effect.position + point * effect.scale

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0c141c"))
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.24, 0.37, 0.43, 0.08))
		for y in range(0, int(size.y), 40):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.24, 0.37, 0.43, 0.08))
		if effect == null:
			return
		var font_size := 17 if hero else 12
		var points := [effect.start_point, effect.control_point, effect.end_point]
		var labels := ["A  发射点", "B  控制点", "C  吸收点"]
		for i in 3:
			if i == 1 and not effect.show_path:
				continue
			var point := _screen_point(points[i])
			var color := Color("79b6b7") if i != 2 else Color("e0dfd1")
			draw_circle(point, 13.0 if hero else 8.0, Color(color, 0.30), false, 1.0, true)
			draw_circle(point, 3.0 if hero else 2.0, color)
			draw_string(get_theme_default_font(), point + Vector2(17, 6), labels[i], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(color, 0.65))

	func _gui_input(event: InputEvent) -> void:
		if not hero or not effect.show_path:
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var points := [effect.start_point, effect.control_point, effect.end_point]
				for i in 3:
					if event.position.distance_to(_screen_point(points[i])) < 22.0:
						_dragging = i
						accept_event()
						break
			else:
				_dragging = -1
		elif event is InputEventMouseMotion and _dragging >= 0:
			var point: Vector2 = (event.position.clamp(Vector2(24, 24), size - Vector2(80, 24)) - effect.position) / effect.scale
			match _dragging:
				0: effect.start_point = point
				1: effect.control_point = point
				2: effect.end_point = point
			queue_redraw()
			path_edited.emit()
			accept_event()

var _hero: RibbonStage
var _phase_stages: Array[RibbonStage] = []
var _sliders: Dictionary = {}
var _palette_buttons: Array[Button] = []
var _pause_button: Button
var _guide_check: CheckButton
var _glow_check: CheckButton
var _timeline: HSlider
var _status: Label
var _progress_label: Label
var _swatches: HBoxContainer
var _paused := false
var _active_preset := 0


func _ready() -> void:
	get_window().title = "像素灵魂光带 · 独立预览"
	var background := ColorRect.new()
	background.color = Color("080f17")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 48)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 22)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("像素灵魂光带", 40, Color("edf4ef")))
	heading.add_child(_label("参考《五星地牢》开发日志 02  ·  曲线加速 / 带状尾迹 / 尾端吸收", 18, Color("80969d")))
	var badge := _label("VFX STUDY  /  02", 17, ACCENT)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(badge)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	page.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 18)
	content.add_child(left)
	var hero_panel := _panel(left)
	hero_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var hero_box := VBoxContainer.new()
	hero_box.add_theme_constant_override("separation", 12)
	hero_panel.add_child(hero_box)
	var title_row := HBoxContainer.new()
	hero_box.add_child(title_row)
	var title := _label("完整效果  /  循环预览", 22, Color("d1deda"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_status = _label("", 17, ACCENT)
	title_row.add_child(_status)
	_hero = RibbonStage.new()
	_hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hero.custom_minimum_size.y = 325
	hero_box.add_child(_hero)
	_hero.build(EFFECT_SCENE, true)
	_hero.path_edited.connect(_path_edited)
	var time_row := HBoxContainer.new()
	time_row.add_theme_constant_override("separation", 14)
	hero_box.add_child(time_row)
	time_row.add_child(_label("动画进度", 16, Color("80969d")))
	_timeline = HSlider.new()
	_timeline.min_value = 0.0
	_timeline.max_value = 1.0
	_timeline.step = 0.001
	_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeline.value_changed.connect(_scrub)
	time_row.add_child(_timeline)
	_progress_label = _label("0.00 / 2.00 秒", 16, ACCENT)
	_progress_label.custom_minimum_size.x = 172
	time_row.add_child(_progress_label)
	left.add_child(_label("三个阶段  /  固定时间对照", 21, Color("d1deda")))
	var phase_row := HBoxContainer.new()
	phase_row.custom_minimum_size.y = 260
	phase_row.add_theme_constant_override("separation", 14)
	left.add_child(phase_row)
	for pair in [["01  生成与加速", "前端起步，尾迹开始展开"], ["02  带状尾迹", "尖尾 → 青色主体 → 浅色圆头"], ["03  尾迹吸收", "前端停在 C，尾端继续追上"]]:
		var panel := _panel(phase_row)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		panel.add_child(box)
		box.add_child(_label(pair[0], 19, Color("d1deda")))
		box.add_child(_label(pair[1], 14, Color("80969d")))
		var stage := RibbonStage.new()
		stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(stage)
		stage.build(EFFECT_SCENE, false)
		_phase_stages.append(stage)
	var side_panel := _panel(content)
	side_panel.custom_minimum_size.x = 370
	side_panel.size_flags_horizontal = Control.SIZE_FILL
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side_panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 12)
	scroll.add_child(controls)
	controls.add_child(_label("实时调整", 25, Color("edf4ef")))
	controls.add_child(_label("拖动进度条可逐帧观察吸收过程", 15, Color("80969d")))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	controls.add_child(presets)
	for i in 3:
		var button := _button(PRESET_NAMES[i].left(2))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.pressed.connect(_set_palette.bind(i))
		presets.add_child(button)
		_palette_buttons.append(button)
	_swatches = HBoxContainer.new()
	_swatches.add_theme_constant_override("separation", 5)
	controls.add_child(_swatches)
	for color in _hero.effect.get_palette():
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size.y = 10
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_swatches.add_child(swatch)
	_add_slider(controls, "飞行时长 / 秒", "flight_duration", 0.3, 3.0, 0.05, 1.35)
	_add_slider(controls, "尾迹保留 / 秒", "trail_delay", 0.1, 1.5, 0.05, 0.65)
	_add_slider(controls, "加速幅度", "acceleration", 1.0, 4.0, 0.1, 2.3)
	_add_slider(controls, "前端宽度", "head_width", 4, 50, 1, 20)
	_add_slider(controls, "尖尾收束", "taper", 0.4, 3.0, 0.1, 1.2)
	_add_slider(controls, "像素颗粒", "pixel_size", 1, 8, 1, 3)
	_add_slider(controls, "弧线高度", "arc_height", 0, 380, 5, 300)
	_guide_check = _check(controls, "显示路径 · 拖拽 A / B / C", false)
	_guide_check.toggled.connect(func(value: bool):
		_hero.effect.show_path = value
		_hero.queue_redraw())
	_glow_check = _check(controls, "柔和光晕", false)
	_glow_check.toggled.connect(func(value: bool):
		for effect in _all_effects():
			effect.glow_enabled = value)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	controls.add_child(actions)
	_pause_button = _button("暂停 / 空格")
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.pressed.connect(_toggle_pause)
	actions.add_child(_pause_button)
	var replay := _button("重新播放")
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	replay.pressed.connect(_replay)
	actions.add_child(replay)
	var reset := _button("恢复全部默认 / R")
	reset.pressed.connect(_reset)
	controls.add_child(reset)
	var tip := _label("主画面循环播放；下方展示三个固定时刻。\n修改参数不会写入场景或正式游戏配置。", 14, Color("80969d"))
	controls.add_child(tip)
	page.add_child(_label("空格 暂停/继续     R 恢复默认     1—3 切换配色     ·     打开路径辅助后，可拖动三个路径点", 16, Color("80969d")))
	_update_phases()
	_set_palette(0)
	print("PIXEL_SOUL_RIBBON_DEMO_READY")
	if "--capture-soul-ribbon-demo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.4).timeout
		_set_paused(true)
		_hero.effect.seek(_hero.effect.flight_duration * 0.96)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-soul-ribbon")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pixel-soul-ribbon/demo.png")
		print("PIXEL_SOUL_RIBBON_DEMO_CAPTURED")
		get_tree().quit()
	elif "--capture-soul-ribbon-animation" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.3).timeout
		_set_paused(true)
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-soul-ribbon/frames")
		for i in 37:
			_hero.effect.seek(minf(float(i) / 15.0, _hero.effect.get_duration()))
			await get_tree().process_frame
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var capture := get_viewport().get_texture().get_image()
			capture.get_region(Rect2i(48, 137, 1430, 542)).save_png("res://.maintenance/pixel-soul-ribbon/frames/%02d.png" % i)
		print("PIXEL_SOUL_RIBBON_ANIMATION_CAPTURED")
		get_tree().quit()


func _process(_delta: float) -> void:
	if _hero == null or _timeline == null:
		return
	var effect := _hero.effect
	_timeline.set_value_no_signal(clampf(effect._elapsed / effect.get_duration(), 0.0, 1.0))
	_progress_label.text = "%.2f / %.2f 秒" % [minf(effect._elapsed, effect.get_duration()), effect.get_duration()]
	var phase := "生成与加速"
	if effect._elapsed >= effect.get_duration():
		phase = "吸收完成"
	elif effect._elapsed >= effect.flight_duration:
		phase = "尾迹吸收"
	elif effect._elapsed > effect.flight_duration * 0.55:
		phase = "带状飞行"
	_status.text = "%s  ·  %s" % ["已暂停" if _paused else "播放中", phase]


func _all_effects() -> Array[Ribbon]:
	var effects: Array[Ribbon] = [_hero.effect]
	for stage in _phase_stages:
		effects.append(stage.effect)
	return effects


func _update_phases() -> void:
	for i in _phase_stages.size():
		var effect := _phase_stages[i].effect
		var times := [effect.flight_duration * 0.65, effect.flight_duration * 0.96,
			effect.flight_duration + effect.trail_delay * 0.55]
		effect.playing = false
		effect.seek(times[i])


func _path_edited() -> void:
	for stage in _phase_stages:
		stage.effect.set_path(_hero.effect.start_point, _hero.effect.control_point, _hero.effect.end_point)
		stage.queue_redraw()
	var height_slider := _sliders["arc_height"] as HSlider
	var height := -_hero.effect.control_point.y
	height_slider.set_value_no_signal(height)
	(height_slider.get_meta("value_label") as Label).text = "%.2f" % height
	_update_phases()


func _set_palette(index: int) -> void:
	_active_preset = index
	for i in _palette_buttons.size():
		_palette_buttons[i].set_pressed_no_signal(i == index)
	for effect in _all_effects():
		effect.palette_preset = index
	for i in 3:
		(_swatches.get_child(i) as ColorRect).color = _hero.effect.get_palette()[i]


func _set_paused(paused: bool) -> void:
	_paused = paused
	_hero.effect.playing = not paused
	_pause_button.text = "继续 / 空格" if paused else "暂停 / 空格"


func _toggle_pause() -> void:
	_set_paused(not _paused)


func _scrub(value: float) -> void:
	_set_paused(true)
	_hero.effect.seek(value * _hero.effect.get_duration())


func _replay() -> void:
	_hero.effect.restart()
	_set_paused(false)


func _reset() -> void:
	_hero.effect.set_path(Vector2.ZERO, Vector2(20, -300), Vector2(760, -40))
	var defaults := {"flight_duration": 1.35, "trail_delay": 0.65, "acceleration": 2.3,
		"head_width": 20, "taper": 1.2, "pixel_size": 3, "arc_height": 300}
	for key in defaults:
		(_sliders[key] as HSlider).value = defaults[key]
	_guide_check.button_pressed = false
	_glow_check.button_pressed = false
	_path_edited()
	_set_palette(0)
	_replay()


func _add_slider(parent: Container, title: String, property: String,
		minimum: float, maximum: float, step_size: float, initial: float) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var title_label := _label(title, 16, Color("c3d1d2"))
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title_label)
	var value_label := _label("%.2f" % initial, 16, ACCENT)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.set_meta("value_label", value_label)
	slider.custom_minimum_size.y = 22
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		if property == "arc_height":
			_hero.effect.control_point = Vector2(_hero.effect.control_point.x, -value)
			_path_edited()
		else:
			for effect in _all_effects():
				effect.set(property, value)
			_update_phases())
	box.add_child(slider)
	_sliders[property] = slider


func _panel(parent: Container) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0c141c")
	style.border_color = Color("22343e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


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
	for pair in [["normal", Color("192a35")], ["hover", Color("28444d")], ["pressed", Color("35666d")]]:
		var style := StyleBoxFlat.new()
		style.bg_color = pair[1]
		style.set_corner_radius_all(6)
		style.content_margin_left = 10
		style.content_margin_right = 10
		button.add_theme_stylebox_override(pair[0], style)
	return button


func _check(parent: Container, title: String, initial: bool) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_font_size_override("font_size", 16)
	parent.add_child(check)
	return check


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: _toggle_pause()
		KEY_R: _reset()
		KEY_1, KEY_2, KEY_3: _set_palette(event.keycode - KEY_1)
		_: return
	get_viewport().set_input_as_handled()
