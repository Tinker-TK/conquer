extends Control
## F6 独立预览。只展示 SpriteFrames，不实例化单位、地图或战斗逻辑。

const FLAME_SCENE := preload("res://scenes/effects/pixel_flame.tscn")
const SKELETON_TEXTURE := preload("res://assets/characters/Skeleton/Skeleton with shadows/Skeleton.png")
const PRESET_NAMES := ["灵魂火", "橙色火焰", "绿色毒焰", "紫色奥术"]
const ACCENT := Color("89cfca")

class FlameStage extends Control:
	var effect: PixelFlame
	var skeleton: AnimatedSprite2D
	var display_scale := 4.0
	var tint := Color("89cfca")

	func build(scene: PackedScene, skeleton_texture: Texture2D, with_skeleton: bool, zoom: float) -> void:
		display_scale = zoom
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		effect = scene.instantiate() as PixelFlame
		add_child(effect)
		if with_skeleton:
			skeleton = AnimatedSprite2D.new()
			skeleton.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			var frames := SpriteFrames.new()
			frames.set_animation_speed("default", 8.0)
			for i in 6:
				var frame := AtlasTexture.new()
				frame.atlas = skeleton_texture
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
		var zoom := minf(display_scale, size.y / 92.0)
		var floor_point := Vector2(size.x * 0.5, size.y * 0.84)
		effect.scale = Vector2.ONE * zoom
		effect.position = floor_point + Vector2(0, 9.0 * zoom)
		if skeleton != null:
			skeleton.scale = Vector2.ONE * zoom * 1.55
			skeleton.position = floor_point + Vector2(-4, -11) * zoom * 1.55
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0c141c"))
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0.24, 0.37, 0.43, 0.08))
		for y in range(0, int(size.y), 40):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.24, 0.37, 0.43, 0.08))
		var floor_point := Vector2(size.x * 0.5, size.y * 0.84)
		for i in range(5, 0, -1):
			var radius := Vector2(38.0 + i * 12.0, 4.0 + i * 3.0) * minf(display_scale / 3.0, 1.4)
			var polygon := PackedVector2Array()
			for j in 48:
				polygon.append(floor_point + Vector2(cos(j * TAU / 48), sin(j * TAU / 48)) * radius)
			draw_colored_polygon(polygon, Color(tint, 0.018))
		draw_line(floor_point + Vector2(-62, 0), floor_point + Vector2(62, 0), Color(tint, 0.23), 1.0)

var _stages: Array[FlameStage] = []
var _variants: Array[FlameStage] = []
var _sliders: Dictionary = {}
var _palette_buttons: Array[Button] = []
var _pause_button: Button
var _shape_picker: OptionButton
var _view_picker: OptionButton
var _embers_check: CheckButton
var _glow_check: CheckButton
var _status: Label
var _paused := false
var _active_preset := 0


func _ready() -> void:
	get_window().title = "像素灵魂火焰 · 独立预览"
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
	heading.add_child(_label("像素灵魂火焰", 40, Color("edf4ef")))
	heading.add_child(_label("参考《五星地牢》开发日志 04  ·  独立效果预览", 18, Color("80969d")))
	var badge := _label("VFX STUDY  /  04", 17, ACCENT)
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
	var hero_row := HBoxContainer.new()
	hero_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hero_row.add_theme_constant_override("separation", 16)
	left.add_child(hero_row)
	_stages.append(_stage_card(hero_row, "01  /  独立火焰", "观察火苗轮廓、亮芯和脱落火星", false, 4.7, 0, true))
	_stages.append(_stage_card(hero_row, "02  /  骷髅背焰", "角色仅用于尺寸与前后层次参照", true, 4.7, 0, true))
	left.add_child(_label("配色变体", 21, Color("d1deda")))
	var variants := HBoxContainer.new()
	variants.add_theme_constant_override("separation", 14)
	variants.custom_minimum_size.y = 226
	left.add_child(variants)
	for i in 4:
		_variants.append(_stage_card(variants, PRESET_NAMES[i], "", false, 1.9, i, false))
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 356
	sidebar.add_theme_stylebox_override("panel", _panel_style(Color("101b24")))
	content.add_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 12)
	scroll.add_child(controls)
	controls.add_child(_label("实时调整", 25, Color("edf4ef")))
	controls.add_child(_label("调整立即作用于上方两种预览", 15, Color("80969d")))
	var preset_grid := GridContainer.new()
	preset_grid.columns = 2
	preset_grid.add_theme_constant_override("h_separation", 8)
	preset_grid.add_theme_constant_override("v_separation", 8)
	controls.add_child(preset_grid)
	for i in 4:
		var button := _button(PRESET_NAMES[i])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_set_palette.bind(i))
		preset_grid.add_child(button)
		_palette_buttons.append(button)
	_shape_picker = OptionButton.new()
	_shape_picker.add_item("圆润灵魂火")
	_shape_picker.add_item("修长火苗")
	_shape_picker.custom_minimum_size.y = 40
	_shape_picker.item_selected.connect(func(index: int):
		for stage in _stages:
			stage.effect.shape = index)
	controls.add_child(_shape_picker)
	_add_slider(controls, "燃烧强度", "intensity", 0, 1.5, 0.01, 1.0)
	_add_slider(controls, "上升速度", "flow_speed", 0, 3, 0.05, 1.0)
	_add_slider(controls, "火苗摆动", "distortion", 0, 0.65, 0.01, 0.28)
	_add_slider(controls, "边缘侵蚀", "erosion", 0, 0.8, 0.01, 0.30)
	_add_slider(controls, "风向偏移", "wind", -1, 1, 0.05, 0.0)
	_add_slider(controls, "像素颗粒", "pixel_size", 0.5, 4, 0.5, 1.0)
	_embers_check = _check(controls, "上升火星", true, "embers_enabled")
	_glow_check = _check(controls, "柔和光晕", false, "glow_enabled")
	_view_picker = OptionButton.new()
	for view in ["完整效果", "火焰遮罩", "摆动噪声", "侵蚀噪声", "热度分层"]:
		_view_picker.add_item(view)
	_view_picker.custom_minimum_size.y = 40
	_view_picker.item_selected.connect(func(index: int):
		for stage in _stages:
			stage.effect.debug_view = index)
	controls.add_child(_view_picker)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	controls.add_child(actions)
	_pause_button = _button("暂停  /  空格")
	_pause_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_button.pressed.connect(_toggle_pause)
	actions.add_child(_pause_button)
	var reset := _button("恢复默认")
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset.pressed.connect(_reset)
	actions.add_child(reset)
	_status = _label("", 15, ACCENT)
	controls.add_child(_status)
	var footer := _label("空格 暂停/继续     R 恢复默认     1—4 切换配色     ·     所有调整仅作用于此预览场景", 16, Color("80969d"))
	page.add_child(footer)
	_set_palette(0)
	print("PIXEL_FLAME_DEMO_READY")
	if "--capture-flame-demo" in OS.get_cmdline_user_args():
		await get_tree().create_timer(1.0).timeout
		_set_paused(true)
		for stage in _stages + _variants:
			stage.effect.seek(2.4)
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.maintenance/pixel-flame")
		get_viewport().get_texture().get_image().save_png("res://.maintenance/pixel-flame/demo.png")
		print("PIXEL_FLAME_DEMO_CAPTURED")
		get_tree().quit()


