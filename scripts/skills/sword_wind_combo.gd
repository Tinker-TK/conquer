extends "res://scripts/skills/normal_attack.gd"

## 后撤距离；前突使用相同距离回到原攻击位置，遇墙或地表边界提前停止。
@export_range(0.0, 1000.0, 1.0) var retreat_distance: float = 300.0
## 神圣Step后撤的秒数。
@export_range(0.01, 2.0, 0.01) var retreat_seconds: float = 0.15
## 向前突进所需秒数。
@export_range(0.01, 2.0, 0.01) var advance_seconds: float = 0.2
## 强化后三个伤害帧分别发射上30度、下30度和正前方的风。
@export var triple_wind: bool = false
## 吹风伤害倍率，与剩余近战帧的倍率分别配置。
@export var wind_attack_rate: float = 1.6
## 吹风飞行速度，单位为像素/秒，默认沿用原中型龙卷风。
@export var wind_speed: float = 360.0
## 吹风最大飞行距离，单位为世界像素；沿途敌人各命中一次。
@export var wind_distance: float = 760.0
## 吹风的战斗碰撞半径，单位为世界像素，与视觉自身缩放独立。
@export var wind_radius: float = 28.0


func owns_cast_animation() -> bool:
	return true


func requires_live_target_on_hit() -> bool:
	return false


func begin_cast(caster: UnitBase, target: UnitBase) -> bool:
	if not is_instance_valid(target) or not target.can_be_targeted_by(caster):
		return false
	var combo := preload("res://scripts/combat/sword_wind_combo_motion.gd").new()
	caster.get_parent().add_child(combo)
	combo.start(caster, target, self)
	return true


func execute(caster: UnitBase, _target: UnitBase = null) -> void:
	var combo: Node = caster.skill_manager.cast_data.get("sword_combo")
	if is_instance_valid(combo):
		combo.hit_frame(caster.animated_sprite_2d.frame)


func melee(caster: UnitBase, target: UnitBase) -> void:
	if is_instance_valid(target) and caster.global_position.distance_to(target.global_position) <= cast_range + 1:
		super.execute(caster, target)


func card_effect_description() -> String:
	return "三连击：后撤%.0f，%s" % [retreat_distance,
		"依次上30°、下30°、向前放风后突进（风%.0f%%）。" % (wind_attack_rate * 100) if triple_wind else "首帧放风（%.0f%%），前突接两刀（各%.0f%%）。" % [wind_attack_rate * 100, attack_rate * 100]]


func effect_description() -> String:
	return card_effect_description() + "后撤使用神圣Step，吹风使用Lord of the Storm，前突使用冲刺。"
