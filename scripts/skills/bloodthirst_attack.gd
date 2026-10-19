# 这玩意儿是干嘛的（核心逻辑）：命中敌人后，把这次实际扣掉的生命等量回复给攻击者。
# 数据是咋流动的（数据流向）：动画命中帧 → 目标受伤 → 比较受伤前后生命 → 自身治疗与血条刷新。
# 为啥这么写（选型决策）：复用受伤和治疗入口，防御、闪避、死亡和满血限制沿用现有规则。
# 性能咋样（复杂度）：每个命中帧只处理一个目标，不扫描全场，也不保存共享的战斗状态。
extends SkillBase


# 作用：动画命中帧发动吸血攻击；caster 为攻击者，target 为受击目标，没有返回值。
func execute(caster: UnitBase, target: UnitBase = null) -> void:
	# 无效、待删除或死亡单位不能发起或承受这次攻击，自己也不能成为吸血目标。
	if not is_instance_valid(caster) or not is_instance_valid(target) or caster == target:
		return
	if caster.is_queued_for_deletion() or target.is_queued_for_deletion():
		return
	if caster.current_state == UnitBase.State.DEATH or target.current_state == UnitBase.State.DEATH:
		return
	if caster.unit_data == null or caster.current_health <= 0 or target.current_health <= 0:
		return

	# 伤害交给目标扣防御和判闪避；倍率为零时不触发普通受伤接口的最低一点伤害。
	var damage := int(caster.unit_data.attack * attack_rate)
	if damage <= 0:
		return
	var health_before := maxi(int(target.current_health), 0)
	var hit_position := target.global_position
	if not target.get_hurt(damage, caster, true, &"", -1, false, combat_number_kind(), defence_segments()):
		return
	apply_hit_statuses(caster, target)

	# 尸体生命可能为负数，按零计算才能排除溢出伤害；例如剩 3 血被打 20，只吸 3 血。
	if not is_instance_valid(target) or not is_instance_valid(caster):
		return
	var actual_damage := clampi(health_before - maxi(int(target.current_health), 0), 0, health_before)
	if actual_damage > 0 and not caster.is_queued_for_deletion():
		# get_heal 会限制最大生命并拒绝治疗死亡单位，死亡爆炸杀死攻击者时不会把它复活。
		caster.get_heal(actual_damage, caster)
	_play_hit_effect(caster, hit_position)


# 作用：命中后播放可选特效；caster 提供场景树，point 是命中时的世界位置，没有返回值。
func _play_hit_effect(caster: UnitBase, point: Vector2) -> void:
	if on_hit_effect == null or not caster.is_inside_tree() or caster.is_queued_for_deletion():
		return
	var instance := on_hit_effect.instantiate()
	var effect := instance as AnimatedSprite2D
	if effect == null:
		instance.free()
		push_warning("嗜血攻击的命中特效根节点必须是 AnimatedSprite2D")
		return
	# 优先使用通用 effect 动画，没有时使用场景里选中的动画。
	var animation_name: StringName = &"effect" if effect.sprite_frames != null and effect.sprite_frames.has_animation(&"effect") else effect.animation
	if effect.sprite_frames == null or not effect.sprite_frames.has_animation(animation_name):
		effect.free()
		return
	# 为本次实例关闭循环，确保特效能结束并清理，不修改共享的原始动画资源。
	effect.sprite_frames = effect.sprite_frames.duplicate()
	effect.sprite_frames.set_animation_loop(animation_name, false)
	var parent := caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()
	parent.add_child(effect)
	effect.global_position = point
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.stop()
	effect.play(animation_name)
