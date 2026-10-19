# 这玩意儿是干嘛的（核心逻辑）：在常驻 HUD 展示遗物和药水，鼠标移上去就显示名称、效果和相关规则。
# 数据是咋流动的（数据流向）：RunManager 背包变化 → 刷新图标；悬停 → 共用说明框；点击药水 → 战场瞄准。
# 为啥这么写（选型决策）：用一个不拦截鼠标的说明框，禁用中的药水也能查看；地图和战场共用真实库存。
# 性能咋样（复杂度）：库存变化才重建图标；每帧只检查当前悬停控件，换物品时才重新排版效果文字。
extends Control

@onready var relic_row: HBoxContainer = $Relics/Row
@onready var potion_row: HBoxContainer = $Potions/Row
@onready var item_tooltip: VBoxContainer = $ItemTooltip
@onready var tooltip_title: Label = $ItemTooltip/MainPanel/Content/Title
@onready var tooltip_effect: RichTextLabel = $ItemTooltip/MainPanel/Content/Effect
@onready var tooltip_status: RichTextLabel = $ItemTooltip/MainPanel/Content/Status
@onready var tooltip_context: PanelContainer = $ItemTooltip/ContextPanel
@onready var context_title: Label = $ItemTooltip/ContextPanel/Content/Title
@onready var context_effect: RichTextLabel = $ItemTooltip/ContextPanel/Content/Effect

const TOOLTIP_WIDTH := 420.0
const TOOLTIP_MARGIN := 12.0
const ITEM_META := &"run_item"
var hovered_item: Resource
var hovered_button: Control
var number_pattern := RegEx.new()
var relic_notice: Label
var relic_notice_timer: Timer


# 作用：Godot 入树时注册唯一物品 HUD，并监听库存；没有参数，没有返回值。
func _ready() -> void:
	add_to_group("run_items_hud")
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 数字用亮色强调，方便快速读出伤害、持续时间和触发次数。
	number_pattern.compile("[0-9]+(?:\\.[0-9]+)?%?")
	RunManager.items_changed.connect(_rebuild)
	SignalBus.relic_triggered.connect(_on_relic_triggered)
	relic_notice = Label.new()
	relic_notice.position = Vector2(28, 180)
	relic_notice.add_theme_color_override("font_color", Color("f7d365"))
	relic_notice.add_theme_font_size_override("font_size", 23)
	relic_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(relic_notice)
	relic_notice_timer = Timer.new()
	relic_notice_timer.one_shot = true
	relic_notice_timer.timeout.connect(func(): relic_notice.text = "")
	add_child(relic_notice_timer)
	_rebuild()


func _on_relic_triggered(id: StringName, title: String) -> void:
	relic_notice.text = "✦ " + title
	relic_notice_timer.start(1.5)
	for view in relic_row.get_children():
		if view.get_meta(ITEM_META, null) is RelicDefinition and view.get_meta(ITEM_META).id == id:
			view.modulate = Color(2.0, 1.8, 1.1)
			view.create_tween().tween_property(view, "modulate", Color.WHITE, 0.35)
	if hovered_item is RelicDefinition and hovered_item.id == id:
		tooltip_status.text = _item_status(hovered_item)


# 作用：移除旧显示，不改真实库存；row 为按钮容器，没有返回值。
func _clear_row(row: Control) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()


# 作用：检查背包是否还是同一组物品；row 为按钮行，items 为库存，返回是否可以保留现有按钮。
func _row_matches(row: Control, items: Array) -> bool:
	if row.get_child_count() != items.size():
		return false
	for index in items.size():
		if row.get_child(index).get_meta(ITEM_META, null) != items[index]:
			return false
	return true


