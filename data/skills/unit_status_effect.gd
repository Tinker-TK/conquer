class_name UnitStatusEffect
extends Resource
## 技能命中时附加的状态配置。资源不保存任何单位的运行状态。

enum Kind { BLEED, CONFUSION, MORTAL_WOUNDS, SLEEP, STUN, WEAKNESS }
const IDS := [&"bleed", &"confusion", &"mortal_wounds", &"sleep", &"stun", &"weakness"]

## 流血、混乱、禁疗、睡眠、晕眩或虚弱；策反沿用战术卡的阵营转换入口。
@export var kind: Kind = Kind.BLEED
## 流血为每秒固定伤害，忽略防御；虚弱为攻击降低点数。其余状态不读取此值。
@export_range(1, 9999, 1) var amount: int = 5
## 有效战斗秒数；0 持续本场。睡眠始终保持到被攻击或显式解除，不因计时自然醒来。
@export_range(0, 300, 0.1) var duration: float = 5.0


func apply_to(target: Node, caster: Node, skill: Resource, source_identity: int = 0) -> void:
	if kind < 0 or kind >= IDS.size() or not is_finite(duration) or duration < 0:
		return
	# 同一施法者的同一技能刷新期限，不无限叠加；不同来源独立结算与解除。
	var caster_id := caster.get_instance_id() if is_instance_valid(caster) else source_identity
	var source_key := "%d:%d" % [caster_id, skill.get_instance_id()]
	target.apply_status(IDS[kind], duration, amount, caster, source_key)
