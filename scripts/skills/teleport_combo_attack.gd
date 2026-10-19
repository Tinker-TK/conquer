# 施法开始时传送一次；之后按原动画命中帧执行普通攻击，不在每刀重新传送。
extends "res://scripts/skills/normal_attack.gd"

## 传送落点距目标的距离，单位为世界像素；在此距离附近寻找可行走、无碰撞的位置，落点必须位于技能近战范围内。
@export_range(1, 200, 1) var teleport_distance: float = 55.0
## 传送起点与终点的特效场景；默认使用 pixel_portal_demo 展示的像素传送门。
@export var teleport_effect: PackedScene = preload("res://scenes/effects/pixel_portal.tscn")
## 传送门的显示缩放，1 为素材原尺寸；同时应用到起点和落点。
@export_range(0.1, 10, 0.1) var teleport_effect_scale: float = 3.0
## 起点与落点传送门的播放时间，单位为秒；结束或离开交锋阶段后自动移除。
@export_range(0.1, 5, 0.1) var teleport_effect_duration: float = 0.8


func is_global_cast() -> bool:
	return true


func card_effect_description() -> String:
	return "%s：瞬移至最远敌人身边，连击%d次（每次%.0f%%攻击力）。" % [skill_name, hit_frame.size(), attack_rate * 100.0]


func effect_description() -> String:
	return "%s：选中地图中最远的敌人，瞬移到其身边并发动%d次斩击。" % [skill_name, hit_frame.size()]


func begin_cast(caster: UnitBase, target: UnitBase) -> bool:
	if not is_instance_valid(target) or not target.can_be_targeted_by(caster) \
		or target.unit_data.unit_team == caster.unit_data.unit_team:
		return false
	var landing = find_landing_position(caster, target)
	if landing == null:
		return false
	var origin := caster.global_position
	caster.navigation_agent_2d.stop_navigation()
	caster.global_position = landing
	caster.navigation_agent_2d.reset_after_teleport()
	caster.animated_sprite_2d.flip_h = caster.global_position.x > target.global_position.x
	_spawn_portal(caster, origin)
	_spawn_portal(caster, caster.global_position)
	return true


func find_landing_position(caster: UnitBase, target: UnitBase) -> Variant:
	var direction := target.global_position.direction_to(caster.global_position)
	if direction.is_zero_approx():
		direction = Vector2.LEFT
	var map: RID = caster.navigation_agent_2d.get_navigation_map()
	var has_navigation := map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 \
		and not NavigationServer2D.map_get_regions(map).is_empty()
	var collision := caster.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var distance := clampf(teleport_distance, 1.0, maxf(1.0, cast_range))
	# 优先靠近原来的方向；原位置堵住时在目标周围寻找，不能传进墙、水面或其他单位。
	for offset in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, PI, 2.0, -2.0, 2.5, -2.5]:
		var point: Vector2 = target.global_position + direction.rotated(offset) * distance
		if has_navigation:
			var on_map := NavigationServer2D.map_get_closest_point(map, point)
			if on_map.distance_to(point) > 4.0:
				continue
			point = on_map
		if point.distance_to(target.global_position) > cast_range:
			continue
		if collision != null and collision.shape != null:
			var query := PhysicsShapeQueryParameters2D.new()
			query.shape = collision.shape
			query.transform = collision.global_transform
			query.transform.origin += point - caster.global_position
			query.collision_mask = caster.collision_mask
			query.exclude = [caster.get_rid()]
			query.margin = 1.0
			if not caster.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				continue
		return point
	return null


func _spawn_portal(caster: UnitBase, point: Vector2) -> void:
	if teleport_effect == null:
		return
	var burst := preload("res://scripts/combat/teleport_portal_burst.gd").new()
	burst.effect = teleport_effect
	burst.effect_scale = teleport_effect_scale
	burst.remaining = teleport_effect_duration
	var parent := caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()
	parent.add_child(burst)
	# 同脚底位置先绘制传送门，再绘制单位；无 Y 排序的练兵场也保持此顺序。
	var unit_branch: Node = caster
	while unit_branch.get_parent() != null and unit_branch.get_parent() != parent:
		unit_branch = unit_branch.get_parent()
	if unit_branch.get_parent() == parent:
		parent.move_child(burst, unit_branch.get_index())
	burst.global_position = point
