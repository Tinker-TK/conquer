# 一次嘲讽的范围快照、释放者特效和临时防御；不再提供原光环的友军攻击加成。
extends Node2D

var unit: UnitBase
var skill: SkillBase
var left := 0.0
var targets: Array[WeakRef] = []
var visual: Node2D


func _ready() -> void:
	unit = get_parent()
	unit.unit_died.connect(func(_unit): clear())
	SignalBus.phase_change.connect(func(phase):
		if phase != Global.GamePhase.AUTO_BATTLE:
			clear())
	set_physics_process(false)


func start(config: SkillBase) -> void:
	clear()
	skill = config
	left = skill.taunt_duration
	if skill.taunt_effect != null:
		visual = skill.taunt_effect.instantiate() as Node2D
		if visual != null:
			visual.z_index = 0
			if visual is GPUParticles2D:
				visual.local_coords = true
				visual.process_material = visual.process_material.duplicate(true)
				visual.process_material.emission_ring_radius = skill.taunt_radius
				visual.process_material.emission_ring_inner_radius = maxf(0.0, skill.taunt_radius - 7.0)
				visual.visibility_rect = Rect2(Vector2.ONE * (-skill.taunt_radius - 40), Vector2.ONE * (2 * skill.taunt_radius + 80))
			add_child(visual)
	var enemies := "team_b" if unit.unit_data.unit_team == "team_a" else "team_a"
	for node in get_tree().get_nodes_in_group(enemies):
		var enemy := node as UnitBase
		if not is_instance_valid(enemy) or not enemy.can_be_targeted_by(unit) or enemy.is_in_group("player_base") \
			or not enemy.shares_encounter(unit) or unit.global_position.distance_squared_to(enemy.global_position) > skill.taunt_radius ** 2:
			continue
		if enemy.apply_status(&"taunt", left, 0, unit, _source_key()):
			targets.append(weakref(enemy))
	refresh_defence()
	set_physics_process(true)
	unit._refresh_passive_status()


func _source_key() -> String:
	return "taunt_%d" % unit.get_instance_id()


func refresh_defence() -> void:
	var count := 0
	if left > 0:
		for node in get_tree().get_nodes_in_group("team_b" if unit.unit_data.unit_team == "team_a" else "team_a"):
			var enemy := node as UnitBase
			if is_instance_valid(enemy) and enemy.can_be_targeted_by(unit) and enemy.shares_encounter(unit) \
				and enemy.skill_manager.attack_target() == unit:
				count += 1
	unit.set_taunt_defence_bonus(count * skill.defence_per_attacker, count)


func _physics_process(delta: float) -> void:
	if unit.current_state == UnitBase.State.DEATH or unit._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE or not unit.unit_data.is_skill_unlocked(skill):
		clear()
		return
	left = maxf(0.0, left - delta)
	if left <= 0.000001:
		clear()
		return
	refresh_defence()


func clear() -> void:
	left = 0.0
	for reference: WeakRef in targets:
		var target = reference.get_ref()
		if is_instance_valid(target):
			target.remove_status(&"taunt", _source_key())
	targets.clear()
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()
	visual = null
	if is_instance_valid(unit):
		unit.set_taunt_defence_bonus(0, 0)
		unit._refresh_passive_status()
	set_physics_process(false)


func _exit_tree() -> void:
	clear()
