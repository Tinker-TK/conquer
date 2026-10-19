# 胜利奖励清单与卡牌三选一；界面只调用会话领取，不直接改动库存。
extends Control

signal continue_requested
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const STYLE = preload("res://scripts/ui/comic_style.gd")
const CardChoice = preload("res://scripts/ui/card_choice_button.gd")
var session: RefCounted
var canvas: Control
var list_view: Control
var cards_view: Control
var rows: VBoxContainer
var reward_buttons: Array[Button] = []
var reward_labels: Array[Label] = []
var card_buttons: Array[Button] = []
var proceed: Button
var skip: Button
var back: Button
var heading: Label
var subtitle: Label
var card_offer := -1
var card_row: HBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = Theme.new()
	theme.default_font = STYLE.chinese()
	theme.default_font_size = 22
	var dim := ColorRect.new()
	dim.color = Color(0.025, 0.04, 0.06, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	list_view = Control.new()
	list_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(list_view)
	var panel := Panel.new()
	panel.position = Vector2(500, 185)
	panel.size = Vector2(920, 745)
	panel.add_theme_stylebox_override("panel", UI.panel())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_view.add_child(panel)
	heading = _label(list_view, "战斗胜利", Vector2(560, 225), Vector2(800, 76), 54, STYLE.GOLD)
	UI.caption(heading, "blue", 44)
	subtitle = _label(list_view, "点击奖励领取，整备后继续征途。", Vector2(560, 307), Vector2(800, 44), 24, UI.INK)
	rows = VBoxContainer.new()
	rows.position = Vector2(575, 385)
	rows.size = Vector2(770, 392)
	rows.add_theme_constant_override("separation", 14)
	list_view.add_child(rows)
	proceed = _button(list_view, "继续前进", Vector2(700, 827), Vector2(520, 64), func(): continue_requested.emit())
	cards_view = Control.new()
	cards_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(cards_view)
	_label(cards_view, "选择一张卡牌", Vector2(450, 225), Vector2(1020, 76), 48, STYLE.GOLD)
	_label(cards_view, "点击卡牌加入牌库，也可以跳过。右键兵种牌查看单位详情。", Vector2(450, 305), Vector2(1020, 44), 24, Color("b9c8c9"))
	var background := CardChoice.row_background()
	background.position = Vector2(420, 380)
	background.size = Vector2(1080, 446)
	cards_view.add_child(background)
	card_row = HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 40)
	background.add_child(card_row)
	skip = _button(cards_view, "跳过卡牌奖励", Vector2(990, 865), Vector2(340, 62), _skip_cards)
	back = _button(cards_view, "返回奖励列表", Vector2(590, 865), Vector2(340, 62), _show_list)
	cards_view.hide()
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	if canvas == null:
		return
	var factor := minf(size.x / 1920.0, size.y / 1080.0)
	canvas.scale = Vector2.ONE * factor
	canvas.position = (size - Vector2(1920, 1080) * factor) * 0.5

func open_rewards(value: RefCounted) -> void:
	session = value
	session.changed.connect(_refresh)
	for index in session.offers.size():
		var offer: Dictionary = session.offers[index]
		var button := _button(rows, "", Vector2.ZERO, Vector2(770, 88), _take_reward.bind(index))
		button.custom_minimum_size = Vector2(770, 88)
		var texture: Texture2D
		if offer.kind == "gold":
			texture = load("res://assets/ui_redrawn/icons/gold_coin.png")
		elif offer.has("data"):
			texture = offer.data.icon
		else:
			texture = load("res://assets/ui_redrawn/components/draw_book.png")
		if texture != null:
			var icon := TextureRect.new()
			# 先取消贴图的原始最小尺寸，再指定图标尺寸，避免大素材撑出奖励行。
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = texture
			icon.position = Vector2(22, 6)
			icon.size = Vector2(60, 60)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
		var label := _label(button, "", Vector2(106, 1), Vector2(625, 68), 26, UI.INK)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if offer.has("data"):
			button.tooltip_text = offer.data.description
		button.button_down.connect(_shift_reward_content.bind(button, 4.0))
		button.button_up.connect(_shift_reward_content.bind(button, 0.0))
		reward_buttons.append(button)
		reward_labels.append(label)
	_refresh()
	_show_list()
	show()

func show_defeat() -> void:
	heading.text = "战斗失败"
	subtitle.text = "征途暂歇，重新整备后再出发。"
	proceed.text = "返回主菜单"
	_show_list()
	show()

func _refresh() -> void:
	if session == null:
		return
	for index in reward_buttons.size():
		var offer: Dictionary = session.offers[index]
		var text := ""
		match str(offer.kind):
			"gold": text = "%d 金币" % offer.amount
			"cards": text = "卡牌奖励  ·  三选一"
			"relic": text = "遗物奖励  ·  三选一" if offer.get("options", []).size() > 1 else "遗物 · " + offer.data.display_name
			_: text = ("药水  ·  " if offer.kind == "potion" else "遗物  ·  ") + offer.data.display_name
		if offer.state == "claimed":
			text += "    已领取"
		elif offer.state == "skipped":
			text += "    已跳过"
		reward_labels[index].text = text
		reward_buttons[index].disabled = not session.available(index)
		reward_buttons[index].modulate = Color(1, 1, 1, 0.48) if offer.state != "available" else Color.WHITE
	proceed.text = "继续前进" if session.remaining() == 0 else "继续前进（放弃未领取奖励）"

func _take_reward(index: int) -> void:
	if not session.available(index):
		return
	if session.offers[index].kind == "cards":
		card_offer = index
		_show_cards()
	elif session.offers[index].kind == "relic" and session.offers[index].get("options", []).size() > 1:
		if get_node_or_null("RelicChoice") != null: return
		var picker := preload("res://scripts/ui/relic_choice_panel.gd").new()
		picker.name = "RelicChoice"
		add_child(picker)
		picker.selected.connect(func(choice: int): session.claim(index, choice))
		picker.open(session.offers[index].options)
	else:
		session.claim(index)

func _show_cards() -> void:
	if card_buttons.is_empty():
		for index in session.candidates.size():
			var button := CardChoice.new()
			button.custom_minimum_size = Vector2(320, 430)
			button.focus_mode = Control.FOCUS_NONE
			card_row.add_child(button)
			button.setup(CardInstance.new(session.candidates[index]), 1.03)
			button.pressed.connect(_take_card.bind(index))
			card_buttons.append(button)
	list_view.hide()
	cards_view.show()

func _take_card(index: int) -> void:
	if session.claim(card_offer, index):
		_show_list()

func _skip_cards() -> void:
	session.skip_cards()
	_show_list()

func _show_list() -> void:
	cards_view.hide()
	list_view.show()

func _button(parent: Node, text: String, point: Vector2, extent: Vector2, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = point
	button.size = extent
	button.focus_mode = Control.FOCUS_NONE
	UI.button(button, 25)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

# 奖励图标和文字使用独立子节点，跟随底板的按压位移。
func _shift_reward_content(button: Button, shift: float) -> void:
	for child in button.get_children():
		if child is Control:
			if not child.has_meta("surface_y"):
				child.set_meta("surface_y", child.position.y)
			child.position.y = float(child.get_meta("surface_y")) + shift

func _label(parent: Node, text: String, point: Vector2, extent: Vector2, font_size: int, color: Color) -> Label:
	var label := STYLE.label(text, point, font_size, color)
	label.size = extent
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label

