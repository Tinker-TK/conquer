# 这玩意儿是干嘛的（核心逻辑）：攻击命中后扣血，并在命中点播放技能配置的特效。
# 数据是咋流动的（数据流向）：攻击帧触发 execute → 目标受伤 → 特效场景在目标位置播放。
# 为啥这么写（选型决策）：优先播放通用 effect 动画；没有时使用特效场景已经选中的动画。
# 性能咋样（复杂度）：每个命中帧只处理一个目标和一个特效，不扫描整个战场。
extends SkillBase

# 作用：caster 攻击 target；两者分别是施法者与受击者，没有返回值。
func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(target):
		return
	if target.is_queued_for_deletion() or target.current_state == UnitBase.State.DEATH:
		return
	var hit_position := target.global_position
	# 直接执行技能也先确认目标，保证新目标的首击不会继承旧连击属性。
	caster.notify_attack_target(target)
	var damage := damage_for(caster, target)
	if not target.get_hurt(damage, caster, true, &"", -1, false, combat_number_kind(), defence_segments()):
		return
	apply_hit_statuses(caster, target)
	if on_hit_effect == null:
		return
	# 特效使用自己的动画名，避免配置了资源却因名称不同而看不到画面。
	var instance := on_hit_effect.instantiate()
	var effect := instance as AnimatedSprite2D
	if effect == null:
		instance.free()
		push_warning("命中特效的根节点必须是 AnimatedSprite2D")
		return
	var animation_name: StringName = &"effect" if effect.sprite_frames != null and effect.sprite_frames.has_animation(&"effect") else effect.animation
	if effect.sprite_frames == null or not effect.sprite_frames.has_animation(animation_name):
		effect.free()
		push_warning("命中特效缺少可播放的动画")
		return
	# 特效加到战场容器，画面位置保持在受击点；播完后自动清理。
	var parent := caster.get_tree().current_scene
	if parent == null:
		parent = caster.get_parent()
	parent.add_child(effect)
	effect.global_position = hit_position
	effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)
	effect.stop()
	effect.play(animation_name)


func damage_for(caster: UnitBase, _target: UnitBase) -> int:
	return int(caster.unit_data.attack * attack_rate)
