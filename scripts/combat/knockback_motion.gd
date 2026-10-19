# 击退按物理步扫描完整身体，接触本层地形时停止；不把其它单位当作墙壁。
extends Node

var unit: UnitBase
var source: WeakRef
var direction := Vector2.ZERO
var remaining := 0.0
var speed := 0.0
var wall_stun := 0.0
var source_team := ""
var done := false


static func push(target: UnitBase, caster: UnitBase, distance: float, seconds: float, stun_seconds: float) -> void:
	if not is_instance_valid(target) or target.current_state == UnitBase.State.DEATH or target.has_status(&"steadfast") or distance <= 0:
		return
	# 撤销旧施法/击退后再接管移动，避免遗留导航速度把目标拉回。
	target.skill_manager.interrupt_actions()
	var previous := target.get_node_or_null("KnockbackMotion")
	if previous != null:
		previous.finish()
		previous.name = "FinishedKnockback%d" % previous.get_instance_id()
	var motion = load("res://scripts/combat/knockback_motion.gd").new()
	motion.name = "KnockbackMotion"
	motion.unit = target
	motion.source = weakref(caster)
	motion.source_team = caster.unit_data.unit_team
	motion.direction = caster.global_position.direction_to(target.global_position)
	if motion.direction.is_zero_approx():
		motion.direction = Vector2.LEFT if caster.animated_sprite_2d.flip_h else Vector2.RIGHT
	motion.remaining = distance
	motion.speed = distance / maxf(0.01, seconds)
	motion.wall_stun = stun_seconds
	target.add_child(motion)
	target.skill_manager.is_forced_moving = true
	target.navigation_agent_2d.stop_navigation()
	target.animated_sprite_2d.play("idle")
	target.actions_interrupted.connect(motion.finish)


## 药水没有施法单位；复用同一套完整身体扫墙和地表检测。
static func push_from_point(target: UnitBase, point: Vector2, distance: float, seconds: float = 0.3) -> void:
	if not is_instance_valid(target) or not target.is_alive() or target.has_status(&"steadfast") or distance <= 0:
		return
	target.skill_manager.interrupt_actions()
	var previous := target.get_node_or_null("KnockbackMotion")
	if previous != null:
		previous.finish()
		previous.name = "FinishedKnockback%d" % previous.get_instance_id()
	var motion = load("res://scripts/combat/knockback_motion.gd").new()
	motion.name = "KnockbackMotion"
	motion.unit = target
	motion.source_team = "team_a"
	motion.direction = point.direction_to(target.global_position)
	if motion.direction.is_zero_approx():
		motion.direction = Vector2.RIGHT
	motion.remaining = distance
	motion.speed = distance / maxf(seconds, 0.01)
	target.add_child(motion)
	target.skill_manager.is_forced_moving = true
	target.navigation_agent_2d.stop_navigation()
	target.actions_interrupted.connect(motion.finish)


func _physics_process(delta: float) -> void:
	if done:
		return
	if unit.current_state == UnitBase.State.DEATH or unit.is_queued_for_deletion() or unit._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE or unit.unit_data.unit_team == source_team or unit.has_status(&"steadfast"):
		finish()
		return
	var step := direction * minf(remaining, speed * delta)
	var fraction := 1.0
	var shape := unit.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape != null and shape.shape != null:
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.motion = step
		query.margin = 0.01
		query.collision_mask = (unit.floor_map.terrain_bit(unit.floor_id) | 4) if is_instance_valid(unit.floor_map) else 12
		query.exclude = [unit.get_rid()]
		var sweep := unit.get_world_2d().direct_space_state.cast_motion(query)
		if sweep.size() == 2:
			fraction = sweep[0]
	var next := unit.global_position + step * fraction
	# 实战用原始地表，不让导航留白提前挡住真正的撞墙接触。
	if is_instance_valid(unit.floor_map):
		if not unit.floor_map.has_ground_at(next, unit.floor_id):
			finish()
			return
	# 独立练兵场只有导航轮廓：边缘不是碰撞体，不触发撞墙眩晕。
	var map := unit.navigation_agent_2d.get_navigation_map()
	if not is_instance_valid(unit.floor_map) and map.is_valid() and NavigationServer2D.map_get_iteration_id(map) > 0 \
		and not NavigationServer2D.map_get_regions(map).is_empty() \
		and NavigationServer2D.map_get_closest_point(map, next).distance_to(next) > 2.0:
		finish()
		return
	unit.global_position = next
	remaining = maxf(0.0, remaining - step.length() * fraction)
	if fraction < 0.9999:
		var attacker: UnitBase = source.get_ref() if source != null else null
		finish()
		if wall_stun > 0.0:
			unit.apply_status(&"stun", wall_stun, 0, attacker, "axeman_wall")
	elif remaining <= 0.001:
		finish()


func finish() -> void:
	if done:
		return
	done = true
	if is_instance_valid(unit):
		unit.skill_manager.is_forced_moving = false
		unit.navigation_agent_2d.reset_after_teleport()
		if unit.actions_interrupted.is_connected(finish):
			unit.actions_interrupted.disconnect(finish)
	queue_free()
