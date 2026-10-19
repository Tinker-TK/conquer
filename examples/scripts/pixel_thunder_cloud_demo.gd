extends Control
## 乌云细节与组合落雷的独立预览，不创建战斗单位。

const EFFECT := preload("res://scenes/effects/pixel_thunder_cloud.tscn")
const SKELETON := preload("res://assets/characters/Skeleton/Skeleton with shadows/Skeleton.png")
const ACCENT := Color("88c9ce")
const MUTED := Color("8293a1")
const PALETTES := [
	[Color("242c36"), Color("404957"), Color("606976"), Color("88c9ce"), Color("dcebdd")],
	[Color("2d263d"), Color("4e435e"), Color("796c88"), Color("ba97de"), Color("f2e2ff")],
	[Color("302b26"), Color("504a40"), Color("79715e"), Color("e2b16b"), Color("fff0cd")],
]

class CloudStage extends Control:
	var effect: PixelThunderCloud
	var skeleton: AnimatedSprite2D
	var cloud_only := false
	var max_zoom := 3.0
	var show_dummy := true

	func build(only_cloud: bool, zoom: float, dummy: bool) -> void:
		cloud_only = only_cloud
		max_zoom = zoom
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		effect = EFFECT.instantiate() as PixelThunderCloud
		effect.playing = false
		effect.lightning_enabled = not only_cloud
		add_child(effect)
		if dummy:
			skeleton = AnimatedSprite2D.new()
			skeleton.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var frames := SpriteFrames.new()
			frames.set_animation_speed("default", 8)
			for i in 6:
				var atlas := AtlasTexture.new()
				atlas.atlas = SKELETON
				atlas.region = Rect2(i * 100, 0, 100, 100)
				frames.add_frame("default", atlas)
			skeleton.sprite_frames = frames
			add_child(skeleton)
			skeleton.play()
		resized.connect(layout)
		layout()

	func layout() -> void:
		if effect == null:
			return
		var zoom := max_zoom
		if cloud_only:
			zoom = minf(zoom, minf(size.x / (effect.cloud_size.x + 24), size.y / (effect.cloud_size.y + 22)))
		else:
			zoom = minf(zoom, (size.y - 20) / (effect.cloud_altitude + effect.cloud_size.y * 0.7))
		zoom = maxf(zoom, 0.2)
		if zoom >= 1.0:
			zoom = floorf(zoom)
		effect.scale = Vector2.ONE * zoom
		if cloud_only:
			effect.position = (size * 0.5 + Vector2(0, effect.cloud_altitude * zoom)).floor()
		else:
			effect.position = Vector2(floorf(size.x * 0.5), floorf(size.y - 18))
		if skeleton != null:
			skeleton.position = effect.position + Vector2(-4, -11) * zoom * 1.5
			skeleton.scale = Vector2.ONE * zoom * 1.5
			skeleton.visible = show_dummy
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("111620"))
		for x in range(0, int(size.x), 32):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.44, 0.56, 0.67, 0.035))
		for y in range(0, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.44, 0.56, 0.67, 0.035))
		if not cloud_only:
			draw_line(Vector2(16, size.y - 18), Vector2(size.x - 16, size.y - 18), Color("283640"), 1)
			if effect != null:
				draw_line(effect.position + Vector2(-6, 4), effect.position + Vector2(6, 4), Color(ACCENT, 0.5), 1)

var _stages: Array[CloudStage] = []
var _phases: Array[CloudStage] = []
var _sliders: Dictionary = {}
var _palette_buttons: Array[Button] = []
var _pause_button: Button
var _time_slider: HSlider
var _time_label: Label
var _phase_label: Label
var _view_picker: OptionButton
var _lightning_picker: OptionButton
var _checks: Dictionary = {}
var _clock := 0.0
var _speed := 1.0
var _paused := false
var _looping := true
var _cycle_duration := 2.4


func _ready() -> void:
	get_window().title = "像素雷击乌云 · 独立预览"
	_build_ui()
	_set_palette(0)
	_refresh_phases()
	_sync_time()
	print("PIXEL_THUNDER_CLOUD_DEMO_READY")
	if "--capture-thunder-cloud-demo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		_set_paused(true)
		_seek(0.725)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-thunder-cloud")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pixel-thunder-cloud/demo.png")
		print("PIXEL_THUNDER_CLOUD_DEMO_CAPTURED")
		get_tree().quit()


