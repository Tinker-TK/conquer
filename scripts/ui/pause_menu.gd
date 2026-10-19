# 顶部设置/Esc 打开暂停菜单；设置返回菜单，继续恢复打开前的暂停状态。
extends CanvasLayer
const Style = preload("res://scripts/ui/settings_style.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")
signal save_exit_requested
signal standalone_requested
var blocker: Control
var design: Control
var menu: Control
var settings: Control
var encyclopedia: Control
var buttons: Array[Button] = []
var message: Label
var opened := false
var previous_pause := false
var previous_focus: Control


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	blocker = Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.012, 0.017, 0.88)
	blocker.add_child(dim)
	design = Control.new()
	design.size = Vector2(1920, 1080)
	design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blocker.add_child(design)
	menu = Control.new()
	menu.size = design.size
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design.add_child(menu)
	var title := Style.FontStyle.label("已暂停", Vector2(710, 250), 64, Style.GOLD)
	title.size = Vector2(500, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu.add_child(title)
	var actions := [close, show_settings, show_encyclopedia, func(): save_exit_requested.emit()]
	for index in 4:
		var button := Button.new()
		button.text = ["继续", "设置", "图鉴", "保存并退出"][index]
		button.name = ["Continue", "Settings", "Encyclopedia", "SaveExit"][index]
		button.position = Vector2(795, 365 + index * 82)
		button.size = Vector2(330, 66)
		Style.button(button, 34)
		button.pressed.connect(actions[index])
		menu.add_child(button)
		buttons.append(button)
	message = Style.FontStyle.label("", Vector2(560, 701), 22, Color("afbcb7"))
	message.size = Vector2(800, 100)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	menu.add_child(message)
	settings = SettingsPanel.new()
	design.add_child(settings)
	settings.close_requested.connect(show_menu)
	settings.standalone_requested.connect(func(): standalone_requested.emit())
	settings.hide()
	blocker.hide()
	get_viewport().size_changed.connect(_resize)
	_resize()


func _resize() -> void:
	var extent := get_viewport().get_visible_rect().size
	var factor := minf(extent.x / 1920, extent.y / 1080)
	design.scale = Vector2.ONE * factor
	design.position = (extent - design.size * factor) / 2


func open(restart_location: bool = false) -> void:
	if opened or SceneTransition.busy:
		return
	previous_pause = get_tree().paused
	previous_focus = get_viewport().gui_get_focus_owner()
	get_tree().paused = true
	opened = true
	blocker.show()
	message.text = "保存后返回主菜单；未完成的地点将从进入前继续。" if restart_location else "保存当前征途，并返回主菜单。"
	show_menu()


func show_menu() -> void:
	if is_instance_valid(encyclopedia): encyclopedia.close_book()
	settings.hide()
	menu.show()
	buttons[0].grab_focus()


func show_settings() -> void:
	if is_instance_valid(encyclopedia): encyclopedia.close_book()
	menu.hide()
	settings.show()
	settings.refresh()
	settings.focus_first()


func show_encyclopedia() -> void:
	if not is_instance_valid(encyclopedia):
		encyclopedia = preload("res://scenes/ui/encyclopedia.tscn").instantiate()
		design.add_child(encyclopedia)
		encyclopedia.close_requested.connect(show_menu)
	menu.hide()
	settings.hide()
	encyclopedia.open_book()


func close() -> void:
	if not opened:
		return
	opened = false
	if is_instance_valid(encyclopedia): encyclopedia.close_book()
	blocker.hide()
	get_tree().paused = previous_pause
	if is_instance_valid(previous_focus) and previous_focus.is_visible_in_tree():
		previous_focus.grab_focus()


func _input(event: InputEvent) -> void:
	if opened and event.is_action_pressed("ui_cancel"):
		if is_instance_valid(encyclopedia) and encyclopedia.visible:
			if encyclopedia.directory.get_popup().visible:
				encyclopedia.directory.get_popup().hide()
			else:
				show_menu()
			get_viewport().set_input_as_handled()
			return
		# 下拉列表先自行关闭；不能把同一个 Esc 继续传给背景卡组或商店。
		if settings.visible and settings.has_open_popup():
			return
		if settings.visible:
			show_menu()
		else:
			close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if opened:
		get_tree().paused = previous_pause
