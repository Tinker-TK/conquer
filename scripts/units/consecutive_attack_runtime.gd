# 仅成功的攻击命中叠层；技能收尾时临时清空索敌字段，不代表切换敌人。
extends Node

var caster: UnitBase
var skill
var hits := 0
var _target: WeakRef


func _ready() -> void:
	name = "ConsecutiveAttack"
	caster.attack_target_selected.connect(_on_target_selected)
	caster.attack_landed.connect(_on_attack_landed)
	caster.unit_died.connect(_on_caster_died)


func _alive(unit: UnitBase) -> bool:
	return is_instance_valid(unit) and unit.is_inside_tree() and not unit.is_queued_for_deletion() \
		and unit.current_state != UnitBase.State.DEATH and int(unit.current_health) > 0


func _enabled() -> bool:
	return _alive(caster) and not caster._encounter_finished() and caster.unit_data.is_skill_unlocked(skill)


func _enemy(target: UnitBase) -> bool:
	return _alive(target) and target.unit_data.unit_team != caster.unit_data.unit_team


func _on_target_selected(target: UnitBase) -> void:
	if not _enabled() or not _enemy(target):
		return
	if _target != null and _target.get_ref() == target:
		return
	clear()
	_target = weakref(target)
	target.unit_died.connect(_on_target_died)


func _on_attack_landed(target: UnitBase) -> void:
	if not _enabled() or not _enemy(target):
		return
	_on_target_selected(target)
	hits += 1
	caster.set_consecutive_attack_bonus(hits * maxi(0, skill.attack_bonus_per_hit), hits, target.unit_data.unit_name)


func clear() -> void:
	var target = _target.get_ref() if _target != null else null
	if is_instance_valid(target) and target.unit_died.is_connected(_on_target_died):
		target.unit_died.disconnect(_on_target_died)
	_target = null
	hits = 0
	if is_instance_valid(caster):
		caster.set_consecutive_attack_bonus(0, 0, "")


func _on_target_died(_unit: UnitBase) -> void:
	clear()


func _on_caster_died(_unit: UnitBase) -> void:
	clear()


func _exit_tree() -> void:
	clear()


func _physics_process(_delta: float) -> void:
	if not _enabled() or (_target != null and not _enemy(_target.get_ref())):
		clear()
