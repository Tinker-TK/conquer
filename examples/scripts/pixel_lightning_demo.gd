extends Control
## F6 独立落雷预览。角色只显示已有 SpriteFrames，不实例化游戏单位。

const LIGHTNING := preload("res://scenes/effects/pixel_lightning.tscn")
const SKELETON := preload("res://assets/characters/Skeleton/Skeleton with shadows/Skeleton.png")
const ACCENT := Color("87c6cb")
const MUTED := Color("80939f")
const PALETTES := [
	[Color("e5e5d5"), Color("87c6cb"), Color("385e69")],
	[Color("f6e6ff"), Color("bb98df"), Color("574273")],
	[Color("fff3cd"), Color("e8b56c"), Color("765238")],
]

class LightningStage extends Control:
	var effect: PixelLightning
	var skeleton: AnimatedSprite2D
	var max_zoom := 3.2
	var show_dummy := true

	func build(kind: int, seed_value: int, zoom: float, dummy: bool) -> void:
		max_zoom = zoom
		show_dummy = dummy
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		effect = LIGHTNING.instantiate() as PixelLightning
		effect.lightning_type = kind
		effect.random_seed = seed_value
		effect.playing = false
		add_child(effect)
		if dummy:
			skeleton = AnimatedSprite2D.new()
			skeleton.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var frames := SpriteFrames.new()
			frames.set_animation_speed("default", 8.0)
			for i in 6:
				var frame := AtlasTexture.new()
				frame.atlas = SKELETON
				frame.region = Rect2(i * 100, 0, 100, 100)
				frames.add_frame("default", frame)
			skeleton.sprite_frames = frames
			add_child(skeleton)
			skeleton.play()
		resized.connect(layout)
		layout()

	func layout() -> void:
		if effect == null:
			return
		var zoom := minf(max_zoom, (size.y - 18) / effect.bolt_height)
		zoom = maxf(zoom, 0.25)
		# 像素缩放优先整数，容器不足一倍时才缩小。
		if zoom >= 1.0:
			zoom = floorf(zoom)
		effect.position = Vector2(floorf(size.x * 0.5), floorf(size.y - 18.0))
		effect.scale = Vector2.ONE * zoom
		if skeleton != null:
			skeleton.position = effect.position + Vector2(-4, -11) * zoom * 1.5
			skeleton.scale = Vector2.ONE * zoom * 1.5
			skeleton.visible = show_dummy
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("10151e"))
		for x in range(0, int(size.x), 32):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.42, 0.58, 0.65, 0.035))
		for y in range(0, int(size.y), 32):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.42, 0.58, 0.65, 0.035))
		var ground_y := size.y - 18.0
		draw_line(Vector2(18, ground_y), Vector2(size.x - 18, ground_y), Color("273540"), 1)
		if effect != null:
			var origin := effect.position
			draw_line(origin + Vector2(-6, 4), origin + Vector2(6, 4), Color(ACCENT, 0.45), 1)

var _stages: Array[LightningStage] = []
var _phase_stages: Array[LightningStage] = []
var _sliders: Dictionary = {}
var _palette_buttons: Array[Button] = []
var _pause_button: Button
var _time_slider: HSlider
var _time_label: Label
var _phase_label: Label
var _view_picker: OptionButton
var _dummy_check: CheckButton
var _loop_check: CheckButton
var _spark_check: CheckButton
var _glint_check: CheckButton
var _restrike_check: CheckButton
var _paused := false
var _looping := true
var _clock := 0.0
var _speed := 1.0
var _loop_gap := 1.25
var _active_palette := 0


func _ready() -> void:
	get_window().title = "像素落雷 · 单雷与树状闪电预览"
	_build_ui()
	_set_palette(0)
	_refresh_phases()
	_sync_time()
	print("PIXEL_LIGHTNING_DEMO_READY")
	if "--capture-lightning-demo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(0.5).timeout
		_set_paused(true)
		_seek(0.075)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-lightning")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pixel-lightning/demo.png")
		print("PIXEL_LIGHTNING_DEMO_CAPTURED")
		get_tree().quit()


