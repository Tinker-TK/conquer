# 连续命中被动只保存配置；每个出场剑士各自记录目标和连击层数。
extends SkillBase

## 每次成功命中当前敌人后增加的攻击力，下一次命中按技能倍率计算伤害；连击技能的每个命中帧分别计数。切换目标时全部清除，不设叠加上限。
@export_range(0, 999, 1) var attack_bonus_per_hit: int = 1


func is_passive() -> bool:
	return true


func create_passive(caster: UnitBase) -> Node:
	var instance := preload("res://scripts/units/consecutive_attack_runtime.gd").new()
	instance.caster = caster
	instance.skill = self
	return instance


func passive_parameters() -> String:
	return "被动 · 每次命中攻击 +%d\n连击各次命中分别计数 · 切换目标清零" % attack_bonus_per_hit


func passive_icon() -> String:
	return "consecutive_attack"


func card_effect_description() -> String:
	return "%s：每次命中同一目标，攻击力增加%d；切换目标清零。" % [skill_name, attack_bonus_per_hit]


func effect_description() -> String:
	return "%s：每次命中同一目标后，攻击力增加%d，下一击生效；切换目标时清除增益。" % [skill_name, attack_bonus_per_hit]
