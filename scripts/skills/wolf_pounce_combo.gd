# 狼人锁定最大生命值最低的敌人，Angel冲刺完成后才播放五连斩击。
extends "res://scripts/skills/normal_attack.gd"

## 扑击位移的战斗秒数，沿用实验室Angel冲刺原配方的0.3秒。
@export_range(0.05, 3.0, 0.01) var pounce_seconds: float = 0.3
## 扑击落点与锁定目标的间距，单位为世界像素；目标身边阻挡时尝试其他方向。
@export_range(1.0, 200.0, 1.0) var landing_distance: float = 55.0
## 每刀的实际近战命中距离，独立于350/450像素的扑击施法距离。
@export_range(1.0, 300.0, 1.0) var melee_range: float = 80.0
## 成功命中后施加的眩晕秒数；强化为2秒，五刀各自刷新，基础为0。
@export_range(0.0, 30.0, 0.1) var stun_seconds: float = 0.0
## 强化后由本狼人击杀本次锁定目标，立即清空本技能冷却并结束当前连击。
@export var refresh_on_target_kill: bool = false


func owns_cast_animation() -> bool:
	return true


func has_custom_targeting() -> bool:
	return true


func select_target(caster: UnitBase) -> UnitBase:
	var best: UnitBase
	var approach: UnitBase
	for node in caster.get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
		var enemy := node as UnitBase
		if not _enemy(caster, enemy) or not _reachable_floor(caster, enemy):
			continue
		if _better(caster, enemy, approach):
			approach = enemy
		if caster.global_position.distance_squared_to(enemy.global_position) <= cast_range * cast_range + 0.001 and _better(caster, enemy, best):
			best = enemy
	# 施法距离内优先锁定；没有可扑击的目标时保留同样规则的追击目标。
	return best if best != null else approach


func _better(caster: UnitBase, candidate: UnitBase, previous: UnitBase) -> bool:
	return previous == null or candidate.unit_data.max_hp < previous.unit_data.max_hp \
		or (candidate.unit_data.max_hp == previous.unit_data.max_hp \
		and caster.global_position.distance_squared_to(candidate.global_position) < caster.global_position.distance_squared_to(previous.global_position))


func _enemy(caster: UnitBase, target: UnitBase) -> bool:
	return is_instance_valid(target) and target.can_be_targeted_by(caster) and caster.shares_encounter(target) \
		and target.unit_data.unit_team != caster.unit_data.unit_team and not target.is_in_group("player_base")


func begin_cast(caster: UnitBase, target: UnitBase) -> bool:
	if not _enemy(caster, target) or not _reachable_floor(caster, target) \
		or caster.global_position.distance_to(target.global_position) > cast_range + 0.001:
		return false
	var landing: Variant = find_landing_position(caster, target)
	if landing == null:
		return false
	var motion := preload("res://scripts/combat/wolf_pounce_motion.gd").new()
	caster.get_parent().add_child(motion)
	motion.start(caster, target, self, landing)
	return not motion.done


func _reachable_floor(caster: UnitBase, target: UnitBase) -> bool:
	return caster.is_on_same_floor(target) or preload("res://scripts/combat/unit_motion_path.gd").can_cross_stairs(caster, target, cast_range)


func find_landing_position(caster: UnitBase, target: UnitBase) -> Variant:
	var direction := target.global_position.direction_to(caster.global_position)
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	var map: RID = caster.floor_map.get_floor_map(target.floor_id) if is_instance_valid(caster.floor_map) else caster.navigation_agent_2d.get_navigation_map()
	var navigable := map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 and not NavigationServer2D.map_get_regions(map).is_empty()
	var shape := caster.get_node_or_null("CollisionShape2D") as CollisionShape2D
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, PI, 2.0, -2.0, 2.5, -2.5]:
		var point := target.global_position + direction.rotated(angle) * minf(landing_distance, melee_range)
		if navigable:
			var closest := NavigationServer2D.map_get_closest_point(map, point)
			if closest.distance_to(point) > 4.0:
				continue
			point = closest
		if point.distance_to(target.global_position) > melee_range:
			continue
		if shape != null and shape.shape != null:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = shape.shape
			query.transform = shape.global_transform
			query.transform.origin += point - caster.global_position
			query.collision_mask = (caster.floor_map.terrain_bit(target.floor_id) | caster.floor_map.unit_bit(target.floor_id) | 4) if is_instance_valid(caster.floor_map) else caster.collision_mask
			query.exclude = [caster.get_rid()]
			query.margin = 1.0
			if not caster.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
		var path := preload("res://scripts/combat/unit_motion_path.gd").plan(caster, caster.global_position, point, target.floor_id)
		if not path.is_empty() and path.points[-1].distance_to(point) < 1.0 and path.length <= cast_range + 0.001:
			return point
	return null


func execute(caster: UnitBase, target: UnitBase = null) -> void:
	var motion: Node = caster.skill_manager.cast_data.get("wolf_pounce")
	if not is_instance_valid(motion) or motion.stage != "attack" or not _enemy(caster, target) \
		or not caster.is_on_same_floor(target) or caster.global_position.distance_to(target.global_position) > melee_range + 0.001:
		return
	super.execute(caster, target)


func apply_hit_statuses(caster: UnitBase, target: UnitBase) -> void:
	super.apply_hit_statuses(caster, target)
	if stun_seconds > 0.0 and is_instance_valid(target) and target.current_state != UnitBase.State.DEATH:
		target.apply_status(&"stun", stun_seconds, 0, caster, "wolf_pounce:%d" % caster.get_instance_id())


func card_effect_description() -> String:
	return "五连斩击：%.0f内扑向最大生命最低者，5次×%.0f%%。%s" % [cast_range, attack_rate * 100,
		"命中眩晕%.0f秒，击杀锁定目标刷新CD。" % stun_seconds if refresh_on_target_kill else ""]


func effect_description() -> String:
	return card_effect_description() + "最大生命相同则选较近者；Angel冲刺后在%.0f像素内近战，CD%.0f秒。" % [melee_range, cooldown]
