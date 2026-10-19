extends "res://scripts/skills/normal_attack.gd"

## 每次血影斩击命中追加的流血层数，每层每秒固定扣除1点生命。
@export_range(1, 99, 1) var bleed_stacks_per_hit: int = 1
## 鲜血回归的战斗秒数间隔；仅返还自身流血实际扣除的生命。
@export_range(0.1, 60.0, 0.1) var blood_return_interval: float = 6.0


func apply_hit_statuses(caster: UnitBase, target: UnitBase) -> void:
	super.apply_hit_statuses(caster, target)
	if target.current_state != UnitBase.State.DEATH and caster.knight_runtime != null:
		caster.knight_runtime.add_bleed(target, bleed_stacks_per_hit)


func card_effect_description() -> String:
	var seconds := str(int(blood_return_interval)) if is_equal_approx(blood_return_interval, roundf(blood_return_interval)) else str(blood_return_interval)
	return "血影斩击：%.0f%%伤害，CD%.0f秒；流血+%d层（1/秒）。鲜血回归：每%s秒回复自身流血扣血量。" % [attack_rate * 100.0, cooldown, bleed_stacks_per_hit, seconds]


func effect_description() -> String:
	return card_effect_description()