# 作用：重建遗物与药水入口；没有参数，没有返回值。
func _rebuild() -> void:
	if not is_node_ready():
		return
	# 抽牌计数和使用阶段变化也会发库存信号；物品没变就保留按钮，静止悬停不会被打断。
	if _row_matches(relic_row, RunManager.relics) and _row_matches(potion_row, RunManager.potions):
		_process(0.0)
		return
	# 真正增减库存才换掉按钮，并清理旧说明，避免继续显示已消耗的药水。
	_hide_item_tooltip()
	_clear_row(relic_row)
	_clear_row(potion_row)
	for relic in RunManager.relics:
		var icon := _make_relic_icon(relic.display_name, relic.icon, relic_row)
		icon.set_meta(ITEM_META, relic)
		# 遗物只读，没有点击行为；说明由 HUD 检查悬停，避免出现第二份系统提示。
	for potion in RunManager.potions:
		var button := _make_button(potion.display_name, potion.icon, potion_row)
		button.set_meta(ITEM_META, potion)
		button.pressed.connect(_use_potion.bind(potion))
		button.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var dialog := ConfirmationDialog.new()
				dialog.dialog_text = "丢弃%s？无法返还。" % potion.display_name
				dialog.confirmed.connect(func(): RunManager.discard_potion(potion))
				dialog.canceled.connect(dialog.queue_free)
				dialog.confirmed.connect(dialog.queue_free)
				add_child(dialog)
				dialog.popup_centered())
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.06, 0.1, 0.35)
		style.border_color = [Color("bec5cb"), Color("6aacf3"), Color("f3ce70")][potion.rarity]
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		for state in ["normal", "hover", "pressed", "disabled"]:
			button.add_theme_stylebox_override(state, style)
	$RelicEmpty.visible = RunManager.relics.is_empty()
	$PotionEmpty.visible = RunManager.potions.is_empty()
	_process(0.0)


# 作用：遗物使用只读图标，无素材时显示名字占位；title 为名字，icon 为可选图片，row 为容器，返回控件。
func _make_relic_icon(title: String, icon: Texture2D, row: Control) -> Control:
	var view: Control
	if icon != null:
		var texture := TextureRect.new()
		texture.texture = icon
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		view = texture
	else:
		var label := Label.new()
		label.text = title.left(2)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 17)
		view = label
	view.custom_minimum_size = Vector2(52, 48)
	# 保留悬停说明和原有输入遮挡，图标本身没有按钮的按下行为。
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(view)
	return view


# 作用：创建没有底板的药水按钮；title 为名字，icon 为可选图片，row 为容器，返回按钮。
func _make_button(title: String, icon: Texture2D, row: Control) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(52, 48)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 17)
	var empty_style := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, empty_style)
	if icon != null:
		button.icon = icon
		button.expand_icon = true
	else:
		# 无素材时用名字前两字占位，之后配置 Icon 即可替换，不需要修改脚本。
		button.text = title.left(2)
	row.add_child(button)
	return button


# 作用：尝试选用指定瓶；potion 是库存实例，没有返回值。
func _use_potion(potion: PotionDefinition) -> void:
	if is_instance_valid(RunManager.item_battle):
		RunManager.item_battle.select_potion(potion)


# 作用：暂停或阶段改变后更新是否可点击；delta 为帧间隔，没有返回值。
func _process(_delta: float) -> void:
	if not is_node_ready():
		return
	var runtime = RunManager.item_battle
	for button in potion_row.get_children():
		var usable: bool = is_instance_valid(runtime) and runtime.can_select(button.get_meta(ITEM_META))
		if button.disabled != not usable:
			button.disabled = not usable
	_update_item_hover()


# 作用：识别鼠标下面的物品按钮；没有参数，没有返回值，禁用按钮仍允许读说明。
func _update_item_hover() -> void:
	# 切场幕布和拖牌过程中不显示背景物品；暂停地图时仍然可以查看效果。
	if not is_visible_in_tree() or SceneTransition.busy or get_viewport().gui_is_dragging():
		_hide_item_tooltip()
		return
	var control := get_viewport().gui_get_hovered_control()
	if control == null or not is_ancestor_of(control) or not control.has_meta(ITEM_META):
		_hide_item_tooltip()
		return
	var item: Resource = control.get_meta(ITEM_META)
	if control != hovered_button or item != hovered_item:
		_show_item_tooltip(control, item)
	else:
		# 可用阶段或抽牌计数变化时更新小字，不重复创建或排版整个面板。
		var status := _item_status(item)
		if tooltip_status.text != status:
			tooltip_status.text = status
	_position_item_tooltip()


