## 按十条流派分页；未发现的遗物只展示图标轮廓和流派。
extends Control

const STYLE = preload("res://scripts/ui/comic_style.gd")
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const TAGS: Array[StringName] = [&"wide", &"tall", &"death", &"dot", &"control", &"cycle", &"guard", &"ranged", &"economy", &"neutral"]
var grid: GridContainer
var title: Label
var catalog: Array[Resource] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200

func open() -> void:
	catalog = preload("res://scripts/events/event_rewards.gd").pool([], "relic")
	var dim := ColorRect.new()
	dim.color = Color(0.035, 0.05, 0.075, 0.98)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	title = Label.new()
	title.add_theme_font_override("font", STYLE.chinese())
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)
	var tabs := HFlowContainer.new()
	column.add_child(tabs)
	for tag in TAGS:
		var probe := RelicDefinition.new()
		probe.tags = [tag]
		var button := Button.new()
		button.text = probe.school_name()
		UI.button(button, 21)
		tabs.add_child(button)
		button.pressed.connect(_page.bind(tag))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)
	var close := Button.new()
	close.text = "返回游戏"
	UI.button(close, 24)
	column.add_child(close)
	close.pressed.connect(queue_free)
	_page(TAGS[0])

func _page(tag: StringName) -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var total := 0
	var collected := 0
	for relic: RelicDefinition in catalog:
		if not relic.tags.has(tag): continue
		total += 1
		var known: bool = RunManager.discovered_relics.has(String(relic.id)) or RunManager.has_relic(relic.id)
		if known: collected += 1
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(340, 170)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel", UI.panel())
		grid.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		panel.add_child(row)
		var icon := TextureRect.new()
		icon.texture = relic.icon
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color.WHITE if known else Color(0.12, 0.14, 0.17)
		row.add_child(icon)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_override("font", STYLE.chinese())
		label.add_theme_font_size_override("font_size", 20)
		label.add_theme_color_override("font_color", UI.INK)
		label.text = (relic.display_name + " · " + relic.rarity_name() + "\n" + relic.description) if known else ("未发现\n" + relic.school_name())
		row.add_child(label)
	title.text = "遗物图鉴 · 本流派 %d / %d · 全部 %d 件" % [collected, total, catalog.size()]
