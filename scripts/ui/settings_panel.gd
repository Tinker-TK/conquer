# 两个设置页只建立一次；值由常驻 GameSettings 保存并应用。
extends Control
signal close_requested
signal standalone_requested
const Style = preload("res://scripts/ui/settings_style.gd")
var tabs: Array[Button] = []
var pages: Array[Control] = []
var controls: Dictionary = {}
var status: Label
var active_tab := 0
var standalone_button: Button


func _ready() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 2:
		var tab := _button(["视频设置", "音频设置"][index], Vector2(710 + index * 260, 145), Vector2(240, 76), select_tab.bind(index))
		tab.toggle_mode = true
		tabs.append(tab)
		var page := Control.new()
		page.size = size
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(page)
		pages.append(page)
	_build_video()
	_build_audio()
	_button("←  返回", Vector2(55, 880), Vector2(190, 72), func(): close_requested.emit())
	status = _label(self, "", Vector2(455, 1000), 20, Color("aaafa8"))
	status.size = Vector2(1110, 65)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	standalone_button = _button("在独立窗口中打开", Vector2(1490, 145), Vector2(340, 76), func(): standalone_requested.emit())
	standalone_button.visible = Engine.is_embedded_in_editor()
	standalone_button.tooltip_text = "保存征途后在独立窗口继续，并打开设置。未完成的地点将从进入前重开。"
	GameSettings.changed.connect(refresh)
	refresh()
	select_tab(0)


func _label(parent: Node, text: String, point: Vector2, font_size: int = 28, color: Color = Style.PAPER) -> Label:
	var label := Style.FontStyle.label(text, point, font_size, color)
	parent.add_child(label)
	return label


func _button(text: String, point: Vector2, extent: Vector2, callback: Callable, parent: Node = self) -> Button:
	var result := Button.new()
	result.text = text
	result.position = point
	result.size = extent
	Style.button(result)
	result.pressed.connect(callback)
	parent.add_child(result)
	return result


func _row(page: Control, title: String, index: int) -> float:
	var y := 252.0 + index * 78.0
	_label(page, title, Vector2(466, y + 10))
	var divider := ColorRect.new()
	divider.color = Color("484a40")
	divider.position = Vector2(455, y + 74)
	divider.size = Vector2(1010, 1)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(divider)
	return y


func _check(page: Control, title: String, index: int, key: String, audio: bool = false) -> void:
	var y := _row(page, title, index)
	var check := CheckBox.new()
	check.position = Vector2(1268, y + 3)
	check.size = Vector2(56, 56)
	check.name = key
	Style.checkbox(check)
	page.add_child(check)
	check.toggled.connect(func(value: bool):
		if audio: GameSettings.set_audio(key, value)
		else: GameSettings.set_video(key, value))
	controls[key] = check


func _option(page: Control, title: String, index: int, key: String, entries: Array, values: Array) -> void:
	var y := _row(page, title, index)
	var option := OptionButton.new()
	option.position = Vector2(1135, y + 4)
	option.size = Vector2(320, 62)
	option.name = key
	option.alignment = HORIZONTAL_ALIGNMENT_CENTER
	Style.button(option, 27)
	option.add_theme_color_override("font_color", Style.UI.INK)
	var popup := option.get_popup()
	popup.add_theme_font_override("font", Style.FontStyle.chinese())
	popup.add_theme_font_size_override("font_size", 26)
	popup.add_theme_color_override("font_color", Style.PAPER)
	popup.add_theme_stylebox_override("panel", Style.box(Color("243c48")))
	for entry in entries:
		option.add_item(str(entry))
	option.set_meta("values", values)
	option.item_selected.connect(func(selected: int): GameSettings.set_video(key, values[selected]))
	page.add_child(option)
	controls[key] = option


func _stepper(page: Control, title: String, index: int, key: String, entries: Array, values: Array) -> void:
	var y := _row(page, title, index)
	for direction in [-1, 1]:
		var arrow := _button("◀" if direction == -1 else "▶", Vector2(1135 if direction == -1 else 1395, y + 4), Vector2(60, 60), _cycle.bind(key, direction), page)
		arrow.name = key + ("_previous" if direction == -1 else "_next")
	var value := _label(page, "", Vector2(1200, y + 10))
	value.size.x = 190
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.set_meta("values", values)
	value.set_meta("entries", entries)
	controls[key] = value


