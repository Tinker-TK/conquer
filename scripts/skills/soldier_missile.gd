extends SkillBase


func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(target) or not target.can_be_targeted_by(caster) or target.unit_data.unit_team == caster.unit_data.unit_team:
		return
	var shot = load("res://scripts/combat/soldier_missile_flight.gd").new()
	caster.get_parent().add_child(shot)
	shot.start(caster, target, int(caster.unit_data.attack * attack_rate))


func card_effect_description() -> String:
	return "飞弹：%.0f%%伤害并标记；命中时，攻击目标的N名己方士兵各攻击+N，均持续本场。" % (attack_rate * 100.0)


func effect_description() -> String:
	return card_effect_description()
