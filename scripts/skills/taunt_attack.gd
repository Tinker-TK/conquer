# 嘲讽以释放瞬间的范围选取敌人，持续期间由目标自己的状态系统维护强制索敌。
extends SkillBase

## 释放嘲讽时选取敌人的世界像素半径。
@export_range(1.0, 2000.0, 1.0) var taunt_radius: float = 200.0
## 每次命中的敌人保持嘲讽的战斗秒数；离开范围不会提前解除。
@export_range(0.1, 30.0, 0.1) var taunt_duration: float = 3.0
## 嘲讽期间，每名当前瞄准施法者的敌人提供的防御；0不提供。
@export_range(0, 99, 1) var defence_per_attacker: int = 0
## 嘲讽期间在施法者脚下显示的特效，沿用圣殿骑士原光环。
@export var taunt_effect: PackedScene = preload("res://assets/effect/godot_vfx_library/effects/magic/magic_aura.tscn")


func execute(caster: UnitBase, _target: UnitBase = null) -> void:
	if not is_instance_valid(caster) or not caster.can_use_skills() or caster._encounter_finished() \
		or Global.game_phase != Global.GamePhase.AUTO_BATTLE:
		return
	if caster.taunt_runtime == null:
		caster.taunt_runtime = preload("res://scripts/units/templar_taunt_runtime.gd").new()
		caster.taunt_runtime.name = "TemplarTaunt"
		caster.add_child(caster.taunt_runtime)
	caster.taunt_runtime.start(self)


func card_effect_description() -> String:
	return "嘲讽攻击：%.0f内敌人转攻自身%.0f秒，CD%.0f秒。%s" % [taunt_radius, taunt_duration, cooldown,
		"期间每名瞄准敌人使防御+%d。" % defence_per_attacker if defence_per_attacker > 0 else ""]


func effect_description() -> String:
	return card_effect_description() + "多个嘲讽重叠时，目标攻击距离最近的嘲讽者。"
