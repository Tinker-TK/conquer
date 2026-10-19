# 这玩意儿是干嘛的（核心逻辑）：用真实战场验证单位回弃牌堆后，原牌费用每次增加 1 点。
# 数据是咋流动的（数据流向）：旧兵种和共享新配方 → 出牌、死亡、清场、重抽 → 检查卡面与能量。
# 为啥这么写（选型决策）：走正式出牌和退场入口，能同时发现重复加费、同名牌串数据与扣费遗漏。
# 性能咋样（复杂度）：仅手动回归时运行，创建两个小战场，不参与正常游戏。
extends Node

var battle: Node2D
var hand: Node2D
var runtime: Node2D
var rounds: BattleRoundManager


# 作用：Godot 入树后延迟验收，失败时由超时退出；没有参数，没有返回值。
func _ready() -> void:
	get_tree().create_timer(15.0).timeout.connect(func(): get_tree().quit(1))
	_run.call_deferred()


# 作用：创建不自动抽牌、没有敌阵的正式战场；没有参数，没有返回值。
func _create_battle() -> void:
	battle = load("res://scenes/battle/battle_scene.tscn").instantiate()
	var config := BattleLevelConfig.new()
	config.cards_per_round = 0
	battle.configure_level(config)
	get_tree().root.add_child(battle)
	hand = battle.hand_manager
	runtime = battle.card_runtime
	rounds = battle.battle_round_manager
	runtime.set_physics_process(false)


# 作用：将测试牌从抽牌堆移入手牌；card 为要部署的原牌，没有返回值。
func _give(card: CardInstance) -> void:
	hand.draw_pile.erase(card)
	hand.hand.append(card)


# 作用：部署已在手中的征召牌并关闭移动；card 为原牌，返回绑定的新单位。
func _recruit(card: CardInstance) -> UnitBase:
	rounds.current_energy = 99
	assert(runtime.try_play(card, Vector2(450, 450)))
	var unit: UnitBase = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	return unit


# 作用：检查真实卡面显示当前费用；card 为具体牌，没有返回值。
func _check_view(card: CardInstance) -> void:
	var view: UnitCard = load("res://scenes/cards/unit_card.tscn").instantiate()
	add_child(view)
	view.setup(card)
	assert(view.get_node("CostIcon/CostLabel").text == str(card.get_cost()))
	view.queue_free()


