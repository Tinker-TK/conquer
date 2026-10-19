# 这玩意儿是干嘛的（核心逻辑）：显示能量和牌堆，让手牌动画管理器处理圆弧布局和移动。
# 数据是咋流动的（数据流向）：牌堆移动说明、手牌快照和能量 → 手牌管理器；按钮 → 只读牌堆面板。
# 为啥这么写（选型决策）：卡面由手牌管理器持续保留，不在每次抽牌时重建；查看牌堆时恢复原暂停状态。
# 性能咋样（复杂度）：只在牌堆变化时更新数字、打开时生成卡面，不逐帧重建。
extends CanvasLayer

const UI = preload("res://scripts/ui/pixel_ui_style.gd")

@onready var battle_time_left: Label = $BisicUI/BattleTimeLeft
@onready var battle_name_label: Label = $BisicUI/EnemyHealth/BattleName
@onready var enemy_health_bar: ProgressBar = $BisicUI/EnemyHealth/HealthBar
@onready var enemy_health_value: Label = $BisicUI/EnemyHealth/HealthBar/HealthValue
var current_max_energy: int
var current_useable_energy: int
@onready var cost_number: Label = $BisicUI/Cost/CostNumber
@onready var hand_manager: Node = get_parent().get_node_or_null("HandManager")
@onready var hand_presenter: Control = $Hand
var pile_view: Control
var _pile_open := false
var _paused_before_pile := false
var _health_tween: Tween
var _health_target := -1
var upgrade_choice: Control
var card_choice: Control


# 作用：Godot 入树时连接按钮并建立独立模态层；没有参数，没有返回值。
func _ready() -> void:
	UI.caption(battle_time_left, "blue", 26)
	battle_name_label.add_theme_stylebox_override("normal", UI.strip(Vector2(14, 6)))
	battle_name_label.add_theme_color_override("font_color", UI.INK)
	battle_name_label.add_theme_constant_override("outline_size", 0)
	UI.button($CardButtons/ActiveButton, 22)
	UI.button($CardButtons/ExhaustButton, 22)
	var start_button := get_node_or_null("ButtonPanel/AutoBattle") as Button
	if start_button != null:
		UI.button(start_button, 20, true)
	for button_name in ["DrawButton", "DiscardButton", "ExhaustButton", "ActiveButton"]:
		var button := get_node("CardButtons/" + button_name) as Button
		button.pressed.connect(_open_pile.bind(button_name))
		# 书本图片只负责装饰，不能挡住底下按钮的点击。
		for child in button.get_children():
			_ignore_button_decoration(child)
	var overlay := CanvasLayer.new()
	overlay.name = "PileOverlay"
	overlay.layer = 100
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(overlay)
	pile_view = preload("res://scenes/ui/deck_view.tscn").instantiate()
	overlay.add_child(pile_view)
	pile_view.close_requested.connect(_close_pile)
	var choice_layer := CanvasLayer.new()
	choice_layer.name = "EvolutionOverlay"
	choice_layer.layer = 110
	choice_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(choice_layer)
	upgrade_choice = preload("res://scripts/ui/evolution_choice.gd").new()
	choice_layer.add_child(upgrade_choice)
	card_choice = preload("res://scripts/ui/card_selection_choice.gd").new()
	choice_layer.add_child(card_choice)
	if hand_manager != null:
		hand_manager.shuffled.connect(func(): UIAudio.play(&"card_shuffle"))
		hand_manager.card_motion_requested.connect(hand_presenter.queue_card_motion)
		hand_manager.unit_card_motion_requested.connect(hand_presenter.queue_unit_card_motion)
		_on_hand_manager_piles_changed(hand_manager.draw_pile.size(), hand_manager.discard_pile.size())
	SignalBus.phase_change.connect(_on_card_phase_changed)


