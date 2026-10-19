# 核心逻辑：中世纪魔法征服主菜单，提供出征、继续存档、设置和退出。
# 数据流向：鼠标/键盘 → 菜单选择 → 新局或存档 → 常驻幕布切场。
# 选型决策：1920×1080 设计画布中，标题与纵向菜单共用左侧视觉中心，皮肤独立于战斗主题。
# 性能：开局创建一次控件，按钮仅在高亮补间期间重画；完整插画静态展示。
extends CanvasLayer

const Style = preload("res://scripts/ui/fantasy_menu_style.gd")
const HeraldicButton = preload("res://scripts/ui/fantasy_menu_button.gd")
## 主菜单显示的英文游戏标题；只改变菜单文字，不修改项目设置中的应用名称或存档标识。
@export var game_title := "CONQUER!"
## 主菜单显示的中文游戏标题；只控制菜单文字。
@export var chinese_title := "征服"
## 主菜单右侧战斗插画，独立于战斗单位资源。
@export var character_art: Texture2D = preload("res://assets/ui/comic_menu/fantasy-battle-extended.png")
var design: Control
var hero: TextureRect
var route_status: Label
var menu_buttons: Array[Button] = []
var panels: Dictionary = {}
var panel_open := ""
var selected_index := 0
var volume_slider: HSlider
var settings_panel: Control
var fullscreen_check: CheckBox
var continue_button: Button
var leaving := false
@onready var route_error: AcceptDialog = $RouteError


# 作用：引擎打开菜单时建立画面并接线；没有参数，没有返回值。
func _ready() -> void:
	RunManager.reload_map_selection()
	_build_interface()
	_build_settings()
	GameAudio.set_context(self)
	SceneTransition.finished.connect(_on_transition_finished)
	get_viewport().size_changed.connect(_resize)
	_resize()
	_refresh_route_status()
	_select(0, true)
	menu_buttons[0].grab_focus()
	_play_entrance()
	if not RunManager.map_load_error.is_empty():
		_show_route_error(RunManager.map_load_error)
	_handle_startup_settings.call_deferred()


func _handle_startup_settings() -> void:
	# 参数只消费一次；从独立窗口返回主菜单时不再次自动继续。
	if not GameSettings.consume_startup_settings():
		return
	if "--resume-settings" in OS.get_cmdline_user_args():
		var error := RunManager.load_saved_run()
		if not error.is_empty():
			_show_route_error(error)
			return
		leaving = true
		SceneTransition.change_scene("res://scenes/app/game_session.tscn", "继续征途 / 独立窗口", "grassland")
	else:
		_open_panel("settings")


