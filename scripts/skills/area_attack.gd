# 这玩意儿是干嘛的（核心逻辑）：处理范围攻击中的目标和伤害结算。
# 数据是咋流动的（数据流向）：Inspector 中的配置进入资源，再由战斗或界面节点读取并执行。
# 为啥这么写（选型决策）：保持原有接口，把同类职责归到一起，便于查找和配置。
# 性能咋样（复杂度）：资源本身不运行每帧循环，仅在对应系统使用时处理。
extends SkillBase

## 命中存活敌人后向外击退的世界像素；0不击退。
@export_range(0.0, 2000.0, 1.0) var knockback_distance: float = 0.0
## 完整击退所需秒数；实际碰到本层地形碰撞体时提前停止。
@export_range(0.01, 5.0, 0.01) var knockback_duration: float = 0.3
## 击退撞到本层地形或实体障碍时施加的眩晕秒数；0不眩晕。
@export_range(0.0, 30.0, 0.1) var wall_stun_duration: float = 0.0
## 释放时在施法者自身播放的实验室特效原名；留空不播放。
@export var self_effect: String = ""


func begin_cast(caster: UnitBase, _target: UnitBase) -> bool:
	var area := caster.get_node_or_null("AttackArea") as Area2D
	if area != null:
		area.set_deferred("monitoring", true)
	return area != null


func execute(caster: UnitBase, _target: UnitBase = null):
	if not is_instance_valid(caster):
		return
	if caster.current_state == caster.State.DEATH:
		return
	if not self_effect.is_empty():
		preload("res://scripts/effects/combat_vfx.gd").spawn(caster, self_effect, 1.2)
	var damage := int(caster.unit_data.attack * attack_rate)  # 己方单位造成的伤害
	var attack_area := caster.get_node_or_null("AttackArea") as Area2D
	if attack_area == null:
		push_warning("缺少攻击判定区")
		return
	var enemy_team := caster.enemy_team()
	for body in attack_area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if body == null:
			continue
		if not body.is_in_group(enemy_team):
			continue
		if body.current_state == body.State.DEATH:
			continue
		if body.get_hurt(damage, caster, true, &"", -1, false, combat_number_kind(), defence_segments()):
			apply_hit_statuses(caster, body)
			if knockback_distance > 0.0 and body is UnitBase and body.current_state != UnitBase.State.DEATH:
				preload("res://scripts/combat/knockback_motion.gd").push(body, caster, knockback_distance, knockback_duration, wall_stun_duration)


func card_effect_description() -> String:
	if knockback_distance <= 0:
		return ""
	return "%s：周围敌人受到%.0f%%伤害并击退%.0f。%s" % [skill_name, attack_rate * 100.0, knockback_distance,
		"撞墙眩晕%.0f秒。" % wall_stun_duration if wall_stun_duration > 0 else ""]


func effect_description() -> String:
	return card_effect_description() if knockback_distance > 0 else super.effect_description()
