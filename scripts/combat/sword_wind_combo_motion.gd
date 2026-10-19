extends Node2D

var caster: UnitBase
var target: WeakRef
var skill: SkillBase
var facing := Vector2.RIGHT
var stage := "retreat"
var tween: Tween
var motion_done := false
var animation_done := false
var frames_hit: Dictionary = {}
var visuals: Array[Node2D] = []
var done := false
var path: Dictionary
var attack_origin: Vector2
var attack_floor: int
var retreat_path: Dictionary


func start(unit: UnitBase, enemy: UnitBase, config: SkillBase) -> void:
	caster = unit
	target = weakref(enemy)
	skill = config
	attack_origin = caster.global_position
	attack_floor = caster.floor_id
	facing = caster.global_position.direction_to(enemy.global_position)
	if facing.is_zero_approx():
		facing = Vector2.LEFT if caster.animated_sprite_2d.flip_h else Vector2.RIGHT
	caster.skill_manager.cast_data["sword_combo"] = self
	caster.skill_manager.is_forced_moving = true
	caster.navigation_agent_2d.stop_navigation()
	caster.velocity = Vector2.ZERO
	caster.animated_sprite_2d.flip_h = facing.x < 0
	caster.animated_sprite_2d.play("walk")
	caster.actions_interrupted.connect(cancel)
	caster.animated_sprite_2d.animation_finished.connect(_animation_finished)
	caster.get_node("CollisionShape2D").set_deferred("disabled", true)
	_move(caster.global_position - facing * skill.retreat_distance, skill.retreat_seconds, "holy_step")


func _move(to: Vector2, seconds: float, effect: String, destination_floor: int = -1) -> void:
	var from := caster.global_position
	if stage == "advance" and not retreat_path.is_empty():
		# 后撤已验证并真实经过的楼梯可以原路返回，不受“施法时靠近坡口”的限制。
		path = preload("res://scripts/combat/unit_motion_path.gd").reverse(retreat_path)
	else:
		path = preload("res://scripts/combat/unit_motion_path.gd").plan(caster, from, to, destination_floor)
	if path.is_empty():
		path = {"points": PackedVector2Array([from]), "floors": PackedInt32Array([caster.floor_id]), "links": [], "length": 0.0}
	if stage == "retreat":
		retreat_path = path
	var end: Vector2 = path.points[-1]
	var visual := preload("res://scripts/combat/unit_dash_vfx.gd").new()
	caster.get_parent().add_child(visual)
	visual.start(caster, effect, from, end, seconds)
	visuals.append(visual)
	tween = caster.create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	caster.skill_manager.forced_movement_tween = tween
	tween.tween_method(_advance, 0.0, 1.0, seconds)
	motion_done = false


func _advance(progress: float) -> void:
	if not done and is_instance_valid(caster):
		if not preload("res://scripts/combat/unit_motion_path.gd").move(caster, path, progress):
			cancel()


func _valid() -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() \
		and caster.can_use_skills() and not caster._encounter_finished() \
		and caster.skill_manager.current_skill == skill and caster.skill_manager.cast_data.get("sword_combo") == self \
		and caster.unit_data.is_skill_unlocked(skill) and Global.game_phase == Global.GamePhase.AUTO_BATTLE


func _physics_process(_delta: float) -> void:
	if done:
		return
	if not _valid():
		cancel()
		return
	if tween != null and not tween.is_running():
		motion_done = true
		if stage == "retreat":
			stage = "attack"
			caster.animated_sprite_2d.stop()
			caster.animated_sprite_2d.play(skill.cast_animation)
	if animation_done and motion_done:
		finish()


func hit_frame(frame: int) -> void:
	if not _valid() or stage == "retreat" or frames_hit.has(frame):
		return
	frames_hit[frame] = true
	var index: int = skill.hit_frame.find(frame)
	if index < 0:
		return
	if skill.triple_wind or index == 0:
		var angle := 0.0
		if skill.triple_wind and index < 2:
			angle = deg_to_rad(-30 if index == 0 else 30) * (-1 if facing.x < 0 else 1)
		var wind := preload("res://scripts/combat/sword_wind_projectile.gd").new()
		caster.get_parent().add_child(wind)
		wind.start(caster, facing.rotated(angle), skill)
	else:
		skill.melee(caster, target.get_ref())
	if (not skill.triple_wind and index == 0) or (skill.triple_wind and index == skill.hit_frame.size() - 1):
		stage = "advance"
		_move(attack_origin, skill.advance_seconds, "dash", attack_floor)


func _animation_finished() -> void:
	if not done and caster.animated_sprite_2d.animation == skill.cast_animation:
		animation_done = true
		if motion_done:
			finish()


func cancel() -> void:
	for visual: Node2D in visuals:
		if is_instance_valid(visual):
			visual.cancel()
	finish()


func finish() -> void:
	if done:
		return
	done = true
	if tween != null and tween.is_valid():
		tween.kill()
	if is_instance_valid(caster):
		if caster.actions_interrupted.is_connected(cancel):
			caster.actions_interrupted.disconnect(cancel)
		if caster.animated_sprite_2d.animation_finished.is_connected(_animation_finished):
			caster.animated_sprite_2d.animation_finished.disconnect(_animation_finished)
		if caster.skill_manager.cast_data.get("sword_combo") == self:
			caster.skill_manager.cast_data.erase("sword_combo")
			caster.skill_manager.is_forced_moving = false
			caster.skill_manager.forced_movement_tween = null
			caster.get_node("CollisionShape2D").set_deferred("disabled", false)
			caster.navigation_agent_2d.reset_after_teleport()
			caster.navigation_agent_2d.refresh_forced_movement_visual(path.links)
			caster.skill_manager.finish_skill(skill)
	queue_free()


func _exit_tree() -> void:
	if not done:
		cancel()