func _process(delta: float) -> void:
	if _paused or _stages.is_empty():
		return
	var previous_cycle := int(floor(_clock / _cycle_duration))
	_clock += delta * _speed
	if not _looping and _clock >= _cycle_duration - 0.001:
		_clock = _cycle_duration - 0.001
		_set_paused(true)
	for stage in _stages:
		stage.effect.seek(_clock)
	if int(floor(_clock / _cycle_duration)) != previous_cycle:
		_refresh_phases()
	_sync_time()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("090e16")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("像素雷击乌云", 38, Color("e4e8e4")))
	heading.add_child(_label("参考《五星地牢》特效拆解 06  ·  云团翻滚与同步落雷", 18, MUTED))
	var badge := _label("独立预览  /  06", 18, ACCENT)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(badge)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 22)
	page.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 14)
	content.add_child(left)
	var hero := HBoxContainer.new()
	hero.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero.add_theme_constant_override("separation", 16)
	left.add_child(hero)
	_stages.append(_stage_card(hero, "01  /  乌云细节", "云团层叠 · 噪声侵蚀 · 三色翻滚", true, 4.0, false, true))
	_stages.append(_stage_card(hero, "02  /  乌云 + 落雷", "云内闪光同步 · 出雷点变化 · 落点固定", false, 3.0, true, true))
	_build_timeline(left)
	left.add_child(_label("动画拆解  /  云内闪光与落雷同步", 18, Color("c8d3dd")))
	var phases := HBoxContainer.new()
	phases.custom_minimum_size.y = 226
	phases.add_theme_constant_override("separation", 12)
	left.add_child(phases)
	for i in 4:
		_phases.append(_stage_card(phases, "%02d  /  %s" % [i + 1, ["翻滚待机", "云内蓄光", "放电落雷", "余光恢复"][i]], "", false, 0.82, false, false))
	_build_sidebar(content)
	page.add_child(_label("空格 暂停 / 继续     R 新放电     Enter 重播     → 单帧     ·     时间轴定位一个完整放电周期", 16, MUTED))


func _build_timeline(parent: Container) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color("101925"), 14))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	panel.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	_phase_label = _label("", 17, ACCENT)
	_phase_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_phase_label)
	_time_label = _label("", 16, MUTED)
	row.add_child(_time_label)
	_time_slider = HSlider.new()
	_time_slider.min_value = 0.0
	_time_slider.step = 0.001
	_time_slider.custom_minimum_size.y = 22
	_time_slider.value_changed.connect(func(value: float):
		_set_paused(true)
		_seek(floorf(_clock / _cycle_duration) * _cycle_duration + value))
	column.add_child(_time_slider)


