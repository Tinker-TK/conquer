# 这玩意儿是干嘛的（核心逻辑）：管理真实牌堆，并告诉界面每张牌是抽入、使用、收回还是弃置。
# 数据是咋流动的（数据流向）：先发送移动原因和世界落点，再更新手牌；界面播放动画，规则立即结算。
# 为啥这么写（选型决策）：动画不拖慢扣费和效果；原牌实例始终不变，死亡与清场共用加费入口。
# 性能咋样（复杂度）：只在牌堆操作时遍历本次移动的牌，不逐帧扫描场景。
extends Node2D
## 每轮常规抽牌张数，也是 draw_cards 未指定数量时的默认值。关卡 Cards Per Round 可覆盖；禁抽状态或可用牌数不足会减少实际抽牌。
@export var draw_per_turn: int = 5

var draw_pile: Array[CardInstance] = []
var hand: Array[CardInstance] = []
var discard_pile: Array[CardInstance] = []
var board_cards: Dictionary[int, CardInstance] = {}
# resolving 暂存正在结算的牌，避免抽牌效果把自己抽回来。
var resolving: Array[CardInstance] = []
var exhaust_pile: Array[CardInstance] = []
var active_cards: Array[CardInstance] = []
var draw_locked := false
var pending_bonus_draw: int = 0
var recurring_bonus_draw: int = 0
var _opening_hand_pending := true
var relic_retained: CardInstance
var pending_shuffle_draw := 0
signal shuffled

signal hand_changed(hand_cards: Array[CardInstance])
signal not_enough_cards(draw_count, cards_can_draw)
signal piles_changed(draw_pile_size: int, discard_pile_size: int)
# 界面收到的是移动说明，不是修改牌堆的命令；动画完成与否不影响游戏规则。
signal card_motion_requested(card: CardInstance, motion: StringName, world_position: Vector2)
signal unit_card_motion_requested(card: CardInstance, target: UnitBase, from_draw: bool)

	
# 作用：抽指定张数，受本回合禁抽限制；count 为 -1 时使用常规张数，没有返回值。
func draw_cards(count: int = -1) -> Array[CardInstance]:
	if draw_locked:
		return []
	var requested := draw_per_turn if count < 0 else count
	var cards_available: int= draw_pile.size() + discard_pile.size()
	var draw_count: = mini(cards_available, requested)
	
	if draw_count < requested:
		not_enough_cards.emit(draw_count, requested)
	
	var drawn: Array[CardInstance] = []
	for i in draw_count:
		if draw_pile.is_empty():
			draw_pile.append_array(discard_pile)
			discard_pile.clear()
			draw_pile.shuffle()
			shuffled.emit()
		
		var card: CardInstance = draw_pile.pop_back()
		hand.append(card)
		drawn.append(card)
	# 仅实际抽入手牌才计数，洗牌、随机直接出牌、收回单位都不是抽牌。
	var relic_energy := RunManager.record_draws(draw_count)
	if relic_energy > 0:
		get_parent().get_node("BattleRoundManager").gain_energy(relic_energy)
	# 先告诉界面这些牌从抽牌堆来，随后的一次刷新就能逐张安排飞入。
	for card in drawn:
		card_motion_requested.emit(card, &"draw", Vector2.ZERO)
	_notify_hand_changed()
	piles_changed.emit(draw_pile.size(), discard_pile.size())
	if pending_shuffle_draw > 0:
		var bonus := pending_shuffle_draw
		pending_shuffle_draw = 0
		drawn.append_array(draw_cards(bonus))
	return drawn

# 作用：开始战斗时恢复基础费用并把本局全部牌放入抽牌堆；没有参数，没有返回值。
func build_initial_deck():
	# 只清理本场的牌堆，绝不能 clear RunManager.deck。
	draw_pile.clear()
	hand.clear()
	discard_pile.clear()
	board_cards.clear()
	resolving.clear()
	exhaust_pile.clear()
	active_cards.clear()
	draw_locked = false
	pending_bonus_draw = 0
	recurring_bonus_draw = 0
	_opening_hand_pending = true
	# 开场仍重置一次，兼容直接退出旧战场后重新进入的流程。
	RunManager.reset_battle_card_costs()
	draw_pile.append_array(RunManager.deck)
	draw_pile.shuffle()
	piles_changed.emit(draw_pile.size(), discard_pile.size())

# 作用：回合末弃置非固有手牌；force_all 用于战斗结束回收全部手牌。
func discard_unused_card(force_all: bool = false):
	# 先记录离场原因，界面才会飞向弃牌堆，而不是误播成功出牌动画。
	var retained: Array[CardInstance] = []
	for card in hand:
		if (card.definition.retain_in_hand or card == relic_retained) and not force_all:
			retained.append(card)
			continue
		card.next_unit_discount = false
		card.free_until_discard = false
		card_motion_requested.emit(card, &"discard", Vector2.ZERO)
		discard_pile.append(card)
	hand.assign(retained)
	relic_retained = null
	_notify_hand_changed()
	piles_changed.emit(draw_pile.size(), discard_pile.size())

# 作用：把原征召牌绑定到上场单位；card 是原牌，unit 是新单位，没有返回值。
func move_hand_card_to_board(card, unit):
	hand.erase(card)
	resolving.erase(card)
	board_cards[unit.get_instance_id()] = card
	unit.unit_died.connect(_on_unit_died)
	_notify_hand_changed()
	