# 作用：更新顶部敌方血条；battle_name 为战斗名，current/maximum 为剩余和最大血量，没有返回值。
func update_enemy_health(battle_name: String, current: int, maximum: int, animated: bool = false) -> void:
	var safe_maximum := maxi(maximum, 1)
	var remaining := clampi(current, 0, safe_maximum)
	battle_name_label.text = battle_name if not battle_name.strip_edges().is_empty() else "战斗"
	enemy_health_bar.max_value = safe_maximum
	if not animated or remaining != _health_target:
		if _health_tween != null and _health_tween.is_valid():
			_health_tween.kill()
		if animated and remaining < enemy_health_bar.value:
			_health_tween = create_tween()
			_health_tween.tween_property(enemy_health_bar, "value", float(remaining), 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		else:
			enemy_health_bar.value = remaining
	_health_target = remaining
	enemy_health_value.text = "%d / %d" % [remaining, safe_maximum]


# 作用：装饰控件不拦截鼠标；node 是装饰节点，没有返回值。
func _ignore_button_decoration(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_button_decoration(child)


# 作用：打开某个牌堆，不移走或洗乱真实卡牌；button_name 为入口名称，没有返回值。
func _open_pile(button_name: String) -> void:
	if hand_manager == null or _pile_open or upgrade_choice.visible or card_choice.visible or get_viewport().gui_is_dragging():
		return
	var cards: Array[CardInstance] = []
	var heading := ""
	var hint := "仅供查看，不能从这里出牌。"
	match button_name:
		"DrawButton":
			cards.assign(hand_manager.draw_pile)
			heading = "抽牌堆"
			# 按名字展示，不泄露下一张抽牌顺序，也不改变真正的抽牌顺序。
			cards.sort_custom(func(a: CardInstance, b: CardInstance): return a.definition.card_name < b.definition.card_name)
			hint += " 按名称排列，不代表抽牌顺序。"
		"DiscardButton":
			cards.assign(hand_manager.discard_pile)
			heading = "弃牌堆"
		"ExhaustButton":
			cards.assign(hand_manager.exhaust_pile)
			heading = "消耗牌堆"
			hint += " 本场战斗已消耗的牌，不参与弃牌堆洗回。"
		"ActiveButton":
			cards.assign(hand_manager.active_cards)
			heading = "常驻卡牌"
			hint += " 效果持续到本场战斗结束，不参与抽牌或弃牌堆洗回。"
		_:
			return
	_paused_before_pile = get_tree().paused
	_pile_open = true
	get_tree().paused = true
	pile_view.open_cards(cards, heading, hint)


# 作用：关闭查看并恢复原暂停状态；没有参数，没有返回值。
func _close_pile() -> void:
	if not _pile_open:
		return
	_pile_open = false
	pile_view.hide()
	get_tree().paused = _paused_before_pile


# 作用：Godot 移除战斗界面时解除本面板持有的暂停；没有参数，没有返回值。
func _exit_tree() -> void:
	if _pile_open:
		get_tree().paused = _paused_before_pile


# 作用：能量变化时更新数字；current 为当前值、maximum 为每回合基础值，没有返回值。
func _on_battle_round_manager_energy_changed(current: int, maximum: int) -> void:
	current_useable_energy = current
	current_max_energy = maximum
	cost_number.text = str(current)
	hand_presenter.set_available_energy(current)


# 作用：手牌变化时保留旧卡面并增删实际移动的牌；hand_cards 是手牌快照，没有返回值。
func _on_hand_manager_hand_changed(hand_cards: Array[CardInstance]) -> void:
	hand_presenter.sync_hand(hand_cards)


# 作用：阶段切换立即刷新可用光效；_phase 是新的游戏阶段，没有返回值。
func _on_card_phase_changed(_phase: int) -> void:
	if not Global.is_card_play_phase() and is_instance_valid(upgrade_choice):
		upgrade_choice.close()
	if not Global.is_card_play_phase() and is_instance_valid(card_choice):
		card_choice.close()
	hand_presenter.refresh_availability()


func open_upgrade_choice(card: CardInstance, point: Vector2) -> void:
	if not _pile_open:
		upgrade_choice.open(card, point, get_parent().card_runtime)


func open_card_choice(card: CardInstance, point: Vector2) -> void:
	if not _pile_open:
		card_choice.open(card, point, get_parent().card_runtime)


# 作用：牌不足时输出提示；draw_count 为实际张数、cards_can_draw 为请求张数，没有返回值。
func _on_hand_manager_not_enough_cards(draw_count: Variant, cards_can_draw: Variant) -> void:
	print('牌库只有%s张牌，无法抽%s张牌' % [draw_count , cards_can_draw])


# 作用：更新三个牌堆数量；两个参数分别为抽牌和弃牌数量，消耗数从管理器读取，没有返回值。
func _on_hand_manager_piles_changed(draw_pile_size: int, discard_pile_size: int) -> void:
	$CardButtons/DrawButton/CardNumber.text = str(draw_pile_size)
	$CardButtons/DiscardButton/CardNumber.text = str(discard_pile_size)
	if hand_manager != null:
		$CardButtons/ExhaustButton.text = "消耗牌堆 · %d" % hand_manager.exhaust_pile.size()
		$CardButtons/ActiveButton.text = "常驻卡牌 · %d" % hand_manager.active_cards.size()