func _build_sidebar(parent: Container) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 352
	panel.add_theme_stylebox_override("panel", _panel_style(Color("111c28"), 18))
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	scroll.add_child(controls)
	controls.add_child(_label("预览控制", 24, Color("e4e8e4")))
	controls.add_child(_label("乌云细节与落雷组合同步展示", 15, MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	controls.add_child(row)
	_pause_button = _button("暂停 / 空格")
	_pause_button.pressed.connect(func(): _set_paused(not _paused))
	row.add_child(_pause_button)
	var trigger_button := _button("新放电 / R")
	trigger_button.pressed.connect(_new_strike)
	row.add_child(trigger_button)
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 8)
	controls.add_child(second_row)
	var replay := _button("重播当前周期")
	replay.pressed.connect(_replay)
	second_row.add_child(replay)
	var step_button := _button("单帧 +1/60")
	step_button.pressed.connect(_step)
	second_row.add_child(step_button)
	_add_slider(controls, "播放速度", "speed", 0.1, 2, 0.05, 1)
	_add_slider(controls, "放电周期 / 秒", "cycle_duration", 1.2, 5, 0.05, 2.4)
	_add_check(controls, "自动循环", "looping", true)
	_add_check(controls, "显示骷髅参照", "dummy", true)
	controls.add_child(HSeparator.new())
	controls.add_child(_label("乌云与放电", 20, Color("c8d3dd")))
	_add_slider(controls, "云宽", "cloud_width", 70, 150, 1, 112)
	_add_slider(controls, "云层高度", "cloud_altitude", 95, 210, 1, 156)
	_add_slider(controls, "翻滚速度", "roll_speed", 0, 1.8, 0.05, 0.65)
	_add_slider(controls, "翻滚幅度", "roll_amount", 0, 2, 0.05, 1)
	_add_slider(controls, "边缘噪声", "edge_noise", 0, 4, 0.1, 1.8)
	_add_slider(controls, "像素颗粒", "pixel_size", 1, 3, 1, 1)
	_add_slider(controls, "云内闪光强度", "flash_strength", 0, 2, 0.05, 1)
	_add_check(controls, "云内闪光", "flash_enabled", true)
	_add_check(controls, "落雷", "lightning_enabled", true)
	_add_check(controls, "触地火花", "sparks_enabled", true)
	_lightning_picker = OptionButton.new()
	_lightning_picker.add_item("单雷")
	_lightning_picker.add_item("树状落雷")
	_lightning_picker.custom_minimum_size.y = 38
	_lightning_picker.item_selected.connect(func(index: int): _set_effect_property("lightning_type", index))
	controls.add_child(_lightning_picker)
	var palette_row := HBoxContainer.new()
	palette_row.add_theme_constant_override("separation", 6)
	controls.add_child(palette_row)
	for i in 3:
		var button := _button(["参考配色", "紫云", "暖云"][i])
		button.toggle_mode = true
		button.pressed.connect(_set_palette.bind(i))
		palette_row.add_child(button)
		_palette_buttons.append(button)
	_view_picker = OptionButton.new()
	for text in ["完整效果", "椭圆结构", "像素遮罩", "三色明暗", "云内闪光", "流动噪声"]:
		_view_picker.add_item(text)
	_view_picker.custom_minimum_size.y = 38
	_view_picker.item_selected.connect(func(index: int):
		for stage in _stages:
			stage.effect.debug_view = index)
	controls.add_child(_view_picker)
	var reset := _button("恢复默认参数")
	reset.pressed.connect(_reset)
	controls.add_child(reset)


func _stage_card(parent: Container, title: String, subtitle: String, cloud_only: bool,
		zoom: float, dummy: bool, hero: bool) -> CloudStage:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("111620"), 16 if hero else 12))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(_label(title, 21 if hero else 16, Color("c8d3dd")))
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, 15, MUTED))
	var stage := CloudStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 240 if hero else 158
	column.add_child(stage)
	stage.build(cloud_only, zoom, dummy)
	return stage


func _add_slider(parent: Container, title: String, property: String, minimum: float,
		maximum: float, step_size: float, initial: float) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	parent.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	var label := _label(title, 15, Color("bccbd5"))
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value_label := _label(str(initial), 15, ACCENT)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.custom_minimum_size.y = 20
	slider.value_changed.connect(func(value: float):
		value_label.text = str(value)
		if property == "speed":
			_speed = value
			_set_paused(_paused)
		else:
			_set_effect_property(property, value))
	column.add_child(slider)
	_sliders[property] = slider


func _add_check(parent: Container, title: String, property: String, initial: bool) -> void:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_font_size_override("font_size", 15)
	check.toggled.connect(func(value: bool):
		if property == "looping":
			_looping = value
			if not value:
				_seek(fposmod(_clock, _cycle_duration))
		elif property == "dummy":
			_stages[1].show_dummy = value
			_stages[1].layout()
		else:
			_set_effect_property(property, value))
	parent.add_child(check)
	_checks[property] = check


func _set_effect_property(property: String, value: Variant) -> void:
	if property == "cycle_duration":
		_cycle_duration = value
	for stage in _stages + _phases:
		if property == "cloud_width":
			stage.effect.cloud_size = Vector2(value, stage.effect.cloud_size.y)
		elif property == "lightning_enabled":
			stage.effect.lightning_enabled = value and not stage.cloud_only
		else:
			stage.effect.set(property, value)
		stage.layout()
	_refresh_phases()
	_sync_time()


