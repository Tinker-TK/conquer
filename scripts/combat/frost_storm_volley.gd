# 直接继承特效实验室的原播放器，只接入数量、战斗命中与目标跟踪。
extends "res://assets/effect/eslabong_vfx/skills/skill_player.gd"

const Skills = preload("res://assets/effect/eslabong_vfx/skills/skill_library.gd")
const Visuals = preload("res://scripts/effects/combat_vfx.gd")
var caster_ref: WeakRef
var target_ref: WeakRef
var source_team := ""
var source_id := 0
var source_floor := 1
var frost_skill: SkillBase


func start(caster: UnitBase, target: UnitBase, data: SkillBase, count: int) -> void:
	name = "FrostStormVolley"
	caster_ref = weakref(caster)
	target_ref = weakref(target)
	source_team = caster.unit_data.unit_team
	source_id = caster.get_instance_id()
	source_floor = caster.floor_id
	frost_skill = data
	z_index = maxi(caster.z_index, target.z_index)
	# 原目录数据独立复制；原实验室仍保留25颗，此处只替换实际数量。
	var recipe: Dictionary = Skills.find("ice_storm").duplicate(true)
	recipe.actions[0].count = count
	# 单位的 attack_02 动画已经完成前摇，命中帧开始原版弹雨流程。
	recipe.cast_seconds = 0.0
	target_hit.connect(_on_target_hit)
	SignalBus.phase_change.connect(_on_phase_changed)
	play(recipe, to_local(caster.global_position), to_local(target.global_position), {"unit_height": 48.0})
	set_process(false)


# 全部冰晶、拖尾、命中碎冰、雪与减速动画都由实验室的原方法创建。
func _spawn(data: Dictionary, at: Vector2, controlled: bool = false) -> Node2D:
	var holder := super._spawn(data, at, controlled)
	if holder != null:
		Visuals.use_physics_clock(holder)
	return holder


func _physics_process(delta: float) -> void:
	var caster: UnitBase = caster_ref.get_ref() if caster_ref != null else null
	var target: UnitBase = target_ref.get_ref() if target_ref != null else null
	if Global.game_phase != Global.GamePhase.AUTO_BATTLE or not is_instance_valid(target) \
		or target.is_queued_for_deletion() or target.current_state == UnitBase.State.DEATH \
		or target._encounter_finished() or target.unit_data.unit_team == source_team \
		or (is_instance_valid(caster) and caster.unit_data.unit_team != source_team):
		clear()
		queue_free()
		return
	# 原版落点由预览位置给定；实战只更新目标坐标，不改变弹雨轨迹算法。
	destination = to_local(target.global_position)
	for flight: Dictionary in _flights:
		flight["to"] = destination
	super._process(delta)


func _on_target_hit(_position: Vector2) -> void:
	var caster: UnitBase = caster_ref.get_ref() if caster_ref != null else null
	var target: UnitBase = target_ref.get_ref() if target_ref != null else null
	if not is_instance_valid(target) or target.unit_data.unit_team == source_team:
		return
	if not target.get_hurt(frost_skill.projectile_damage, caster, false, &"ice", source_floor, true, frost_skill.combat_number_kind()):
		return
	if frost_skill.slow_amount <= 0 or target.current_state == UnitBase.State.DEATH:
		return
	var key := "FrostStormImpact_%d" % source_id
	var storm = target.get_node_or_null(key)
	if storm == null:
		storm = load("res://scripts/combat/frost_storm_impact.gd").new()
		storm.name = key
		storm.source_team = source_team
		storm.source = caster_ref
		target.add_child(storm)
	storm.refresh(frost_skill.slow_radius, frost_skill.slow_amount, frost_skill.slow_duration)


func _on_phase_changed(phase: int) -> void:
	if phase != Global.GamePhase.AUTO_BATTLE:
		clear()
		queue_free()
