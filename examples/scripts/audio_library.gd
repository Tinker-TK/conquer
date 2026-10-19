# F6 统一音效试听库。素材节点与来源都保存在 audio_library.tscn，新增节点自动出现在界面。
extends Control

const PREVIEW_BUS := &"AudioLibraryPreview"
const PREFERENCES := "user://audio_library.cfg"
const INK := Color("eaf0fc")
const MUTED := Color("9caec9")
const ACCENT := Color("7eb5ff")

var samples: Array[AudioStreamPlayer] = []
var category_buttons: Dictionary = {}
var sample_buttons: Dictionary = {}
var favorites: Dictionary = {}
var active_category := "latest"
var selected_sample: AudioStreamPlayer
var playing_sample: AudioStreamPlayer
var volume_db := -8.0
var preview_pitch := 1.0
var loop_enabled := false
var _created_bus := false
var _search: LineEdit
var _favorites_only: CheckButton
var _rows: VBoxContainer
var _list_scroll: ScrollContainer
var _heading: Label
var _category_description: Label
var _count: Label
var _selected_title: Label
var _details: Label
var _status: Label
var _time: Label
var _progress: ProgressBar
var _volume_label: Label
var _pitch_label: Label


func _ready() -> void:
	_load_preferences()
	_ensure_preview_bus()
	for category in $Samples.get_children():
		for child in category.get_children():
			if child is AudioStreamPlayer and child.stream != null:
				child.bus = PREVIEW_BUS
				child.autoplay = false
				child.stop()
				child.finished.connect(_on_finished.bind(child))
				samples.append(child)
	_build_ui()
	if str(get_meta("audition_batch", "")).is_empty():
		active_category = "kenney_impact"
	set_category(active_category)
	var initial_samples := visible_samples()
	if not initial_samples.is_empty():
		_show_details(initial_samples[0])


func _ensure_preview_bus() -> void:
	if AudioServer.get_bus_index(PREVIEW_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, PREVIEW_BUS)
	AudioServer.set_bus_send(index, &"Master")
	AudioServer.add_bus_effect(index, AudioEffectLimiter.new())
	_created_bus = true