func _set_palette(index: int) -> void:
	for i in _palette_buttons.size():
		_palette_buttons[i].set_pressed_no_signal(i == index)
	for stage in _stages + _phases:
		stage.effect.dark_color = PALETTES[index][0]
		stage.effect.body_color = PALETTES[index][1]
		stage.effect.light_color = PALETTES[index][2]
		stage.effect.flash_color = PALETTES[index][3]
		stage.effect.flash_core = PALETTES[index][4]


func _refresh_phases() -> void:
	var base := floorf(_clock / _cycle_duration) * _cycle_duration
	for i in _phases.size():
		var effect := _phases[i].effect
		var times := [effect.strike_delay - 0.30, effect.strike_delay - 0.03,
			effect.strike_delay + 0.075, effect.strike_delay + 0.20]
		effect.seek(base + times[i])


func _seek(seconds: float) -> void:
	_clock = maxf(seconds, 0)
	for stage in _stages:
		stage.effect.seek(_clock)
	_refresh_phases()
	_sync_time()


func _sync_time() -> void:
	if _time_slider == null or _stages.is_empty():
		return
	var phase := fposmod(_clock, _cycle_duration)
	_time_slider.set_block_signals(true)
	_time_slider.max_value = _cycle_duration - 0.001
	_time_slider.value = phase
	_time_slider.set_block_signals(false)
	_time_label.text = "%.3f / %.2f s" % [phase, _cycle_duration]
	var effect := _stages[1].effect
	var status := "翻滚待机"
	if phase >= effect.strike_delay - 0.18 and phase < effect.strike_delay:
		status = "云内蓄光"
	elif phase >= effect.strike_delay and phase < effect.strike_delay + 0.10:
		status = "云内闪光 + 落雷"
	elif phase >= effect.strike_delay + 0.10 and phase < effect.get_strike_end():
		status = "落雷余光 / 云层恢复"
	_phase_label.text = ("已暂停  /  " if _paused else "播放中  /  ") + status


func _set_paused(value: bool) -> void:
	_paused = value
	_pause_button.text = "继续 / 空格" if value else "暂停 / 空格"
	if _stages[1].skeleton != null:
		_stages[1].skeleton.speed_scale = 0.0 if value else _speed
	_sync_time()


func _new_strike() -> void:
	for stage in _stages + _phases:
		stage.effect.trigger()
	_clock = 0.0
	_refresh_phases()
	_set_paused(false)


func _replay() -> void:
	_seek(floorf(_clock / _cycle_duration) * _cycle_duration)
	_set_paused(false)


func _step() -> void:
	_set_paused(true)
	_seek(_clock + 1.0 / 60.0)


func _reset() -> void:
	var defaults := {"speed": 1.0, "cycle_duration": 2.4, "cloud_width": 112.0, "cloud_altitude": 156.0,
		"roll_speed": 0.65, "roll_amount": 1.0, "edge_noise": 1.8, "pixel_size": 1.0, "flash_strength": 1.0}
	for property in defaults:
		(_sliders[property] as HSlider).value = defaults[property]
	for property in _checks:
		(_checks[property] as CheckButton).button_pressed = true
	_lightning_picker.select(0)
	_set_effect_property("lightning_type", 0)
	_view_picker.select(0)
	for stage in _stages + _phases:
		stage.effect.debug_view = 0
		stage.effect.random_seed = 11
		stage.effect.reset_sequence()
	_set_palette(0)
	_seek(0)
	_set_paused(false)


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_set_paused(not _paused)
		KEY_R:
			_new_strike()
		KEY_ENTER, KEY_KP_ENTER:
			_replay()
		KEY_RIGHT:
			_step()
		_:
			return
	get_viewport().set_input_as_handled()


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = 36
	button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = {"normal": Color("1b2c3b"), "hover": Color("2a4355"), "pressed": Color("38616c")}[state]
		style.set_corner_radius_all(5)
		style.content_margin_left = 9
		style.content_margin_right = 9
		button.add_theme_stylebox_override(state, style)
	return button


func _panel_style(color: Color, inset: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("263441")
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = inset
	style.content_margin_right = inset
	style.content_margin_top = inset
	style.content_margin_bottom = inset
	return style
