## 战斗和宝箱共用的遗物三选一；取消只关闭展示，候选由会话缓存。
extends Control

signal selected(index: int)
const STYLE = preload("res://scripts/ui/comic_style.gd")
const UI = preload("res://scripts/ui/pixel_ui_style.gd")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200

func open(options: Array, allow_defer: bool = true) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.96)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 24)
	center.add_child(column)
	var title := Label.new()
	title.text = "选择一件遗物"
	title.add_theme_font_override("font", STYLE.chinese())
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)
	for index in options.size():
		var relic: RelicDefinition = options[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(310, 420)
		UI.button(button, 24)
		button.tooltip_text = relic.description
		row.add_child(button)
		var content := VBoxContainer.new()
		content.position = Vector2(24, 24)
		content.size = Vector2(262, 372)
		content.add_theme_constant_override("separation", 18)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		var icon := TextureRect.new()
		icon.texture = relic.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(96, 96)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(icon)
		for text in [relic.display_name, relic.rarity_name() + " · " + relic.school_name(), relic.description]:
			var label := Label.new()
			label.text = text
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_override("font", STYLE.chinese())
			label.add_theme_font_size_override("font_size", 22 if text != relic.display_name else 28)
			label.add_theme_color_override("font_color", UI.INK)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(label)
		button.pressed.connect(func():
			selected.emit(index)
			queue_free())
	var back := Button.new()
	back.text = "稍后再选"
	UI.button(back, 24)
	back.custom_minimum_size.y = 56
	column.add_child(back)
	back.visible = allow_defer
	back.pressed.connect(queue_free)
