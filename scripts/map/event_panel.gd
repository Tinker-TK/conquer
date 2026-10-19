# 事件画面：左插图右叙事、横条选项、两组五选一、结算展示；每次打开持有独立事件会话。
@tool
extends Control
class_name EventPanel
signal resolved(choice_index: int)
const UI = preload("res://scripts/ui/pixel_ui_style.gd")
const CardChoice = preload("res://scripts/ui/card_choice_button.gd")
const EventStyle = preload("res://scripts/ui/event_ui_style.gd")
const Illustrations = preload("res://scripts/events/event_illustrations.gd")
const SESSION = preload("res://scripts/events/event_session.gd")
const ROUTE = preload("res://scripts/events/route_effects.gd")
const GOLD := EventStyle.GOLD
var session: RefCounted
var selected: Array[int] = [-1, -1]
var title_label: Label
var description_label: RichTextLabel
var art: TextureRect
var story: HBoxContainer
var choices_box: VBoxContainer
var cards_box: VBoxContainer
var result_box: VBoxContainer
var confirm_button: Button
var choice_1: Button
var choice_2: Button
var card_buttons: Array[Array] = [[], []]
var group_labels: Array[Label] = []
var hint: Label
var _finished := false
var upgrade_grid: GridContainer
var allocation_box: HBoxContainer
var attack_input: SpinBox
var defence_input: SpinBox
var allocation_hint: Label
var soldier_choice: HBoxContainer
var treasure_mode := false
var chest_button: TextureButton
var eyebrow: Label
var body_margin: MarginContainer
var narrative: VBoxContainer
const CHEST_CLOSED = preload("res://assets/ui/events/illustrations/treasure-closed.png")
const CHEST_OPEN = preload("res://assets/ui/events/illustrations/treasure-open.png")

func _ready() -> void:
	_build()
	hide()

