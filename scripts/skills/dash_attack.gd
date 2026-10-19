# 参数保存在资源中，位移和分段命中由每次施法的独立节点维护。
extends SkillBase

func defence_segments() -> int:
	return maxi(1, dash_count)

## 每段冲锋的最大距离，遇到本层墙体或地表边界提前停止。
@export_range(1.0, 2000.0, 1.0) var dash_distance: float = 600.0
## 每段的世界像素/秒速度。
@export_range(1.0, 5000.0, 1.0) var dash_speed: float = 300.0
## 一次技能连续冲锋的次数，每段对同一敌人最多命中一次。
@export_range(1, 10, 1) var dash_count: int = 1
## 连续冲锋之间的短暂停顿，让转向和再次出发清晰可见。
@export_range(0.0, 2.0, 0.01) var dash_pause: float = 0.12


# 本技能在第0帧出发；AnimatedSprite从idle第0帧切换时未必发出frame_changed。
func begin_cast(caster: UnitBase, target: UnitBase) -> bool:
	execute(caster, target)
	return caster.skill_manager.cast_data.has("dash_motion")


func execute(caster: UnitBase, target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or caster.skill_manager.is_forced_moving:
		return
	if not is_instance_valid(target) or not target.can_be_targeted_by(caster):
		caster.skill_manager.finish_skill(self)
		return
	var motion := preload("res://scripts/combat/cavalry_dash_motion.gd").new()
	caster.get_parent().add_child(motion)
	motion.start(caster, target, self)


func card_effect_description() -> String:
	return "%s：冲锋%d次，每段沿途敌人受到%.0f%%伤害，速度%.0f，CD%.0f秒。" % [skill_name, dash_count, attack_rate * 100.0, dash_speed, cooldown]


func effect_description() -> String:
	return card_effect_description() + "每段最多前进%.0f像素，后续冲锋重新朝有效敌人转向。" % dash_distance