func _style(color: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style


func _label(text: String, font_size: int = 22, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 46
	button.pressed.connect(action)
	return button


func _panel(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("121e32"), Color("293a55")))
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column


func _build_ui() -> void:
	var skin := Theme.new()
	skin.default_font_size = 21
	skin.set_color("font_color", "Button", INK)
	skin.set_stylebox("normal", "Button", _style(Color("192840"), Color("2a3a55")))
	skin.set_stylebox("hover", "Button", _style(Color("253c5b"), ACCENT))
	skin.set_stylebox("pressed", "Button", _style(Color("254b78"), ACCENT))
	skin.set_stylebox("focus", "Button", _style(Color(0, 0, 0, 0), ACCENT))
	skin.set_stylebox("normal", "LineEdit", _style(Color("192840"), Color("3c526f")))
	skin.set_color("font_color", "LineEdit", INK)
	skin.set_color("font_placeholder_color", "LineEdit", MUTED)
	theme = skin
	var background := ColorRect.new()
	background.color = Color("0b1424")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 18)
	margin.add_child(page)
	var header := HBoxContainer.new()
	page.add_child(header)
	var intro := VBoxContainer.new()
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(intro)
	intro.add_child(_label("音效 · 音乐试听库", 34))
	intro.add_child(_label("点击试听  /  空格或 Esc 停止  /  R 重播  /  标星收藏", 19, MUTED))
	header.add_child(_label("共 %d 条音效" % samples.size(), 22, ACCENT))
	var online = JSON.parse_string(str(get_meta("online_previews", "[]")))
	if online is Array and not online.is_empty():
		var links := HBoxContainer.new()
		links.add_theme_constant_override("separation", 14)
		page.add_child(links)
		links.add_child(_label("Suno 生成曲 · 免费档下载额度 0", 18, MUTED))
		for preview in online:
			if preview is Dictionary:
				var url := str(preview.get("url", ""))
				if url.begins_with("https://suno.com/song/"):
					var link := _button(str(preview.get("title", "在线听")), OS.shell_open.bind(url))
					link.tooltip_text = "在浏览器试听 Suno 生成曲；本地列表中的曲目另标明制作来源。"
					links.add_child(link)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	var sidebar := _panel(body)
	sidebar.get_parent().custom_minimum_size.x = 286
	sidebar.add_child(_label("分类", 24))
	var navigation := ScrollContainer.new()
	navigation.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(navigation)
	var categories := VBoxContainer.new()
	categories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	categories.add_theme_constant_override("separation", 8)
	navigation.add_child(categories)
	_add_category_button(categories, "", "全部音效", samples.size())
	var batch_id := str(get_meta("audition_batch", ""))
	if not batch_id.is_empty():
		var batch_count := 0
		for sample in samples:
			if str(sample.get_meta("batch", "")) == batch_id:
				batch_count += 1
		_add_category_button(categories, "latest", str(get_meta("audition_title", "本批试听")), batch_count)
	for category in $Samples.get_children():
		var count := 0
		for sample in samples:
			if sample.get_parent() == category:
				count += 1
		_add_category_button(categories, str(category.name), str(category.get_meta("title", category.name)), count)
	var workspace := VBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 14)
	body.add_child(workspace)
	var title_row := HBoxContainer.new()
	workspace.add_child(title_row)
	_heading = _label("", 28)
	_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_heading)
	_count = _label("", 20, MUTED)
	title_row.add_child(_count)
	_category_description = _label("", 19, MUTED)
	workspace.add_child(_category_description)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 14)
	workspace.add_child(filters)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索名称、文件名、作者、许可…"
	_search.custom_minimum_size.y = 48
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String): _refresh_list())
	filters.add_child(_search)
	_favorites_only = CheckButton.new()
	_favorites_only.text = "只看收藏"
	_favorites_only.toggled.connect(func(_value: bool): _refresh_list())
	filters.add_child(_favorites_only)
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	workspace.add_child(_list_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	_list_scroll.add_child(_rows)
	var detail := _panel(workspace)
	_selected_title = _label("请选择音效", 25, ACCENT)
	_selected_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	detail.add_child(_selected_title)
	_details = _label("", 18, MUTED)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(_details)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	detail.add_child(actions)
	actions.add_child(_button("重播", func(): play_sample(selected_sample)))
	actions.add_child(_button("停止", stop_preview))
	actions.add_child(_button("复制资源路径", _copy_path))
	actions.add_child(_button("查看素材来源", _open_source))
	_status = _label("就绪", 18, MUTED)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	actions.add_child(_status)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 14)
	page.add_child(controls)
	_volume_label = _label("音量 %d dB" % volume_db, 20)
	_volume_label.custom_minimum_size.x = 140
	controls.add_child(_volume_label)
	var volume := HSlider.new()
	volume.min_value = -36
	volume.max_value = 0
	volume.step = 1
	volume.value = volume_db
	volume.custom_minimum_size.x = 220
	volume.value_changed.connect(_set_volume)
	controls.add_child(volume)
	_pitch_label = _label("音调 %.2f×" % preview_pitch, 20)
	_pitch_label.custom_minimum_size.x = 140
	controls.add_child(_pitch_label)
	var pitch := HSlider.new()
	pitch.min_value = .5
	pitch.max_value = 1.5
	pitch.step = .05
	pitch.value = preview_pitch
	pitch.custom_minimum_size.x = 200
	pitch.value_changed.connect(_set_pitch)
	controls.add_child(pitch)
	controls.add_child(_button("原音调", func(): pitch.value = 1.0))
	var loop_toggle := CheckButton.new()
	loop_toggle.text = "循环"
	loop_toggle.tooltip_text = "循环播放当前条目，便于检查 BGM / 环境音的接缝"
	loop_toggle.button_pressed = loop_enabled
	loop_toggle.toggled.connect(_set_loop)
	controls.add_child(loop_toggle)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.custom_minimum_size.y = 14
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	controls.add_child(_progress)
	_time = _label("0.00 / 0.00 s", 19, MUTED)
	_time.custom_minimum_size.x = 160
	controls.add_child(_time)


