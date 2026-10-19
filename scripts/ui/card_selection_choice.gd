# 检索和弃牌共用的具体卡牌选择；确认前暂停，不修改牌堆或支付费用。
extends Control

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
var runtime: Node2D
var source: CardInstance
var point := Vector2.ZERO
var selected: Array[CardInstance] = []
var grid: GridContainer
var title: Label
var confirm_button: Button
var hint: Label
var buttons: Dictionary = {}
var _opened := false
var _was_paused := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color("06111cdb")
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 130
	panel.offset_right = -130
	panel.offset_top = 115
	panel.offset_bottom = -95
	panel.add_theme_stylebox_override("panel", UI.button_box("normal", false, false, true))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	title = Label.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UI.INK)
	header.add_child(title)
	var cancel := Button.new()
	UI.button(cancel, 22)
	cancel.text = "取消（不扣费）"
	cancel.pressed.connect(close)
	header.add_child(cancel)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	hint = Label.new()
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", UI.INK)
	column.add_child(hint)
	confirm_button = Button.new()
	UI.button(confirm_button, 24, true)
	confirm_button.custom_minimum_size.y = 52
	confirm_button.pressed.connect(confirm)
	column.add_child(confirm_button)
	hide()


func open(card: CardInstance, position: Vector2, owner_runtime: Node2D) -> void:
	if _opened:
		return
	runtime = owner_runtime
	source = card
	point = position
	selected.clear()
	buttons.clear()
	_was_paused = get_tree().paused
	_opened = true
	get_tree().paused = true
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var count: int = runtime.expanded.selection_count(source)
	var effect: CardEffect = runtime.expanded.selection_effect(source)
	title.text = "%s · 选择%d张%s" % [card.definition.card_name, count, "单位牌" if effect.kind == CardEffect.Kind.TUTOR_UNIT else "要弃置的手牌"]
	for candidate: CardInstance in runtime.expanded.candidates(source):
		var button := Button.new()
		button.custom_minimum_size = Vector2(218, 295)
		UI.button(button)
		button.pressed.connect(toggle_card.bind(candidate))
		grid.add_child(button)
		buttons[candidate.id] = button
		var view := preload("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
		view.is_playable = false
		button.add_child(view)
		view.setup(candidate)
		view.position = Vector2(117, 158)
		view.scale = Vector2.ONE * 0.70
	_refresh()
	show()


func toggle_card(card: CardInstance) -> void:
	if not _opened or not runtime.expanded.candidates(source).has(card):
		return
	if selected.has(card):
		selected.erase(card)
	elif selected.size() < runtime.expanded.selection_count(source):
		selected.append(card)
	_refresh()


func _refresh() -> void:
	var count: int = runtime.expanded.selection_count(source)
	hint.text = "已选%d/%d张。确认后结算；取消不会消耗卡牌或能量。" % [selected.size(), count]
	confirm_button.text = "确认 · %d费" % source.get_cost()
	confirm_button.disabled = selected.size() != count
	for id: int in buttons:
		buttons[id].modulate = Color("f0d49b") if selected.any(func(card: CardInstance): return card.id == id) else Color.WHITE


func confirm() -> void:
	if not _opened or confirm_button.disabled:
		return
	var card := source
	var play_position := point
	var choice := {"cards": selected.duplicate()}
	close()
	runtime.try_play(card, play_position, false, 0, false, choice)


func close() -> void:
	if not _opened:
		return
	_opened = false
	hide()
	get_tree().paused = _was_paused
	source = null
	selected.clear()


func _input(event: InputEvent) -> void:
	if _opened and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _opened:
		get_tree().paused = _was_paused
