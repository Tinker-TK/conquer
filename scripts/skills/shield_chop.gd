extends "res://scripts/skills/normal_attack.gd"

## 首刀出手时消耗全部护盾，记录值作为本次两刀各自的额外伤害。
@export var consume_shield: bool = false


func begin_cast(caster: UnitBase, _target: UnitBase) -> bool:
	if consume_shield:
		caster.skill_manager.cast_data["shield_chop"] = {"bonus": -1}
	return true


func damage_for(caster: UnitBase, target: UnitBase) -> int:
	var base := super.damage_for(caster, target)
	if not consume_shield:
		return base
	var context: Dictionary = caster.skill_manager.cast_data.get("shield_chop", {})
	if context.is_empty():
		return base
	if context.bonus < 0:
		context.bonus = caster.shield_amount
		caster.clear_shield()
	return base + int(context.bonus)


func card_effect_description() -> String:
	return "劈砍：两刀各%.0f%%伤害。%s" % [attack_rate * 100.0,
		"首刀消耗护盾，两刀各额外造成该护盾值伤害。" if consume_shield else ""]


func effect_description() -> String:
	return card_effect_description()
