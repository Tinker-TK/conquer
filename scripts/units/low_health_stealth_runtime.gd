# 使用单位自己的部署状态和物理时钟，不把触发次数写进共享技能或卡牌。
extends Node

var caster: UnitBase
var skill
var triggered := false
var remaining := 0.0


func _ready() -> void:
	name = "LowHealthStealth"
	caster.health_changed.connect(check_health)
	caster.unit_died.connect(_on_caster_died)


func _enabled() -> bool:
	return is_instance_valid(caster) and caster.is_inside_tree() and not caster.is_queued_for_deletion() \
		and caster.current_state != UnitBase.State.DEATH and int(caster.current_health) > 0 \
		and not caster._encounter_finished() and caster.unit_data.is_skill_unlocked(skill)


func check_health() -> void:
	if triggered or not _enabled() or caster.unit_data.max_hp <= 0:
		return
	if float(caster.current_health) / caster.unit_data.max_hp < skill.stealth_health_percent / 100.0:
		triggered = true
		remaining = maxf(0.0, skill.stealth_duration)
		caster.stealth_seconds_left = remaining
		caster.set_stealthed(remaining > 0)


func clear() -> void:
	remaining = 0
	if is_instance_valid(caster):
		caster.stealth_seconds_left = 0
		caster.set_stealthed(false)


func _on_caster_died(_unit: UnitBase) -> void:
	clear()


func _exit_tree() -> void:
	clear()


func _physics_process(delta: float) -> void:
	if not _enabled():
		clear()
		return
	if remaining > 0:
		remaining = maxf(0.0, remaining - delta)
		caster.stealth_seconds_left = remaining
		if remaining <= 0:
			caster.set_stealthed(false)
		else:
			caster._refresh_passive_status()
	else:
		check_health()
