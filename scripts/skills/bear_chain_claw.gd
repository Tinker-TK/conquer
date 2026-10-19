extends "res://scripts/skills/normal_attack.gd"

## 每次爪击在主目标之外最多连接的敌人数；同一条链不重复命中。
@export_range(0, 10, 1) var lightning_links: int = 2
## 每段闪电从上一个受伤目标继续寻找敌人的世界像素半径。
@export_range(1.0, 2000.0, 1.0) var lightning_radius: float = 220.0


func try_other_skills_when_out_of_range() -> bool:
	return true


func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or not _enemy(caster, target):
		return
	caster.notify_attack_target(target)
	if not target.get_hurt(damage_for(caster, target), caster, true, &"", -1, false, combat_number_kind(), defence_segments()):
		return
	apply_hit_statuses(caster, target)
	var visited := {target.get_instance_id(): true}
	var previous := target
	for link in lightning_links:
		if not caster.can_use_skills() or caster._encounter_finished():
			break
		var next: UnitBase
		var distance := lightning_radius * lightning_radius
		for node in caster.get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
			var enemy := node as UnitBase
			if not _enemy(caster, enemy) or visited.has(enemy.get_instance_id()):
				continue
			var squared := previous.global_position.distance_squared_to(enemy.global_position)
			if squared <= distance:
				next = enemy
				distance = squared
		if next == null:
			break
		visited[next.get_instance_id()] = true
		if not next.get_hurt(damage_for(caster, next), caster, true, &"", -1, false, &"lightning", defence_segments()):
			break
		apply_hit_statuses(caster, next)
		var visual := preload("res://scripts/combat/bear_lightning_vfx.gd").new()
		caster.get_parent().add_child(visual)
		visual.start(caster, previous, next)
		previous = next


func _enemy(caster: UnitBase, target: UnitBase) -> bool:
	return is_instance_valid(target) and target.can_be_targeted_by(caster) and caster.shares_encounter(target) \
		and target.unit_data.unit_team != caster.unit_data.unit_team and not target.is_in_group("player_base")


func card_effect_description() -> String:
	return "二连爪：2次×%.0f%%伤害，每击连锁闪电%d段（各%.0f%%），不重复连接。" % [attack_rate * 100, lightning_links, attack_rate * 100]


func effect_description() -> String:
	return card_effect_description() + "每段在上一目标附近%.0f像素内寻找最近敌人。" % lightning_radius
