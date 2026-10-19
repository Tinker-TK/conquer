# 强化后解锁的驻场技能；资源只保存配置，每个出场单位创建独立光环。
extends SkillBase

## 庇护光环半径，单位为世界像素；与特效环半径一致，可在技能配置中调整。
@export_range(1, 2000, 1) var aura_radius: float = 200.0
## 光环内己方单位获得的攻击力加成；同类光环重叠取最高值，不累加。
@export_range(0, 999, 1) var aura_attack_bonus: int = 2
## 开启后光环也庇护施放者自身；关闭后只庇护范围内其他己方单位。
@export var aura_include_caster: bool = true
## 驻场光环特效场景；默认使用特效演示中的魔法光环，随施放者移动、存活期间持续播放。
@export var aura_effect: PackedScene = preload("res://assets/effect/godot_vfx_library/effects/magic/magic_aura.tscn")


func is_passive() -> bool:
	return true


func create_passive(caster: UnitBase) -> Node:
	var instance := preload("res://scripts/units/protection_aura_runtime.gd").new()
	instance.caster = caster
	instance.skill = self
	return instance


func passive_parameters() -> String:
	return "驻场光环 · 半径 %.0f · 攻击 +%d\n同类光环重叠取最高加成%s" % [aura_radius, aura_attack_bonus, " · 包含自身" if aura_include_caster else ""]


func card_effect_description() -> String:
	return "%s：半径%.0f内%s己方单位攻击力提升%d。" % [skill_name, aura_radius, "" if aura_include_caster else "其他", aura_attack_bonus]


func effect_description() -> String:
	return "%s：存活时庇护半径%.0f内的己方单位，攻击力提升%d。" % [skill_name, aura_radius, aura_attack_bonus]