func _process(delta: float) -> void:
	if _stages.is_empty() or _paused:
		return
	_clock += delta * _speed
	var duration := _stages[0].effect.get_duration()
	if _looping and _clock >= duration + _loop_gap:
		_new_strike()
	elif not _looping and _clock >= duration:
		_clock = duration
		_set_paused(true)
	for stage in _stages:
		stage.effect.seek(_clock)
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
	heading.add_child(_label("像素落雷", 38, Color("e5e5d5")))
	heading.add_child(_label("参考《五星地牢》开发日志 05  ·  单雷与树状闪电", 18, MUTED))
	var badge := _label("独立预览  /  05", 18, ACCENT)
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
	_stages.append(_stage_card(hero, "01  /  单雷", "细主干 · 折点亮片 · 触地火花", 0, 17, 4.0, true, true))
	_stages.append(_stage_card(hero, "02  /  树状落雷", "长短分支 · 亮度分层 · 分支先消退", 1, 17, 4.0, true, true))
	_build_timeline(left)
	left.add_child(_label("动画拆解  /  同一形状的四个时刻", 18, Color("c4d0d8")))
	var phases := HBoxContainer.new()
	phases.add_theme_constant_override("separation", 12)
	phases.custom_minimum_size.y = 220
	left.add_child(phases)
	var names := ["劈落", "亮闪 / 火花", "余光", "消退"]
	for i in 4:
		_phase_stages.append(_stage_card(phases, "%02d  /  %s" % [i + 1, names[i]], "", 1, 17, 1.0, false, false))
	_build_sidebar(content)
	page.add_child(_label("空格 暂停 / 继续     R 新落雷     Enter 重播     → 单帧     ·     滑动时间轴可查看任意时刻", 16, MUTED))


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
		_seek(value))
	column.add_child(_time_slider)


func _build_sidebar(parent: Container) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 340
	panel.add_theme_stylebox_override("panel", _panel_style(Color("111c28"), 18))
	parent.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 10)
	scroll.add_child(controls)
	controls.add_child(_label("预览控制", 24, Color("e5e5d5")))
	controls.add_child(_label("两种落雷同步播放，便于对照", 15, MUTED))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	controls.add_child(actions)
	_pause_button = _button("暂停 / 空格")
	_pause_button.pressed.connect(func(): _set_paused(not _paused))
	actions.add_child(_pause_button)
	var trigger_button := _button("新落雷 / R")
	trigger_button.pressed.connect(_new_strike)
	actions.add_child(trigger_button)
	var second_row := HBoxContainer.new()
	second_row.add_theme_constant_override("separation", 8)
	controls.add_child(second_row)
	var replay := _button("重播形状")
	replay.pressed.connect(_replay)
	second_row.add_child(replay)
	var step_button := _button("单帧 +1/60")
	step_button.pressed.connect(_step)
	second_row.add_child(step_button)
	_add_slider(controls, "播放速度", "speed", 0.1, 2.0, 0.05, 1.0)
	_add_slider(controls, "循环间隔 / 秒", "loop_gap", 0.2, 3.0, 0.05, 1.25)
	_loop_check = _check(controls, "自动循环", true, "looping")
	_dummy_check = _check(controls, "显示骷髅参照", true, "dummy")
	controls.add_child(HSeparator.new())
	controls.add_child(_label("形状与细节", 20, Color("c4d0d8")))
	_add_slider(controls, "雷长", "bolt_height", 72, 200, 1, 136)
	_add_slider(controls, "折点数量", "segment_count", 3, 12, 1, 7)
	_add_slider(controls, "主干偏折", "lateral_spread", 0, 30, 1, 11)
	_add_slider(controls, "分支展开", "branch_spread", 12, 65, 1, 38)
	_add_slider(controls, "像素颗粒", "pixel_size", 1, 3, 1, 1)
	_spark_check = _check(controls, "触地火花", true, "sparks_enabled")
	_glint_check = _check(controls, "折点亮片", true, "glints_enabled")
	_restrike_check = _check(controls, "二次闪击", false, "restrike_enabled")
	var palette_row := HBoxContainer.new()
	palette_row.add_theme_constant_override("separation", 6)
	controls.add_child(palette_row)
	for i in 3:
		var button := _button(["参考配色", "紫雷", "金雷"][i])
		button.toggle_mode = true
		button.pressed.connect(_set_palette.bind(i))
		palette_row.add_child(button)
		_palette_buttons.append(button)
	_view_picker = OptionButton.new()
	for text in ["完整效果", "折线与折点", "只看主干", "只看分支", "只看亮片", "只看火花"]:
		_view_picker.add_item(text)
	_view_picker.custom_minimum_size.y = 38
	_view_picker.item_selected.connect(func(index: int):
		for stage in _stages:
			stage.effect.debug_view = index)
	controls.add_child(_view_picker)
	var reset_button := _button("恢复默认参数")
	reset_button.pressed.connect(_reset)
	controls.add_child(reset_button)


