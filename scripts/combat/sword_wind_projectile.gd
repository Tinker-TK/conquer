# Lord of the Storm原中型龙卷风视觉；战斗伤害由扫过的真实路径统一结算。
extends Node2D

var caster: UnitBase
var skill: SkillBase
var direction := Vector2.RIGHT
var travelled := 0.0
var hits: Dictionary = {}
var visual: Node2D
var shape := CircleShape2D.new()


func start(unit: UnitBase, facing: Vector2, config: SkillBase) -> void:
	caster = unit
	skill = config
	direction = facing.normalized()
	global_position = caster.global_position
	z_index = caster.z_index + 1
	shape.radius = skill.wind_radius
	var recipe: Dictionary = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd").find("lord_of_the_storm")
	visual = preload("res://assets/effect/eslabong_vfx/eslabong_vfx.gd").spawn(self, recipe.actions[0].effect, caster._smoke_body_rect().get_center(), {
		"unit": caster, "controlled_flight": true, "max_lifetime": 0.0, "ground_position": global_position})
	var root: Node2D = visual.get_meta("visual_root")
	root.set_direction(direction)
	preload("res://scripts/effects/combat_vfx.gd").use_physics_clock(visual)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(caster) or caster.current_state == UnitBase.State.DEATH or caster._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		queue_free()
		return
	var step := minf(skill.wind_speed * delta, maxf(0.0, skill.wind_distance - travelled))
	var from := global_position
	var to := from + direction * step
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, from)
	query.motion = to - from
	query.collision_mask = (caster.floor_map.terrain_bit(caster.floor_id) | 4) if is_instance_valid(caster.floor_map) else 12
	var sweep := get_world_2d().direct_space_state.cast_motion(query)
	var blocked := sweep.size() == 2 and sweep[0] < 0.9999
	if blocked:
		to = from.lerp(to, sweep[0])
	var count := maxi(1, ceili(from.distance_to(to) / maxf(1, shape.radius)))
	for sample in range(count + 1):
		query.transform.origin = from.lerp(to, float(sample) / count)
		query.motion = Vector2.ZERO
		query.collision_mask = 3
		for contact: Dictionary in get_world_2d().direct_space_state.intersect_shape(query, 256):
			var enemy := contact.collider as UnitBase
			if not is_instance_valid(enemy) or not enemy.can_be_targeted_by(caster) or not enemy.shares_encounter(caster) \
				or enemy.unit_data.unit_team == caster.unit_data.unit_team or enemy.is_in_group("player_base") or hits.has(enemy.get_instance_id()):
				continue
			hits[enemy.get_instance_id()] = true
			if enemy.get_hurt(int(caster.unit_data.attack * skill.wind_attack_rate), caster, true, &"", -1, false, skill.combat_number_kind(), skill.defence_segments()):
				skill.apply_hit_statuses(caster, enemy)
	travelled += from.distance_to(to)
	global_position = to
	if blocked or travelled >= skill.wind_distance - 0.001:
		queue_free()
