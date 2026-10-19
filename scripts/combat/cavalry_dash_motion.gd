# 每次冲锋独立维护Tween、分段命中和特效；中断后的旧节点不触碰后续动作。
extends Node2D

var caster: UnitBase
var skill: SkillBase
var segment_index := 0
var segment_from := Vector2.ZERO
var segment_to := Vector2.ZERO
var previous := Vector2.ZERO
var hit_units: Dictionary = {}
var tween: Tween
var pause_left := -1.0
var visual: Node2D
var done := false
var path: Dictionary


func start(unit: UnitBase, target: UnitBase, config: SkillBase) -> void:
	caster = unit
	skill = config
	caster.skill_manager.cast_data["dash_motion"] = self
	caster.skill_manager.is_forced_moving = true
	caster.navigation_agent_2d.stop_navigation()
	caster.velocity = Vector2.ZERO
	caster.actions_interrupted.connect(cancel)
	var collision := caster.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision != null:
		collision.set_deferred("disabled", true)
	var area := caster.get_node_or_null("AttackArea") as Area2D
	if area != null:
		area.set_deferred("monitoring", true)
	_begin_segment(target)


func _valid() -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() \
		and caster.can_use_skills() and not caster._encounter_finished() \
		and caster.unit_data.is_skill_unlocked(skill) \
		and caster.skill_manager.current_skill == skill and caster.skill_manager.cast_data.get("dash_motion") == self \
		and Global.game_phase == Global.GamePhase.AUTO_BATTLE


func _begin_segment(target: UnitBase) -> void:
	if not _valid() or not is_instance_valid(target):
		cancel()
		return
	segment_from = caster.global_position
	var direction := segment_from.direction_to(target.global_position)
	if direction.is_zero_approx():
		direction = Vector2.LEFT if caster.animated_sprite_2d.flip_h else Vector2.RIGHT
	var paths := preload("res://scripts/combat/unit_motion_path.gd")
	if target.floor_id != caster.floor_id:
		path = paths.plan(caster, segment_from, target.global_position, target.floor_id)
		if not path.is_empty():
			var remaining := maxf(0.0, skill.dash_distance - float(path.length))
			var last: Vector2 = path.points[-1]
			path = paths.extend(path, paths.endpoint(caster, last, last + direction * remaining, target.floor_id), target.floor_id)
	else:
		path = paths.plan(caster, segment_from, segment_from + direction * skill.dash_distance, caster.floor_id)
	if path.is_empty():
		finish()
		return
	path = paths.limit(path, skill.dash_distance)
	segment_to = path.points[-1]
	var distance: float = path.length
	if distance <= 0.1:
		finish()
		return
	segment_index += 1
	caster.combat_audio.play_movement(caster, &"charge", skill)
	previous = segment_from
	hit_units.clear()
	caster.skill_manager.cast_target = target
	caster.skill_manager.current_target = target
	caster.animated_sprite_2d.flip_h = direction.x < 0
	caster.animated_sprite_2d.stop()
	caster.animated_sprite_2d.play(skill.cast_animation)
	var seconds := distance / maxf(1.0, skill.dash_speed)
	visual = preload("res://scripts/combat/cavalry_charge_vfx.gd").new()
	caster.get_parent().add_child(visual)
	visual.start(caster, segment_from, segment_to, seconds)
	tween = caster.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	caster.skill_manager.forced_movement_tween = tween
	tween.tween_method(_advance, 0.0, 1.0, seconds)
	pause_left = -1.0
	_hit_between(previous, previous)


func _advance(progress: float) -> void:
	if not done and is_instance_valid(caster):
		if not preload("res://scripts/combat/unit_motion_path.gd").move(caster, path, progress):
			cancel()

func _physics_process(delta: float) -> void:
	if done:
		return
	if not _valid():
		cancel()
		return
	if pause_left >= 0:
		pause_left -= delta
		if pause_left <= 0:
			_begin_segment(_next_target())
		return
	_hit_between(previous, caster.global_position)
	previous = caster.global_position
	if done or not _valid():
		return
	if tween != null and not tween.is_running():
		if is_instance_valid(visual):
			visual.stop_movement()
		if segment_index >= skill.dash_count:
			finish()
		else:
			pause_left = skill.dash_pause


func _next_target() -> UnitBase:
	var forced: UnitBase = caster.status_runtime.taunt_target()
	if forced != null:
		return forced
	var best: UnitBase
	var distance := INF
	for node in get_tree().get_nodes_in_group("team_b" if caster.unit_data.unit_team == "team_a" else "team_a"):
		var enemy := node as UnitBase
		if not is_instance_valid(enemy) or not enemy.can_be_targeted_by(caster) or not enemy.shares_encounter(caster) or enemy.is_in_group("player_base"):
			continue
		var squared := caster.global_position.distance_squared_to(enemy.global_position)
		if squared < distance:
			best = enemy
			distance = squared
	return best


func _hit_between(from: Vector2, to: Vector2) -> void:
	var shape := caster.get_node_or_null("AttackArea/CollisionShape2D") as CollisionShape2D
	if shape == null:
		return
	# 覆盖相邻物理帧之间的全部路径，加速后也不能越过敌人漏判。
	var steps := maxi(1, ceili(from.distance_to(to) / 12.0))
	for step in range(steps + 1):
		var query := PhysicsShapeQueryParameters2D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.transform.origin += from.lerp(to, float(step) / steps) - caster.global_position
		query.collision_mask = 3
		query.exclude = [caster.get_rid()]
		for contact: Dictionary in caster.get_world_2d().direct_space_state.intersect_shape(query, 128):
			var enemy := contact.collider as UnitBase
			if not is_instance_valid(enemy) or enemy.unit_data.unit_team == caster.unit_data.unit_team \
				or not enemy.can_be_targeted_by(caster) or not enemy.shares_encounter(caster) \
				or enemy.is_in_group("player_base") or hit_units.has(enemy.get_instance_id()):
				continue
			hit_units[enemy.get_instance_id()] = true
			if enemy.get_hurt(int(caster.unit_data.attack * skill.attack_rate), caster, true, &"", -1, false, skill.combat_number_kind(), skill.defence_segments()):
				skill.apply_hit_statuses(caster, enemy)
				if is_instance_valid(visual):
					visual.impact(enemy)
			if done or not _valid():
				return


func cancel() -> void:
	if is_instance_valid(visual):
		visual.cancel()
	finish()


func finish() -> void:
	if done:
		return
	done = true
	if tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(visual):
		visual.stop_movement()
	if is_instance_valid(caster):
		if caster.actions_interrupted.is_connected(cancel):
			caster.actions_interrupted.disconnect(cancel)
		# 中断可能已经启动击退或新技能，不能覆盖新的移动锁。
		if caster.skill_manager.cast_data.get("dash_motion") == self:
			caster.skill_manager.cast_data.erase("dash_motion")
			caster.skill_manager.is_forced_moving = false
			caster.skill_manager.forced_movement_tween = null
			var collision := caster.get_node_or_null("CollisionShape2D") as CollisionShape2D
			if collision != null:
				collision.set_deferred("disabled", false)
			caster.get_node("AttackArea").set_deferred("monitoring", false)
			caster.navigation_agent_2d.reset_after_teleport()
			if not path.is_empty():
				caster.navigation_agent_2d.refresh_forced_movement_visual(path.links)
			caster.skill_manager.finish_skill(skill)
	queue_free()


func _exit_tree() -> void:
	if not done:
		cancel()