func _cycle(key: String, direction: int) -> void:
	var values: Array = controls[key].get_meta("values")
	var current := values.find(GameSettings.video[key])
	GameSettings.set_video(key, values[posmod(current + direction, values.size())])


func _build_video() -> void:
	var page := pages[0]
	_check(page, "全屏模式", 0, "fullscreen")
	var monitors: Array = []
	var monitor_values: Array = []
	for index in maxi(1, DisplayServer.get_screen_count()):
		monitors.append("显示器 (%d)" % (index + 1))
		monitor_values.append(index)
	_option(page, "显示器选择", 1, "monitor", monitors, monitor_values)
	_option(page, "窗口化分辨率", 2, "resolution", ["1280 × 720", "1600 × 900", "1920 × 1080", "2560 × 1440", "3840 × 2160"], [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)])
	_option(page, "画面宽高比", 3, "aspect", GameSettings.ASPECTS.keys(), GameSettings.ASPECTS.keys())
	_check(page, "窗口缩放", 4, "resizable")
	_stepper(page, "垂直同步", 5, "vsync", ["关闭", "开启", "自适应"], [0, 1, 2])
	_stepper(page, "帧数上限", 6, "fps", ["无限制", "30", "60", "90", "120", "144", "165", "240"], GameSettings.FPS_OPTIONS)
	_stepper(page, "MSAA", 7, "msaa", ["关闭", "2×", "4×", "8×"], [0, 1, 2, 3])
	var y := _row(page, "重置为默认", 8)
	var reset := _button("重置", Vector2(1167, y + 8), Vector2(256, 56), GameSettings.reset_video, page)
	Style.UI.button(reset, 30, true)


func _build_audio() -> void:
	var titles := ["全局音量", "音乐音量", "音效音量", "环境音音量"]
	var keys := ["master_volume", "music_volume", "sfx_volume", "ambience_volume"]
	for index in 4:
		var key: String = keys[index]
		var y := _row(pages[1], titles[index], index)
		var slider := HSlider.new()
		slider.position = Vector2(1135, y + 9)
		slider.size = Vector2(320, 50)
		slider.step = 1
		slider.name = key
		Style.slider(slider)
		pages[1].add_child(slider)
		var value := _label(pages[1], "", Vector2(1020, y + 10))
		value.size.x = 90
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.set_meta("label", value)
		slider.value_changed.connect(func(amount: float):
			GameSettings.set_audio(key, amount / 100.0)
			GameAudio.preview_channel(key))
		controls[key] = slider
	_check(pages[1], "在后台时静音", 4, "mute_in_background", true)


func refresh() -> void:
	for key in controls:
		var control: Control = controls[key]
		var value: Variant = GameSettings.audio[key] if GameSettings.audio.has(key) else GameSettings.video[key]
		if control is CheckBox:
			control.set_pressed_no_signal(bool(value))
		elif control is OptionButton:
			control.select(control.get_meta("values").find(value))
		elif control is HSlider:
			control.set_value_no_signal(float(value) * 100)
			control.get_meta("label").text = "%d%%" % roundi(float(value) * 100)
		else:
			var index: int = control.get_meta("values").find(value)
			control.text = control.get_meta("entries")[maxi(0, index)]
	controls.resolution.disabled = bool(GameSettings.video.fullscreen)
	controls.resizable.disabled = bool(GameSettings.video.fullscreen)
	status.text = GameSettings.last_error if not GameSettings.last_error.is_empty() else (GameSettings.video_notice if active_tab == 0 else "调整后立即生效并自动保存；拖动滑条可试听对应通道。")


func select_tab(index: int) -> void:
	active_tab = index
	for i in 2:
		pages[i].visible = i == index
		tabs[i].set_pressed_no_signal(i == index)
		Style.UI.select(tabs[i], i == index)
	tabs[index].grab_focus()
	refresh()


func focus_first() -> void:
	tabs[active_tab].grab_focus()


func has_open_popup() -> bool:
	for control in controls.values():
		if control is OptionButton and control.get_popup().visible:
			return true
	return false
