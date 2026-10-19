extends SkillBase

## 每次施法的跳跃次数；强化版为2，每跳重新寻找密集敌群。
@export_range(1, 5, 1) var jump_count: int = 1
## 落地范围伤害半径，同时用来统计最密集敌群，单位为世界像素。
@export_range(1.0, 1000.0, 1.0) var impact_radius: float = 140.0
## 跳跃所需秒数，沿用实验室Abyssal重击的0.32秒。
@export_range(0.05, 3.0, 0.01) var jump_seconds: float = 0.32
## 落地时把命中的存活敌人向外震开的世界像素距离。
@export_range(0.0, 2000.0, 1.0) var knockback_distance: float = 250.0
## 震开移动的战斗秒数；遇本层地形或地表边界提前停止。
@export_range(0.01, 3.0, 0.01) var knockback_seconds: float = 0.3


func has_custom_targeting() -> bool:
	return true


func requires_live_target_on_hit() -> bool:
	return false


func select_target(caster: UnitBase) -> UnitBase:
	var enemies: Array[UnitBase] = []
	for node in caster.get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
		var enemy := node as UnitBase
		if _target(caster, enemy):
			enemies.append(enemy)
	var best: UnitBase
	var best_count := -1
	var nearest := INF
	for candidate: UnitBase in enemies:
		var distance := caster.global_position.distance_squared_to(candidate.global_position)
		if distance > cast_range * cast_range:
			continue
		var count := 0
		for other: UnitBase in enemies:
			if candidate.floor_id == other.floor_id and candidate.global_position.distance_squared_to(other.global_position) <= impact_radius * impact_radius:
				count += 1
		if count > best_count or (count == best_count and distance < nearest):
			best = candidate
			best_count = count
			nearest = distance
	return best


func _enemy(caster: UnitBase, target: UnitBase) -> bool:
	return is_instance_valid(target) and target.can_be_targeted_by(caster) and caster.shares_encounter(target) \
		and target.unit_data.unit_team != caster.unit_data.unit_team and not target.is_in_group("player_base") \
		and target.floor_id == caster.floor_id


func _target(caster: UnitBase, target: UnitBase) -> bool:
	return _enemy(caster, target) or (is_instance_valid(target) and target.can_be_targeted_by(caster) \
		and caster.shares_encounter(target) and target.unit_data.unit_team != caster.unit_data.unit_team \
		and not target.is_in_group("player_base") \
		and preload("res://scripts/combat/unit_motion_path.gd").can_cross_stairs(caster, target, cast_range))


func begin_cast(caster: UnitBase, _target: UnitBase) -> bool:
	var motion := preload("res://scripts/combat/bear_jump_motion.gd").new()
	caster.get_parent().add_child(motion)
	motion.start(caster, self)
	return true


func execute(caster: UnitBase, _target: UnitBase = null) -> void:
	var motion: Node = caster.skill_manager.cast_data.get("bear_jump")
	if is_instance_valid(motion):
		motion.take_off()


func land(caster: UnitBase) -> void:
	caster.combat_audio.play_movement(caster, &"heavy", self)
	var library := preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd")
	var mark := library.spawn(caster.get_parent(), "scenes_vfx_leapgrounddecal", caster.get_parent().to_local(caster.global_position), {
		"unit": caster, "ground_position": caster.global_position, "max_lifetime": 1.6})
	if mark != null:
		mark.z_index = caster.z_index + 1
		preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(mark)
	for node in caster.get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
		var enemy := node as UnitBase
		if not _enemy(caster, enemy) or caster.global_position.distance_squared_to(enemy.global_position) > impact_radius * impact_radius:
			continue
		if enemy.get_hurt(int(caster.unit_data.attack * attack_rate), caster, true, &"", -1, false, combat_number_kind()):
			apply_hit_statuses(caster, enemy)
			if enemy.current_state != UnitBase.State.DEATH:
				preload("res://scripts/combat/knockback_motion.gd").push(enemy, caster, knockback_distance, knockback_seconds, 0.0)


func card_effect_description() -> String:
	return "撼地：跳向密集敌群%d次，落地周围%.0f%%伤害并震开%.0f。" % [jump_count, attack_rate * 100, knockback_distance]


func effect_description() -> String:
	return card_effect_description() + "施法距离%.0f、落地半径%.0f；每跳重新选点。" % [cast_range, impact_radius]