# 作用：验证加费累计、免费出牌、普通弃牌与跨战斗重置；没有参数，没有返回值。
func _run() -> void:
	# 同一旧兵种和同一新配方各建两张牌，验证只有实际退场的那张会涨价。
	var soldier: UnitData = load("res://data/units/soldier.tres")
	var definition := CardDefinition.new()
	definition.category = CardDefinition.Category.RECRUIT
	definition.target = CardDefinition.Target.POSITION
	definition.summon_unit = soldier
	definition.card_cost = 2
	var start := RunStartData.new()
	start.cards.assign([soldier, soldier, definition, definition])
	RunManager.start_new_run(start)
	_create_battle()
	var card: CardInstance = RunManager.deck[0]
	var peer: CardInstance = RunManager.deck[1]
	var shared: CardInstance = RunManager.deck[2]
	var shared_peer: CardInstance = RunManager.deck[3]
	var base := soldier.card_cost
	_give(card)
	var unit := _recruit(card)
	unit.die()
	assert(hand.discard_pile.has(card) and card.get_cost() == base + 1)
	assert(peer.get_cost() == base and soldier.card_cost == base)
	# 重复死亡通知和紧随其后的清场不能再为同一退场加费。
	unit.unit_died.emit(unit)
	battle.clear_round_units()
	assert(card.get_cost() == base + 1 and hand.discard_pile.count(card) == 1)
	_check_view(card)
	# 弃牌堆洗回并重抽后，显示、拒绝出牌和实际扣费都使用新的费用。
	hand.draw_pile.clear()
	hand.draw_cards(1)
	assert(hand.hand.has(card) and card.get_cost() == base + 1)
	_check_view(card)
	rounds.current_energy = base
	assert(not runtime.try_play(card, Vector2(450, 450)))
	assert(hand.hand.has(card) and rounds.current_energy == base and hand.board_cards.is_empty())
	rounds.current_energy = base + 1
	assert(runtime.try_play(card, Vector2(450, 450)))
	assert(rounds.current_energy == 0)
	unit = battle.get_node("Entities/TeamA").get_children().back()
	unit.set_physics_process(false)
	# 真正结束一轮交锋：幸存者清场也加 1，累计到基础费用 +2。
	rounds.start_auto_battle()
	await rounds.finish_unit_combat()
	assert(card.get_cost() == base + 2 and hand.discard_pile.count(card) == 1)
	await get_tree().process_frame
	assert(rounds.current_round == 2 and not battle.battle_finished)
	# 收回原牌直接回手，不加费；随后手牌未用而弃置也不加费。
	hand.draw_cards(1)
	unit = _recruit(card)
	assert(hand.recall_unit(unit))
	unit.get_parent().remove_child(unit)
	unit.queue_free()
	assert(card.get_cost() == base + 2)
	hand.discard_unused_card()
	assert(card.get_cost() == base + 2)
	# 免费随机出牌不受涨价阻拦，但下一次单位清场仍继续加费。
	hand.draw_pile.append_array(hand.discard_pile)
	hand.discard_pile.clear()
	rounds.current_energy = 0
	assert(runtime.try_play(card, Vector2(450, 450), true, 1, true))
	assert(rounds.current_energy == 0)
	battle.clear_round_units()
	assert(card.get_cost() == base + 3)
	# 新征召配方共享资源也必须隔离；没有绑定原牌的单位退场不能凭空造牌。
	_give(shared)
	_recruit(shared)
	var unbound: UnitBase = load("res://scenes/units/soldier.tscn").instantiate()
	battle.get_node("Entities/TeamA").add_child(unbound)
	var count: int = hand.discard_pile.size()
	battle.clear_round_units()
	assert(hand.discard_pile.size() == count + 1)
	assert(shared.get_cost() == 3 and shared_peer.get_cost() == 2 and definition.card_cost == 2)
	_check_view(shared)
	# 强化或能力牌只是结算后弃置，没有场上单位退场，所以不能加费。
	var ability := CardInstance.new(load("res://data/cards/defend.tres"))
	hand.resolving.append(ability)
	hand.finish_resolve(ability)
	assert(ability.get_cost() == ability.definition.card_cost)
	# 整场胜利立即恢复所有原牌费用；打开的卡组也必须刷新，不能等下一场才重置。
	card.permanent_buffs.append({"effect": CardEffect.new(), "label": "测试永久记录"})
	assert(card.train(soldier.upgrade_ability_points - 1, 1))
	_give(peer)
	unit = _recruit(peer)
	peer.cost_increase = 4
	var deck_view: Control = load("res://scenes/ui/deck_view.tscn").instantiate()
	add_child(deck_view)
	deck_view.open_deck()
	assert(deck_view.grid.get_child(0).get_child(0).get_node("CostIcon/CostLabel").text == str(base + 3))
	battle.finish_battle(true)
	assert(card.get_cost() == base and peer.get_cost() == base and shared.get_cost() == 2)
	for slot in deck_view.grid.get_children():
		var view := slot.get_child(0) as UnitCard
		assert(view.get_node("CostIcon/CostLabel").text == str(view.card_instance.definition.card_cost))
	assert(card.permanent_buffs.size() == 1 and card.upgrade_count == 1)
	assert(card.attack_points == soldier.upgrade_ability_points - 1 and card.defence_points == 1)
	# 提前结束后遗留单位的死亡通知与清场，不能再次带回本场加费。
	unit.unit_died.emit(unit)
	battle.clear_round_units()
	assert(peer.get_cost() == base and card.get_cost() == base)
	deck_view.queue_free()
	battle.queue_free()
	await get_tree().process_frame
	# 用同一局的原牌进入新战场，仍使用基础费用并保留永久强化。
	_create_battle()
	assert(card.get_cost() == base and shared.get_cost() == 2)
	assert(card.permanent_buffs.size() == 1 and RunManager.deck[0] == card)
	_give(card)
	unit = _recruit(card)
	unit.die()
	assert(card.get_cost() == base + 1)
	battle.finish_battle(false)
	assert(card.get_cost() == base and shared.get_cost() == 2)
	_check_view(card)
	battle.queue_free()
	await get_tree().process_frame
	RunManager.start_new_run(start)
	assert(RunManager.deck[0] != card and RunManager.deck[0].get_cost() == base)
	assert(RunManager.deck[0].permanent_buffs.is_empty())
	print("CARD_COST_INCREASE_PASS")
	get_tree().quit()
