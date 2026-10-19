# 常驻顶部倍速选择；地图和暂停中可预选，战斗开始或恢复时生效。
extends HBoxContainer

const UI = preload("res://scripts/ui/pixel_ui_style.gd")


func _ready() -> void:
	var group := ButtonGroup.new()
	for index in get_child_count():
		var button := get_child(index) as Button
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(60, 44)
		UI.button(button, 18, false, true)
		button.icon = null
		button.text = ["原速", "2倍", "3倍"][index]
		button.tooltip_text = "战斗按原速播放" if index == 0 else "战斗以 %d 倍速播放" % (index + 1)
		button.pressed.connect(BattleSpeed.set_multiplier.bind(index + 1))
	BattleSpeed.multiplier_changed.connect(_refresh)
	_refresh(BattleSpeed.multiplier)
	reset_size()


func _refresh(value: int) -> void:
	for index in get_child_count():
		var button := get_child(index) as Button
		button.set_pressed_no_signal(index + 1 == value)