# 作用：创建海报和四个菜单；没有参数，没有返回值，使用 1920×1080 设计坐标。
func _build_interface() -> void:
	design = Control.new()
	design.name = "Design"
	design.size = Vector2(1920, 1080)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	$Control.add_child(design)
	var paper := ColorRect.new()
	paper.color = Color("f4ecd4")
	paper.size = design.size
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(paper)
	# 立绘可在主场景 Inspector 更换，底板和按钮不需要跟着重做。
	hero = TextureRect.new()
	hero.name = "CharacterArt"
	hero.texture = character_art
	# 固定画高、保持纹理比例并右对齐；扩出的左侧画幅补齐斜边，不缩放原有主体。
	hero.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	hero.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	hero.size = Vector2(design.size.y * float(character_art.get_width()) / character_art.get_height(), design.size.y)
	hero.position = Vector2(design.size.x - hero.size.x, 0)
	hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(hero)
	_add_art_layer("AtlasAndArcana", preload("res://assets/ui/comic_menu/fantasy-backdrop.svg"))
	_make_ribbon(Vector2(978, 58), 0.07, Style.PAPER, Style.INK, "CROWN  ·  ARCANA  ·  CONQUEST", "王权 · 魔法 · 征服")
	_make_ribbon(Vector2(825, 1016), -0.13, Style.RED, Style.PAPER, "RAISE YOUR BANNER", "高举战旗，征服未知之境")
	_add_art_layer("HeraldicOrnaments", preload("res://assets/ui/comic_menu/fantasy-ornaments.svg"))
	_add_label(design, game_title, Vector2(159, 189), 96, Style.INK, true)
	var title := _add_label(design, game_title, Vector2(156, 185), 96, Style.PAPER, true)
	title.name = "GameTitle"
	var subtitle := _add_label(design, chinese_title, Vector2(148, 350), 38)
	subtitle.size = Vector2(582, 56)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_add_label(design, "王命", Vector2(787, 168), 17, Style.GOLD)
	var entries := [["开始征途", "PLAY", _on_start_pressed], ["继续征途", "CONTINUE", _on_continue_pressed], ["设置", "SETTINGS", _on_settings_pressed], ["退出", "EXIT", _on_end_pressed]]
	for index in entries.size():
		var button := HeraldicButton.new()
		button.name = ["Play", "ContinueRun", "Settings", "Exit"][index]
		button.text = entries[index][0]
		# 主菜单已有键盘/鼠标统一反馈，避免全局按钮接线再播放一次。
		button.set_meta("ui_sound", &"silent")
		button.english = entries[index][1]
		button.position = Vector2(148, 466 + index * 116)
		button.size = Vector2(620, 106)
		button.pressed.connect(entries[index][2])
		button.selection_requested.connect(_on_selection_requested)
		design.add_child(button)
		menu_buttons.append(button)
	continue_button = menu_buttons[1]
	# 无存档也保留第二行，维持排版；禁用时方向键/手柄自动跳过。
	continue_button.disabled = not RunManager.has_saved_run()
	continue_button.tooltip_text = "尚无存档，请先开始征途。" if continue_button.disabled else "重返上次保存的征途。"
	_update_menu_focus()
	route_status = _add_label(design, "", Vector2(161, 978), 18, Style.MUTED)
	route_status.size = Vector2(660, 32)
	route_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	route_status.visible = false
	_make_keycap("↑↓", "选择", Vector2(178, 996))
	_make_keycap("ENTER", "确认", Vector2(346, 996))
	_make_keycap("ESC", "返回", Vector2(548, 996))
	var version := _add_label(design, "v0.1  /  CONQUER", Vector2(1630, 32), 14, Style.INK, true)
	version.size = Vector2(226, 28)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var speech := _add_label(design, "以王冠之名，出征！", Vector2(1103, 248), 27, Style.INK)
	speech.name = "Speech"
	var side := _add_label(design, "CROWN   ·   ARCANA   ·   CONQUEST", Vector2(42, 182), 14, Style.BRONZE, true)
	side.rotation = PI / 2.0


func _add_art_layer(layer_name: String, texture: Texture2D) -> void:
	var art := TextureRect.new()
	art.name = layer_name
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.size = design.size
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(art)


func _update_menu_focus() -> void:
	var available: Array[Button] = []
	for button in menu_buttons:
		button.focus_mode = Control.FOCUS_NONE if button.disabled else Control.FOCUS_ALL
		if not button.disabled:
			available.append(button)
	for index in available.size():
		var button := available[index]
		button.focus_neighbor_top = button.get_path_to(available[posmod(index - 1, available.size())])
		button.focus_neighbor_bottom = button.get_path_to(available[(index + 1) % available.size()])
		button.focus_previous = button.focus_neighbor_top
		button.focus_next = button.focus_neighbor_bottom


# 作用：放置文字；parent 是所属节点，value 是内容，point 是位置，font_size/color/latin 是样式，返回标签。
func _add_label(parent: Node, value: String, point: Vector2, font_size: int, color: Color = Style.INK, latin: bool = false) -> Label:
	var result := Style.label(value, point, font_size, color, latin)
	parent.add_child(result)
	return result


# 作用：放置纸片；parent 是所属节点，points 是角点，color 是底色，没有返回值。
func _polygon(parent: Node, points: Array, color: Color) -> void:
	var shape := Polygon2D.new()
	shape.polygon = PackedVector2Array(points)
	shape.color = color
	parent.add_child(shape)