func _add_category_button(parent: Node, key: String, title: String, count: int) -> void:
	var button := _button("%s  ·  %d" % [title, count], set_category.bind(key))
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 19)
	parent.add_child(button)
	category_buttons[key] = button


func set_category(key: String) -> void:
	active_category = key
	_list_scroll.scroll_vertical = 0
	var category := $Samples.get_node_or_null(NodePath(key)) if not key.is_empty() else null
	_heading.text = str(category.get_meta("title", category.name)) if category != null else "全部音效"
	_category_description.text = str(category.get_meta("description", "")) if category != null else "所有后续收集素材统一保存在此场景；上一批可用于对照。"
	if key == "latest":
		_heading.text = str(get_meta("audition_title", "本批试听"))
		_category_description.text = str(get_meta("audition_description", ""))
	for button_key in category_buttons:
		category_buttons[button_key].add_theme_stylebox_override("normal", _style(
			Color("254b78") if button_key == key else Color("192840"),
			ACCENT if button_key == key else Color("2a3a55")))
	_refresh_list()


func visible_samples() -> Array[AudioStreamPlayer]:
	var result: Array[AudioStreamPlayer] = []
	var query := _search.text.strip_edges().to_lower()
	for sample in samples:
		if active_category == "latest":
			if str(sample.get_meta("batch", "")) != str(get_meta("audition_batch", "")):
				continue
		elif not active_category.is_empty() and str(sample.get_parent().name) != active_category:
			continue
		if _favorites_only.button_pressed and not favorites.has(sample.stream.resource_path):
			continue
		var searchable := "%s %s %s %s %s" % [sample.get_meta("title", sample.name),
			sample.stream.resource_path, sample.get_meta("author", ""),
			sample.get_meta("license", ""), sample.get_meta("notes", "")]
		if query.is_empty() or query in searchable.to_lower():
			result.append(sample)
	if active_category == "latest":
		var order := {"ai_combat": 0, "card": 1, "ui": 2, "ambience": 3, "music": 4}
		result.sort_custom(func(a: AudioStreamPlayer, b: AudioStreamPlayer) -> bool:
			var a_order: int = order.get(str(a.get_parent().name), 5)
			var b_order: int = order.get(str(b.get_parent().name), 5)
			return a.get_index() < b.get_index() if a_order == b_order else a_order < b_order)
	return result


func _refresh_list() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	sample_buttons.clear()
	var matching_samples := visible_samples()
	_count.text = "%d / %d 条" % [matching_samples.size(), samples.size()]
	for sample in matching_samples:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rows.add_child(row)
		var button := _button("▷  %s\n     %s  ·  %s  ·  %.2f s" % [sample.get_meta("title", sample.name),
			sample.stream.resource_path.get_file(), sample.get_meta("license", ""), sample.stream.get_length()], play_sample.bind(sample))
		button.custom_minimum_size.y = 78
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.tooltip_text = str(sample.get_meta("notes", ""))
		row.add_child(button)
		sample_buttons[sample] = button
		var favorite := _button("★" if favorites.has(sample.stream.resource_path) else "☆", _toggle_favorite.bind(sample))
		favorite.custom_minimum_size.x = 56
		favorite.tooltip_text = "收藏 / 取消收藏"
		favorite.add_theme_color_override("font_color", Color("ffd18b"))
		row.add_child(favorite)
	if matching_samples.is_empty():
		_rows.add_child(_label("没有匹配的音效；可清空搜索或切换分类。", 22, MUTED))
	_update_selection()


func play_sample(sample: AudioStreamPlayer) -> void:
	if not is_instance_valid(sample) or sample.stream == null:
		return
	stop_preview()
	selected_sample = sample
	playing_sample = sample
	sample.volume_db = volume_db
	sample.pitch_scale = preview_pitch
	_apply_loop(sample.stream)
	sample.play()
	_show_details(sample)
	_status.text = "正在播放"
	_update_selection()


