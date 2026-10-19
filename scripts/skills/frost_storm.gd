# 霜暴在发射帧读取本战场消耗牌堆；每颗冰晶独立飞行、命中与结算。
extends SkillBase

## 不计消耗牌堆时的冰霜子弹数量；基础为3，强化版本为5。
@export_range(1, 999, 1) var base_projectile_count: int = 3
## 每颗子弹的固定单体伤害，无视攻击力、防御和伤害倍率。
@export_range(1, 9999, 1) var projectile_damage: int = 10
## 强化命中后的减速半径，单位为世界像素。
@export var slow_radius: float = 150.0
## 命中风暴持续秒数；后续命中刷新，范围随受击目标移动。
@export var slow_duration: float = 2.0
## 范围内敌军降低的移动速度；0表示此版本不减速，同类重叠取最高值。
@export var slow_amount: int = 0


func projectile_count(caster: UnitBase) -> int:
	var exhausted := 0
	if caster.has_meta("battle_owner"):
		var reference: WeakRef = caster.get_meta("battle_owner")
		var battle = reference.get_ref() if reference != null else null
		if is_instance_valid(battle) and is_instance_valid(battle.hand_manager):
			exhausted = battle.hand_manager.exhaust_pile.size()
	return base_projectile_count + exhausted


func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or not is_instance_valid(target) or caster._encounter_finished() \
		or target.is_queued_for_deletion() or target.current_state == UnitBase.State.DEATH \
		or caster.unit_data.unit_team == target.unit_data.unit_team:
		return
	var volley = load("res://scripts/combat/frost_storm_volley.gd").new()
	caster.get_parent().add_child(volley)
	volley.start(caster, target, self, projectile_count(caster))


func card_effect_description() -> String:
	return "%s：发射%d+x颗冰晶，每颗固定%d点伤害，冷却%s秒；x为消耗牌堆张数。%s" % [
		skill_name, base_projectile_count, projectile_damage, cooldown,
		"命中后使目标周围%s范围敌军移速-%d，持续%s秒。" % [slow_radius, slow_amount, slow_duration] if slow_amount > 0 else ""]


func effect_description() -> String:
	return card_effect_description()
