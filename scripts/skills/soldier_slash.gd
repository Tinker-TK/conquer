extends "res://scripts/skills/normal_attack.gd"


func has_custom_targeting() -> bool:
	return true


func accepts_forced_target(caster: UnitBase, target: UnitBase) -> bool:
	return caster.soldier_runtime != null and not caster.soldier_runtime.has_slashed(target)


func select_target(caster: UnitBase) -> UnitBase:
	var runtime = caster.soldier_runtime
	if runtime == null:
		return null
	var previous: UnitBase = runtime.last_target.get_ref() if runtime.last_target != null else null
	# 已斩过的当前目标继续用普攻；换目标之后才发动下一次斩击。
	if is_instance_valid(previous) and previous.can_be_targeted_by(caster) and runtime.has_slashed(previous):
		return null
	var best: UnitBase
	var marked_best: UnitBase
	var nearest := INF
	var marked_nearest := INF
	for node in caster.get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
		var target := node as UnitBase
		if not is_instance_valid(target) or not target.can_be_targeted_by(caster) or target.is_in_group("player_base") \
			or not runtime.same_encounter(caster, target) or runtime.has_slashed(target):
			continue
		var distance := caster.global_position.distance_to(target.global_position)
		if distance > cast_range + 0.001:
			continue
		if distance < nearest:
			best = target
			nearest = distance
		var mark := target.get_node_or_null("SoldierMissileMark")
		if mark != null and mark.active and mark.source_team == caster.unit_data.unit_team and distance < marked_nearest:
			marked_best = target
			marked_nearest = distance
	return marked_best if marked_best != null else best


func begin_cast(caster: UnitBase, target: UnitBase) -> bool:
	if not is_instance_valid(target) or caster.soldier_runtime == null or caster.soldier_runtime.has_slashed(target) \
		or not target.can_be_targeted_by(caster) or caster.global_position.distance_to(target.global_position) > cast_range + 0.001:
		return false
	var landing: Variant = _landing(caster, target)
	if landing == null:
		return false
	caster.soldier_runtime.register_slash(target)
	var leap = load("res://scripts/combat/soldier_leap.gd").new()
	caster.get_parent().add_child(leap)
	leap.start(caster, target, landing)
	return true


func _landing(caster: UnitBase, target: UnitBase) -> Variant:
	var direction := target.global_position.direction_to(caster.global_position)
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	var map := target.navigation_agent_2d.get_navigation_map()
	var navigable := map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 and not NavigationServer2D.map_get_regions(map).is_empty()
	var collision := caster.get_node_or_null("CollisionShape2D") as CollisionShape2D
	for angle in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, PI]:
		var point := target.global_position + direction.rotated(angle) * 55.0
		if navigable:
			var closest := NavigationServer2D.map_get_closest_point(map, point)
			if closest.distance_to(point) > 4.0:
				continue
			point = closest
		if collision != null:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = collision.shape
			query.transform = collision.global_transform
			query.transform.origin += point - caster.global_position
			query.collision_mask = caster.collision_mask
			query.exclude = [caster.get_rid()]
			if not caster.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
		return point
	return null


func card_effect_description() -> String:
	return "斩击：350内飞跃，%.0f%%攻击力伤害，每敌仅一次；优先飞弹标记，斩过目标死亡攻击+1（本场）。" % (attack_rate * 100.0)


func effect_description() -> String:
	return card_effect_description()