func _stage_card(parent: Container, title: String, subtitle: String, with_skeleton: bool,
		zoom: float, preset: int, hero: bool) -> FlameStage:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _panel_style(Color("0c141c")))
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title, 20 if hero else 17, Color("d1deda")))
	if not subtitle.is_empty():
		box.add_child(_label(subtitle, 15, Color("80969d")))
	var stage := FlameStage.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size.y = 260 if hero else 124
	box.add_child(stage)
	stage.build(FLAME_SCENE, SKELETON_TEXTURE, with_skeleton, zoom)
	stage.effect.palette_preset = preset
	stage.effect.random_seed = 2.0 if with_skeleton else 1.0
	stage.tint = stage.effect.get_palette()[3]
	var swatches := HBoxContainer.new()
	swatches.add_theme_constant_override("separation", 4)
	box.add_child(swatches)
	for color in stage.effect.get_palette():
		var swatch := ColorRect.new()
		swatch.color = color
		swatch.custom_minimum_size = Vector2(18, 5 if hero else 4)
		swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		swatches.add_child(swatch)
	stage.set_meta("swatches", swatches)
	return stage


func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("22343e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 18
	style.content_margin_bottom = 18
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
	button.add_theme_stylebox_override("normal", _button_style(Color("192a35")))
	button.add_theme_stylebox_override("hover", _button_style(Color("28444d")))
	button.add_theme_stylebox_override("pressed", _button_style(Color("35666d")))
	return button


func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	return style


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
	slider.custom_minimum_size.y = 22
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		for stage in _stages:
			stage.effect.set(property, value))
	box.add_child(slider)
	_sliders[property] = slider


func _check(parent: Container, title: String, initial: bool, property: String) -> CheckButton:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.add_theme_font_size_override("font_size", 16)
	check.toggled.connect(func(value: bool):
		for stage in _stages:
			stage.effect.set(property, value))
	parent.add_child(check)
	return check


func _set_palette(index: int) -> void:
	_active_preset = index
	for i in _palette_buttons.size():
		_palette_buttons[i].set_pressed_no_signal(i == index)
	for stage in _stages:
		stage.effect.palette_preset = index
		stage.tint = stage.effect.get_palette()[3]
		stage.queue_redraw()
		var swatches := stage.get_meta("swatches") as HBoxContainer
		for i in 5:
			(swatches.get_child(i) as ColorRect).color = stage.effect.get_palette()[i]
	_update_status()


func _toggle_pause() -> void:
	_set_paused(not _paused)


func _set_paused(paused: bool) -> void:
	_paused = paused
	for stage in _stages + _variants:
		stage.effect.playing = not paused
		if stage.skeleton != null:
			stage.skeleton.speed_scale = 0.0 if paused else 1.0
	_pause_button.text = "继续  /  空格" if paused else "暂停  /  空格"
	_update_status()


func _update_status() -> void:
	if _status != null:
		_status.text = "%s  ·  %s" % [PRESET_NAMES[_active_preset], "已暂停" if _paused else "播放中"]


func _reset() -> void:
	var defaults := {"intensity": 1.0, "flow_speed": 1.0, "distortion": 0.28,
		"erosion": 0.30, "wind": 0.0, "pixel_size": 1.0}
	for key in defaults:
		(_sliders[key] as HSlider).value = defaults[key]
	_shape_picker.select(0)
	_view_picker.select(0)
	_embers_check.button_pressed = true
	_glow_check.button_pressed = false
	for stage in _stages:
		stage.effect.shape = 0
		stage.effect.debug_view = 0
	for stage in _stages + _variants:
		stage.effect.restart()
	_set_palette(0)
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
