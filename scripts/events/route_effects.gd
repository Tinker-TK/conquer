@tool
extends RefCounted
# 路线选项的成本、目标筛选和新增效果；候选在 EventSession 中固定，确认前不改本局。
const TYPES := ["remove_card", "duplicate_card", "enhance_random", "max_hp", "gamble", "gold", "heal"]

static func cost_error(choice: Dictionary, run: Object) -> String:
	if run == null:
		return ""
	var cost: Dictionary = choice.get("cost", {})
	if run.gold < int(cost.get("gold", 0)):
		return "还差 %d 金币" % (int(cost.gold) - run.gold)
	if int(cost.get("hp", 0)) > 0 and run.hp <= int(cost.hp):
		return "生命不足，支付后必须至少保留 1 点生命"
	if int(cost.get("max_hp", 0)) > 0 and run.max_hp - int(cost.max_hp) < 10:
		return "最大生命不足，支付后必须至少保留 10 点"
	return ""

static func candidates(deck: Array, kind: String, filter: String = "any") -> Array:
	var found: Array = []
	if kind == "remove_card" and deck.size() <= 1:
		return found
	for card in deck:
		if not card is CardInstance:
			continue
		if filter == "recruit" and not card.is_unit_card():
			continue
		if kind in ["train_unit", "enhance_card", "enhance_random"] and not card.can_upgrade(kind == "train_unit"):
			continue
		found.append(card)
	return found

static func effects(choice: Dictionary) -> Array:
	if choice.has("effects"):
		return choice.effects
	return [choice.effect] if choice.has("effect") else []

static func summary(choice: Dictionary) -> String:
	if choice.has("summary"):
		return str(choice.summary)
	var parts: Array[String] = []
	var cost: Dictionary = choice.get("cost", {})
	for key in ["gold", "hp", "max_hp"]:
		if int(cost.get(key, 0)) > 0:
			parts.append({"gold": "支付 %d 金币", "hp": "失去 %d 生命", "max_hp": "最大生命 -%d"}[key] % int(cost[key]))
	for effect: Dictionary in effects(choice):
		match str(effect.get("type", "")):
			"choose_cards":
				for kind in ["unit", "effect"]:
					if int(effect.get(kind + "_picks", 1)) > 0:
						parts.append("%d 张%s中选 1 张" % [int(effect.get(kind + "_offer", 5)), "征召牌" if kind == "unit" else "战术牌"])
			"max_hp":
				parts.append("最大生命 +%d" % int(effect.amount))
			"enhance_random":
				parts.append("随机强化 %d 张战术牌" % int(effect.get("count", 1)))
			"gamble":
				parts.append("成功率 %d%%" % roundi(float(effect.chance) * 100))
			_:
				parts.append({"random_relic": "获得 1 件随机遗物", "random_potion": "获得 1 瓶随机药水", "train_unit": "训练 1 张兵种卡", "enhance_card": "强化 1 张战术牌", "remove_card": "移除 1 张牌", "duplicate_card": "复制 1 张牌（保留强化）", "gold": "获得 %d 金币" % int(effect.get("amount", 0)), "heal": "回复 %d 生命" % int(effect.get("amount", 0))}.get(str(effect.get("type", "")), ""))
	if int(choice.get("gold", 0)) > 0:
		parts.append("获得 %d 金币" % int(choice.gold))
	if int(choice.get("heal", 0)) > 0:
		parts.append("回复 %d 生命" % int(choice.heal))
	if float(choice.get("heal_percent", 0)) > 0:
		parts.append("回复最大生命的 %s%%" % str(choice.heal_percent))
	return " · ".join(parts)

static func clone_card(card: CardInstance) -> CardInstance:
	var copy := CardInstance.new(card.persistent_definition().duplicate(true))
	for key in card.persistent_upgrade_state():
		copy.set(key, card.persistent_upgrade_state()[key])
	copy.permanent_buffs.assign(card.permanent_buffs.duplicate(true))
	return copy

static func validate(effect: Dictionary, depth: int = 0) -> String:
	if depth > 4:
		return "赌局嵌套过深。"
	match str(effect.type):
		"remove_card", "duplicate_card", "enhance_random":
			var count: Variant = effect.get("count", 1)
			if not (count is int or count is float) or count != floor(float(count)) or count < 1 or count > (5 if effect.type == "enhance_random" else 1):
				return "删牌/复制每次只支持 1 张，随机强化支持 1–5 张。"
			if effect.get("filter", "any") not in ["any", "recruit"]:
				return "卡牌筛选只支持 any / recruit。"
		"gold", "heal", "max_hp":
			var amount: Variant = effect.get("amount", 0)
			if not (amount is int or amount is float) or amount != floor(float(amount)) or amount < (1 if effect.type == "max_hp" else 0) or amount > 9999:
				return "效果数值必须是 1–9999 的整数。"
		"gamble":
			var chance: Variant = effect.get("chance")
			if not (chance is int or chance is float) or not is_finite(float(chance)) or chance < 0 or chance > 1:
				return "赌局概率必须在 0–1 之间。"
			for side in ["win", "lose"]:
				if not effect.get(side) is Dictionary:
					return "赌局必须包含 win / lose 效果。"
				var branch: Dictionary = effect[side]
				if branch.get("type", "") in ["gamble", "choose_cards", "train_unit", "enhance_card", "remove_card", "duplicate_card"]:
					return "赌局结果需直接结算，不能嵌套赌局或手动选牌。"
				var issue: String = load("res://scripts/events/event_rewards.gd").validate_effect(branch)
				if not issue.is_empty():
					return issue
	return ""