func _stage_card(parent: Container, title: String, subtitle: String, kind: int, seed_value: int,
		zoom: float, dummy: bool, hero: bool) -> LightningStage:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("10151e"), 16 if hero else 12))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	column.add_child(_label(title, 21 if hero else 16, Color("c4d0d8")))
	if not subtitle.is_empty():
		column.add_child(_label(subtitle, 15, MUTED))
	var stage := LightningStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 240 if hero else 150
	column.add_child(stage)
	stage.build(kind, seed_value, zoom, dummy)
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
			for stage in _stages:
				if stage.skeleton != null:
					stage.skeleton.speed_scale = 0.0 if _paused else value
			slider.release_focus()
		elif property == "loop_gap":
			_loop_gap = value
		else:
			_set_effect_property(property, value))
	column.add_child(slider)
	_sliders[property] = slider


func _check(parent: Container, title: String, initial: bool, property: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_font_size_override("font_size", 15)
	check.toggled.connect(func(value: bool):
		if property == "looping":
			_looping = value
		elif property == "dummy":
			for stage in _stages:
				stage.show_dummy = value
				stage.layout()
		else:
			_set_effect_property(property, value))
	parent.add_child(check)
	return check


func _set_effect_property(property: String, value: Variant) -> void:
	for stage in _stages + _phase_stages:
		stage.effect.set(property, value)
		stage.layout()
	_refresh_phases()
	_sync_time()


func _set_palette(index: int) -> void:
	_active_palette = index
	for i in _palette_buttons.size():
		_palette_buttons[i].set_pressed_no_signal(index == i)
	for stage in _stages + _phase_stages:
		stage.effect.core_color = PALETTES[index][0]
		stage.effect.branch_color = PALETTES[index][1]
		stage.effect.dim_color = PALETTES[index][2]


func _refresh_phases() -> void:
	for i in _phase_stages.size():
		var effect := _phase_stages[i].effect
		var times := [effect.strike_duration * 0.55, effect.strike_duration + effect.flash_duration * 0.25,
			effect.strike_duration + effect.flash_duration + effect.afterglow_duration * 0.28,
			effect.strike_duration + effect.flash_duration + effect.afterglow_duration * 0.72]
		effect.restrike_enabled = false
		effect.seek(times[i])


func _seek(seconds: float) -> void:
	_clock = maxf(seconds, 0.0)
	for stage in _stages:
		stage.effect.seek(_clock)
	_sync_time()


func _sync_time() -> void:
	if _time_slider == null or _stages.is_empty():
		return
	var effect := _stages[0].effect
	var duration := effect.get_duration()
	_time_slider.set_block_signals(true)
	_time_slider.max_value = duration
	_time_slider.value = minf(_clock, duration)
	_time_slider.set_block_signals(false)
	_time_label.text = "%.3f / %.3f s" % [minf(_clock, duration), duration]
	var phase := "等待下一次落雷"
	if _clock < effect.strike_duration:
		phase = "劈落  ·  从上向下逐段显现"
	elif _clock < effect.strike_duration + effect.flash_duration:
		phase = "亮闪  ·  骨白主干与触地火花"
	elif _clock < duration:
		phase = "余光  ·  分支先消退，主干随后消退"
	_phase_label.text = ("已暂停  /  " if _paused else "播放中  /  ") + phase


func _set_paused(value: bool) -> void:
	_paused = value
	_pause_button.text = "继续 / 空格" if value else "暂停 / 空格"
	for stage in _stages:
		if stage.skeleton != null:
			stage.skeleton.speed_scale = 0.0 if value else _speed
	_sync_time()


func _new_strike() -> void:
	_clock = 0.0
	for stage in _stages + _phase_stages:
		stage.effect.trigger()
	_refresh_phases()
	_set_paused(false)


func _replay() -> void:
	for stage in _stages:
		stage.effect.restart()
	_seek(0.0)
	_set_paused(false)


func _step() -> void:
	_set_paused(true)
	var duration := _stages[0].effect.get_duration()
	_seek(0.0 if _clock >= duration else minf(_clock + 1.0 / 60.0, duration))


func _reset() -> void:
	var defaults := {"speed": 1.0, "loop_gap": 1.25, "bolt_height": 136.0, "segment_count": 7,
		"lateral_spread": 11.0, "branch_spread": 38.0, "pixel_size": 1.0}
	for property in defaults:
		(_sliders[property] as HSlider).value = defaults[property]
	_loop_check.button_pressed = true
	_dummy_check.button_pressed = true
	_spark_check.button_pressed = true
	_glint_check.button_pressed = true
	_restrike_check.button_pressed = false
	_view_picker.select(0)
	for stage in _stages + _phase_stages:
		stage.effect.debug_view = 0
		stage.effect.random_seed = 17
		stage.effect.reset_sequence()
	_set_palette(0)
	_seek(0.0)
	_refresh_phases()
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