# 作用：显示某件物品的说明；button 为悬停按钮，item 为库存资源，没有返回值。
func _show_item_tooltip(button: Control, item: Resource) -> void:
	hovered_button = button
	hovered_item = item
	tooltip_title.text = item.display_name
	tooltip_effect.text = _highlight_numbers(_item_description(item))
	tooltip_status.text = _item_status(item)
	_set_item_context(item)
	item_tooltip.show()
	# 文字允许自动换行；高度交给容器计算，避免长说明被固定面板截掉。
	item_tooltip.size = Vector2(TOOLTIP_WIDTH, 0)
	_position_item_tooltip()


# 作用：关闭说明框并释放旧按钮引用；没有参数，没有返回值。
func _hide_item_tooltip() -> void:
	hovered_button = null
	hovered_item = null
	item_tooltip.hide()


# 作用：把说明放在按钮下方并限制在屏幕内；没有参数，没有返回值。
func _position_item_tooltip() -> void:
	if not is_instance_valid(hovered_button) or not item_tooltip.visible:
		return
	var bounds := get_viewport_rect()
	# 富文本换行会在容器布局后改变最小高度；同步缩回实际高度，避免首个提示因旧高度跳到屏幕顶端。
	var tooltip_size := Vector2(minf(TOOLTIP_WIDTH, bounds.size.x - TOOLTIP_MARGIN * 2.0), item_tooltip.get_combined_minimum_size().y)
	if item_tooltip.size != tooltip_size:
		item_tooltip.size = tooltip_size
	var button_rect := hovered_button.get_global_rect()
	var point := Vector2(button_rect.position.x, button_rect.end.y + TOOLTIP_MARGIN)
	# 下方不够放时移到按钮上方；横向也留出边距，右侧物品不会把说明推到屏幕外。
	point.x = clampf(point.x, TOOLTIP_MARGIN, maxf(TOOLTIP_MARGIN, bounds.end.x - item_tooltip.size.x - TOOLTIP_MARGIN))
	if point.y + item_tooltip.size.y > bounds.end.y - TOOLTIP_MARGIN:
		point.y = button_rect.position.y - item_tooltip.size.y - TOOLTIP_MARGIN
	point.y = clampf(point.y, TOOLTIP_MARGIN, maxf(TOOLTIP_MARGIN, bounds.end.y - item_tooltip.size.y - TOOLTIP_MARGIN))
	item_tooltip.global_position = point


# 作用：读取资源说明，漏填时用实际参数补上；item 为物品，返回玩家能读懂的效果文字。
func _item_description(item: Resource) -> String:
	if not item.description.strip_edges().is_empty():
		return item.description
	# Description 是策划可编辑的介绍；空白时仍然展示具体效果，不让玩家只能看到名字。
	if item is RelicDefinition:
		match item.kind:
			RelicDefinition.Kind.DRAW_ENERGY:
				return "每实际抽到 %d 张牌，获得 %d 点本回合能量。" % [item.draw_threshold, item.amount]
			RelicDefinition.Kind.BASE_HEALTH:
				return "本局生命上限增加 %d，获得时当前生命也增加 %d。" % [item.amount, item.amount]
			RelicDefinition.Kind.OPENING_DEFENCE:
				return "每场首次开打时，已上场己方单位防御增加 %d，持续 %d 轮。" % [item.amount, item.rounds]
			RelicDefinition.Kind.MAX_ENERGY:
				return "本局额外能量上限增加 %d。" % item.amount
	elif item is PotionDefinition:
		var targets: String = ["敌军", "己方单位", "双方单位"][item.targets]
		match item.kind:
			PotionDefinition.Kind.TORNADO:
				return "龙卷风移动 %s 秒，落地及每 %s 秒对半径 %s 内的%s造成 %d 点伤害。" % [item.duration, item.interval, item.radius, targets, item.damage]
			PotionDefinition.Kind.LIGHTNING:
				return "依次选择 %d 个落点，每次对半径 %s 内的%s造成 %d 点伤害，施放间隔 %s 秒。" % [item.casts, item.radius, targets, item.damage, item.cast_delay]
			PotionDefinition.Kind.FIRE:
				return "落地及每 %s 秒对半径 %s 内的%s造成 %d 点伤害，持续到本轮结束。" % [item.interval, item.radius, targets, item.damage]
			PotionDefinition.Kind.THUNDER_CLOUD:
				return "雷云固定在落点，每 %s 秒轮流锁定半径 %s 内一个%s，落雷造成 %d 点伤害。没有目标时不出雷，持续 %d 回合（含施放当回合）。" % [item.interval, item.radius, targets, item.damage, item.rounds]
	return "尚未填写效果说明。"