func _label(text: String, font_size: int, color: Color = EventStyle.INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_font_override("font", EventStyle.FONT.chinese())
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.clip_text = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.tooltip_text = text
	button.custom_minimum_size.y = 92 if "\n" in text else 62
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	EventStyle.button(button)
	var caption := RichTextLabel.new()
	caption.name = "ChoiceCaption"
	caption.bbcode_enabled = true
	caption.scroll_active = false
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_override("normal_font", EventStyle.body_font())
	caption.add_theme_font_override("bold_font", EventStyle.FONT.chinese())
	caption.add_theme_font_size_override("normal_font_size", 23)
	caption.add_theme_font_size_override("bold_font_size", 23)
	caption.add_theme_color_override("default_color", EventStyle.PAPER)
	caption.add_theme_constant_override("line_separation", 5)
	var lines := text.split("\n", true, 1)
	caption.text = "[b][color=#f4d69b]" + EventStyle.escape(lines[0]) + "[/color][/b]"
	if lines.size() > 1:
		var detail := EventStyle.escape(lines[1])
		var cost_pattern := RegEx.new()
		cost_pattern.compile("最大生命 -[0-9]+|支付 [0-9]+ 金币|失去 [0-9]+ 生命")
		var matches := cost_pattern.search_all(detail)
		matches.reverse()
		for found in matches:
			detail = detail.substr(0, found.get_start()) + "[color=#ffc6aa]" + found.get_string() + "[/color]" + detail.substr(found.get_end())
		caption.text += "\n[font_size=20]" + detail + "[/font_size]"
	button.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption.offset_left = 24
	caption.offset_right = -24
	caption.offset_top = 10 if lines.size() > 1 else 16
	caption.offset_bottom = -8
	button.draw.connect(func(): caption.modulate.a = 0.5 if button.disabled else 1.0)
	button.pressed.connect(action)
	return button

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#eee7d1")
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var wash := TextureRect.new()
	wash.texture = preload("res://assets/ui/events/event_backdrop.svg")
	wash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wash)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	body_margin = margin
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 100)
	margin.add_theme_constant_override("margin_top", 150)
	margin.add_theme_constant_override("margin_bottom", 46)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	margin.add_child(body)
	story = HBoxContainer.new()
	story.size_flags_vertical = Control.SIZE_EXPAND_FILL
	story.add_theme_constant_override("separation", 90)
	body.add_child(story)
	art = TextureRect.new()
	art.custom_minimum_size.x = 680
	art.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var focus := ShaderMaterial.new()
	focus.shader = preload("res://shaders/event_illustration_focus.gdshader")
	art.material = focus
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	story.add_child(art)
	chest_button = TextureButton.new()
	chest_button.ignore_texture_size = true
	chest_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	chest_button.texture_normal = CHEST_CLOSED
	chest_button.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	chest_button.material = focus
	chest_button.tooltip_text = "打开宝箱，获得一件随机遗物"
	chest_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chest_button.pressed.connect(_open_treasure)
	art.add_child(chest_button)
	chest_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	chest_button.hide()
	var paper := PanelContainer.new()
	paper.name = "StoryPaper"
	paper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var padding := StyleBoxEmpty.new()
	padding.content_margin_top = 40
	padding.content_margin_bottom = 20
	paper.add_theme_stylebox_override("panel", padding)
	story.add_child(paper)
	narrative = VBoxContainer.new()
	narrative.custom_minimum_size.x = 596
	narrative.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrative.add_theme_constant_override("separation", 20)
	paper.add_child(narrative)
	eyebrow = _label("✦   旅 途 奇 遇   ✦", 18, EventStyle.MUTED)
	narrative.add_child(eyebrow)
	title_label = _label("", 42, EventStyle.GOLD)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narrative.add_child(title_label)
	var rule := HSeparator.new()
	rule.modulate = Color("#c6b88e")
	narrative.add_child(rule)
	description_label = RichTextLabel.new()
	description_label.custom_minimum_size.y = 210
	description_label.scroll_active = true
	description_label.fit_content = false
	description_label.bbcode_enabled = true
	description_label.add_theme_font_override("normal_font", EventStyle.body_font())
	description_label.add_theme_font_size_override("normal_font_size", 26)
	description_label.add_theme_color_override("default_color", EventStyle.INK)
	description_label.add_theme_constant_override("line_separation", 10)
	narrative.add_child(description_label)
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 14)
	narrative.add_child(choices_box)
	result_box = VBoxContainer.new()
	result_box.add_theme_constant_override("separation", 16)
	narrative.add_child(result_box)
	cards_box = VBoxContainer.new()
	cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_box.add_theme_constant_override("separation", 12)
	body.add_child(cards_box)
	hint = _label("", 19, EventStyle.MUTED)
	hint.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	body.add_child(hint)

func open_content(content: Dictionary, manager: Node = null, preview: bool = false) -> void:
	treasure_mode = false
	_set_treasure_layout(false)
	chest_button.hide()
	eyebrow.text = "✦   旅 途 奇 遇   ✦"
	session = SESSION.new()
	session.configure(content, manager, preview)
	selected = [-1, -1]
	_finished = false
	title_label.text = str(content.get("title", "旅途奇遇"))
	_set_description(str(content.get("description", "")))
	art.texture = Illustrations.texture_for(content)
	_clear(choices_box)
	_clear(cards_box)
	_clear(result_box)
	cards_box.hide()
	result_box.hide()
	story.show()
	choices_box.show()
	hint.text = "做出选择，书写你的旅途。" if not preview else "预览模式 · 奖励不会写入本局"
	for index in content.choices.size():
		var choice: Dictionary = content.choices[index]
		var text: String = choice.text
		var summary := ROUTE.summary(choice)
		if not summary.is_empty():
			text += "\n" + summary
		var button := _button(text, _choose.bind(index))
		var unavailable: String = session.option_error(index)
		button.disabled = not unavailable.is_empty()
		if button.disabled:
			button.tooltip_text = text + "\n" + unavailable
		choices_box.add_child(button)
		if index == 0:
			choice_1 = button
		elif index == 1:
			choice_2 = button
	show()

