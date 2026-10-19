# 幕间配置提示和整局胜利共用的模态面板。
extends CanvasLayer

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const Style = preload("res://scripts/ui/comic_style.gd")
signal retry_requested
signal menu_requested(save_current: bool)
var design: Control
var heading: Label
var description: Label
var retry_button: Button
var menu_button: Button
var completed := false

func _ready() -> void:
	layer = 55
	process_mode = Node.PROCESS_MODE_ALWAYS
	var blocker := Control.new()
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(blocker)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.005, 0.012, 0.017, 0.88)
	blocker.add_child(dim)
	design = Control.new()
	design.size = Vector2(1920, 1080)
	blocker.add_child(design)
	var card := Panel.new()
	card.position = Vector2(490, 280)
	card.size = Vector2(940, 520)
	card.add_theme_stylebox_override("panel", UI.panel())
	design.add_child(card)
	heading = Style.label("", Vector2(40, 55), 54, Style.GOLD)
	heading.size = Vector2(860, 80)
	UI.caption(heading, "blue", 46)
	card.add_child(heading)
	description = Style.label("", Vector2(65, 162), 27, UI.INK)
	description.size = Vector2(810, 155)
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)
	retry_button = _button(card, "进入下一幕", Vector2(150, 340))
	retry_button.pressed.connect(func(): retry_requested.emit())
	menu_button = _button(card, "返回主菜单", Vector2(150, 425))
	menu_button.pressed.connect(func(): menu_requested.emit(not completed))
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func _button(parent: Control, title: String, point: Vector2) -> Button:
	var button := Button.new()
	button.text = title
	button.position = point
	button.size = Vector2(640, 65)
	UI.button(button, 28)
	parent.add_child(button)
	return button

func _resize() -> void:
	var extent := get_viewport().get_visible_rect().size
	var factor := minf(extent.x / 1920.0, extent.y / 1080.0)
	design.scale = Vector2.ONE * factor
	design.position = (extent - design.size * factor) / 2.0

func open_summary(title: String, text: String, won_run: bool) -> void:
	completed = won_run
	heading.text = title
	description.text = text
	retry_button.visible = not completed
	menu_button.text = "返回主菜单" if completed else "保存并返回主菜单"
	menu_button.position.y = 360 if completed else 425
	show()
	(menu_button if completed else retry_button).grab_focus()

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
