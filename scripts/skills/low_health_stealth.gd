extends SkillBase

## 生命比例严格低于此百分比时触发隐身；50 表示低于最大生命的一半。每次部署只触发一次。
@export_range(1, 100, 1) var stealth_health_percent: float = 50.0
## 隐身持续的战斗时间，单位为秒；暂停时不计时，战斗倍速会同步加快。隐身不提供伤害免疫，攻击不会提前解除。
@export_range(0.1, 60, 0.1) var stealth_duration: float = 5.0


func is_passive() -> bool:
	return true


func create_passive(caster: UnitBase) -> Node:
	var instance := preload("res://scripts/units/low_health_stealth_runtime.gd").new()
	instance.caster = caster
	instance.skill = self
	return instance


func passive_icon() -> String:
	return "stealth"


func passive_parameters() -> String:
	return "被动 · 生命低于%.0f%% · 隐身%.1f秒\n每次部署只触发一次" % [stealth_health_percent, stealth_duration]


func card_effect_description() -> String:
	return "%s：生命低于%.0f%%时隐身%.1f秒，每次部署只触发一次。" % [skill_name, stealth_health_percent, stealth_duration]


func effect_description() -> String:
	return "%s：生命低于%.0f%%时隐身%.1f秒，无法被敌方索敌选中；每次部署只触发一次。" % [skill_name, stealth_health_percent, stealth_duration]
