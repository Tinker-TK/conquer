# 士兵每个出场实例独立记录斩击目标和本场成长，不写入卡牌或共享资源。
extends Node

var unit: UnitBase
var last_target: WeakRef
var slashed: Dictionary = {}
var slash_bonus := 0
var missile_bonus := 0


func _ready() -> void:
	unit = get_parent()
	unit.attack_target_selected.connect(_on_target_selected)
	unit.unit_died.connect(_on_died)


static func same_encounter(a: UnitBase, b: UnitBase) -> bool:
	if a.has_meta("battle_owner") or b.has_meta("battle_owner"):
		var ar: WeakRef = a.get_meta("battle_owner") if a.has_meta("battle_owner") else null
		var br: WeakRef = b.get_meta("battle_owner") if b.has_meta("battle_owner") else null
		return ar != null and br != null and ar.get_ref() != null and ar.get_ref() == br.get_ref()
	return a.get_parent().get_parent() == b.get_parent().get_parent()


func _on_target_selected(target: UnitBase) -> void:
	last_target = weakref(target)


func attacks(target: UnitBase) -> bool:
	var manager := unit.skill_manager
	return manager.current_target == target or manager.cast_target == target or (last_target != null and last_target.get_ref() == target)


func has_slashed(target: UnitBase) -> bool:
	return slashed.has(target.get_instance_id())


func register_slash(target: UnitBase) -> void:
	if has_slashed(target):
		return
	var id := target.get_instance_id()
	slashed[id] = weakref(target)
	target.unit_died.connect(_on_slashed_target_died.bind(id), CONNECT_ONE_SHOT)


func _on_slashed_target_died(_target: UnitBase, id: int) -> void:
	if slashed.has(id) and unit.current_state != UnitBase.State.DEATH and not unit._encounter_finished():
		slash_bonus += 1
		_sync_bonus()


func gain_missile_bonus(amount: int) -> void:
	missile_bonus += maxi(0, amount)
	_sync_bonus()


func _sync_bonus() -> void:
	unit.set_soldier_attack_bonus(slash_bonus + missile_bonus)


func statuses() -> Array[Dictionary]:
	if slash_bonus + missile_bonus == 0 or unit.current_state == UnitBase.State.DEATH:
		return []
	return [{"icon": "soldier_growth", "count": slash_bonus + missile_bonus,
		"tooltip": "士兵成长：攻击+%d\n斩击目标死亡：+%d；飞弹协同：+%d。\n持续本场战斗，不写入原牌。" % [slash_bonus + missile_bonus, slash_bonus, missile_bonus]}]


func clear() -> void:
	for id in slashed:
		var target = slashed[id].get_ref()
		var callback := _on_slashed_target_died.bind(id)
		if is_instance_valid(target) and target.unit_died.is_connected(callback):
			target.unit_died.disconnect(callback)
	slashed.clear()
	last_target = null
	slash_bonus = 0
	missile_bonus = 0
	_sync_bonus()


func _on_died(_unit: UnitBase) -> void:
	clear()


func _physics_process(_delta: float) -> void:
	if unit._encounter_finished() and (slash_bonus + missile_bonus > 0 or not slashed.is_empty()):
		clear()


func _exit_tree() -> void:
	clear()