# 作用：给说明中的数字上色；value 为原始说明，返回安全的 BBCode 文字。
func _highlight_numbers(value: String) -> String:
	# 把资源文字里的左括号当普通字符，避免自定义说明意外变成富文本标签。
	var escaped := value.replace("[", "[lb]")
	return number_pattern.sub(escaped, "[color=#f7d365]$0[/color]", true)


# 作用：给物品附加当前进度或使用状态；item 为资源，返回说明框底部的小字。
func _item_status(item: Resource) -> String:
	if item is RelicDefinition:
		if item.kind == RelicDefinition.Kind.DRAW_ENERGY:
			return "当前累计：[color=#f7d365]%d / %d[/color] 张\n计数跨回合、跨战斗保留" % [RunManager.relic_draw_counts.get(item.id, 0), item.draw_threshold]
		var text: String = item.rarity_name() + "遗物 · " + item.school_name()
		var runtime: Node = RunManager.relic_battle
		if is_instance_valid(runtime) and not runtime.stopped:
			text += "\n本场触发 %d%s · 本轮 %d%s" % [runtime.count(item.id),
				" / %d" % item.max_per_battle if item.max_per_battle > 0 else "",
				runtime.count(item.id, true), " / %d" % item.max_per_round if item.max_per_round > 0 else ""]
		return text
	var runtime = RunManager.item_battle
	var rarity: String = ["普通", "稀有", "传说"][item.rarity]
	if item.target_mode == PotionDefinition.TargetMode.PASSIVE:
		return rarity + "药水 · 被动触发，无需手动使用"
	if is_instance_valid(runtime) and runtime.can_select(item):
		return rarity + "药水 · [color=#f7d365]" + ("点击选择落点" if item.needs_aim() else "点击立即使用") + "[/color]"
	if item.prep_usable:
		return rarity + "药水 · 准备或交锋阶段可使用"
	return "药水 · 仅自动战斗阶段可使用"


# 作用：显示相关规则的第二个说明框；item 为物品，没有返回值。
func _set_item_context(item: Resource) -> void:
	tooltip_context.show()
	if item is PotionDefinition:
		context_title.text = "使用方式"
		if item.kind == PotionDefinition.Kind.EFFECTS:
			var window := "准备或交锋阶段" if item.prep_usable else "交锋阶段"
			context_effect.text = "被动药水：受到致命伤时自动消耗。" if item.target_mode == PotionDefinition.TargetMode.PASSIVE else (
				window + "可用。" + ("点击药水后选择目标，右键/Esc取消。" if item.needs_aim() else "点击立即结算。") +
				"合法施放才消耗1瓶，不消耗能量。" + ("占用场地生效槽。" if item.occupies_slot() else "即时生效，可与场地药水一起使用。"))
			return
		var rules := "点击药水，再点击战场落点。首次有效施放消耗 1 瓶，不消耗能量。"
		if item.kind == PotionDefinition.Kind.LIGHTNING:
			rules += "首次施放后，继续点击释放剩余次数；回合结束时未用次数作废。"
		elif item.kind == PotionDefinition.Kind.THUNDER_CLOUD:
			rules += "雷云不能移动，雷线跟随锁定目标。每次只命中一个单位，范围内多个目标轮流受击；空范围不出雷。准备和结算时暂停，最后一回合结束时消失。占用场地槽，仍可使用即时药水。"
		else:
			rules += "占用场地槽，结束后才能使用另一瓶场地药水；仍可使用即时药水。"
		context_effect.text = _highlight_numbers(rules)
	elif item.kind == RelicDefinition.Kind.DRAW_ENERGY or item.kind == RelicDefinition.Kind.MAX_ENERGY:
		context_title.text = "能量"
		context_effect.text = "用于打出卡牌。遗物提供的额外能量可以超过基础上限。"
	elif item.kind == RelicDefinition.Kind.OPENING_DEFENCE:
		context_title.text = "防御"
		context_effect.text = "降低单位受到的普通攻击伤害。开局护甲只加给首次开打时已上场的己方单位。"
	else:
		tooltip_context.hide()
