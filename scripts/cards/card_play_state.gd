# 战友的下一单位减费与进化的选牌校验；只持有本场状态，原牌费用始终独立保留。
extends Node

var runtime: Node2D
var comrade_threshold := 0
var next_unit_free := false
var potion_free_plays := 0


func setup(owner_runtime: Node2D) -> void:
	runtime = owner_runtime


func known_cards() -> Array[CardInstance]:
	var cards: Array[CardInstance] = []
	cards.assign(RunManager.deck)
	for pile in [runtime.hand.hand, runtime.hand.draw_pile, runtime.hand.discard_pile,
		runtime.hand.exhaust_pile, runtime.hand.active_cards, runtime.hand.resolving, runtime.hand.board_cards.values()]:
		for card: CardInstance in pile:
			if not cards.has(card):
				cards.append(card)
	return cards


func refresh_costs() -> void:
	for card in known_cards():
		card.next_unit_discount = next_unit_free and card.is_unit_card() and runtime.hand.hand.has(card)
		card.potion_cost_free = potion_free_plays > 0 and runtime.hand.hand.has(card)
		var relics: Node = runtime.battle.get_node_or_null("RelicRuntime")
		card.relic_cost_reduction = relics.card_discount(card) if relics != null and runtime.hand.hand.has(card) else 0


func prepare_cost(card: CardInstance) -> void:
	var relics: Node = runtime.battle.get_node_or_null("RelicRuntime")
	card.relic_cost_reduction = relics.card_discount(card) if relics != null else 0
	card.next_unit_discount = next_unit_free and card.is_unit_card()
	card.potion_cost_free = potion_free_plays > 0 and runtime.hand.hand.has(card)


func played(card: CardInstance, cost: int) -> void:
	if card.potion_cost_free:
		potion_free_plays = maxi(0, potion_free_plays - 1)
		card.potion_cost_free = false
	if next_unit_free and card.is_unit_card():
		next_unit_free = false
		card.free_until_discard = true
	if comrade_threshold > 0 and cost >= comrade_threshold:
		next_unit_free = true
	refresh_costs()


func candidates(source: CardInstance) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for card: CardInstance in runtime.hand.hand:
		if card != source and card.can_evolve():
			result.append(card)
	return result


func validate(effect: CardEffect, context: Dictionary) -> String:
	if effect.lifetime != CardEffect.Lifetime.BATTLE:
		return "此效果只支持本场战斗。"
	if effect.kind == CardEffect.Kind.COMRADE:
		if not is_finite(effect.amount) or effect.amount < 1 or effect.amount != floorf(effect.amount):
			return "战友触发费用必须为正整数。"
		if context.card.definition.after_use != CardDefinition.AfterUse.PERSIST:
			return "战友需要设置为常驻卡牌。"
		return "本场已启用战友。" if comrade_threshold > 0 else ""
	if context.card.definition.target != CardDefinition.Target.HAND_CARD:
		return "进化需要选择手牌目标。"
	var choices := candidates(context.card)
	if choices.is_empty():
		return "当前没有可升级的其它手牌。"
	var target := context.get("target_card") as CardInstance
	if target == null:
		return ""
	if not choices.has(target):
		return "请选择仍在手中、可以升级的其它卡牌。"
	if target.is_unit_card():
		if target.needs_soldier_choice() and context.get("soldier_branch", "") not in ["slash", "missile"]:
			return "请选择士兵强化技能：斩击或飞弹。"
		var allocation: Vector2i = context.allocation
		var points := target.ability_points + maxi(0, target.unit_data.upgrade_ability_points)
		if allocation.x < 0 or allocation.y < 0 or allocation.x + allocation.y != points:
			return "请分配全部训练点数到攻击或防御。"
	return ""


func clear_battle() -> void:
	potion_free_plays = 0
	comrade_threshold = 0
	next_unit_free = false
	for card in known_cards():
		card.reset_battle_modifiers()
