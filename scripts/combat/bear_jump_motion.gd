# 动画伤害帧起跳，真实地面位置沿路径移动，精灵按实验室Abyssal重击的65像素弧线腾空。
extends Node2D

var caster: UnitBase
var skill: SkillBase
var stage := "windup"
var jumps := 0
var elapsed := 0.0
var from := Vector2.ZERO
var landing := Vector2.ZERO
var sprite_position := Vector2.ZERO
var visual: Node2D
var done := false
var path: Dictionary


func start(unit: UnitBase, config: SkillBase) -> void:
	caster = unit
	skill = config
	sprite_position = caster.animated_sprite_2d.position
	caster.skill_manager.cast_data["bear_jump"] = self
	caster.skill_manager.is_forced_moving = true
	caster.navigation_agent_2d.stop_navigation()
	caster.velocity = Vector2.ZERO
	caster.actions_interrupted.connect(finish)
	caster.animated_sprite_2d.animation_finished.connect(_animation_finished)


func _valid() -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() \
		and caster.can_use_skills() and not caster._encounter_finished() \
		and caster.skill_manager.current_skill == skill and caster.skill_manager.cast_data.get("bear_jump") == self \
		and caster.unit_data.is_skill_unlocked(skill) and Global.game_phase == Global.GamePhase.AUTO_BATTLE


func take_off() -> void:
	if stage != "windup" or not _valid():
		return
	var target: UnitBase = caster.skill_manager.find_target_for_skill(skill)
	if not is_instance_valid(target) or not skill._target(caster, target) \
		or caster.global_position.distance_to(target.global_position) > skill.cast_range + 0.001:
		finish()
		return
	from = caster.global_position
	path = preload("res://scripts/combat/unit_motion_path.gd").plan(caster, from, target.global_position, target.floor_id)
	if path.is_empty():
		finish()
		return
	landing = path.points[-1]
	caster.animated_sprite_2d.flip_h = landing.x < from.x
	caster.animated_sprite_2d.pause()
	caster.get_node("CollisionShape2D").set_deferred("disabled", true)
	stage = "air"
	elapsed = 0.0
	visual = preload("res://scripts/combat/bear_leap_vfx.gd").new()
	caster.get_parent().add_child(visual)
	visual.start(caster, "abyssal_slam", from, landing, skill.jump_seconds)


func _physics_process(delta: float) -> void:
	if done:
		return
	if not _valid():
		finish()
		return
	if stage != "air":
		return
	elapsed += delta
	var progress := clampf(elapsed / skill.jump_seconds, 0.0, 1.0)
	if not preload("res://scripts/combat/unit_motion_path.gd").move(caster, path, progress):
		finish()
		return
	caster.animated_sprite_2d.position = sprite_position + Vector2(0, -sin(progress * PI) * 65.0)
	if progress >= 1.0:
		stage = "landing"
		jumps += 1
		caster.animated_sprite_2d.position = sprite_position
		caster.get_node("CollisionShape2D").set_deferred("disabled", false)
		caster.navigation_agent_2d.reset_after_teleport()
		skill.land(caster)
		if _valid():
			caster.animated_sprite_2d.play()


func _animation_finished() -> void:
	if not _valid() or stage != "landing" or caster.animated_sprite_2d.animation != skill.cast_animation:
		return
	if jumps >= skill.jump_count:
		finish()
		return
	stage = "windup"
	caster.animated_sprite_2d.stop()
	caster.animated_sprite_2d.play(skill.cast_animation)


func finish() -> void:
	if done:
		return
	done = true
	if is_instance_valid(visual):
		visual.cancel()
	if is_instance_valid(caster):
		if caster.actions_interrupted.is_connected(finish):
			caster.actions_interrupted.disconnect(finish)
		if caster.animated_sprite_2d.animation_finished.is_connected(_animation_finished):
			caster.animated_sprite_2d.animation_finished.disconnect(_animation_finished)
		caster.animated_sprite_2d.position = sprite_position
		# 中断已清空旧上下文时，不覆盖新技能的强制位移状态。
		if caster.skill_manager.cast_data.get("bear_jump") == self:
			caster.skill_manager.cast_data.erase("bear_jump")
			caster.skill_manager.is_forced_moving = false
			caster.get_node("CollisionShape2D").set_deferred("disabled", false)
			caster.navigation_agent_2d.reset_after_teleport()
			if not path.is_empty():
				caster.navigation_agent_2d.refresh_forced_movement_visual(path.links)
			caster.skill_manager.finish_skill(skill)
	queue_free()


func _exit_tree() -> void:
	if not done:
		finish()