# 作用：准备阶段抽牌，交锋继续保留本轮手牌；current_phase 为新阶段，_round 为轮数，没有返回值。
func _on_battle_round_manager_phase_changed(current_phase: int, _round: int) -> void:
	if current_phase == Global.GamePhase.CARD_PLAY:
		draw_locked = false
		var relics := get_parent().get_node_or_null("RelicRuntime")
		if relics != null:
			relics.fire(RelicDefinition.Trigger.ROUND_START)
		if _opening_hand_pending:
			_opening_hand_pending = false
			for card: CardInstance in draw_pile.duplicate():
				if card.definition.starts_in_hand:
					draw_pile.erase(card)
					hand.append(card)
					card_motion_requested.emit(card, &"draw", Vector2.ZERO)
		var count := draw_per_turn + pending_bonus_draw + recurring_bonus_draw
		pending_bonus_draw = 0
		draw_cards(count)


# 作用：成功出牌后移入结算区；card 是原牌，from_draw 表示随机出牌，play_position 是世界落点，target 是已验证单位，没有返回值。
func begin_resolve(card: CardInstance, from_draw: bool = false, play_position: Vector2 = Vector2.ZERO, target: UnitBase = null) -> void:
	# 已经通过验证和扣费，只有这时才允许界面播放使用成功的反馈。
	UIAudio.play(&"card_play")
	if is_instance_valid(target) and card.definition.category != CardDefinition.Category.RECRUIT:
		unit_card_motion_requested.emit(card, target, from_draw)
	else:
		card_motion_requested.emit(card, &"random_play" if from_draw else &"play", play_position)
	if from_draw:
		draw_pile.erase(card)
	else:
		hand.erase(card)
	resolving.append(card)
	# 先移走自己再触发下一层随机效果，避免连锁反复抽到正在使用的牌。
	if from_draw:
		piles_changed.emit(draw_pile.size(), discard_pile.size())
	else:
		_notify_hand_changed()


# 作用：非征召牌结算后按配置进入弃牌、消耗或常驻区；card 为已用牌，没有返回值。
func finish_resolve(card: CardInstance) -> void:
	resolving.erase(card)
	match card.definition.after_use:
		CardDefinition.AfterUse.EXHAUST:
			exhaust_pile.append(card)
		CardDefinition.AfterUse.PERSIST:
			active_cards.append(card)
		_:
			discard_pile.append(card)
	piles_changed.emit(draw_pile.size(), discard_pile.size())


# 战斗结束时释放常驻区，原牌仍保留在总卡组供下场使用。
func finish_active_cards() -> void:
	exhaust_pile.append_array(active_cards)
	active_cards.clear()
	piles_changed.emit(draw_pile.size(), discard_pile.size())


# 作用：收回单位对应的原牌；unit 为已绑定单位，返回成功与否，不触发死亡。
func recall_unit(unit: UnitBase) -> bool:
	var card := board_cards.get(unit.get_instance_id()) as CardInstance
	if card == null:
		return false
	board_cards.erase(unit.get_instance_id())
	if unit.unit_died.is_connected(_on_unit_died):
		unit.unit_died.disconnect(_on_unit_died)
	hand.append(card)
	card_motion_requested.emit(card, &"return", unit.global_position)
	_notify_hand_changed()
	return true

# 作用：回合清场时弃置未留存的原征召牌；留存单位保持原牌绑定，没有参数和返回值。
func discard_board_cards() -> void:
	# 死亡和收回已经移走各自的记录，这里只处理剩下的牌，避免重复弃牌或凭空增加复制品的牌。
	var cards := board_cards.duplicate()
	for unit_id: int in cards:
		var card := cards[unit_id] as CardInstance
		var unit := instance_from_id(unit_id) as UnitBase
		if get_parent().card_runtime.should_retain_unit(unit):
			continue
		board_cards.erase(unit_id)
		_discard_board_card(card)
		# 清场移走单位前记录世界起点；动画只展示原牌，不把它重新加入手牌。
		if is_instance_valid(unit) and unit.is_inside_tree():
			card_motion_requested.emit(card, &"board_discard", unit.global_position)
	piles_changed.emit(draw_pile.size(), discard_pile.size())


# 作用：真实死亡时将该单位绑定的原征召牌加费并弃置；unit 是死者，没有返回值。
func _on_unit_died(unit: UnitBase) -> void:
	var unit_id: = unit.get_instance_id()
	var card: = board_cards.get(unit_id) as CardInstance
	
	if card == null:
		return
		
	board_cards.erase(unit_id)
	if unit.has_meta("relic_return_hand"):
		if not unit.has_meta("relic_no_cost_increase"):
			card.cost_increase += get_parent().card_runtime.unit_discard_cost_increase
		card.cost_increase -= 2
		hand.append(card)
		card_motion_requested.emit(card, &"return", unit.global_position)
		_notify_hand_changed()
		piles_changed.emit(draw_pile.size(), discard_pile.size())
		return
	if unit.has_meta("relic_no_cost_increase"):
		discard_pile.append(card)
		piles_changed.emit(draw_pile.size(), discard_pile.size())
		return
	_discard_board_card(card)
	piles_changed.emit(draw_pile.size(), discard_pile.size())


# 作用：统一结算上场单位回弃牌堆的费用惩罚；card 是单位绑定的原牌，没有返回值。
func _discard_board_card(card: CardInstance) -> void:
	card.next_unit_discount = false
	card.free_until_discard = false
	# 在发牌堆变化信号前完成加费，下次查看或抽到这张牌时就能显示新的费用。
	# 结算后的遗留死亡或清场不能再次给已经恢复基础费用的原牌加费。
	if not get_parent().battle_finished:
		card.cost_increase += get_parent().card_runtime.unit_discard_cost_increase
	discard_pile.append(card)


# 先同步战友的实际卡面费用，再让界面读取手牌快照。
func _notify_hand_changed() -> void:
	var runtime := get_parent().get_node_or_null("CardBattleRuntime")
	if runtime != null and runtime.plays != null:
		runtime.plays.refresh_costs()
	hand_changed.emit(hand)