# 保留原来的调用入口，便于旧事件测试与外部场景使用。
# 作用：沿用事件会话的结算保护，宝箱图与按钮都触发同一次开箱。
func open_treasure(content: Dictionary, manager: Node, preview: bool = false) -> void:
	open_content(content, manager, preview)
	treasure_mode = true
	_set_treasure_layout(true)
	eyebrow.text = "✦   旅 途 宝 藏   ✦"
	art.texture = null
	chest_button.texture_normal = CHEST_CLOSED
	chest_button.disabled = false
	chest_button.modulate = Color.WHITE
	chest_button.show()
	_clear(choices_box)
	choice_1 = _button("打开宝箱\n获得一件随机遗物", _open_treasure)
	choice_2 = null
	choices_box.add_child(choice_1)
	hint.text = "点击宝箱或打开按钮，揭晓你的遗物。" if not preview else "预览模式 · 奖励不会写入本局"


# 所有奇遇共用左插画、右叙事的列宽，宝箱也不再缩成一张小图标。
func _set_treasure_layout(_enabled: bool) -> void:
	for side in ["left", "right"]:
		body_margin.add_theme_constant_override("margin_" + side, 100)
	body_margin.add_theme_constant_override("margin_top", 150)
	body_margin.add_theme_constant_override("margin_bottom", 46)
	story.add_theme_constant_override("separation", 90)
	art.custom_minimum_size.x = 680
	narrative.custom_minimum_size.x = 596
	chest_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_description(value: String) -> void:
	description_label.text = EventStyle.highlight(value)


func _open_treasure() -> void:
	if not treasure_mode or not visible or session == null or session.claimed:
		return
	var prepared: Dictionary = session.choose(0)
	if prepared.has("error"):
		if prepared.get("code", "") != "relic_pool_exhausted":
			hint.text = prepared.error
			return
		# 遗物有限且不能重复；收集齐后也可以完成宝箱节点，避免卡住路线。
		session.choose(1)
		var result: Dictionary = session.claim()
		if result.has("error"):
			hint.text = result.error
			return
		choices_box.hide()
		_clear(result_box)
		result_box.show()
		_set_description("你打开了宝箱。\n所有可获得的遗物都已收集，继续踏上征途吧。")
		result_box.add_child(_button("继续前进   →", _finish))
		hint.text = "已拥有全部遗物。"
	else:
		_choose_relic_or_claim(prepared)
	if session.claimed:
		chest_button.texture_normal = CHEST_OPEN
		chest_button.disabled = true
		var tween := create_tween()
		chest_button.modulate = Color(1.5, 1.3, 0.8)
		tween.tween_property(chest_button, "modulate", Color.WHITE, 0.4)


func open_event(heading: String, description: String, choices: Array[String]) -> void:
	var options: Array = []
	for text in choices:
		options.append({"text": text, "heal": 0, "gold": 0})
	open_content({"title": heading, "description": description, "choices": options},
		null if Engine.is_editor_hint() else get_node("/root/RunManager"))

func _choose(index: int) -> void:
	if not visible or session == null or session.claimed:
		return
	var prepared: Dictionary = session.choose(index)
	if prepared.has("error"):
		hint.text = prepared.error
		return
	_present_prepared()

func _present_prepared() -> void:
	var prepared: Dictionary = session.prepared
	if prepared.type == "choose_cards":
		_show_cards(prepared)
	elif prepared.type in ["train_unit", "enhance_card", "remove_card", "duplicate_card"]:
		_show_upgrades(prepared)
	else:
		_choose_relic_or_claim(prepared)


func _choose_relic_or_claim(prepared: Dictionary) -> void:
	if prepared.get("type", "") == "random_relic" and prepared.get("options", []).size() > 1:
		if get_node_or_null("RelicChoice") != null: return
		var picker := preload("res://scripts/ui/relic_choice_panel.gd").new()
		picker.name = "RelicChoice"
		add_child(picker)
		var source_session = session
		picker.selected.connect(func(index: int):
			if session != source_session or not visible: return
			remove_child(picker)
			picker.queue_free()
			selected = [index, -1]
			_claim()
			if treasure_mode and session.claimed:
				chest_button.texture_normal = CHEST_OPEN
				chest_button.disabled = true)
		picker.open(prepared.options)
	else:
		_claim()


