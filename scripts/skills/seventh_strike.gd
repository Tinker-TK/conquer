extends SkillBase

## 每累计多少次对敌人实际造成攻击伤害，追加一次百分比真实伤害。
@export_range(1, 99, 1) var damage_trigger_count: int = 7
## 最大生命真实伤害的基础百分比，另加原征召牌费用x。
@export_range(0.0, 100.0, 0.1) var true_damage_base_percent: float = 3.0


func is_passive() -> bool:
	return true


func create_passive(caster: UnitBase) -> Node:
	var runtime := preload("res://scripts/units/seventh_strike_runtime.gd").new()
	runtime.caster = caster
	runtime.skill = self
	return runtime


func passive_icon() -> String:
	return "seventh_strike"


func passive_parameters() -> String:
	return "被动 · 每%d次伤害触发\n真伤比例：%.0f%%＋原牌费用%%" % [damage_trigger_count, true_damage_base_percent]


func card_effect_description() -> String:
	return "七伤：每%d次攻击伤害追加目标最大生命(%.0f+x)%%真伤；x为原牌费用，忽略临时0费。" % [damage_trigger_count, true_damage_base_percent]


func card_text_for_cost(cost: int) -> String:
	return "七伤：每%d次伤害追加%.0f%%最大生命真伤。" % [damage_trigger_count, true_damage_base_percent + cost]


func effect_description() -> String:
	return card_effect_description() + "不同目标累计计数，触发后清零。"
