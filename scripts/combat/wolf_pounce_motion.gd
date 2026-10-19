extends Node2D

var caster: UnitBase
var target: UnitBase
var skill: SkillBase
var stage := "pounce"
var tween: Tween
var visual: Node2D
var done := false
var path: Dictionary


func start(unit: UnitBase, enemy: UnitBase, config: SkillBase, landing: Vector2) -> void:
	caster = unit
	target = enemy
	skill = config
	path = preload("res://scripts/combat/unit_motion_path.gd").plan(caster, caster.global_position, landing, target.floor_id)
	if path.is_empty():
		finish()
		return
	caster.skill_manager.cast_data["wolf_pounce"] = self
	caster.skill_manager.is_forced_moving = true
	caster.navigation_agent_2d.stop_navigation()
	caster.velocity = Vector2.ZERO
	caster.animated_sprite_2d.flip_h = target.global_position.x < caster.global_position.x
	caster.animated_sprite_2d.play("walk")
	caster.get_node("CollisionShape2D").set_deferred("disabled", true)
	caster.actions_interrupted.connect(finish)
	caster.animated_sprite_2d.animation_finished.connect(_animation_finished)
	target.kill_confirmed.connect(_target_killed)
	visual = preload("res://scripts/combat/unit_dash_vfx.gd").new()
	caster.get_parent().add_child(visual)
	visual.start(caster, "angel_dash", caster.global_position, landing, skill.pounce_seconds)
	tween = caster.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	caster.skill_manager.forced_movement_tween = tween
	tween.tween_method(_advance, 0.0, 1.0, skill.pounce_seconds)


func _advance(progress: float) -> void:
	if not done and is_instance_valid(caster):
		if not preload("res://scripts/combat/unit_motion_path.gd").move(caster, path, progress):
			finish()


func _valid() -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() \
		and caster.can_use_skills() and not caster._encounter_finished() and skill._enemy(caster, target) \
		and (caster.is_on_same_floor(target) or (stage == "pounce" and target.floor_id == path.floors[-1])) \
		and caster.skill_manager.current_skill == skill \
		and caster.skill_manager.cast_data.get("wolf_pounce") == self \
		and caster.unit_data.is_skill_unlocked(skill) and Global.game_phase == Global.GamePhase.AUTO_BATTLE


func _physics_process(_delta: float) -> void:
	if done:
		return
	if not _valid():
		finish()
		return
	if stage == "pounce" and tween != null and not tween.is_running():
		stage = "attack"
		caster.get_node("CollisionShape2D").set_deferred("disabled", false)
		caster.navigation_agent_2d.reset_after_teleport()
		caster.animated_sprite_2d.flip_h = target.global_position.x < caster.global_position.x
		caster.animated_sprite_2d.stop()
		caster.animated_sprite_2d.play(skill.cast_animation)
		caster.navigation_agent_2d.refresh_forced_movement_visual(path.links)


func _target_killed(victim: UnitBase, killer: UnitBase) -> void:
	if victim != target or not is_instance_valid(caster):
		return
	if skill.refresh_on_target_kill and killer == caster and caster.can_use_skills() and not caster._encounter_finished() \
		and caster.skill_manager.cast_data.get("wolf_pounce") == self \
		and caster.unit_data.is_skill_unlocked(skill) and Global.game_phase == Global.GamePhase.AUTO_BATTLE:
		caster.skill_manager.reset_cooldown(skill)
	# 死亡后立即结束旧连击，让已刷新的技能下一次索敌即可发动。
	finish()


func _animation_finished() -> void:
	if not done and stage == "attack" and is_instance_valid(caster) and caster.animated_sprite_2d.animation == skill.cast_animation:
		finish()


func finish() -> void:
	if done:
		return
	done = true
	if tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(visual):
		visual.cancel()
	if is_instance_valid(target) and target.kill_confirmed.is_connected(_target_killed):
		target.kill_confirmed.disconnect(_target_killed)
	if is_instance_valid(caster):
		if caster.actions_interrupted.is_connected(finish):
			caster.actions_interrupted.disconnect(finish)
		if caster.animated_sprite_2d.animation_finished.is_connected(_animation_finished):
			caster.animated_sprite_2d.animation_finished.disconnect(_animation_finished)
		if caster.skill_manager.cast_data.get("wolf_pounce") == self:
			caster.skill_manager.cast_data.erase("wolf_pounce")
			caster.skill_manager.is_forced_moving = false
			caster.skill_manager.forced_movement_tween = null
			caster.get_node("CollisionShape2D").set_deferred("disabled", false)
			caster.navigation_agent_2d.reset_after_teleport()
			caster.navigation_agent_2d.refresh_forced_movement_visual(path.links)
			caster.skill_manager.finish_skill(skill)
	queue_free()


func _exit_tree() -> void:
	if not done:
		finish()