# 作用：放置倾斜丝带；point/angle 是位置与角度，paper/ink 是底色与文字色，没有返回值。
func _make_ribbon(point: Vector2, angle: float, paper: Color, ink: Color, motto: String, translation: String) -> void:
	var ribbon := Control.new()
	ribbon.position = point
	ribbon.rotation = angle
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(ribbon)
	_polygon(ribbon, [Vector2.ZERO, Vector2(1300, 0), Vector2(1300, 54), Vector2(0, 54)], paper)
	_polygon(ribbon, [Vector2(0, 3), Vector2(1300, 3), Vector2(1300, 5), Vector2(0, 5)], Style.BRONZE)
	_polygon(ribbon, [Vector2(0, 49), Vector2(1300, 49), Vector2(1300, 51), Vector2(0, 51)], Style.BRONZE)
	_polygon(ribbon, [Vector2(26, 18), Vector2(33, 27), Vector2(26, 36), Vector2(19, 27)], ink)
	_add_label(ribbon, motto, Vector2(54, 15), 19, ink, true)
	_add_label(ribbon, translation, Vector2(545, 14), 23, ink)


# 作用：建立底部键位提示；key/meaning 是键位和作用，point 是位置，没有返回值。
func _make_keycap(key: String, meaning: String, point: Vector2) -> void:
	var width := 83.0 if key == "ENTER" else 57.0
	_polygon(design, [point + Vector2(7, 0), point + Vector2(width, 0), point + Vector2(width - 7, 32), point + Vector2(0, 32)], Style.BRONZE)
	_polygon(design, [point + Vector2(8, 1), point + Vector2(width - 2, 1), point + Vector2(width - 8, 31), point + Vector2(2, 31)], Style.PAPER)
	_add_label(design, key, point + Vector2(10, 5), 17, Style.INK, true)
	_add_label(design, meaning, point + Vector2(width + 12, 5), 19)


# 作用：播放确认或移动音；accept 表示是否确认，没有返回值。
func _play_sound(accept: bool = false) -> void:
	UIAudio.play(&"confirm" if accept else &"hover")


# 作用：窗口变化时居中缩放海报；没有参数，没有返回值，窄窗口仍能看到完整菜单。
func _resize() -> void:
	var view_size := get_viewport().get_visible_rect().size
	var factor := minf(view_size.x / 1920.0, view_size.y / 1080.0)
	design.scale = Vector2.ONE * factor
	design.position = (view_size - design.size * factor) * 0.5


# 作用：播放菜单入场；没有参数，没有返回值，减少动效时直接显示终点。
func _play_entrance() -> void:
	if SceneTransition.reduced_motion:
		return
	for index in menu_buttons.size():
		var button := menu_buttons[index]
		var destination := button.position
		button.position.x -= 110.0
		button.modulate.a = 0.0
		var tween := create_tween().set_parallel(true)
		tween.tween_property(button, "position", destination, 0.45).set_delay(index * 0.07).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(button, "modulate:a", 1.0, 0.25).set_delay(index * 0.07)


# 作用：按钮焦点或悬停改变当前行；button 是发信号的按钮，没有返回值。
func _on_selection_requested(button: Button) -> void:
	if not button.disabled and panel_open.is_empty() and not SceneTransition.busy:
		# 鼠标悬停也移交键盘焦点，否则看到“设置”高亮时按 Enter 可能误开旧选项。
		if not button.has_focus():
			button.grab_focus()
		_select(menu_buttons.find(button))


# 作用：更新高亮和角色对话；index 是目标行，instant 表示跳过补间，没有返回值。
func _select(index: int, instant: bool = false) -> void:
	if index < 0 or index >= menu_buttons.size():
		return
	if index != selected_index:
		_play_sound()
	selected_index = index
	for row in menu_buttons.size():
		menu_buttons[row].set_selected(row == index, instant or SceneTransition.reduced_motion)
	design.get_node("Speech").text = ["以王冠之名，出征！", "战旗未落，征途未尽。", "整备军势，再赴征途。", "暂别疆场，来日再战。 "][index]


# 作用：处理 Esc 关闭弹层；event 是尚未消费的输入，没有返回值。
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not panel_open.is_empty():
		_close_panel()
		get_viewport().set_input_as_handled()


# 作用：主菜单共用视频/音频设置页，不另建一套偏好。
func _build_settings() -> void:
	var container := Control.new()
	container.size = design.size
	container.mouse_filter = Control.MOUSE_FILTER_STOP
	design.add_child(container)
	var dim := ColorRect.new()
	dim.size = design.size
	dim.color = Color(0.005, 0.012, 0.017, 0.91)
	container.add_child(dim)
	settings_panel = preload("res://scripts/ui/settings_panel.gd").new()
	container.add_child(settings_panel)
	settings_panel.close_requested.connect(_close_panel)
	settings_panel.standalone_requested.connect(func(): GameSettings.open_standalone())
	panels["settings"] = container
	container.hide()
	volume_slider = settings_panel.controls.master_volume
	fullscreen_check = settings_panel.controls.fullscreen

