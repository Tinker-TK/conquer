# 这玩意儿是干嘛的（核心逻辑）：闪避成功后，委托单位播放防守和反击。
# 数据是咋流动的（数据流向）：受击者和攻击者进入技能，再由技能管理器处理命中与收尾。
# 为啥这么写（选型决策）：资源可能被多个单位共用，反击进度必须保存在各自的管理器中。
# 性能咋样（复杂度）：只在闪避时调用一次，不使用逐帧等待循环。
extends SkillBase

## 强化后反击命中附加的眩晕秒数；0表示不附加。
@export_range(0.0, 30.0, 0.1) var upgraded_stun_duration: float = 0.0
## 每次成功反击减少目标的防御；多命中帧仅叠一次，持续本场战斗。
@export_range(0, 99, 1) var counter_armor_break: int = 0


func apply_reaction_hit_statuses(caster: UnitBase, target: UnitBase, first_hit: bool) -> void:
	apply_hit_statuses(caster, target)
	if not first_hit or counter_armor_break <= 0 or not is_instance_valid(target) or target.current_state == UnitBase.State.DEATH:
		return
	var key := "counter_%d" % caster.get_instance_id()
	var previous: Dictionary = target.status_runtime.effects.get(&"armor_break", {}).get(key, {})
	target.apply_status(&"armor_break", 0.0, int(previous.get("amount", 0)) + counter_armor_break, caster, key)


func effect_description() -> String:
	return super.effect_description() + ("每次成功反击使目标防御-%d，可叠加，持续本场战斗。" % counter_armor_break if counter_armor_break > 0 else "")


func apply_hit_statuses(caster: UnitBase, target: UnitBase) -> void:
	super.apply_hit_statuses(caster, target)
	if upgraded_stun_duration > 0 and caster.unit_data.card_upgrade_level >= 1 and target.current_state != UnitBase.State.DEATH:
		target.apply_status(&"stun", upgraded_stun_duration, 0, caster, "counter_%d" % caster.get_instance_id())

# 作用：让 caster 反击 target；两个参数分别是防守者和攻击者，没有返回值。
func execute(caster: UnitBase, target: UnitBase = null):
	# 死亡或即将移除的单位不再参与反击，避免动画结束后攻击已经消失的对象。
	if not is_instance_valid(caster) or not is_instance_valid(target):
		return
	if caster.is_queued_for_deletion() or target.is_queued_for_deletion():
		return
	if caster.current_state == UnitBase.State.DEATH or target.current_state == UnitBase.State.DEATH:
		return
	caster.skill_manager.start_reaction(self, target)
