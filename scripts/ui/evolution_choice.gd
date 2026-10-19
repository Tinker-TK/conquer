# 进化的手牌选择与点数分配；确认前只升级预览副本，取消不扣费、不改变原牌。
extends Control

const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const CARD_SCENE := preload("res://scenes/cards/unit_card.tscn")
var runtime: Node2D
var source: CardInstance
var target: CardInstance
var play_position := Vector2.ZERO
var grid: GridContainer
var preview: UnitCard
var attack_input: SpinBox
var defence_input: SpinBox
var allocation_row: HBoxContainer
var hint: Label
var confirm_button: Button
var _opened := false
var _was_paused := false
var _points := 0
var soldier_choice: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color("06111cdb")
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 110
	panel.offset_right = -110
	panel.offset_top = 110
	panel.offset_bottom = -90
	panel.add_theme_stylebox_override("panel", UI.button_box("normal", false, false, true))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label("进化 · 选择一张手牌临时升级", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var cancel := Button.new()
	UI.button(cancel, 22)
	cancel.text = "取消（不消耗卡牌或能量）"
	cancel.pressed.connect(close)
	header.add_child(cancel)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 32)
	column.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	scroll.add_child(grid)
	scroll.resized.connect(func(): grid.columns = maxi(1, int(scroll.size.x / 235.0)))
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 370
	body.add_child(detail)
	detail.add_child(_label("升级后的卡牌", 24))
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(370, 355)
	detail.add_child(slot)
	preview = CARD_SCENE.instantiate()
	preview.is_playable = false
	slot.add_child(preview)
	preview.position = Vector2(200, 190)
	preview.scale = Vector2.ONE * 0.85
	preview.hide()
	allocation_row = HBoxContainer.new()
	allocation_row.add_theme_constant_override("separation", 10)
	detail.add_child(allocation_row)
	allocation_row.add_child(_label("攻击", 21))
	attack_input = _spin()
	allocation_row.add_child(attack_input)
	allocation_row.add_child(_label("防御", 21))
	defence_input = _spin()
	allocation_row.add_child(defence_input)
	attack_input.value_changed.connect(_attack_changed)
	defence_input.value_changed.connect(_defence_changed)
	soldier_choice = preload("res://scripts/ui/soldier_branch_choice.gd").new()
	detail.add_child(soldier_choice)
	soldier_choice.chosen.connect(func(_branch: String): _update_preview())
	hint = _label("请选择一张可升级的手牌。", 20)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 370
	detail.add_child(hint)
	confirm_button = Button.new()
	UI.button(confirm_button, 24, true)
	confirm_button.text = "确认进化 · 1费"
	confirm_button.custom_minimum_size.y = 54
	confirm_button.pressed.connect(confirm)
	detail.add_child(confirm_button)
	hide()


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", UI.INK)
	return label


func _spin() -> SpinBox:
	var input := SpinBox.new()
	input.step = 1
	input.min_value = 0
	input.custom_minimum_size = Vector2(100, 42)
	return input


func open(card: CardInstance, point: Vector2, owner_runtime: Node2D) -> void:
	if _opened:
		return
	runtime = owner_runtime
	source = card
	target = null
	play_position = point
	_was_paused = get_tree().paused
	_opened = true
	get_tree().paused = true
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for candidate: CardInstance in runtime.plays.candidates(source):
		var button := Button.new()
		button.custom_minimum_size = Vector2(218, 295)
		UI.button(button)
		button.pressed.connect(choose_card.bind(candidate))
		grid.add_child(button)
		var view := CARD_SCENE.instantiate() as UnitCard
		view.is_playable = false
		button.add_child(view)
		view.setup(candidate)
		view.position = Vector2(117, 158)
		view.scale = Vector2.ONE * 0.70
	preview.hide()
	allocation_row.hide()
	soldier_choice.hide()
	confirm_button.text = "确认进化 · %d费" % source.get_cost()
	confirm_button.disabled = true
	hint.text = "请选择一张可升级的手牌。取消不会扣费。"
	show()


func choose_card(card: CardInstance) -> void:
	if not runtime.plays.candidates(source).has(card):
		return
	target = card
	soldier_choice.set_card(card)
	_points = target.ability_points + maxi(0, target.unit_data.upgrade_ability_points) if target.is_unit_card() else 0
	attack_input.max_value = _points
	defence_input.max_value = _points
	attack_input.set_value_no_signal(_points)
	defence_input.set_value_no_signal(0)
	allocation_row.visible = target.is_unit_card()
	confirm_button.disabled = false
	_update_preview()


func _attack_changed(value: float) -> void:
	defence_input.set_value_no_signal(_points - int(value))
	_update_preview()


func _defence_changed(value: float) -> void:
	attack_input.set_value_no_signal(_points - int(value))
	_update_preview()


func _update_preview() -> void:
	if target == null:
		return
	if target.needs_soldier_choice() and soldier_choice.selected_branch.is_empty():
		confirm_button.disabled = true
		preview.hide()
		hint.text = "请选择士兵本次进化技能：斩击或飞弹。"
		return
	confirm_button.disabled = false
	var copy := CardInstance.new(target.definition)
	for key in ["upgrade_count", "ability_points", "attack_points", "defence_points", "cost_increase", "next_unit_discount", "free_until_discard", "round_cost_reduction"]:
		copy.set(key, target.get(key))
	copy.soldier_specialization = target.soldier_specialization
	copy.temporary_upgrade(Vector2i(int(attack_input.value), int(defence_input.value)), soldier_choice.selected_branch)
	preview.setup(copy)
	preview.show()
	hint.text = "分配 %d 点：攻击 +%d，防御 +%d。\n下次使用后恢复升级前原状，保留原品质及已有永久升级。" % [_points, int(attack_input.value), int(defence_input.value)] if target.is_unit_card() else "下次使用后恢复升级前原状，保留原品质及已有永久升级。"


func confirm() -> void:
	if not _opened or target == null:
		return
	var selection := {"card": target, "allocation": Vector2i(int(attack_input.value), int(defence_input.value)), "soldier_branch": soldier_choice.selected_branch}
	var card := source
	var point := play_position
	close()
	runtime.try_play(card, point, false, 0, false, selection)


func close() -> void:
	if not _opened:
		return
	_opened = false
	hide()
	get_tree().paused = _was_paused
	target = null
	source = null


func _input(event: InputEvent) -> void:
	if _opened and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _opened:
		get_tree().paused = _was_paused