func _show_upgrades(prepared: Dictionary) -> void:
	story.hide()
	cards_box.show()
	_clear(cards_box)
	selected = [-1, -1]
	card_buttons = [[], []]
	var training: bool = prepared.type == "train_unit"
	var heading := _label({"train_unit": "训练兵种 · 选择一张兵种卡", "enhance_card": "强化 · 选择一张战术牌", "remove_card": "移除 · 选择一张牌", "duplicate_card": "复制 · 选择一张牌（保留强化）"}[str(prepared.type)], 36, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_box.add_child(heading)
	if prepared.type in ["remove_card", "duplicate_card"]:
		var filter := OptionButton.new()
		for caption in ["全部卡牌", "征召牌", "战术牌"]:
			filter.add_item(caption)
		filter.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		filter.item_selected.connect(func(value: int):
			for i in card_buttons[0].size():
				var unit: bool = prepared.candidates[i].is_unit_card()
				card_buttons[0][i].visible = value == 0 or (unit if value == 1 else not unit))
		cards_box.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cards_box.add_child(scroll)
	upgrade_grid = GridContainer.new()
	upgrade_grid.columns = 5
	upgrade_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upgrade_grid.add_theme_constant_override("h_separation", 24)
	upgrade_grid.add_theme_constant_override("v_separation", 16)
	scroll.add_child(upgrade_grid)
	for index in prepared.candidates.size():
		var card: CardInstance = prepared.candidates[index]
		var button := Button.new()
		button.custom_minimum_size = Vector2(280, 352)
		UI.button(button)
		button.tooltip_text = card.definition.card_name + "\n" + card.upgrade_summary()
		button.pressed.connect(_select_upgrade.bind(index))
		upgrade_grid.add_child(button)
		card_buttons[0].append(button)
		if not Engine.is_editor_hint():
			var view := preload("res://scenes/cards/unit_card.tscn").instantiate() as UnitCard
			view.is_playable = false
			button.add_child(view)
			view.position = Vector2(146, 151)
			view.scale = Vector2(0.70, 0.70)
			view.setup(card)
			_ignore_mouse(view)
			view.enable_unit_details()
		else:
			var name_label := _label(card.definition.card_name, 24, UI.INK)
			button.add_child(name_label)
			name_label.position = Vector2(24, 100)
		var summary := _label(card.upgrade_summary(), 17, UI.INK)
		summary.position = Vector2(16, 292)
		summary.size.x = 248
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_child(summary)
	allocation_box = HBoxContainer.new()
	allocation_box.alignment = BoxContainer.ALIGNMENT_CENTER
	allocation_box.add_theme_constant_override("separation", 20)
	cards_box.add_child(allocation_box)
	allocation_hint = _label("先选择兵种卡，再分配能力点", 22, GOLD)
	allocation_box.add_child(allocation_hint)
	for stat in ["攻击 +", "防御 +"]:
		allocation_box.add_child(_label(stat, 22, GOLD))
		var input := SpinBox.new()
		input.min_value = 0
		input.max_value = 0
		input.step = 1
		input.custom_minimum_size.x = 110
		input.add_theme_font_size_override("font_size", 22)
		allocation_box.add_child(input)
		input.value_changed.connect(_allocation_changed)
		if stat == "攻击 +":
			attack_input = input
		else:
			defence_input = input
	allocation_box.visible = training
	soldier_choice = preload("res://scripts/ui/soldier_branch_choice.gd").new()
	cards_box.add_child(soldier_choice)
	soldier_choice.chosen.connect(func(_branch: String): _allocation_changed(0))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	cards_box.add_child(footer)
	confirm_button = _button({"train_unit": "确认训练", "enhance_card": "确认强化", "remove_card": "确认移除", "duplicate_card": "确认复制"}[str(prepared.type)], _claim)
	confirm_button.custom_minimum_size.x = 300
	confirm_button.disabled = true
	footer.add_child(confirm_button)
	var back := _button("取消并返回", _back_to_choices)
	back.custom_minimum_size.x = 260
	footer.add_child(back)
	hint.text = {"train_unit": "每 1 点能力点增加 1 点攻击或防御；技能按此牌强化等级和已选分支生效。", "enhance_card": "每张牌独立记录强化；确认前不会支付成本。", "remove_card": "仅移除选中的牌；牌组至少保留 1 张。", "duplicate_card": "复制保留训练、强化和永久增益；原牌保持不变。"}[str(prepared.type)]


func _back_to_choices() -> void:
	if session.claimed:
		return
	session.cancel()
	cards_box.hide()
	story.show()
	choices_box.show()
	hint.text = "本次奇遇只能选择一项，确认前不会支付成本。"


func _select_upgrade(index: int) -> void:
	if session.claimed:
		return
	selected[0] = index
	for i in card_buttons[0].size():
		UI.select(card_buttons[0][i], i == index)
	if session.prepared.type == "train_unit":
		soldier_choice.set_card(session.prepared.candidates[index])
		attack_input.set_value_no_signal(0)
		defence_input.set_value_no_signal(0)
		_allocation_changed(0)
	else:
		confirm_button.disabled = false


func _allocation_changed(_value: float) -> void:
	if selected[0] < 0 or session.prepared.type != "train_unit":
		return
	var card: CardInstance = session.prepared.candidates[selected[0]]
	var total := card.ability_points + maxi(0, card.unit_data.upgrade_ability_points)
	attack_input.max_value = maxi(0, total - int(defence_input.value))
	defence_input.max_value = maxi(0, total - int(attack_input.value))
	var remaining := total - int(attack_input.value) - int(defence_input.value)
	allocation_hint.text = "可分配 %d 点 · 剩余 %d 点" % [total, remaining]
	confirm_button.disabled = remaining != 0 or (card.needs_soldier_choice() and soldier_choice.selected_branch.is_empty())
	if card.needs_soldier_choice():
		if soldier_choice.selected_branch.is_empty():
			allocation_hint.text += " · 请选择斩击或飞弹"
			hint.text = "斩击：放弃弓箭，飞跃与击杀成长；飞弹：保留远近普攻，标记与友军士兵协同成长。"
		else:
			allocation_hint.text += " · 已选" + ("斩击" if soldier_choice.selected_branch == "slash" else "飞弹")
			hint.text = "斩击：350范围飞跃，每个敌人仅一次；斩过的目标死亡，自身攻击+1。" if soldier_choice.selected_branch == "slash" else "飞弹：保留远近普攻；命中时有N名己方士兵攻击目标，这N名士兵各攻击+N。"
	else:
		hint.text = "每 1 点能力点增加 1 点攻击或防御；技能按此牌强化等级和已选分支生效。"

func _show_cards(prepared: Dictionary) -> void:
	story.hide()
	# 两排卡牌与悬停放大需要完整的纵向空间，底部操作保持在窗口内。
	body_margin.add_theme_constant_override("margin_top", 150)
	body_margin.add_theme_constant_override("margin_bottom", 20)
	cards_box.show()
	_clear(cards_box)
	selected = [-1, -1]
	group_labels.clear()
	card_buttons = [[], []]
	var heading := _label(session.event.get("title", "挑选卡牌"), 36, GOLD)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cards_box.add_child(heading)
	for group in 2:
		var offers: Array = prepared.units if group == 0 else prepared.effects
		var caption := _label("", 22, GOLD)
		UI.caption(caption, "blue", 22)
		caption.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cards_box.add_child(caption)
		group_labels.append(caption)
		caption.visible = not offers.is_empty()
		var background := CardChoice.row_background()
		background.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cards_box.add_child(background)
		background.visible = not offers.is_empty()
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 26)
		background.add_child(row)
		for index in offers.size():
			var button := CardChoice.new()
			button.custom_minimum_size = Vector2(248, 294)
			button.pressed.connect(_select_card.bind(group, index))
			row.add_child(button)
			card_buttons[group].append(button)
			button.setup(CardInstance.new(offers[index]))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 20)
	cards_box.add_child(footer)
	var count: int = prepared.unit_picks + prepared.effect_picks
	confirm_button = _button("确认获得 %d 张卡牌" % count, _claim)
	confirm_button.custom_minimum_size.x = 380
	footer.add_child(confirm_button)
	var leave := _button("取消并返回", _back_to_choices)
	leave.custom_minimum_size.x = 300
	footer.add_child(leave)
	_update_selection()

