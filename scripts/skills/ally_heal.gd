# 这玩意儿是干嘛的（核心逻辑）：治疗技能选中的友军并播放治疗特效。
# 数据是咋流动的（数据流向）：Inspector 中的配置进入资源，再由战斗或界面节点读取并执行。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：资源本身不运行每帧循环，仅在对应系统使用时处理。
extends SkillBase

## 强化治疗：全体友军满血时仍可选最高当前生命友军，并把溢出治疗按1:1转成护盾。
@export var overflow_to_shield: bool = false

func execute(caster: UnitBase, target: UnitBase = null):
	if not is_instance_valid(caster) or not is_instance_valid(target) or target.is_queued_for_deletion() \
		or target.unit_data.unit_team != caster.unit_data.unit_team:
		return
	var hit_position = target.global_position
	var damage := int(caster.unit_data.attack * attack_rate)  # 己方单位造成的治疗量
	if not target.receive_healing(damage, caster, overflow_to_shield):
		return
	if on_hit_effect != null:
		var effect = on_hit_effect.instantiate() as AnimatedSprite2D
		var parent := caster.get_tree().current_scene
		if parent == null:
			parent = caster.get_parent()
		parent.add_child(effect)
		effect.global_position = hit_position
		effect.stop()
		effect.play('effect')
		effect.animation_finished.connect(effect.queue_free, CONNECT_ONE_SHOT)


func card_effect_description() -> String:
	return "%s：治疗生命比例最低的友军（含自身），回复%.0f%%攻击力的生命。%s" % [skill_name, attack_rate * 100.0,
		"全员满血时选当前生命最高者，溢出量转为护盾。" if overflow_to_shield else ""]


func effect_description() -> String:
	return card_effect_description()