func _set_loop(value: bool) -> void:
	loop_enabled = value
	if is_instance_valid(playing_sample):
		_apply_loop(playing_sample.stream)
		playing_sample.stop()
		playing_sample.play()


func _apply_loop(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop_enabled
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = loop_enabled
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if loop_enabled:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			if wav.loop_end <= wav.loop_begin:
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
		else:
			wav.loop_mode = AudioStreamWAV.LOOP_DISABLED


func stop_preview() -> void:
	if is_instance_valid(playing_sample):
		playing_sample.stop()
	playing_sample = null
	if is_instance_valid(_status):
		_status.text = "已停止"


func _show_details(sample: AudioStreamPlayer) -> void:
	selected_sample = sample
	_selected_title.text = str(sample.get_meta("title", sample.name))
	_details.text = "%s\n%s  ·  %s\n%s" % [sample.get_meta("notes", ""),
		sample.get_meta("author", ""), sample.get_meta("license", ""), sample.stream.resource_path]
	_update_selection()


func _update_selection() -> void:
	for sample in sample_buttons:
		sample_buttons[sample].add_theme_stylebox_override("normal", _style(
			Color("203f62") if sample == selected_sample else Color("192840"),
			ACCENT if sample == selected_sample else Color("2a3a55")))


func _on_finished(sample: AudioStreamPlayer) -> void:
	if playing_sample == sample:
		playing_sample = null
		_status.text = "播放完毕"
		_progress.value = 100


func _process(_delta: float) -> void:
	if not is_instance_valid(selected_sample):
		return
	var length := selected_sample.stream.get_length()
	var playback_position := playing_sample.get_playback_position() if is_instance_valid(playing_sample) else 0.0
	if _status.text == "播放完毕":
		playback_position = length
	_progress.value = 100.0 * playback_position / maxf(length, .001)
	_time.text = "%.2f / %.2f s" % [playback_position, length]


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE or (event.keycode == KEY_SPACE and not _search.has_focus()):
			stop_preview()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and not _search.has_focus():
			play_sample(selected_sample)
			get_viewport().set_input_as_handled()


func _set_volume(value: float) -> void:
	volume_db = value
	_volume_label.text = "音量 %d dB" % value
	if is_instance_valid(playing_sample):
		playing_sample.volume_db = value
	_save_preferences()


func _set_pitch(value: float) -> void:
	preview_pitch = value
	_pitch_label.text = "音调 %.2f×" % value
	if is_instance_valid(playing_sample):
		playing_sample.pitch_scale = value
	_save_preferences()


func _copy_path() -> void:
	if is_instance_valid(selected_sample):
		DisplayServer.clipboard_set(selected_sample.stream.resource_path)
		_status.text = "资源路径已复制"


func _open_source() -> void:
	if is_instance_valid(selected_sample):
		OS.shell_open(str(selected_sample.get_meta("source", "")))


func _toggle_favorite(sample: AudioStreamPlayer) -> void:
	var path := sample.stream.resource_path
	if favorites.has(path):
		favorites.erase(path)
	else:
		favorites[path] = true
	_save_preferences()
	_refresh_list()


func _load_preferences() -> void:
	var config := ConfigFile.new()
	if config.load(PREFERENCES) != OK:
		return
	volume_db = clampf(float(config.get_value("preview", "volume_db", -8.0)), -36.0, 0.0)
	preview_pitch = clampf(float(config.get_value("preview", "pitch", 1.0)), .5, 1.5)
	for path in config.get_value("preview", "favorites", []):
		favorites[path] = true


func _save_preferences() -> void:
	var config := ConfigFile.new()
	config.set_value("preview", "volume_db", volume_db)
	config.set_value("preview", "pitch", preview_pitch)
	config.set_value("preview", "favorites", favorites.keys())
	config.save(PREFERENCES)


func _exit_tree() -> void:
	stop_preview()
	for sample in samples:
		sample.stop()
	if _created_bus:
		var index := AudioServer.get_bus_index(PREVIEW_BUS)
		if index >= 0:
			AudioServer.remove_bus(index)