func _select_card(group: int, index: int) -> void:
	if session.claimed:
		return
	selected[group] = index
	_update_selection()

func _update_selection() -> void:
	var needed := 0
	var picked := 0
	for group in 2:
		var offers: Array = session.prepared.units if group == 0 else session.prepared.effects
		if not offers.is_empty():
			needed += 1
			picked += int(selected[group] >= 0)
		group_labels[group].text = ("%s · %d 选 1" % ["征召牌" if group == 0 else "战术牌", offers.size()]) + ("   ✓ 已选择" if selected[group] >= 0 else "   · 待选择")
		for index in card_buttons[group].size():
			var button = card_buttons[group][index]
			button.set_selected(selected[group] == index)
	confirm_button.disabled = picked != needed
	hint.text = "每组选择 1 张（%d / %d）· 确认后支付成本并加入牌组" % [picked, needed]

func _claim() -> void:
	# 提交输入框里尚未失焦的数字，再由事件会话验证全部分配。
	var allocation := Vector2i.ZERO
	if session != null and session.prepared.get("type", "") == "train_unit" and selected[0] >= 0:
		if attack_input.get_line_edit().has_focus():
			attack_input.apply()
		if defence_input.get_line_edit().has_focus():
			defence_input.apply()
		allocation = Vector2i(int(attack_input.value), int(defence_input.value))
	var branch := str(soldier_choice.selected_branch) if is_instance_valid(soldier_choice) and soldier_choice.visible else ""
	var result: Dictionary = session.claim(selected, allocation, branch)
	if result.has("error"):
		hint.text = result.error
		return
	if result.get("pending", false):
		_present_prepared()
		return
	var choice: Dictionary = session.event.choices[session.choice_index]
	if choice.get("leave", false) or (session.choice_index == session.event.choices.size() - 1 and not choice.has("effect") and int(choice.get("heal", 0)) == 0 and float(choice.get("heal_percent", 0.0)) == 0 and int(choice.get("gold", 0)) == 0):
		_finish()
		return
	cards_box.hide()
	_set_treasure_layout(treasure_mode)
	story.show()
	choices_box.hide()
	result_box.show()
	_set_description(str(result.get("result_text", "你将收获妥善收好，继续踏上征途。")))
	_clear(result_box)
	if result.has("message"):
		var message := _label(result.message, 24, UI.INK)
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		result_box.add_child(message)
	for item in result.get("items", []):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		result_box.add_child(row)
		var icon := TextureRect.new()
		icon.texture = item.icon if item.icon != null else preload("res://assets/ui_extracted/icons/equipment_potion.png") if item is PotionDefinition else preload("res://assets/ui_extracted/icons/relic_crystal.png")
		icon.custom_minimum_size = Vector2(88, 88)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var text := _label("获得 · " + item.display_name + "\n" + item.description, 23, UI.INK)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
	for card in result.get("cards", []):
		result_box.add_child(_label("✓  " + card.card_name + "  已加入牌组", 25, UI.INK))
	result_box.add_child(_button("继续前进   →", _finish))
	hint.text = "奖励已获得。" if not session.preview else "预览结束 · 奖励未写入本局"

func _finish() -> void:
	if _finished or session == null or not session.claimed:
		return
	_finished = true
	hide()
	resolved.emit(session.choice_index)

func _on_choice_pressed(index: int) -> void:
	_choose(index)

func _clear(parent: Node) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