# 作用：打开弹层并移交焦点；key 是面板标识，没有返回值，Enter 不会再误触背景出征按钮。
func _open_panel(key: String) -> void:
	if SceneTransition.busy:
		return
	panel_open = key
	design.move_child(panels[key], -1)
	panels[key].show()
	for button in menu_buttons:
		button.focus_mode = Control.FOCUS_NONE
	var focusables: Array[Node] = panels[key].find_children("*", "Button", true, false)
	if not focusables.is_empty():
		focusables[0].grab_focus()
	if key == "settings":
		settings_panel.refresh()
		settings_panel.focus_first()
	_play_sound(true)


# 作用：关闭当前弹层并恢复焦点；没有参数，没有返回值。
func _close_panel() -> void:
	if panel_open.is_empty():
		return
	panels[panel_open].hide()
	panel_open = ""
	_update_menu_focus()
	menu_buttons[selected_index].grab_focus()
	_play_sound()


# 作用：打开设置；没有参数，没有返回值。
func _on_settings_pressed() -> void:
	_open_panel("settings")


# 显示当前出征路线；地图工坊的正式路线加载逻辑仍由 RunManager 管理。
func _refresh_route_status() -> void:
	var config: Dictionary = RunManager.selected_map
	if config.get("mode", "") == "procedural":
		route_status.text = "三幕随机征途 · 15 层房间 + Boss"
	elif config.is_empty():
		route_status.text = "当前路线：内置十层地图"
	else:
		route_status.text = "当前路线：%s · %d 层" % [config.name, int(config.floors)]
		for path in RunManager.project_map_paths:
			if FileAccess.file_exists(path):
				route_status.text = "三幕征途 · 第1幕：%s" % config.name
				break

# 作用：校验并导入路线；path 是文件路径，没有返回值，失败时保留旧选择。
func _on_route_selected(path: String) -> void:
	var error := RunManager.import_fixed_map(path)
	if not error.is_empty():
		_show_route_error(error)
		return
	_refresh_route_status()


# 作用：恢复内置地图；没有参数，没有返回值。
func _on_default_route_pressed() -> void:
	var error := RunManager.use_default_map()
	if not error.is_empty():
		_show_route_error(error)
	_refresh_route_status()


# 作用：显示操作失败原因；message 是提示，没有返回值。
func _show_route_error(message: String) -> void:
	route_error.dialog_text = message
	route_error.popup_centered(Vector2i(680, 240))


# 作用：重置进度并通过幕布开启一局；没有参数，没有返回值，快速双击只开启一次。
func _on_start_pressed() -> void:
	if leaving or SceneTransition.busy:
		return
	var error := RunManager.reload_map_selection()
	if not error.is_empty():
		_show_route_error(error)
		return
	var seed_text := ""
	var difficulty := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map-seed="):
			seed_text = argument.trim_prefix("--map-seed=")
		elif argument.begins_with("--map-difficulty="):
			difficulty = argument.trim_prefix("--map-difficulty=")
	error = RunManager.start_new_run(null, seed_text, difficulty)
	if not error.is_empty():
		_show_route_error(error)
		return
	leaving = true
	_play_sound(true)
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/app/game_session.tscn", "征途展开 / 翠绿原野", "grassland")


func _on_continue_pressed() -> void:
	if leaving or SceneTransition.busy or not panel_open.is_empty():
		return
	var error := RunManager.load_saved_run()
	if not error.is_empty():
		_show_route_error(error)
		return
	leaving = true
	get_tree().paused = false
	SceneTransition.change_scene("res://scenes/app/game_session.tscn", "继续征途 / 重返路线", "grassland")


# 作用：加载失败时恢复菜单操作；success 是切场结果，没有返回值。
func _on_transition_finished(success: bool) -> void:
	if not success:
		leaving = false
		_show_route_error(SceneTransition.last_error)


# 作用：退出游戏；没有参数，没有返回值，切场期间忽略退出按钮。
func _on_end_pressed() -> void:
	if not SceneTransition.busy:
		get_tree().quit()
